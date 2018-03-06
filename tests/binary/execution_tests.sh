#!/bin/bash

# Copyright Copyright 2018 The Bazel Authors.
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

set -eou pipefail

# The rule can be executed with bazel run
bazel run //binary | grep -q yDja77yb
bazel run //binary:binary_shebang | grep -q yDja77yb

# Or standalone
bazel-bin/binary/binary | grep -q yDja77yb
bazel-bin/binary/binary_shebang | grep -q yDja77yb

# And arguments can be passed
bazel run //binary:binary_shebang -- hello world | grep "hello world" > /dev/null