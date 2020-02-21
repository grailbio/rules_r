# Copyright 2020 The Bazel Authors.
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

load("@com_grail_rules_r//R:defs.bzl", "r_test")

r_test(
    name = "stamp_test",
    src = "stamp_test.sh",
    stamp = True,
)

r_test(
    name = "nostamp_test",
    src = "nostamp_test.sh",
)

r_test(
    name = "pkg_metadata",
    src = "pkg_metadata.R",
    deps = [
        "//exampleA",
        "//exampleB",
    ],
)
