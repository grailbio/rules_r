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
"""This module provides a local toolchain used to test runfiles propagation and hermeticity."""

load(
    "@com_grail_rules_r//R/toolchains:common.bzl",
    _find_executable = "find_executable",
    _get_r_version = "get_r_version",
    _must_execute = "must_execute",
)

_BUILD = """
load("@com_grail_rules_r//R/toolchains:defs.bzl", "define_r_toolchain")

define_r_toolchain(
    name = "toolchain",
    tools = ["//bin:R", "//bin:Rscript"],
    r_version = "{r_version}",
)
"""

_BUILD_BIN = """
package(default_visibility = ["//visibility:public"])

sh_binary(
    name = "R",
    srcs = ["R.sh"],
    data = ["R2.sh"],
)

sh_binary(
    name = "Rscript",
    srcs = ["Rscript.sh"],
    data = ["Rscript2.sh"],
)
"""

_BIN_WRAPPER = """#!/bin/bash

# The -f option is not available on Mac OSX, but the test toolchain is only used on Linux.
"$(dirname $(readlink -f "$0"))/{actual}" "$@"
"""

def _test_r_toolchain_impl(rctx):
    r_bin = _find_executable(rctx, "R")
    rscript_bin = _find_executable(rctx, "Rscript")
    if not r_bin or not rscript_bin:
        fail("R installation was not found")

    actual_version = _get_r_version(rctx, rscript_bin)

    rctx.file("WORKSPACE", "workspace(name = \"{name}\")\n".format(name=rctx.name))
    rctx.file("BUILD", _BUILD.format(r_version=actual_version))
    rctx.file("bin/BUILD", _BUILD_BIN)
    rctx.file("bin/R.sh", _BIN_WRAPPER.format(actual="R2.sh"), executable = True)
    rctx.file("bin/Rscript.sh", _BIN_WRAPPER.format(actual="Rscript2.sh"), executable = True)
    
    _must_execute(rctx, ["cp", "-L", r_bin, "bin/R2.sh"])
    _must_execute(rctx, ["cp", "-L", rscript_bin, "bin/Rscript2.sh"])

test_r_toolchain = repository_rule(
    attrs = {},
    implementation = _test_r_toolchain_impl,
    local = True,
    environ = ["R_TOOLCHAIN_INVALIDATE"],
)
