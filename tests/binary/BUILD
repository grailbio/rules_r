# Copyright 2018 The Bazel R Rules Authors.
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

load("@com_grail_rules_r//R:defs.bzl", "r_binary", "r_test")

exports_files(["script.R"])

r_binary(
    name = "binary",
    src = "script.R",
    data = [
        "data.txt",
    ],
    env_vars = {
        "FOO": "bar",
    },
    rscript_args = "--default-packages=base,exampleA",
    visibility = ["//r_image:__pkg__"],
    deps = [
        "//exampleA",
        "@R_testthat//:testthat",
    ],
)

r_binary(
    name = "binary_shebang",
    src = "script.sh",
    env_vars = {
        "FOO": "bar",
    },
    deps = [
        "//exampleA",
        "@R_testthat//:testthat",
    ],
)

sh_test(
    name = "sh_test",
    size = "small",
    srcs = ["test.sh"],
    data = [":binary"],
)

r_test(
    name = "test",
    size = "small",
    src = "script.R",
    data = [
        "data.txt",
    ],
    env_vars = {
        "FOO": "bar",
    },
    rscript_args = "--default-packages=base,exampleA",
    deps = [
        "//exampleA",
        "@R_testthat//:testthat",
    ],
)
