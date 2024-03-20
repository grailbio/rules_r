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

# Ensure that we are using the same compiler for both cc_library and for R.
# This is usually a problem when our default local toolchain for R on macOS
# picks the homebrew LLVM compiler but bazel's C++ toolchain is using the Apple
# toolchain. When object files from two different compilers is used in the same
# run, .gcda files will be generated without version information and will be
# considered invalid by gcov.
if [[ "$(uname)" == "Darwin" ]]; then
  export BAZEL_R_HOMEBREW=false
fi

testlogs="$("${bazel}" info bazel-testlogs)"
readonly testlogs
readonly coverage_file_C="${testlogs}/packages/exampleC/test/coverage.dat"
readonly coverage_file_D="${testlogs}/packages/exampleD/test/coverage.dat"
readonly coverage_file_external="${testlogs}/external/workspaceroot/test/coverage.dat"

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
expect_equal "default_instrumented.xml" "${coverage_file_C}"
echo "Done!"

# For instrumentation of packages without tests, and of indirect test dependencies.
echo ""
echo "=== Testing workspace instrumentation ==="
"${bazel}" coverage "${bazel_test_opts[@]}" --instrumentation_filter=^// //...
expect_equal "workspace_instrumented_C.xml" "${coverage_file_C}"
expect_equal "workspace_instrumented_D.xml" "${coverage_file_D}"
echo "Done!"

# Set instrumentation filter to everything.
# Packages tagged external-r-repo are never instrumented in rules_r; so we
# should not fail here. But otherwise packages in external repos
# (workspaceroot) should be fine. The protobuf and zlib libraries can be heavy
# dependencies to collect through covr, so we omit them explicitly.
echo ""
echo "=== Testing all instrumentation ==="
"${bazel}" coverage "${bazel_test_opts[@]}" --test_output=summary \
  --instrumentation_filter='.,-protobuf,-zlib' \
  //... @workspaceroot//:all
expect_equal "all_instrumented_C.xml" "${coverage_file_C}"
expect_equal "all_instrumented_D.xml" "${coverage_file_D}"
expect_equal "workspaceroot.xml" "${coverage_file_external}"
echo "Done!"

# There is a problem with the protobuf library in the CI environment; perhaps
# run a simpler coverage test.
echo ""
echo "=== Testing custom toolchain ==="
# Check if we can compute coverage using supplied LLVM tools.
# Note that this toolchain is currently not producing .gcda files, so
# coverage from cc_deps is missing.
echo "Checking coverage results with the LLVM toolchain:"
toolchain_args=(
  "--extra_toolchains=//:toolchain-${os}"
  "--extra_toolchains=@llvm_toolchain//:cc-toolchain-${bzl_arch}-${os}"
  "--toolchain_resolution_debug=rules_r"
)
"${bazel}" coverage "${bazel_test_opts[@]}" "${toolchain_args[@]}" //...
expect_equal "custom_toolchain_C.xml" "${coverage_file_C}"
expect_equal "custom_toolchain_D.xml" "${coverage_file_D}"
echo "Done!"
