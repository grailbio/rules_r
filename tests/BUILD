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

load("@com_grail_rules_r//R:defs.bzl", "r_library", "r_binary", "r_test")

r_library(
    name = "library",
    pkgs = [
        "//exampleC",
        "@R_bitops//:bitops",
    ],
    tar_dir = "r-libs",
)

load("@io_bazel_rules_docker//container:container.bzl", "container_image")

container_image(
    name = "image",
    base = "@r_base//image",
    directory = "/",
    env = {"R_LIBS_USER": "/r-libs"},
    tars = [":library.tar"],
)

sh_test(
    name = "image_test",
    size = "small",
    srcs = ["image_test.sh"],
    data = [":image-layer.tar"],
)

r_binary(
    name = "binary",
    src = "binary.R",
    data = ["binary_data.txt"],
    deps = [
        ":library",
        "@R_R6",
    ],
)

r_test(
    name = "binary_test",
    src = "binary.R",
    data = ["binary_data.txt"],
    deps = [
        ":library",
        "@R_R6",
    ],
)

r_test(
    name = "binary_r_test",
    src = "binary_test.sh",
    env_vars = {
        "R_TEST": "true",
    },
    deps = [":binary"],
)

# Example of using the binary in sh_test instead of r_test.
sh_test(
    name = "binary_sh_test",
    srcs = ["binary_test.sh"],
    data = [":binary"],
)
