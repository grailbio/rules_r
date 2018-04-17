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

# This script collects the given src files and directories into a destination
# directory by copying them.

set -euo pipefail

if [[ $# -le 0 ]]; then >&2 echo "Insufficient arguments."; fi

# First argument is the path to the output tar file followed by the input files being collected.
DST_ROOT="$1"
shift

SRCS=("$@")

mkdir -p "${DST_ROOT}"
for SRC in "${SRCS[@]+"${SRCS[@]}"}"; do
  cp -rf "${SRC}/" "${DST_ROOT}"
done
