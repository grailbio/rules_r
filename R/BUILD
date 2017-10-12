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
    GFORTRAN=""
    if command -v gfortran > /dev/null; then
      GFORTRAN=$$(command -v gfortran)
    elif brew --prefix gcc > /dev/null; then
      GFORTRAN=$$(realpath -e $$(brew --prefix gcc))/bin/gfortran
    else
      echo "WARNING: gfortran not found"
      touch $@
      exit
    fi

    # Find the version directory by looking for libgfortran.dylib in subdirectories.
    GCC_LIB_PATH=$${GFORTRAN/%\/bin\/gfortran/}/lib/gcc
    LIB=$$(find -L $${GCC_LIB_PATH} -name 'libgfortran.dylib' -maxdepth 2 | tail -n1)

    if [[ -z $${LIB} ]]; then
      echo "WARNING: libgfortran not found"
      touch $@
      exit
    fi
    GCC_LIB_PATH=$$(dirname $${LIB})

    subst=(
      's|@GFORTRAN@|'"$${GFORTRAN}"'|g;'
      's|@GCC_LIB_PATH@|'"$${GCC_LIB_PATH}"'|g;'
    )
    sed -e "$${subst[*]}" $< > $@
    """,
)

exports_files([
    "Makevars.darwin",
    "Makevars.linux",
    "configure.empty",
])
