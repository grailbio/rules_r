#!/bin/bash
# Copyright 2018 GRAIL, Inc.
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
test -d "${PKG_TESTS_DIR}"

if ! compgen -G "${PKG_TESTS_DIR}/"'*.[Rr]' >/dev/null; then
  echo 'No test files found.'
  exit 1
fi

# Export path to tool needed for the test.
{tools_export_cmd}

R_LIBS="{lib_dirs}"
R_LIBS="${R_LIBS//_EXEC_ROOT_/$PWD/}"
export R_LIBS
export R_LIBS_USER=dummy

if [[ ${TEST_TMPDIR:-} ]]; then
  readonly IS_TEST_SANDBOX=1
else
  readonly IS_TEST_SANDBOX=0
fi
(( IS_TEST_SANDBOX )) || TEST_TMPDIR=$(mktemp -d)

# Copy the tests to a writable directory.
cp -LR "${PKG_TESTS_DIR}/"* ${TEST_TMPDIR}
pushd ${TEST_TMPDIR} >/dev/null

cleanup() {
  popd >/dev/null
  (( IS_TEST_SANDBOX )) || rm -rf "${TEST_TMPDIR}"
}

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

cleanup
