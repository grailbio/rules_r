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

set -euxo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# r_binary related tests.  Run these individually most layered target first,
# before building everything so we don't have runfiles built for wrapped
# targets. The alternative is to clean the workspace before each test.
bazel clean
bazel run //binary:binary_sh_test
bazel-bin/binary/binary_sh_test
bazel run //binary:binary_r_test
bazel-bin/binary/binary_r_test
bazel run //binary
bazel-bin/binary/binary

export BAZEL_TEST_OPTS=(
"--color=yes"
"--show_progress_rate_limit=30"
"--keep_going"
"--test_output=errors"
)

bazel test "${BAZEL_TEST_OPTS[@]}" //...

coverage/coverage_test.sh
