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

load("@com_grail_rules_r//R:defs.bzl", "r_library_tar")

r_library_tar(
    name = "library_archive",
    extension = "tar.gz",
    layers = [
        "external",
        "tools",
    ],
    library = "//:library",
    library_path = "grail/r-libs",
)

## Image related tests

load("@com_grail_rules_r//R/container:defs.bzl", "r_binary_image", "r_library_image")

r_library_image(
    name = "library_image",
    base = "@r_base//image",
    directory = "grail",
    library = "//:library",
    library_path = "r-libs",
)

sh_test(
    name = "image_test",
    size = "small",
    srcs = ["image_test.sh"],
    data = [
        ":binary_image",
        ":binary_image_explicit_layers",
        ":library_archive",
        ":library_image",
    ],
)

r_binary_image(
    name = "binary_image",
    base = "@r_base//image",
    binary = "//binary",
)

r_binary_image(
    name = "binary_image_explicit_layers",
    base = "@r_base//image",
    binary = "//binary",
    layers = [
        "@R_bitops",
        "@R_R6",
    ],
)
