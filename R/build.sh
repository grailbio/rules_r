#!/bin/bash
# Copyright 2018 GRAIL, Inc.
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

PWD=$(pwd -P)

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

eval "${EXPORT_ENV_VARS_CMD}"

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

eval "${BUILD_TOOLS_EXPORT_CMD}"

if [[ "${CONFIG_OVERRIDE}" ]]; then
  cp "${CONFIG_OVERRIDE}" "${PKG_SRC_DIR}/configure"
fi

if [[ "${ROCLETS}" ]]; then
  silent "${RSCRIPT}" -e "roxygen2::roxygenize(package.dir='${PKG_SRC_DIR}', roclets=c(${ROCLETS}))"
fi

if "${BUILD_SRC_ARCHIVE:-"false"}"; then
  silent "${R}" CMD build "${BUILD_ARGS}" "${PKG_SRC_DIR}"
  mv "${PKG_NAME}"*.tar.gz "${PKG_SRC_ARCHIVE}"

  trap - EXIT
  cleanup
  exit
fi

export PKG_LIBS="${C_LIBS_FLAGS//_EXEC_ROOT_/$PWD/}"
export PKG_CPPFLAGS="${C_CPP_FLAGS//_EXEC_ROOT_/$PWD/}"
export R_MAKEVARS_USER="${PWD}/${R_MAKEVARS_USER}"

# Use R_LIBS in place of R_LIBS_USER because on some sytems (e.g., Ubuntu),
# R_LIBS_USER is parameter substituted with a default in .Renviron, which
# imposes length limits.
export R_LIBS="${R_LIBS//_EXEC_ROOT_/$PWD/}"
export R_LIBS_USER=dummy

mkdir -p "${PKG_LIB_PATH}"
if ! ${REPRODUCIBLE_BUILD}; then
  silent "${R}" CMD INSTALL "${INSTALL_ARGS}" --build --library="${PKG_LIB_PATH}" \
    "${PKG_SRC_DIR}"
  mv "${PKG_NAME}"*gz "${PKG_BIN_ARCHIVE}"  # .tgz on macOS and .tar.gz on Linux.

  trap - EXIT
  cleanup
  exit
fi

# There is additional complexity to ensure that the the build produces the same
# file content.  This feature is turned off by default and can be enabled on
# the bazel command line by --features=rlang-no-stamp.

# TODO: Implement locking mechanism for reproducible builds.
echo "REPRODUCIBLE_BUILD not implemented yet."
exit 1
