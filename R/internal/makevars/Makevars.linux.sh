#!/bin/bash
# Copyright 2021 The Bazel Authors.
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

if [[ $(uname -s) != "Linux" ]]; then
  exit
fi

warn() {
  >&2 echo "WARNING: $*"
}

error() {
  >&2 echo "ERROR: $*"
}

# Allow user to specify where to find R.
if ! [[ "${BAZEL_R_HOME:-}" ]]; then
  BAZEL_R_HOME="$(R RHOME)"
fi

# Determine if the default compiler is gcc.
is_gcc=0
cc="$("${BAZEL_R_HOME}/bin/R" CMD config CC)"
cc_version="$(${cc} --version | head -n1)"
if [[ "${cc_version}" == "gcc"* ]]; then
  is_gcc=1
fi

cppflags=""
if (( is_gcc )); then
  # Additional gcc specific flags.
  cppflags="-fno-canonical-system-headers"
fi

subst=(
's|@CPPFLAGS@|'"${cppflags}"'|g;'
)
sed -e "${subst[*]}"
