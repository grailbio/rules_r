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

set -exuo pipefail

tmpdir="$(mktemp -d)"

fail() {
  >&2 echo "$@"
  exit 1
}

pids=()
# Acquire a lock in a subshell for some time.
(
  exec 200>"${tmpdir}/1"
  external/com_grail_rules_r/R/scripts/flock 200 || fail "unable to acquire lock 1 in proc 1"
  sleep 1
) &
pids+=($!)

# Try to acquire a lock on the first file, fail on first attempt, and then succeed after waiting.
(
  exec 200>"${tmpdir}/1"
  external/com_grail_rules_r/R/scripts/flock 200 && fail "should not have acquired lock 1 in proc 2"
  sleep 1.5
  external/com_grail_rules_r/R/scripts/flock 200 || fail "unable to acquire lock 1 in proc 2"
) &
pids+=($!)

# Try to acquire a lock on a different file, and succeed immediately.
(
  exec 200>"${tmpdir}/2"
  external/com_grail_rules_r/R/scripts/flock 200 || fail "unable to acquire lock 2 in proc 3"
  sleep 2
) &
pids+=($!)

# The sleep times in all subshells guarantee this order of completion.
for pid in "${pids[@]}"; do
  # This will fail if the subshell failed.
  wait "${pid}"
done
