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
        "src/lib/**",  # Handled through cc_library.
    ],
)

PKG_DEPS = [
    "//packages/exampleB",
]

PKG_CHECK_DEPS = [
    "@R_RProtoBuf//:RProtoBuf",
    "@R_testthat//:testthat",
]

r_pkg(
    name = PKG_NAME,
    srcs = PKG_SRCS,
    # Override default to build package vignettes and manuals.
    # Note that we have a custom Makefile to create dummy HTMLs as vignettes.
    build_args = [],
    cc_deps = [":cc_lib"],
    deps = PKG_DEPS,
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
    suggested_deps = PKG_CHECK_DEPS,
)

r_pkg_test(
    name = "check",
    timeout = "short",
    pkg = PKG_NAME,
    suggested_deps = PKG_CHECK_DEPS,
)

cc_library(
    name = "cc_lib",
    srcs = [
        "src/lib/getCharacter.c",
        "src/lib/rcpp.cc",
    ],
    hdrs = ["src/lib/rcpp.h"],
    copts = select({
        "@platforms//os:macos": ["-isystem /Library/Frameworks/R.framework/Headers"],
        # symlinked from /usr/share/R/include to work with default cxx_builtin_include_directories
        "@platforms//os:linux": ["-isystem /usr/include/R"],
    }) + ["-Wno-unused-variable"],
    strip_include_prefix = "src",
    deps = ["@R_Rcpp//:Rcpp.cc"],
)
