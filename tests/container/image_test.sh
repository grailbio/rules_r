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
  pushd "${TEST_SRCDIR}/com_rules_r_tests/container"
  echo ""
else
  cd "$(dirname "${BASH_SOURCE[0]}")/bazel-bin/container"
fi

check() {
  local TAR="$1"
  local FILE_TO_CHECK="$2"
  local EXPECT="$3"
  if ! [[ -f "${TAR}" ]]; then
    echo "${TAR}" not found.
    exit 1
  fi
  printf "Looking for file %s in %s: " "${FILE_TO_CHECK}" "${TAR}"
  if tar -tf "${TAR}" "${FILE_TO_CHECK}" >/dev/null 2>/dev/null; then
    ($EXPECT && echo "Found and expecting") || (echo "Found but not expecting!" && exit 1)
  elif $EXPECT; then
    echo "Not found!" && exit 1
  else
    echo "Not found and not expecting"
  fi
}

check "library_image-layer.tar" "./R/r-libs/exampleC/DESCRIPTION" "false"
check "library_image-layer.tar" "./R/r-libs/bitops/DESCRIPTION" "false"
check "library_image_internal-layer.tar" "./R/r-libs/exampleC/DESCRIPTION" "true"
check "library_image_internal-layer.tar" "./R/r-libs/bitops/DESCRIPTION" "false"
check "library_image_external-layer.tar" "./R/r-libs/exampleC/DESCRIPTION" "false"
check "library_image_external-layer.tar" "./R/r-libs/bitops/DESCRIPTION" "true"
check "library_image_tools-layer.tar" "./R/r-libs/exampleC/DESCRIPTION" "false"
check "library_image_tools-layer.tar" "./R/r-libs/bitops/DESCRIPTION" "false"

check "library_archive.tar.gz" "./R/r-libs/exampleC/DESCRIPTION" "false"
check "library_archive.tar.gz" "./R/r-libs/bitops/DESCRIPTION" "true"

# Check binary script and R library packages.
check "binary_image-layer.tar" "/app/binary/binary" "true"
check "binary_image-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/binary/binary.R" "true"
check "binary_image-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/packages/exampleA/lib/exampleA/DESCRIPTION" "true"
check "binary_image-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/packages/exampleB/lib/exampleB/DESCRIPTION" "true"
check "binary_image-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/packages/exampleC/lib/exampleC/DESCRIPTION" "true"
check "binary_image-layer.tar" "./app/binary/binary.runfiles/R_bitops/lib/bitops/DESCRIPTION" "true"
check "binary_image-layer.tar" "./app/binary/binary.runfiles/R_R6/lib/R6/DESCRIPTION" "true"

# Check that explicitly layered packages are not in the top layer, but in one layer below.
check "binary_image_explicit_layers-layer.tar" "/app/binary/binary" "true"
check "binary_image_explicit_layers-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/binary/binary.R" "true"
check "binary_image_explicit_layers-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/packages/exampleA/lib/exampleA/DESCRIPTION" "true"
check "binary_image_explicit_layers-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/packages/exampleB/lib/exampleB/DESCRIPTION" "true"
check "binary_image_explicit_layers-layer.tar" "./app/binary/binary.runfiles/com_rules_r_tests/packages/exampleC/lib/exampleC/DESCRIPTION" "true"
check "binary_image_explicit_layers-layer.tar" "./app/binary/binary.runfiles/R_bitops/lib/bitops/DESCRIPTION" "false"
check "binary_image_explicit_layers-layer.tar" "./app/binary/binary.runfiles/R_R6/lib/R6/DESCRIPTION" "false"
check "binary_image_explicit_layers.0-layer.tar" "./app/R_bitops/lib/bitops/DESCRIPTION" "true"
check "binary_image_explicit_layers.0-layer.tar" "./app/R_R6/lib/R6/DESCRIPTION" "false"
check "binary_image_explicit_layers.1-layer.tar" "./app/R_bitops/lib/bitops/DESCRIPTION" "false"
check "binary_image_explicit_layers.1-layer.tar" "./app/R_R6/lib/R6/DESCRIPTION" "true"

if docker --version; then
  binary_image.executable
  binary_image_explicit_layers.executable
fi

echo "SUCCESS!"
