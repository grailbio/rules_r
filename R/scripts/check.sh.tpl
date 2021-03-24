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

# Hack: We copied these files to the inst/libs directory in build.sh, let's
# ensure that the compiler can find them at link time. Note that these files
# still have the patches we made to them (e.g. through install_name_tool) in
# build.sh.
C_SO_FILES=({c_so_files})
C_SO_LD_FLAGS=""
for so_file in "${C_SO_FILES[@]:+"${C_SO_FILES[@]}"}"; do
  so_file_name="$(basename "${so_file}")"
  if [[ "$(uname)" == "Darwin" ]]; then
    C_SO_LD_FLAGS+="../inst/libs/${so_file_name} "
  elif [[ "$(uname)" == "Linux" ]]; then
    C_SO_LD_FLAGS+="-L../inst/libs -l:${so_file_name} "
  fi
done
if [[ "$(uname)" == "Linux" ]]; then
  #shellcheck disable=SC2016
  C_SO_LD_FLAGS+="-Wl,-rpath,"\''$$ORIGIN'\'" "
fi

C_LIBS_FLAGS="{c_libs_flags}"
C_CPP_FLAGS="{c_cpp_flags}"
export PKG_LIBS="${C_SO_LD_FLAGS}${C_LIBS_FLAGS//_EXEC_ROOT_/${EXEC_ROOT}/}"
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

if [[ "{pkg_src_archive}" != "{pkg_name}.tar.gz" ]]; then
  ln -s "{pkg_src_archive}" "{pkg_name}.tar.gz"
fi
exec {R} CMD check {check_args} "{pkg_name}.tar.gz"
