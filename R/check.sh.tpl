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

# Export path to tool needed for the test.
{tools_export_cmd}

C_LIBS_FLAGS="{c_libs_flags}"
C_CPP_FLAGS="{c_cpp_flags}"
export PKG_LIBS="${C_LIBS_FLAGS//_EXEC_ROOT_/$PWD/}"
export PKG_CPPFLAGS="${C_CPP_FLAGS//_EXEC_ROOT_/$PWD/}"
export R_MAKEVARS_USER="${PWD}/{r_makevars_user}"

R_LIBS="{lib_dirs}"
R_LIBS="${R_LIBS//_EXEC_ROOT_/$PWD/}"
export R_LIBS
export R_LIBS_USER=dummy

exec R CMD check {check_args} {pkg_src_archive}
