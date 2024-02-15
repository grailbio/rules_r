# Copyright 2022 The Bazel Authors.
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

# Makevars file to use bundled LLVM toolchain w/ GNU extensions.

# This is intended to be used as the site-wide Makevars file and contains the
# necessary flags for build reproducibility.

# This file uses the GNU C/C++ extensions which are assumed by some third-party
# packages (like processx), so we use this as the site-wide default.

# Even though we are using the LLVM toolchain from bazel, the GNU extensions
# come from the shared libraries installed on the host system, so there is
# some dependency on the host environment.

LLVM_BIN = _EXEC_ROOT_external/llvm_toolchain_llvm/bin/

# Mirror the default compiler flags available through:
# echo CC CXX | xargs -n1 R CMD config
CC = ${LLVM_BIN}clang -std=gnu99 -std=gnu11
CXX = ${LLVM_BIN}clang++ -std=gnu++14

CXX98 = ${LLVM_BIN}clang++
CXX11 = ${LLVM_BIN}clang++
CXX14 = ${LLVM_BIN}clang++
CXX17 = ${LLVM_BIN}clang++

# Reproducibility flags copied from @com_grail_rules_r_makevars_linux
CPPFLAGS += "-Wno-builtin-macro-redefined" \
  "-D__DATE__=\"redacted\"" \
  "-D__TIMESTAMP__=\"redacted\"" \
  "-D__TIME__=\"redacted\"" \
  "-fdebug-prefix-map=_EXEC_ROOT_=" \
  "-fmacro-prefix-map=_EXEC_ROOT_=" \
  "-ffile-prefix-map=_EXEC_ROOT_=" \
  "-no-canonical-prefixes" \

# Following flags should be enabled if switching to gcc:
# CPPFLAGS += -fno-canonical-system-headers
