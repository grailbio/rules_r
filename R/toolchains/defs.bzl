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
"""This module implements the toolchain system for `rules_r`.

Direct interaction with the toolchain system is advanced use.
Interacting with the toolchain system through `r_rules_dependencies` should be
enough for most cases.
"""

load("@com_grail_rules_r//R/toolchains:toolchains.bzl", "define_r_toolchain", "r_toolchain")
load("@com_grail_rules_r//R/toolchains:local.bzl", "local_r_toolchain")
