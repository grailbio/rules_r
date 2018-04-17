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

START_DIR=$(pwd)

fatal() {
  >&2 echo "$@"
  exit 1
}

# TODO: Revise after https://github.com/bazelbuild/bazel/issues/4054
cd_runfiles() {
  # Moving to the runfiles directory is necessary because source files
  # will not be present in exec root.
  RUNFILES_DIR="${RUNFILES_DIR:-"${TEST_SRCDIR:-"${BASH_SOURCE[0]}.runfiles"}"}"
  cd "${RUNFILES_DIR}" || \
    fatal "Runfiles directory could not be located."
  export RUNFILES_DIR=$(pwd -P)
  cd "{workspace_name}" || \
    fatal "Workspace not found within runfiles directory."
}
cd_runfiles
PWD=$(pwd -P)

# Export environment variables, if any.
{export_env_vars}

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

# Export path to tool needed for the test.
{tools_export_cmd}

R_LIBS="{lib_dirs}"
R_LIBS="${R_LIBS//_EXEC_ROOT_/$PWD/}"
export R_LIBS
export R_LIBS_USER=dummy

if [[ -x "{src}" ]]; then
  "./{src}" "$@"
else
  {Rscript} {Rscript_args} "{src}"
fi

cd "${START_DIR}" || fatal "Could not go back to start directory."
