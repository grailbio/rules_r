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
  local lock_dir="$1"
  local lock_name="$2"
  # Open the lock file and assign fd 200; file remains open as long as we are alive.
  local lock_file="${lock_dir}/BZL_LOCK-${lock_name}"
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
  local pkg_src="$1"
  silent "${RSCRIPT}" "${INSTRUMENT_SCRIPT}" "${PKG_LIB_PATH}" "${PKG_NAME}" "${pkg_src}"
}

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

# Make a script file for sed that can substitute status vars enclosed in {}, with their values.
status_substitution_commands="$(mktemp)"
TMP_FILES+=("${status_substitution_commands}")
add_substitute_commands() {
  local status_file="$1"
  sed -e 's/@/\\@/' -e 's/^/s@{/' -e 's/ /}@/' -e 's/$/@/' "${status_file}" >> "${status_substitution_commands}"
}

stamped_description="$(mktemp)"
TMP_FILES+=("${stamped_description}")
cp "${PKG_SRC_DIR}/DESCRIPTION" "${stamped_description}"
add_metadata() {
  local IFS=","
  for status_file in ${STATUS_FILES}; do
    add_substitute_commands "${status_file}"
  done
  for key_value in ${METADATA_MAP:-}; do
    IFS=":" read -r key value <<< "${key_value}"
    value=$(echo "${value}" | sed -f "${status_substitution_commands}")
    printf "%s: %s\n" "${key}" "${value}" >> "${stamped_description}"
  done
}
add_metadata

# Hack: copy the .so files inside the package source so that they are installed
# (in bazel's sandbox as well as on user's system) along with package libs, and
# use relative rpath.
if [[ "${C_SO_FILES}" ]]; then
  mkdir -p "${PKG_SRC_DIR}/src"
  eval cp "${C_SO_FILES}" "${PKG_SRC_DIR}/src" # Use eval to remove outermost quotes.
  #shellcheck disable=SC2016
  # Not all toolchains support $ORIGIN variable in rpath.
  C_SO_LD_FLAGS='-Wl,-rpath,'\''$$ORIGIN'\'' '
fi

export PKG_LIBS="${C_SO_LD_FLAGS:-}${C_LIBS_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export PKG_CPPFLAGS="${C_CPP_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export PKG_FCFLAGS="${PKG_CPPFLAGS}"  # Fortran 90/95
export PKG_FFLAGS="${PKG_CPPFLAGS}"   # Fortran 77

# Ensure we have a clean site Makevars file, using user-provided content, if applicable.
tmp_mkvars="$(mktemp)"
TMP_FILES+=("${tmp_mkvars}")
if [[ "${R_MAKEVARS_SITE:-}" ]]; then
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/${R_MAKEVARS_SITE}" > "${tmp_mkvars}"
fi
export R_MAKEVARS_SITE="${tmp_mkvars}"

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
  devtools::document(pkg='${PKG_SRC_DIR}', roclets=c(${ROCLETS}))
} else {
  roxygen2::roxygenize(package.dir='${PKG_SRC_DIR}', roclets=c(${ROCLETS}))
}
EOF
fi

mkdir -p "${PKG_LIB_PATH}"

export R_LIBS="${R_LIBS_DEPS//_EXEC_ROOT_/${EXEC_ROOT}/}"

# We make builds reproducible by asking R to use a constant timestamp, and by
# installing the packages to the same destination, from the same source path,
# to get reproducibility in embedded paths.
LOCK_DIR="/tmp/bazel/R/locks"
TMP_LIB="/tmp/bazel/R/lib_${PKG_NAME}"
TMP_SRC="/tmp/bazel/R/src"
TMP_HOME="/tmp/bazel/R/home"
mkdir -p "${LOCK_DIR}"
mkdir -p "${TMP_LIB}"
mkdir -p "${TMP_SRC}"
lock "${LOCK_DIR}" "${PKG_NAME}"

TMP_SRC_PKG="${TMP_SRC}/${PKG_SRC_DIR}"
TMP_SRC_PKG_TAR="${TMP_SRC}/${PKG_SRC_DIR}.tar.gz"
mkdir -p "${TMP_SRC_PKG}"
rm -rf "${TMP_SRC_PKG}" 2>/dev/null || true
cp -a -L "${EXEC_ROOT}/${PKG_SRC_DIR}" "${TMP_SRC_PKG}"
cp "${stamped_description}" "${TMP_SRC_PKG}/DESCRIPTION"
TMP_FILES+=("${TMP_SRC_PKG}")

# Reset mtime for all files. R's help DB is specially sensitive to timestamps of .Rd files in man/.
TZ=UTC find "${TMP_SRC_PKG}" -type f -exec touch -t 197001010000 {} \+

# Override flags to the compiler for reproducible builds.
repro_flags=(
"-Wno-builtin-macro-redefined"
"-D__DATE__=\"redacted\""
"-D__TIMESTAMP__=\"redacted\""
"-D__TIME__=\"redacted\""
"-fdebug-prefix-map=\"${EXEC_ROOT}/=\""
)
echo "CPPFLAGS += ${repro_flags[*]}" >> "${R_MAKEVARS_SITE}"

# Set HOME for pandoc for building vignettes.
mkdir -p "${TMP_HOME}"
export HOME="${TMP_HOME}"

silent "${R}" CMD build "${BUILD_ARGS}" "${TMP_SRC_PKG}"
mv "${PKG_NAME}"*.tar.gz "${TMP_SRC_PKG_TAR}"
cp "${TMP_SRC_PKG_TAR}" "${PKG_SRC_ARCHIVE}"

# Check if we needed to build only the source archive.
if "${BUILD_SRC_ARCHIVE_ONLY:-"false"}"; then
  trap - EXIT
  cleanup
  exit
fi

# Unzip the built package as the new source, and remove any non-reproducible artifacts.
rm -r "${TMP_SRC_PKG}"
mkdir -p "${TMP_SRC_PKG}"
tar -C "${TMP_SRC_PKG}" --strip-components=1 -xzf "${TMP_SRC_PKG_TAR}"
sed -i'' -e "/^Packaged: /d" "${TMP_SRC_PKG}/DESCRIPTION"

# Install the package to the common temp library.
silent "${R}" CMD INSTALL --built-timestamp='' "${INSTALL_ARGS}" --no-lock --build --library="${TMP_LIB}" "${TMP_SRC_PKG}"
rm -rf "${PKG_LIB_PATH:?}/${PKG_NAME}" # Delete empty directories to make way for move.
mv -f "${TMP_LIB}/${PKG_NAME}" "${PKG_LIB_PATH}/"
mv "${PKG_NAME}"*gz "${PKG_BIN_ARCHIVE}"  # .tgz on macOS and .tar.gz on Linux.

if "${INSTRUMENTED}"; then
  add_instrumentation_hook "${TMP_SRC_PKG}"
fi

trap - EXIT
cleanup
