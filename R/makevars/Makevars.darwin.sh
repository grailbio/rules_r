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

if [[ $(uname -s) != "Darwin" ]]; then
  exit
fi

warn() {
  >&2 echo "WARNING: $*"
}

error() {
  >&2 echo "ERROR: $*"
}

brew=false
clang_installed_dir=""
while getopts "bc:" opt; do
  case "$opt" in
    "b") brew=true;;
    "c") clang_installed_dir="$OPTARG";;
    "?") error "invalid option: -$OPTARG"; exit 1;;
  esac
done

# Override the flag value with user-provided env var.
brew="${BAZEL_R_HOMEBREW:-"${brew}"}"

sysroot="$(xcrun --show-sdk-path)"

export HOME=/tmp  # Needed for Homebrew.
# Prefer brew clang if available, for openmp support.
CC=""
CXX=""
CPPFLAGS="-isysroot ${sysroot} "
LDFLAGS="-isysroot ${sysroot} "
OPENMP_FLAGS=""
if [[ "${clang_installed_dir}" ]]; then
  CC="${clang_installed_dir}/clang"
  CXX="${clang_installed_dir}/clang++"
elif ${brew} && brew ls --versions llvm > /dev/null 2>/dev/null; then
  llvm_prefix="$(brew --prefix llvm)"
  CC="${llvm_prefix}/bin/clang"
  CXX="${llvm_prefix}/bin/clang++"
  CPPFLAGS+="-I${llvm_prefix}/include"
  LDFLAGS+="-L${llvm_prefix}/lib"
  OPENMP_FLAGS+="-fopenmp"
  # Symlink llvm-cov from Homebrew next to the Makevars file so we can
  # reference as an additional tool in the local toolchain later.
  if [[ -x "${llvm_prefix}/bin/llvm-cov" ]]; then
    ln -s -f "${llvm_prefix}/bin/llvm-cov" "llvm-cov"
  fi
elif command -v clang > /dev/null; then
  CC=$(command -v clang)
  CXX=$(command -v clang++)
else
  warn "clang not found"
  exit
fi

# gfortran paths when installed as part of `brew install gcc`
HOMEBREW_GFORTRAN="# gfortran not found"
if ${brew} && brew ls --versions gcc > /dev/null 2>/dev/null; then
  gfortran="$(brew --prefix gcc)/bin/gfortran"
  gcc_lib_path="$(brew --prefix gcc)/lib/gcc"
  if [[ -d "${gcc_lib_path}" ]]; then
    libgfortran_dir=$(find -L "${gcc_lib_path}" -name 'libgfortran.dylib' -maxdepth 2 -exec dirname {} \; | tail -n1)
  fi
  if [[ "${libgfortran_dir:-}" ]]; then
    HOMEBREW_GFORTRAN="F77=${gfortran}\nFC=\${F77}\nFLIBS=-L${libgfortran_dir} -lgfortran -lquadmath -lm"
  fi
fi

subst=(
's|@CC@|'"${CC}"'|g;'
's|@CXX@|'"${CXX}"'|g;'
's|@CPPFLAGS@|'"${CPPFLAGS}"'|g;'
's|@LDFLAGS@|'"${LDFLAGS}"'|g;'
's|@HOMEBREW_GFORTRAN@|'"${HOMEBREW_GFORTRAN}"'|g;'
's|@OPENMP_FLAGS@|'"${OPENMP_FLAGS}"'|g;'
)
sed -e "${subst[*]}"
