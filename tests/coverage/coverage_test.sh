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

cd "$(dirname "${BASH_SOURCE[0]}")"

if ! [[ "${BAZEL_TEST_OPTS[*]:+${BAZEL_TEST_OPTS[*]}}" ]]; then
  BAZEL_TEST_OPTS=("--test_output=errors")
fi

# LLVM and gcc deal with code coverage differently:
#
# - With LLVM, the first statement in a function body is counted double,
# and the function header is ignored.
#
# - With gcc, the function header and the first statement count as separate
# hits, unless they are on the same line.
suffix="_clang"
if [[ $(R CMD config CC) == "gcc"* ]]; then
  suffix="_gcc"
fi

coverage_file="$(bazel info bazel-testlogs)/exampleC/test/coverage.dat"
readonly coverage_file

expect_equal() {
  local expected="$1"
  local actual="$2"

  if ! diff -q "${expected}" "${actual}" >/dev/null; then
    echo "==="
    echo "COVERAGE: ${expected} actual"
    diff "${expected}" "${actual}"
    echo "==="
    return 1
  fi

  printf "\n==== PASSED %s =====\n\n" "${expected}"
}

# For instrumentation of dependencies in the same package.
bazel coverage "${BAZEL_TEST_OPTS[@]}" --instrumentation_filter=exampleC //exampleC:test
expect_equal "default_instrumented${suffix}.xml" "${coverage_file}"

# For instrumentation of packages without tests, and of indirect test dependencies.
bazel coverage "${BAZEL_TEST_OPTS[@]}" --instrumentation_filter=// //...
expect_equal "workspace_instrumented${suffix}.xml" "${coverage_file}"

# Set instrumentation filter to everything.
# Packages tagged external-r-repo are never instrumented in rules_r; so we should not fail here.
bazel coverage "${BAZEL_TEST_OPTS[@]}" --instrumentation_filter='.' --test_output=summary //...
