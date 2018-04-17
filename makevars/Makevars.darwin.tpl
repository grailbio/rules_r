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
F77=@GFORTRAN@
FC=${F77}
FLIBS=-L@GCC_LIB_PATH@ -lgfortran -lquadmath -lm

CC = @CC@
CXX = @CC@
CPPFLAGS = @CPPFLAGS@
LDFLAGS = @LDFLAGS@

# Apple's compilers from Command Line Tools do not have OpenMP support
SHLIB_OPENMP_CFLAGS = @OPENMP_FLAGS@
SHLIB_OPENMP_CXXFLAGS = @OPENMP_FLAGS@
