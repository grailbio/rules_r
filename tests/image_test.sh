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
fi

check() {
  local LAYER_TAR="$1"
  local FILE_TO_CHECK="$2"
  local EXPECT="$3"
  echo "Looking for file ${FILE_TO_CHECK}:"
  if tar -tf "${LAYER_TAR}" | tee /dev/stderr 2| \
    (grep -q "${FILE_TO_CHECK}" || (echo "Not found!" && exit 1)); then $EXPECT
  elif $EXPECT; then exit 1
  fi
}

check "library_image_internal-layer.tar" "^./grail/r-libs/exampleC/DESCRIPTION$" "true"
check "library_image_external-layer.tar" "^./grail/r-libs/exampleC/DESCRIPTION$" "false"
check "library_image_external-layer.tar" "^./grail/r-libs/bitops/DESCRIPTION$" "true"
check "library_image_internal-layer.tar" "^./grail/r-libs/bitops/DESCRIPTION$" "false"

echo "Found!"
