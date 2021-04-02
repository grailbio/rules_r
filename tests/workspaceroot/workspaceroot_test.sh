#!/bin/bash
# Copyright 2021 The Bazel Authors.
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

cd "$(dirname "${BASH_SOURCE[0]}")"

source "../setup-bazel.sh"

"${bazel}" test "${bazel_test_opts[@]}" ":all"

# Check that the source filename was fixed correctly in the coverage xml.
compare_coverage() {
  local actual
  actual="$(${bazel} info bazel-testlogs)/test/coverage.dat"
  local expected="expected_coverage.xml"

  "${bazel}" coverage "${bazel_test_opts[@]}" ":test"

  if ! diff -q "${expected}" "${actual}" >/dev/null; then
    echo "==="
    echo "COVERAGE: expected actual"
    diff "${expected}" "${actual}"
    echo "==="
    exit 1
  fi
}

echo "=== Testing workspaceroot coverage ==="
compare_coverage
echo "Done!"
