# shellcheck shell=bash
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

# This file is sourced from build_pkg_src.sh or build_pkg_bin.sh. It contains
# common utility functions and environment variables.

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

# Hard fail compilation on any gcov error.
export GCOV_EXIT_AT_ERROR=1

eval "${EXPORT_ENV_VARS_CMD:-}"

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

eval "${BUILD_TOOLS_EXPORT_CMD:-}"

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

# Hack: set flags for the .so files that have been provided by the user through
# cc_deps. When we build the package source archive, the files are copied to
# inst/libs. When we are building the package binary archive, the files should
# already be in inst/libs (copied in the previous step).
# See corresponding logic to copy the files in build_pkg_src.sh.
if [[ "${C_SO_FILES}" ]]; then
  C_SO_LD_FLAGS=""
  for so_file in ${C_SO_FILES}; do
    eval so_file="${so_file}" # Use eval to remove outermost quotes.
    so_file_name="$(basename "${so_file}")"
    if [[ "$(uname)" == "Darwin" ]]; then
      C_SO_LD_FLAGS+="../inst/libs/${so_file_name} "
    elif [[ "$(uname)" == "Linux" ]]; then
      C_SO_LD_FLAGS+="-L../inst/libs -l:${so_file_name} "
    fi
  done
  if [[ "$(uname)" == "Linux" ]]; then
    #shellcheck disable=SC2016
    C_SO_LD_FLAGS+="-Wl,-rpath,"\''$$ORIGIN'\'" "
  fi
fi

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

# Symlink the libraries to a single directory instead of using a search path
# with their individual directories because on some sytems (e.g., Ubuntu),
# R_LIBS_USER and R_LIBS are parameter substituted with a default in .Renviron,
# which imposes length limits.
# For reproducibility of embedded paths in compiled native code when using
# "Linking To" type dependencies, use a constant path for this library
# directory.

# Hide R_LIBS from R to prevent packages in here from being picked up, and use
# R_LIBS_USER to stage our packages.
export R_LIBS=dummy
export R_LIBS_USER="${TMP_LIB}"

symlink_r_libs() {
  local r_libs="${1}"
  find "${R_LIBS_USER}" -maxdepth 1 -type l -delete
  (
  IFS=":"
  for lib in ${r_libs}; do
    ln -s "${lib}/"* "${R_LIBS_USER}"
  done
  )
}

# Set HOME for pandoc for building vignettes.
mkdir -p "${TMP_HOME}"
export HOME="${TMP_HOME}"
