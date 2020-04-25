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

EXEC_ROOT=$(pwd -P)

# Export environment variables, if any.
{export_env_vars}

if "${BAZEL_R_DEBUG:-"false"}"; then
  set -x
fi

# Export path to tool needed for the test.
{tools_export_cmd}

# Help find any .so deps in bazel's execution root.
# This is independent of how we install the package in build.sh because this
# test is done through the source archive which can not contain any .so files
# in src subdirectory, and so the .so files have to be found outside the
# package.
C_SO_FILES=({c_so_files})
SO_DIRS=()
for so in "${C_SO_FILES[@]:+"${C_SO_FILES[@]}"}"; do
  SO_DIRS+=("${EXEC_ROOT}/$(dirname "${so}")")
done
LD_LIBRARY_PATH+=$(IFS=:; echo "${SO_DIRS[*]:+"${SO_DIRS[*]}"}")
export LD_LIBRARY_PATH

C_LIBS_FLAGS="{c_libs_flags}"
C_CPP_FLAGS="{c_cpp_flags}"
export PKG_LIBS="${C_LIBS_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export PKG_CPPFLAGS="${C_CPP_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"

if [[ "{r_makevars_site}" ]]; then
  tmp_mkvars="$(mktemp)"
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/{r_makevars_site}" > "${tmp_mkvars}"
  export R_MAKEVARS_SITE="${tmp_mkvars}"
fi
if [[ "{r_makevars_user}" ]]; then
  tmp_mkvars="$(mktemp)"
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/{r_makevars_user}" > "${tmp_mkvars}"
  export R_MAKEVARS_USER="${tmp_mkvars}"
fi

R_LIBS="{lib_dirs}"
R_LIBS="${R_LIBS//_EXEC_ROOT_/${EXEC_ROOT}/}"
export R_LIBS
export R_LIBS_USER=dummy

# Set HOME for pandoc for building vignettes.
TMP_HOME="/tmp/bazel/R/home"
mkdir -p "${TMP_HOME}"
export HOME="${TMP_HOME}"

exec {R} CMD check {check_args} {pkg_src_archive}
