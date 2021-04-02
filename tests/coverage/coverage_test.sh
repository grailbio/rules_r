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

source "../setup-bazel.sh"

if ! [[ "${bazel_test_opts[*]:+${bazel_test_opts[*]}}" ]]; then
  bazel_test_opts=("--test_output=errors")
fi

# Older versions of LLVM and gcc dealt with code coverage differently:
#
# - With LLVM, the first statement in a function body is counted double,
# and the function header is ignored.
#
# - With gcc, the function header and the first statement count as separate
# hits, unless they are on the same line.
# However, LLVM behavior from Apple clang version 11+ onwards is consistent with gcc.
version_info="$($(R CMD config CC) --version)"
echo "Checking coverage results with the following system compiler:"
echo "${version_info}"

testlogs="$("${bazel}" info bazel-testlogs)"
readonly testlogs
readonly coverage_file="${testlogs}/packages/exampleC/test/coverage.dat"
readonly coverage_file_external="${testlogs}/external/workspaceroot/test/coverage.dat"

expect_equal() {
  local expected="$1"
  local actual="$2"

  # coverage profiling in gcc counts the return statement twice in rcpp.cc:32.
  # Let's standardize it to 2 hits for all toolchains.
  sed -i'.bak' 's@<line number="32" hits="4"@<line number="32" hits="2"@' "${actual}"
  if ! diff -q "${expected}" "${actual}" >/dev/null; then
    echo "==="
    echo "COVERAGE: ${expected} actual"
    diff "${expected}" "${actual}"
    echo "==="
    return 1
  fi

  printf "\n==== PASSED %s =====\n" "${expected}"
}

# Check that tests pass without instrumentation.
echo ""
echo "=== Testing no instrumentation ==="
"${bazel}" coverage "${bazel_test_opts[@]}" --instrumentation_filter="^$" //...
echo "Done!"

# For instrumentation of dependencies in the same package.
echo ""
echo "=== Testing default instrumentation ==="
"${bazel}" coverage "${bazel_test_opts[@]}" --instrumentation_filter=exampleC //...
expect_equal "default_instrumented.xml" "${coverage_file}"
echo "Done!"

# For instrumentation of packages without tests, and of indirect test dependencies.
echo ""
echo "=== Testing workspace instrumentation ==="
"${bazel}" coverage "${bazel_test_opts[@]}" --instrumentation_filter=// //...
expect_equal "workspace_instrumented.xml" "${coverage_file}"
echo "Done!"

# Set instrumentation filter to everything.
# Packages tagged external-r-repo are never instrumented in rules_r; so we should not fail here.
# But otherwise packages in external repos (workspaceroot) should be fine.
echo ""
echo "=== Testing all instrumentation ==="
"${bazel}" coverage "${bazel_test_opts[@]}" --instrumentation_filter='.' --test_output=summary \
  //... @workspaceroot//:all
expect_equal "workspace_instrumented.xml" "${coverage_file}"
expect_equal "workspaceroot.xml" "${coverage_file_external}"
echo "Done!"

# There is a problem with the protobuf library in the CI environment; perhaps
# run a simpler coverage test.
echo ""
echo "=== Testing custom toolchain ==="
if [[ "$(uname)" == "Linux" ]] && ! "${CI:-"false"}"; then
  # Check if we can compute coverage using supplied LLVM tools.
  echo "Checking coverage results with the LLVM toolchain:"
  toolchain_args=(
    "--extra_toolchains=//:toolchain-linux"
    "--extra_toolchains=@llvm_toolchain//:cc-toolchain-linux"
    "--crosstool_top=@llvm_toolchain//:toolchain"
    "--toolchain_resolution_debug"
  )
  "${bazel}" coverage "${bazel_test_opts[@]}" "${toolchain_args[@]}" //packages/exampleC:test
  expect_equal "default_instrumented.xml" "${coverage_file}"
fi
echo "Done!"
