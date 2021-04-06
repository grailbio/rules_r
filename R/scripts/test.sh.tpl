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

PWD=$(pwd -P)

# Export environment variables, if any.
{export_env_vars}

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

readonly PKG_TESTS_DIR="{pkg_tests_dir}"
if ! [[ -d "${PKG_TESTS_DIR}" ]]; then
  echo 'No tests dir found.'
  exit 1
fi

if ! compgen -G "${PKG_TESTS_DIR}/"'*.[Rr]' >/dev/null; then
  echo 'No test files found.'
  exit 1
fi

# Export path to tool needed for the test.
{tools_export_cmd}

RUNFILES_DIR="${PWD}"  # Capture before switching to TEST_TMPDIR
export RUNFILES_DIR  # For coverage collection

if [[ ${TEST_TMPDIR:-} ]]; then
  readonly IS_TEST_SANDBOX=1
else
  readonly IS_TEST_SANDBOX=0
fi
(( IS_TEST_SANDBOX )) || TEST_TMPDIR=$(mktemp -d)

cleanup() {
  popd > /dev/null 2>&1 || true
  (( IS_TEST_SANDBOX )) || rm -rf "${TEST_TMPDIR}"
}
trap 'cleanup; exit 1' INT HUP QUIT TERM EXIT

export R_LIBS=dummy
R_LIBS_USER="${TEST_TMPDIR}/.bzl_r_lib"
export R_LIBS_USER
mkdir "${R_LIBS_USER}"

r_libs="{lib_dirs}"
r_libs="${r_libs//_EXEC_ROOT_/$PWD/}"
(IFS=":"; for lib in ${r_libs}; do ln -s "${lib}/"* "${R_LIBS_USER}"; done)

# Copy the tests to a writable directory.
cp -LR "${PKG_TESTS_DIR}/"* ${TEST_TMPDIR}
pushd ${TEST_TMPDIR} >/dev/null

# Set up the code coverage environment
if "{collect_coverage}"; then
  export R_COVR=true  # As exported by covr
  export GCOV_PREFIX_STRIP=0  # We strip later depending on the source of the .gcda file.
  export GCOV_EXIT_AT_ERROR=1
fi

if ls *.Rin > /dev/null 2>&1; then
  for SCRIPT in *.Rin; do
    if ! {Rscript} "${SCRIPT}"; then
      cleanup
      exit 1
    fi
  done
fi

if ls *.[Rr] > /dev/null 2>&1; then
  for SCRIPT in *.[Rr]; do
    if ! {Rscript} "${SCRIPT}"; then
      cleanup
      exit 1
    fi
  done
fi

popd > /dev/null

if "{collect_coverage}"; then
  {Rscript} "${RUNFILES_DIR}/{collect_coverage.R}"
fi

trap - EXIT
cleanup
