#!/bin/bash
# Copyright 2020 The Bazel Authors.
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

fail() {
  echo "$@"
  exit 1
}

if ! grep "^VAR" "volatile-status.txt"; then
  fail "volatile status file expected"
fi
if ! [[ "${VAR:-}" ]]; then
  fail "volatile status var expected as env var"
fi

if ! grep "^STABLE_VAR" "stable-status.txt"; then
  fail "stable status file expected and not empty"
fi
if ! [[ "${STABLE_VAR:-}" ]]; then
  fail "stable status var expected as env var"
fi
