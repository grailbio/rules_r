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

BREW=false
while getopts "b" opt; do
  case "$opt" in
    "b") BREW=true;;
    "?") error "invalid option: -$OPTARG"; exit 1;;
  esac
done

# Override the flag value with user-provided env var.
BREW="${BAZEL_R_HOMEBREW:-"${BREW}"}"

sysroot="$(xcrun --show-sdk-path)"

export HOME=/tmp  # Needed for Homebrew.
# Prefer brew clang if available, for openmp support.
CC=""
CXX=""
CPPFLAGS="-isysroot ${sysroot} "
LDFLAGS="-isysroot ${sysroot} "
OPENMP_FLAGS=""
if $BREW && brew ls --versions llvm > /dev/null 2>/dev/null; then
  LLVM_PREFIX="$(brew --prefix llvm)"
  CC="${LLVM_PREFIX}/bin/clang"
  CXX="${LLVM_PREFIX}/bin/clang++"
  CPPFLAGS+="-I${LLVM_PREFIX}/include"
  LDFLAGS+="-L${LLVM_PREFIX}/lib"
  OPENMP_FLAGS+="-fopenmp"
  # Symlink llvm-cov from Homebrew next to the Makevars file so we can
  # reference as an additional tool in the local toolchain later.
  if [[ -x "${LLVM_PREFIX}/bin/llvm-cov" ]]; then
    ln -s "${LLVM_PREFIX}/bin/llvm-cov" "llvm-cov"
  fi
elif command -v clang > /dev/null; then
  CC=$(command -v clang)
  CXX=$(command -v clang++)
else
  warn "clang not found"
  exit
fi

GFORTRAN=""
if $BREW && brew ls --versions gcc > /dev/null 2>/dev/null; then
  GFORTRAN="$(brew --prefix gcc)/bin/gfortran"
elif command -v gfortran > /dev/null; then
  GFORTRAN=$(command -v gfortran)
else
  warn "gfortran not found"
  exit
fi

# Find the version directory by looking for libgfortran.dylib in subdirectories.
GCC_LIB_PATH=""
if [[ -n "${GFORTRAN}" ]]; then
  GCC_LIB_PATH=${GFORTRAN/%\/bin\/gfortran/}/lib/gcc
  LIB=$(find -L "${GCC_LIB_PATH}" -name 'libgfortran.dylib' -maxdepth 2 | tail -n1)

  if [[ -z ${LIB} ]]; then
    warn "libgfortran not found"
    exit
  fi
  GCC_LIB_PATH=$(dirname "${LIB}")
fi

subst=(
's|@CC@|'"${CC}"'|g;'
's|@CXX@|'"${CXX}"'|g;'
's|@CPPFLAGS@|'"${CPPFLAGS}"'|g;'
's|@LDFLAGS@|'"${LDFLAGS}"'|g;'
's|@GFORTRAN@|'"${GFORTRAN}"'|g;'
's|@GCC_LIB_PATH@|'"${GCC_LIB_PATH}"'|g;'
's|@OPENMP_FLAGS@|'"${OPENMP_FLAGS}"'|g;'
)
sed -e "${subst[*]}"
