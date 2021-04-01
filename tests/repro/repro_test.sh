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

# Clean up bazel-* symlinks in workspace root to not confuse bazel when running
# with a different output_path.
rm "$("${bazel}" info workspace)/bazel-*" 2>/dev/null || true

tmpdir="$(mktemp -d)"
readonly tmpdir
readonly first="${tmpdir}/first"
readonly second="${tmpdir}/second"

run_bazel() {
  base="$1"
  "${bazel}" --bazelrc=/dev/null --output_base="${base}" build //packages/exampleC
  "${bazel}" --bazelrc=/dev/null --output_base="${base}" build //packages/exampleC:exampleC.tar.gz
  "${bazel}" --bazelrc=/dev/null --output_base="${base}" info bazel-bin
}
first_output="$(run_bazel "${first}")"
second_output="$(run_bazel "${second}")"

shutdown_bazel() {
  base="$1"
  "${bazel}" --bazelrc=/dev/null --output_base="${base}" clean --expunge
  "${bazel}" --bazelrc=/dev/null --output_base="${base}" shutdown
}

cleanup() {
  ( shutdown_bazel "${first}" ) 2>/dev/null || true
  ( shutdown_bazel "${second}" ) 2>/dev/null || true
  rm -rf "${tmpdir}" || true
}
trap 'cleanup' INT HUP QUIT TERM # Do not clean up automatically on EXIT.

echo ""
echo "=== Comparing file digests from two clean runs ==="
echo "first set of outputs in ${first_output}"
echo "second set of outputs in ${second_output}"
readonly shasums="${tmpdir}/shasums"
( cd "${first_output}" && find . -type f -exec shasum -a 256 {} \+ ) >"${shasums}"

# Do not compare packaged source and binary tars, they are currently not
# reproducible because of file attributes. They can be made reproducible if we
# really want.
readonly shasums_mod="${tmpdir}/shasums_mod"
grep -v ".tar.gz$" "${shasums}" > "${shasums_mod}"
mv "${shasums_mod}" "${shasums}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  # default Apple clang may not produce reproducible shared libraries; LLVM 7+ should be OK.
  # https://bugs.llvm.org/show_bug.cgi?id=38050
  grep -v ".so$" "${shasums}" > "${shasums_mod}"
  mv "${shasums_mod}" "${shasums}"
fi

( cd "${second_output}" && shasum -a 256 -c "${shasums}" ) | ( grep -v "OK$" || true )

echo "reproducibility test PASSED"
cleanup
