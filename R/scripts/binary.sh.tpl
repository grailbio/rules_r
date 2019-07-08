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

fatal() {
  >&2 echo "$@"
  exit 1
}

# Make bazel status variables available as environment variables, if available.
if [[ -e ./stable-status.txt ]]; then
  e="$(cat ./{stable,volatile}-status.txt | sed -e 's/\([^[:space:]]*\) \(.*\)/export \1=\"\2\"/')"
  eval "${e}"
fi

# Export environment variables, if any.
{export_env_vars}

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

START_DIR=$(pwd)

# Moving to the runfiles directory is necessary because source files
# will not be present in exec root.
# rlocation function from runfiles.bash is only good for giving paths from the
# manifest, so we need our own logic to make sure we are in a runfiles
# directory if we are not already there.
cd_runfiles() {
  # Do nothing if it looks like we are already in a runfiles directory of a workspace.
  if [[ "${PWD}" == *".runfiles/$(basename "${PWD}")" ]]; then
    return
  fi

  # Assume the runfiles directory is next to us.
  RUNFILES_DIR="${RUNFILES_DIR:-"${TEST_SRCDIR:-"${BASH_SOURCE[0]}.runfiles"}"}"
  cd "${RUNFILES_DIR}" || \
    fatal "Runfiles directory could not be located."
  export RUNFILES_DIR=$(pwd -P)
  cd "{workspace_name}" || \
    fatal "Workspace not found within runfiles directory."
}
cd_runfiles
PWD=$(pwd -P)

# Export path to tool needed for the test.
{tools_export_cmd}

R_LIBS="{lib_dirs}"
R_LIBS="${R_LIBS//_EXEC_ROOT_/$PWD/}"
export R_LIBS
export R_LIBS_USER=dummy

src_path="../{workspace_name}/{src}"

if "{ignore_execute_permissions}" || ! [[ -x "${src_path}" ]]; then
  {Rscript} {Rscript_args} "${src_path}" {script_args} "$@"
else
  "${src_path}" {script_args} "$@"
fi

cd "${START_DIR}" || fatal "Could not go back to start directory."
