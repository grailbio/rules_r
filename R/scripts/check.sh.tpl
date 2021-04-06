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
c_so_files="{c_so_files}"
if [[ "${c_so_files}" ]]; then
  c_so_ld_flags=""
  for so_file in ${c_so_files}; do
    so_file_name="$(basename "${so_file}")"
    if [[ "$(uname)" == "Darwin" ]]; then
      c_so_ld_flags+="../inst/libs/${so_file_name} "
    elif [[ "$(uname)" == "Linux" ]]; then
      c_so_ld_flags+="-L../inst/libs -l:${so_file_name} "
    fi
  done
  if [[ "$(uname)" == "Linux" ]]; then
    #shellcheck disable=SC2016
    c_so_ld_flags+="-Wl,-rpath,"\''$$ORIGIN'\'" "
  fi
fi

tmp_mkvars="$(mktemp)"
export R_MAKEVARS_SITE="${tmp_mkvars}"
if [[ "{r_makevars_site}" ]]; then
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/{r_makevars_site}" > "${tmp_mkvars}"
fi
if [[ "{r_makevars_user}" ]]; then
  tmp_mkvars="$(mktemp)"
  sed -e "s@_EXEC_ROOT_@${EXEC_ROOT}/@" "${EXEC_ROOT}/{r_makevars_user}" > "${tmp_mkvars}"
  export R_MAKEVARS_USER="${tmp_mkvars}"
fi

# Get any flags from cc_deps for this package and append to site Makevars file.
# Similar behavior as in build.sh.
c_libs_flags="{c_libs_flags}"
c_cpp_flags="{c_cpp_flags}"
pkg_libs="${c_so_ld_flags}${c_libs_flags//_EXEC_ROOT_/${EXEC_ROOT}/}"
pkg_cppflags="${c_cpp_flags//_EXEC_ROOT_/${EXEC_ROOT}/}"
if [[ "${pkg_libs}" ]] || [[ "${pkg_cppflags}" ]]; then
  echo "
PKG_LIBS += ${pkg_libs}
PKG_CPPFLAGS += ${pkg_cppflags}
PKG_FCFLAGS += ${pkg_cppflags}  # Fortran 90/95
PKG_FFLAGS += ${pkg_cppflags}   # Fortran 77
" >> "${R_MAKEVARS_SITE}"
fi

export R_LIBS=dummy
R_LIBS_USER="$(mktemp -d)"
export R_LIBS_USER
cleanup() {
  rm -rf "${R_LIBS_USER}"
}
trap 'cleanup; exit 1' INT HUP QUIT TERM EXIT

r_libs="{lib_dirs}"
r_libs="${r_libs//_EXEC_ROOT_/$PWD/}"
(IFS=":"; for lib in ${r_libs}; do ln -s "${lib}/"* "${R_LIBS_USER}"; done)

# Set HOME for pandoc for building vignettes.
TMP_HOME="/tmp/bazel/R/home"
mkdir -p "${TMP_HOME}"
export HOME="${TMP_HOME}"

if [[ "{pkg_src_archive}" != "{pkg_name}.tar.gz" ]]; then
  ln -s "{pkg_src_archive}" "{pkg_name}.tar.gz"
fi

{R} CMD check {check_args} "{pkg_name}.tar.gz"

trap - EXIT
cleanup
