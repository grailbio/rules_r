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

load("@com_grail_rules_r//R:defs.bzl", "r_library", "r_pkg", "r_pkg_test", "r_unit_test")

package(default_visibility = ["//visibility:public"])

PKG_NAME = "exampleC"

PKG_SRCS = glob(
    ["**"],
    exclude = [
        "BUILD",
    ],
)

r_library(
    name = "deps",
    pkgs = ["//exampleB"],
)

r_library(
    name = "suggested_deps",
    pkgs = [
        "@R_RProtoBuf",
        "@R_testthat",
    ],
)

r_pkg(
    name = PKG_NAME,
    srcs = PKG_SRCS,
    # Override default to build package vignettes and manuals.
    # Note that we have a custom Makefile to create dummy HTMLs as vignettes.
    build_args = [],
    deps = [":deps"],
)

r_library(
    name = "library",
    pkgs = [PKG_NAME],
    tags = ["manual"],
)

r_unit_test(
    name = "test",
    timeout = "short",
    pkg = PKG_NAME,
    suggested_deps = [":suggested_deps"],
)

r_pkg_test(
    name = "check",
    timeout = "short",
    pkg = PKG_NAME,
    suggested_deps = [":suggested_deps"],
)
