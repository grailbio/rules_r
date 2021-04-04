#!/bin/bash
# Copyright 2018 The Bazel Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# Check version
# TODO: Remove this check when the system state is unconditionally checked.
if [[ "${REQUIRED_VERSION:-}" ]]; then
  r_version="$(${R} \
    -e 'v <- getRversion()' \
    -e 'cat(v$major, v$minor, sep=".")')"
  if [[ "${REQUIRED_VERSION}" != "${r_version}" ]]; then
    >&2 printf "Required R version is %s; you have %s\\n" "${REQUIRED_VERSION}" "${r_version}"
    exit 1
  fi
fi

EXEC_ROOT=$(pwd -P)

TMP_FILES=() # Temporary files to be cleaned up before exiting the script.

# Export PATH from bazel for subprocesses.
export PATH

cleanup() {
  rm -rf "${TMP_FILES[@]+"${TMP_FILES[@]}"}"
}
trap 'cleanup; exit 1' INT HUP QUIT TERM EXIT

# Suppress output if run is successful.
silent() {
  set +e
  # eval is needed to remove outer quotes in independent arguments in $BUILD_ARGS, etc.
  if ! OUT=$(eval "$@" 2>&1); then
    echo "${OUT}"
    exit 1
  fi
  if "${BAZEL_R_VERBOSE:-"false"}"; then
    echo "${OUT}"
  fi
  set -e
}

# TODO: Log only when verbose is set.
log() {
  echo "$@"
}

# Function to lock the common temp library directory for this package, until we
# have moved out of it.
lock() {
  local lock_file="$1"
  # Open the lock file and assign fd 200; file remains open as long as we are alive.
  TMP_FILES+=("${lock_file}")
  # Use fd 200 for the lock; will be released when the fd is closed on process termination.
  exec 200>"${lock_file}"

  # We use a non-blocking lock to define our timeout and messaging strategy here.
  local tries=0
  local max_tries=20
  local backoff=10
  while (( tries++ < max_tries )) && ! "${FLOCK_PATH}" 200; do
    log "Failed to acquire lock; will try again in $backoff seconds"
    sleep $backoff
  done
  if (( tries >= max_tries )); then
    log "Failed to acquire lock on ${lock_file} to build package; is another bazel build running?"
    exit 1
  elif (( tries > 1 )); then
    # Message only if it took more than one attempt.
    log "Acquired lock in $tries attempts"
  fi
}

add_instrumentation_hook() {
  silent "${RSCRIPT}" "${INSTRUMENT_SCRIPT}" "${PKG_LIB_PATH}" "${PKG_NAME}"
}
# Hard fail compilation on any gcov error.
export GCOV_EXIT_AT_ERROR=1

eval "${EXPORT_ENV_VARS_CMD:-}"

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

eval "${BUILD_TOOLS_EXPORT_CMD:-}"

if [[ "${CONFIG_OVERRIDE:-}" ]]; then
  cp "${CONFIG_OVERRIDE}" "${PKG_SRC_DIR}/configure"
fi

copy_inst_files() {
  local IFS=","
  for copy_pair in ${INST_FILES_MAP}; do
    IFS=":" read -r dst src <<< "${copy_pair}"
    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"
  done
}
copy_inst_files

# We make builds reproducible by asking R to use a constant timestamp, and by
# installing the packages to the same destination, from the same source path,
# to get reproducibility in embedded paths.
tmp_path_suffix="${PKG_SRC_DIR}"
if [[ "${tmp_path_suffix}" == "." ]]; then
  tmp_path_suffix="_WORKSPACE_ROOT_"
fi

# Obtain a lock across all builds on this machine for this tmp_path_suffix.
lock_dir="/tmp/bazel/R/locks"
mkdir -p "${lock_dir}"
lock_name="${tmp_path_suffix//\//_}" # Replace all '/' with '_'; will lead to some collision but OK.
lock "${lock_dir}/BZL_LOCK-${lock_name}"

TMP_LIB="/tmp/bazel/R/lib/${tmp_path_suffix}"
TMP_SRC="/tmp/bazel/R/src/${tmp_path_suffix}"
TMP_HOME="/tmp/bazel/R/home"

# Clean any leftover files from previous builds.
rm -rf "${TMP_LIB}" 2>/dev/null || true
rm -rf "${TMP_SRC}" 2>/dev/null || true
mkdir -p "${TMP_LIB}"
mkdir -p "${TMP_SRC}"

TMP_SRC_TAR="${TMP_SRC}.tar.gz"
copy_cmd=(
  rsync "--recursive" "--copy-links" "--no-perms" "--chmod=u+w" "--executability" "--specials")
if [[ "${PKG_SRC_DIR}" == "." ]]; then
  # Need to exclude special directories in the execroot.
  copy_cmd+=("--exclude" "bazel-out" "--exclude" "external" "--delete-excluded")
fi
copy_cmd+=("${EXEC_ROOT}/${PKG_SRC_DIR}/" "${TMP_SRC}")
"${copy_cmd[@]}"
TMP_FILES+=("${TMP_SRC}")

# Make a script file for sed that can substitute status vars enclosed in {}, with their values.
status_substitution_commands="$(mktemp)"
TMP_FILES+=("${status_substitution_commands}")
add_substitute_commands() {
  local status_file="$1"
  sed -e 's/@/\\@/' -e 's/^/s@{/' -e 's/ /}@/' -e 's/$/@/' "${status_file}" >> "${status_substitution_commands}"
}

add_metadata() {
  local IFS=","
  for status_file in ${STATUS_FILES}; do
    add_substitute_commands "${status_file}"
  done
  for key_value in ${METADATA_MAP:-}; do
    IFS=":" read -r key value <<< "${key_value}"
    value=$(echo "${value}" | sed -f "${status_substitution_commands}")
    printf "%s: %s\n" "${key}" "${value}" >> "${TMP_SRC}/DESCRIPTION"
  done
}
add_metadata

# Hack: copy the .so files inside the package source so that they are installed
# (in bazel's sandbox as well as on user's system) along with package libs, and
# use relative rpath (Linux) or change the install name to use @loader_path
# (macOS).
if [[ "${C_SO_FILES}" ]]; then
  C_SO_LD_FLAGS=""
  mkdir -p "${TMP_SRC}/inst/libs"
  for so_file in ${C_SO_FILES}; do
    eval so_file="${so_file}" # Use eval to remove outermost quotes.
    so_file_name="$(basename "${so_file}")"
    cp "${so_file}" "${TMP_SRC}/inst/libs/${so_file_name}"
    if [[ "$(uname)" == "Darwin" ]]; then
      C_SO_LD_FLAGS+="../inst/libs/${so_file_name} "
      install_name_tool -id "@loader_path/${so_file_name}" "${TMP_SRC}/inst/libs/${so_file_name}"
    elif [[ "$(uname)" == "Linux" ]]; then
      C_SO_LD_FLAGS+="-L../inst/libs -l:${so_file_name} "
    fi
  done
  if [[ "$(uname)" == "Linux" ]]; then
    #shellcheck disable=SC2016
    C_SO_LD_FLAGS+="-Wl,-rpath,"\''$$ORIGIN'\'" "
  fi
fi

# Ensure we have a clean site Makevars file, using user-provided content, if applicable.
tmp_mkvars="$(mktemp)"
TMP_FILES+=("${tmp_mkvars}")
if [[ "${R_MAKEVARS_SITE:-}" ]]; then
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/${R_MAKEVARS_SITE}" > "${tmp_mkvars}"
fi
export R_MAKEVARS_SITE="${tmp_mkvars}"

# Same for personal Makevars file.
if [[ "${R_MAKEVARS_USER:-}" ]]; then
  tmp_mkvars="$(mktemp)"
  TMP_FILES+=("${tmp_mkvars}")
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/${R_MAKEVARS_USER}" > "${tmp_mkvars}"
  export R_MAKEVARS_USER="${tmp_mkvars}"
fi

# Use R_LIBS in place of R_LIBS_USER because on some sytems (e.g., Ubuntu),
# R_LIBS_USER is parameter substituted with a default in .Renviron, which
# imposes length limits.
export R_LIBS="${R_LIBS_ROCLETS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export R_LIBS_USER=dummy

if [[ "${ROCLETS}" ]]; then
  silent "${RSCRIPT}" - <<EOF
bazel_libs <- .libPaths()
bazel_libs <- bazel_libs[! bazel_libs %in% c(.Library, .Library.site)]
if ("devtools" %in% installed.packages(bazel_libs)[, "Package"]) {
  devtools::document(pkg='${TMP_SRC}', roclets=c(${ROCLETS}))
} else {
  roxygen2::roxygenize(package.dir='${TMP_SRC}', roclets=c(${ROCLETS}))
}
EOF
fi

mkdir -p "${PKG_LIB_PATH}"

export R_LIBS="${R_LIBS_DEPS//_EXEC_ROOT_/${EXEC_ROOT}/}"

# Override flags to the compiler for reproducible builds.
repro_flags=(
"-Wno-builtin-macro-redefined"
"-D__DATE__=\"redacted\""
"-D__TIMESTAMP__=\"redacted\""
"-D__TIME__=\"redacted\""
"-fdebug-prefix-map=\"${EXEC_ROOT}/=\""
)
echo "CPPFLAGS += ${repro_flags[*]}" >> "${R_MAKEVARS_SITE}"

# Get any flags from cc_deps for this package and append to site Makevars file.
# We keep these last in the site Makevars files so that any flags here may take
# precedence over other conflicting settings specified previously in the file.
pkg_libs="${C_SO_LD_FLAGS:-}${C_LIBS_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"
pkg_cppflags="${C_CPP_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"
if [[ "${pkg_libs}" ]] || [[ "${pkg_cppflags}" ]]; then
  echo "
PKG_LIBS += ${pkg_libs}
PKG_CPPFLAGS += ${pkg_cppflags}
PKG_FCFLAGS += ${pkg_cppflags}  # Fortran 90/95
PKG_FFLAGS += ${pkg_cppflags}   # Fortran 77
" >> "${R_MAKEVARS_SITE}"
fi

# Set HOME for pandoc for building vignettes.
mkdir -p "${TMP_HOME}"
export HOME="${TMP_HOME}"

# Reset mtime for all files. R's help DB is specially sensitive to timestamps of .Rd files in man/.
TZ=UTC find "${TMP_SRC}" -type f -exec touch -t 197001010000 {} \+

silent "${R}" CMD build "${BUILD_ARGS}" "${TMP_SRC}"
mv "${PKG_NAME}"*.tar.gz "${TMP_SRC_TAR}"
TMP_FILES+=("${TMP_SRC_TAR}")

# Unzip the built package as the new source, remove any non-reproducible
# artifacts, perform any additional cleanups, and repackage.
rm -r "${TMP_SRC}"
mkdir -p "${TMP_SRC}"
tar -C "${TMP_SRC}" --strip-components=1 -xzf "${TMP_SRC_TAR}"
sed -i'.bak' -e "/^Packaged: /d" "${TMP_SRC}/DESCRIPTION"
rm "${TMP_SRC}/DESCRIPTION.bak"
if "${INSTRUMENTED}"; then
  # .gcno and .gcda files are not cleaned up after R CMD build.
  find "${TMP_SRC}" \( -name '*.gcda' -or -name '*.gcno' \) -delete
fi
# Repackage tar with package name as root, and without mtime.
(
  cd "${TMP_SRC}"
  if [[ "$(tar --version)" == "bsdtar"* ]]; then
    flags=("-s" "@^@${PKG_NAME}/@")
  else
    flags=("--transform" "s@^@${PKG_NAME}/@")
  fi
  tar "${flags[@]}" -czf "${TMP_SRC_TAR}" -- *
)

# Done building the package source archive.
mv "${TMP_SRC_TAR}" "${PKG_SRC_ARCHIVE}"
if "${BUILD_SRC_ARCHIVE_ONLY:-"false"}"; then
  trap - EXIT
  cleanup
  exit
fi

# Install the package to the common temp library.
silent "${R}" CMD INSTALL --built-timestamp='' "${INSTALL_ARGS}" --no-lock --build --library="${TMP_LIB}" --clean "${TMP_SRC}"
rm -rf "${PKG_LIB_PATH:?}/${PKG_NAME}" # Delete empty directories to make way for move.
mv -f "${TMP_LIB}/${PKG_NAME}" "${PKG_LIB_PATH}/"
mv "${PKG_NAME}"*gz "${PKG_BIN_ARCHIVE}"  # .tgz on macOS and .tar.gz on Linux.

if "${INSTRUMENTED}"; then
  add_instrumentation_hook
  # Copy .gcno files next to the source files.
  if [[ -d "${TMP_SRC}/src" ]]; then
    rsync -am --include='*.gcno' --include='*/' --exclude='*' \
      "${TMP_SRC}/src" "$(dirname "${PKG_LIB_PATH}")"
  fi
fi

trap - EXIT
cleanup
