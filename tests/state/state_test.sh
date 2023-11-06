#!/bin/bash
# Copyright 2020 The Bazel Authors.
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

readonly state_file="./external/com_rules_r_toolchains/system_state.txt"

fail() {
  >&2 echo "$@"
  exit 1
}

# Check R version information.
r_version="$(R \
  -e 'v <- getRversion()' \
  -e 'cat(v$major, v$minor, sep=".")')"
if ! grep -q "^R version ${r_version}" "${state_file}"; then
  fail "R version information not found or mismatch"
fi

# Check CC information.
if ! grep -q "^CC = " "${state_file}"; then
  fail "CC information not found"
fi

# Check R  configuration.
if ! grep -q "^R_INCLUDE_DIR " "${state_file}"; then
  fail "R configuration not found"
fi
