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

help() {
  echo 'Usage: bazel run target_label -- [-l library_path] [-s]'
  echo '  -l  library_path is the directory where R packages will be installed'
  echo '  -s  if specified, will install symlinks pointing into bazel-bin directory'
}

LIBRARY_PATH="{library_path}"
SOFT_INSTALL=false
while getopts "l:sh" opt; do
  case "$opt" in
    "l") LIBRARY_PATH="${OPTARG}";;
    "s") SOFT_INSTALL=true;;
    "h") help; exit 0;;
    "?") error "invalid option: -$OPTARG"; help; exit 1;;
  esac
done

DEFAULT_R_LIBRARY="$({Rscript} -e 'cat(.libPaths()[1])')"
LIBRARY_PATH=${LIBRARY_PATH:-${DEFAULT_R_LIBRARY}}
mkdir -p "${LIBRARY_PATH}"

BAZEL_LIB_DIRS=(
{lib_dirs}
)

if $SOFT_INSTALL; then
  echo "Installing package symlinks from ${PWD} to ${LIBRARY_PATH}"
  CMD=(ln -s -f)
else
  echo "Copying installed packages to ${LIBRARY_PATH}"
  CMD=(cp -R -L -f)
fi

PWD=$(pwd -P)
for LIB_DIR in "${BAZEL_LIB_DIRS[@]+"${BAZEL_LIB_DIRS[@]}"}"; do
  "${CMD[@]}" "${PWD}/${LIB_DIR}"/* "${LIBRARY_PATH}"
  # bazel 0.14 onwards omits write permissions from files; reinstate those in our copy.
  chmod -R u+w "${LIBRARY_PATH}"
done
