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

# If RUNFILES_DIR is set, we must be running under R_TEST, and converse.
if ! [[ "${TEST_SRCDIR:-}" ]]; then
  ! [[ "${RUNFILES_DIR:-}" ]] || "${R_TEST:-false}"
  ! "${R_TEST:-false}" || [[ "${RUNFILES_DIR:-}" ]]
fi

if ! [[ "${RUNFILES_DIR:-}" ]]; then
  # If running under sh_test, we must move to the runfiles directory by ourselves.
  cd "${BASH_SOURCE[0]}.runfiles"
  RUNFILES_DIR=$(pwd -P)
  export RUNFILES_DIR
  cd "com_grail_rules_r_tests"
fi

# shortpath to binary from runfiles dir.
BINARY="../com_grail_rules_r_tests/binary"

if ! "${BINARY}"; then
  echo "Binary should have passed."
  exit 1
fi

if ! "${BINARY}" exampleA; then
  echo "Binary should have passed with argument."
  exit 1
fi

if "${BINARY}" RProtoBuf 2>/dev/null; then
  echo "Binary should have failed."
  exit 1
fi
