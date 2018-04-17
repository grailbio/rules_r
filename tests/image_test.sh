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

set -eou pipefail

if [[ "${TEST_SRCDIR:-}" ]]; then
  # Ensure we are in the correct workspace for this test.
  echo "Moving to the right bazel workspace:"
  pushd "${TEST_SRCDIR}/com_grail_rules_r_tests"
  echo ""
else
  cd "$(dirname "${BASH_SOURCE[0]}")/bazel-bin"
fi

check() {
  local TAR="$1"
  local FILE_TO_CHECK="$2"
  local EXPECT="$3"
  if ! [[ -f "${TAR}" ]]; then
    echo "${TAR}" not found.
    exit 1
  fi
  echo "Looking for file ${FILE_TO_CHECK} in ${TAR}:"
  if tar -tf "${TAR}" "${FILE_TO_CHECK}" >/dev/null 2>/dev/null; then
    $EXPECT || (echo "Found but not expecting!" && exit 1)
  elif $EXPECT; then
    echo "Not found!" && exit 1
  fi
}

check "library_image_internal-layer.tar" "./grail/r-libs/exampleC/DESCRIPTION" "true"
check "library_image_external-layer.tar" "./grail/r-libs/exampleC/DESCRIPTION" "false"
check "library_image_external-layer.tar" "./grail/r-libs/bitops/DESCRIPTION" "true"
check "library_image_internal-layer.tar" "./grail/r-libs/bitops/DESCRIPTION" "false"

check "library_archive.tar.gz" "./grail/r-libs/exampleC/DESCRIPTION" "false"
check "library_archive.tar.gz" "./grail/r-libs/bitops/DESCRIPTION" "true"

echo "Found!"
