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
  startup_flags=("--nohome_rc" "--output_base=${base}")
  "${bazel}" "${startup_flags[@]}" build "${bazel_build_opts[@]}" "--remote_cache=" "--disk_cache=" //packages/exampleC:all
  "${bazel}" "${startup_flags[@]}" info bazel-bin
}
first_output="$(run_bazel "${first}")"
second_output="$(run_bazel "${second}")"

shutdown_bazel() {
  base="$1"
  startup_flags=("--nohome_rc" "--output_base=${base}")
  "${bazel}" "${startup_flags[@]}" clean --expunge
  "${bazel}" "${startup_flags[@]}" shutdown
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

# Filter out manifest files which may contain absolute paths.
sed -i'.bak' -e '/manifest$/d' -e '/MANIFEST$/d' "${shasums}"

# Check shasums match, and if not and running on CI, copy the files to artifacts dir.
file_list="${tmpdir}/mismatch_files.txt"
( ( cd "${second_output}" && shasum -a 256 -c "${shasums}" ) || true ) | \
  ( grep -v "OK$" || true ) | \
  sed -e 's/: .*$//' > "${file_list}"
if [[ "${CI:-false}" ]] && [[ "${ARTIFACTS_DIR:-}" ]]; then
  mkdir -p "${ARTIFACTS_DIR}/repro"
  cp "${shasums}" "${ARTIFACTS_DIR}/repro/"
  (cd "${first_output}" && rsync "--files-from=${file_list}" . "${ARTIFACTS_DIR}/repro/first")
  (cd "${second_output}" && rsync "--files-from=${file_list}" . "${ARTIFACTS_DIR}/repro/second")
fi

if [[ -s "${file_list}" ]]; then
  cat "${file_list}"
  echo "reproducibility test FAILED"
  exit 1
else
  echo "reproducibility test PASSED"
  cleanup
fi
