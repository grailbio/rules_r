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

# This script is intended to be sourced as a library, and makes available a
# bazel env var.

os="$(uname -s | tr "[:upper:]" "[:lower:]")"
readonly os

# Use bazelisk to catch migration problems.
readonly url="https://github.com/bazelbuild/bazelisk/releases/download/v1.11.0/bazelisk-${os}-amd64"
bazel="${TMPDIR:-/tmp}/bazelisk"
readonly bazel

if ! [[ -x "${bazel}" ]]; then
  curl -L -sSf -o "${bazel}" "${url}"
  chmod a+x "${bazel}"
fi

# Exported for scripts that will source this file.
bazel_build_opts=(
"--color=yes"
"--show_progress_rate_limit=30"
"--experimental_convenience_symlinks=ignore" # symlinks in nested workspaces may cause infinite loop
)

# packages/exampleC:cc_lib needs R headers in the system include directories.
# For Unix toolchains in general, we can provide the path as an env var.
# For Xcode toolchains, /Library/ is part of cxx_builtin_include_directories from bazel 4.0.0.
# https://cs.opensource.google/bazel/bazel/+/master:tools/cpp/osx_cc_configure.bzl;l=43;drc=b4b0c321910bc968736ef48e8140528ea7d323cd
if [[ "$(uname)" == "Darwin" ]]; then
  export CPLUS_INCLUDE_PATH=/Library/Frameworks/R.framework/Headers
elif [[ "$(uname)" == "Linux" ]]; then
  export CPLUS_INCLUDE_PATH=/usr/share/R/include
fi

bazel_test_opts=("${bazel_build_opts[@]}")
bazel_test_opts+=(
"--keep_going"
"--test_output=errors"
)
