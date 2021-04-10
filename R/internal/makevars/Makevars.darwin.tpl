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

# macOS specific overrides
# See https://cran.r-project.org/doc/manuals/R-admin.html#macOS-packages

# gfortran paths when installed as part of `brew install gcc`
# If F77 is empty, it is because gfortran was not found.
# If FLIBS search path is empty, it is because libgfortran was not found.
F77=@GFORTRAN@
FC=${F77}
FLIBS=-L@GCC_LIB_PATH@ -lgfortran -lquadmath -lm

CC = @CC@
CXX = @CXX@
CPPFLAGS = @CPPFLAGS@
LDFLAGS = @LDFLAGS@

# Flags for reproducible builds.
# See http://blog.llvm.org/2019/11/deterministic-builds-with-clang-and-lld.html
# Remember to set ZERO_AR_DATE=1 in your environment.
CPPFLAGS += "-Wno-builtin-macro-redefined" \
  "-D__DATE__=\"redacted\"" \
  "-D__TIMESTAMP__=\"redacted\"" \
  "-D__TIME__=\"redacted\"" \
  "-fdebug-prefix-map=_EXEC_ROOT_=" \
  "-fmacro-prefix-map=_EXEC_ROOT_=" \
  "-ffile-prefix-map=_EXEC_ROOT_=" \
  "-no-canonical-prefixes" \

# Apple's compilers from Command Line Tools do not have OpenMP support
SHLIB_OPENMP_CFLAGS = @OPENMP_FLAGS@
SHLIB_OPENMP_CXXFLAGS = @OPENMP_FLAGS@
