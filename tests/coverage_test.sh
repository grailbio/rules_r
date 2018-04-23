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

# Environment variables:
# - TEST_OUTPUT: value of Bazel's "--test_output" (e.g., "errors", "all").
# - COVERAGE_REPORT_DIR: directory where the coverage report is generated
# by genhtml, or "" to output coverage to a temporary directory (for
# testing only the side effects).
# - GENHTML_Bin: path to the 'genhtml' command-line utility (part of the lcov package).
TEST_OUTPUT="${TEST_OUTPUT:-errors}"
COVERAGE_REPORT_DIR="${COVERAGE_REPORT_DIR:-}"
GENHTML_BIN="${GENHTML_BIN:-genhtml}"

expect_equal() {
  local actual
  local actual_content
  
  actual=$1
  actual_content=$(cat "${actual}")
  expected_content=$(cat)
  if [ "${actual_content}" != "${expected_content}" ]; then
    echo "==="
    echo "COVERAGE: ${actual}"
    echo "ACTUAL:"
    echo "${actual_content}"
    echo "---"
    echo "EXPECTED:"
    echo "${expected_content}"
    echo "==="
    return 1
  fi

  echo "PASSED ${actual}"
}

# LLVM and gcc deal with code coverage differently:
#
# - With LLVM, the first statement in a function body is counted double,
# and the function header is ignored.
#
# - With gcc, the function header and the first statement count as separate 
# hits, unless they are on the same line.
#
# That's why we grouped in the example the function header and the first
# statement on the same line, to lower the discrepancy between the platforms.
if [[ $(uname) == "Darwin" ]]; then
  FIRST_HIT=2
else
  FIRST_HIT=1
fi

bazel coverage //exampleD:test \
  --instrumentation_filter=//exampleD,//exampleD:cc_dep \
  --test_output=${TEST_OUTPUT}
expect_equal bazel-testlogs/exampleD/test/coverage.dat <<EOF
SF:exampleD/R/fn.R
DA:16,1
end_of_record
SF:exampleD/ccdep/ccdep.c
DA:17,${FIRST_HIT}
end_of_record
SF:exampleD/src/fn.c
DA:25,${FIRST_HIT}
DA:27,1
DA:28,1
DA:29,1
DA:31,1
DA:33,1
end_of_record
SF:exampleD/src/fn.h
DA:22,${FIRST_HIT}
end_of_record
SF:exampleD/src/lib/getCharacter.c
DA:17,${FIRST_HIT}
end_of_record
EOF

# Use genhtml to generate an html report.  This test is used
# - To assert that the generated LCOV is valid.
# - To assert that files can be resolved relative to the execroot.
if hash "${GENHTML_BIN}" 2>/dev/null; then
  (
    EXEC_ROOT=$(readlink "./bazel-$(basename "$(pwd)")")

    CLEANUP_COVERAGE_REPORT=false
    if [ -z "${COVERAGE_REPORT_DIR}" ]; then
      CLEANUP_COVERAGE_REPORT=true
      COVERAGE_REPORT_DIR=$(mktemp -d)
    fi

    if "${CLEANUP_COVERAGE_REPORT}"; then
      cleanup() {
        rm -rf "${COVERAGE_REPORT_DIR}"
      }
      trap 'cleanup; exit 1' INT HUP QUIT TERM EXIT
    fi

    PROJECT_DIR="$(pwd)"
    pushd "${EXEC_ROOT}" > /dev/null
    "${GENHTML_BIN}" "${PROJECT_DIR}/bazel-testlogs/exampleD/test/coverage.dat" \
      -o "${COVERAGE_REPORT_DIR}"
    popd > /dev/null

    if "${CLEANUP_COVERAGE_REPORT}"; then
      trap - EXIT
      cleanup
    fi
  )
fi
