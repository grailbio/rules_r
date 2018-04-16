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

if [[ $# -le 0 ]]; then >&2 echo "Insufficient arguments."; fi

# First argument is the path to the output tar file followed by the input files being archived.
TAR_PATH="$1"
shift

# Return early if no arguments were supplied.
if ! (( $# )); then
  touch "${TAR_PATH}"
  exit
fi

SRCS=("$@")

TEMP_DIR=$(mktemp -d)
for SRC in "${SRCS[@]+"${SRCS[@]}"}"; do
  ln -s "${PWD}/${SRC}" "${TEMP_DIR}/"
done

# Path transform opt for changing the temp directory to TAR_DIR.
TAR_OPTS=()
if [[ $(tar --version) == bsdtar* ]]; then
  TAR_OPTS+=(-s '|^\./|'"${TAR_DIR:+"${TAR_DIR}/"}|")
else
  TAR_OPTS+=(--xform 's|^\./|'"${TAR_DIR:+"${TAR_DIR}/"}|")
fi

tar -c -h -C "${TEMP_DIR}" -f "${TAR_PATH}" "${TAR_OPTS[@]}" .
rm -rf "${TEMP_DIR}"
