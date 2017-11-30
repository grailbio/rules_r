# Copyright 2017 GRAIL, Inc.
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

package(default_visibility = ["//visibility:public"])

# Generate the Makevars file for a non-default brew prefix.
# Note that the generated file is cached after the first run.
# To pick up any changes in the system, run `bazel clean`.
genrule(
    name = "Makevars.darwin.genrule",
    srcs = ["Makevars.darwin.tpl"],
    outs = ["Makevars.darwin.generated"],
    cmd = """
    if [[ $$(uname -s) != "Darwin" ]]; then
      touch $@
      exit
    fi

    export HOME=/tmp  # Needed for Homebrew.
    # Prefer brew clang if available.
    CC=""
    CPPFLAGS=""
    LDFLAGS=""
    OPENMP_FLAGS=""
    if brew ls --versions llvm > /dev/null 2>/dev/null; then
      LLVM_PREFIX="$$(realpath -e $$(brew --prefix llvm))"
      CC="$${LLVM_PREFIX}/bin/clang"
      CPPFLAGS="-I$${LLVM_PREFIX}/include"
      LDFLAGS="-L$${LLVM_PREFIX}/lib"
      OPENMP_FLAGS="-fopenmp"
    elif command -v clang > /dev/null; then
      CC=$$(command -v clang)
    else
      echo "WARNING: clang not found"
      touch $@
      exit
    fi

    GFORTRAN=""
    if command -v gfortran > /dev/null; then
      GFORTRAN=$$(command -v gfortran)
    elif brew ls --versions gcc > /dev/null 2>/dev/null; then
      GFORTRAN=$$(realpath -e $$(brew --prefix gcc))/bin/gfortran
    else
      echo "WARNING: gfortran not found"
      touch $@
      exit
    fi

    # Find the version directory by looking for libgfortran.dylib in subdirectories.
    GCC_LIB_PATH=""
    if [[ -n "$${GFORTRAN}" ]]; then
      GCC_LIB_PATH=$${GFORTRAN/%\/bin\/gfortran/}/lib/gcc
      LIB=$$(find -L $${GCC_LIB_PATH} -name 'libgfortran.dylib' -maxdepth 2 | tail -n1)

      if [[ -z $${LIB} ]]; then
        echo "WARNING: libgfortran not found"
        touch $@
        exit
      fi
      GCC_LIB_PATH=$$(dirname $${LIB})
    fi

    subst=(
      's|@CC@|'"$${CC}"'|g;'
      's|@CPPFLAGS@|'"$${CPPFLAGS}"'|g;'
      's|@LDFLAGS@|'"$${LDFLAGS}"'|g;'
      's|@GFORTRAN@|'"$${GFORTRAN}"'|g;'
      's|@GCC_LIB_PATH@|'"$${GCC_LIB_PATH}"'|g;'
      's|@OPENMP_FLAGS@|'"$${OPENMP_FLAGS}"'|g;'
    )
    sed -e "$${subst[*]}" $< > $@
    """,
)

exports_files([
    "Makevars.darwin",
    "Makevars.linux",
    "configure.empty",
])
