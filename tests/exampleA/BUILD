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

load("@com_grail_rules_r//R:defs.bzl", "r_pkg")

r_pkg(
    name = "exampleA",
    srcs = glob(
        ["**"],
        exclude = [
            "BUILD",
        ],
    ),
    # Package metadata test in //stamping:pkg_metadata
    metadata = {
        "VAR": "{VAR}",
        "STABLE_VAR": "{STABLE_VAR}",
    },
    visibility = [
        "//exampleB:__pkg__",
        "//stamping:__pkg__",
    ],
)
