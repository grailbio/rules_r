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

load("@rules_r//R:defs.bzl", "r_library", "r_pkg", "r_pkg_test", "r_unit_test")

package(default_visibility = ["//visibility:public"])

PKG_NAME = "exampleC"

PKG_SRCS = glob(
    ["**"],
    exclude = [
        "BUILD",
        "src/lib/**",  # Handled through cc_library.
    ],
)

r_library(
    name = "deps",
    pkgs = [
        "//packages/exampleB",
        "@R_Rcpp",
    ],
)

r_library(
    name = "suggested_deps",
    pkgs = [
        "@R_testthat",
        "@workspaceroot",
    ],
)

r_pkg(
    name = PKG_NAME,
    srcs = PKG_SRCS,
    # Override default to build package vignettes and manuals.
    # Note that we have a custom Makefile to create dummy HTMLs as vignettes.
    build_args = [],
    cc_deps = [":cc_lib"],
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

cc_library(
    name = "cc_lib",
    srcs = [
        "src/lib/getCharacter.c",
        "src/lib/rcpp.cc",
    ],
    hdrs = ["src/lib/rcpp.h"],
    # NOTE: @platforms//os:... targets work in select statement from bazel 4.0.0+.
    copts = select({
        # NOTE: The include path requirements here are met through setup-bazel.sh.
        # When using Xcode toolchains, /Library include paths work out of the box from bazel 4.0.0+.
        # When not using Xcode, relies on the following in the environment.
        # CPLUS_INCLUDE_PATH=/Library/Frameworks/R.framework/Headers
        "@platforms//os:macos": ["-isystem /Library/Frameworks/R.framework/Headers"],
        # Relies on the following in the environment.
        # CPLUS_INCLUDE_PATH=/usr/share/R/include
        "@platforms//os:linux": ["-isystem /usr/share/R/include"],
    }) + ["-Wno-unused-variable"],
    strip_include_prefix = "src",
    deps = ["@R_Rcpp//:Rcpp.cc"],
)
