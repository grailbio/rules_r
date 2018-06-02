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

EXEC_ROOT=$(pwd -P)

TMP_FILES=() # Temporary files to be cleaned up before exiting the script.

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

eval "${EXPORT_ENV_VARS_CMD:-}"

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

# Use R_LIBS in place of R_LIBS_USER because on some sytems (e.g., Ubuntu),
# R_LIBS_USER is parameter substituted with a default in .Renviron, which
# imposes length limits.
export R_LIBS="${R_LIBS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export R_LIBS_USER=dummy

mkdir -p "${PKG_LIB_PATH}"

if ${INSTALL_BIN_ARCHIVE:-"false"}; then
  silent "${R}" CMD INSTALL "${INSTALL_ARGS}" --library="${PKG_LIB_PATH}" "${PKG_BIN_ARCHIVE}"
  trap - EXIT
  cleanup
  exit
fi

eval "${BUILD_TOOLS_EXPORT_CMD:-}"

if [[ "${CONFIG_OVERRIDE:-}" ]]; then
  cp "${CONFIG_OVERRIDE}" "${PKG_SRC_DIR}/configure"
fi

if [[ "${ROCLETS}" ]]; then
  silent "${RSCRIPT}" \
    -e "\"if (requireNamespace('devtools')) {\"" \
    -e "\"  devtools::document(pkg='${PKG_SRC_DIR}', roclets=c(${ROCLETS}))\"" \
    -e "\"} else {\"" \
    -e "\"  roxygen2::roxygenize(package.dir='${PKG_SRC_DIR}', roclets=c(${ROCLETS}))\"" \
    -e "\"}\""
fi

if "${BUILD_SRC_ARCHIVE:-"false"}"; then
  silent "${R}" CMD build "${BUILD_ARGS}" "${PKG_SRC_DIR}"
  mv "${PKG_NAME}"*.tar.gz "${PKG_SRC_ARCHIVE}"

  trap - EXIT
  cleanup
  exit
fi

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
export R_MAKEVARS_USER="${EXEC_ROOT}/${R_MAKEVARS_USER}"

# Easy case -- we allow timestamp and install paths to be stamped inside the package files.
if ! ${REPRODUCIBLE_BUILD}; then
  silent "${R}" CMD INSTALL "${INSTALL_ARGS}" --build --library="${PKG_LIB_PATH}" \
    "${PKG_SRC_DIR}"
  mv "${PKG_NAME}"*gz "${PKG_BIN_ARCHIVE}"  # .tgz on macOS and .tar.gz on Linux.

  trap - EXIT
  cleanup
  exit
fi

# Not so easy case -- we make builds reproducible by asking R to use a constant
# timestamp, and by installing the packages to the same destination, from the
# same source path, to get reproducibility in embedded paths.
LOCK_DIR="/tmp/bazel/R/locks"
TMP_LIB="/tmp/bazel/R/lib"
TMP_SRC="/tmp/bazel/R/src"
mkdir -p "${LOCK_DIR}"
mkdir -p "${TMP_LIB}"
mkdir -p "${TMP_SRC}"
lock "${LOCK_DIR}" "${PKG_NAME}"

TMP_SRC_PKG="${TMP_SRC}/${PKG_NAME}"
rm -rf "${TMP_SRC_PKG}" 2>/dev/null || true
cp -a "${EXEC_ROOT}/${PKG_SRC_DIR}" "${TMP_SRC_PKG}"
TMP_FILES+=("${TMP_SRC_PKG}")

# Override flags to the compiler for reproducible builds.
R_MAKEVARS_SITE="$(mktemp)"
TMP_FILES+=("${R_MAKEVARS_SITE}")
export R_MAKEVARS_SITE

repro_flags=(
"-Wno-builtin-macro-redefined"
"-D__DATE__=\"redacted\""
"-D__TIMESTAMP__=\"redacted\""
"-D__TIME__=\"redacted\""
"-fdebug-prefix-map=\"${EXEC_ROOT}/=\""
)
echo "CPPFLAGS += ${repro_flags[*]}" > "${R_MAKEVARS_SITE}"

# Install the package to the common temp library.
silent "${R}" CMD INSTALL "${INSTALL_ARGS}" --built-timestamp='' --no-lock --build --library="${TMP_LIB}" "${TMP_SRC_PKG}"
rm -rf "${PKG_LIB_PATH:?}/${PKG_NAME}" # Delete empty directories to make way for move.
mv -f "${TMP_LIB}/${PKG_NAME}" "${PKG_LIB_PATH}/"
mv "${PKG_NAME}"*gz "${PKG_BIN_ARCHIVE}"  # .tgz on macOS and .tar.gz on Linux.

trap - EXIT
cleanup
