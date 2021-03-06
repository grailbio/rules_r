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

cd "$(dirname "${BASH_SOURCE[0]}")"

source "./setup-bazel.sh"

# r_binary related tests.  Run these individually most layered target first,
# before building everything so we don't have runfiles built for wrapped
# targets. The alternative is to clean the workspace before each test.
set -x
"${bazel}" clean
"${bazel}" run //binary:binary_sh_test
bazel-bin/binary/binary_sh_test
"${bazel}" run //binary:binary_r_test
bazel-bin/binary/binary_r_test
"${bazel}" run //binary
bazel-bin/binary/binary
set +x

"${bazel}" test "${bazel_test_opts[@]}" //...

coverage/coverage_test.sh

repro/repro_test.sh
