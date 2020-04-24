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
# Value of BAZELISK_GITHUB_TOKEN is set as a secret on Travis.
readonly url="https://github.com/bazelbuild/bazelisk/releases/download/v1.4.0/bazelisk-${os}-amd64"
bazel="${TMPDIR:-/tmp}/bazelisk"
readonly bazel

if ! [[ -x "${bazel}" ]]; then
  curl -L -sSf -o "${bazel}" "${url}"
  chmod a+x "${bazel}"
fi

# Exported for scripts that will source this file.
bazel_test_opts=(
"--color=yes"
"--show_progress_rate_limit=30"
"--keep_going"
"--test_output=errors"
)
