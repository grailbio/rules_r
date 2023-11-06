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
marker_failed="${tmpdir}/failed"
marker_1="${tmpdir}/1"
marker_2="${tmpdir}/2"
marker_3="${tmpdir}/3"
lock_1="${tmpdir}/lock1"
lock_2="${tmpdir}/lock2"

mkdir -p "${tmpdir}"
cleanup() {
  rm -r "${tmpdir}"
}
trap 'cleanup' INT HUP QUIT TERM EXIT

fail() {
  >&2 echo "$@"
  touch "${marker_failed}"
  exit 1
}

mark() {
  touch "$1"
}

wait_on_marker() {
  while ! test -e "$1"; do
    sleep 0.01
  done
}

pids=()
# Acquire a lock on the first file in a subshell for some time.
(
  exec 200>"${lock_1}"
  external/com_rules_r/R/scripts/flock 200 || fail "unable to acquire lock 1 in proc 1"
  mark "${marker_1}"
  wait_on_marker "${marker_2}"  # Wait until the second subshell has tried acquiring the lock.
  exec 200>&- # Close the file descriptor; releasing the lock.
  mark "${marker_3}"
) &
pids+=($!)

# Try to acquire a lock on the first file, fail on first attempt, and then succeed after waiting.
(
  wait_on_marker "${marker_1}"  # Wait until the first subshell has acquired the lock.
  exec 200>"${lock_1}"
  external/com_rules_r/R/scripts/flock 200 && fail "should not have acquired lock 1 in proc 2"
  mark "${marker_2}"
  wait_on_marker "${marker_3}"
  external/com_rules_r/R/scripts/flock 200 || fail "unable to acquire lock 1 in proc 2"
) &
pids+=($!)

# Try to acquire a lock on a different file, and succeed immediately.
(
  exec 200>"${lock_2}"
  external/com_rules_r/R/scripts/flock 200 || fail "unable to acquire lock 2 in proc 3"
) &
pids+=($!)

wait # Wait on all children; return code is always 0.
! test -e "${marker_failed}"
