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

exports_files([
    "binary.sh.tpl",
    "build_pkg_bin.sh",
    "build_pkg_common.sh",
    "build_pkg_src.sh",
    "build_binary.sh",
    "check.sh.tpl",
    "collect_coverage.R",
    "instrument.R",
    "lcov_merger.sh",
    "library.sh.tpl",
    "merge_test_files.sh",
    "render.R.tpl",
    "stamp_description.sh",
    "system_state.sh",
    "test.sh.tpl",
])

cc_binary(
    name = "flock",
    srcs = ["flock.c"],
    visibility = ["//visibility:public"],
)
