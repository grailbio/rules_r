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

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

eval "${EXPORT_ENV_VARS_CMD:-}"

# Use R_LIBS in place of R_LIBS_USER because on some sytems (e.g., Ubuntu),
# R_LIBS_USER is parameter substituted with a default in .Renviron, which
# imposes length limits.
export R_LIBS="${R_LIBS_DEPS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export R_LIBS_USER=dummy

mkdir -p "${PKG_LIB_PATH}"

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

silent "${R}" CMD INSTALL "${INSTALL_ARGS}" --library="${PKG_LIB_PATH}" "${PKG_BIN_ARCHIVE}"
