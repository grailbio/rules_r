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
"""This module provides a rule to define a toolchain from the system installation of R."""

load(
    "@com_grail_rules_r//R/toolchains:common.bzl",
    _find_executable = "find_executable",
    _path_must_exist = "path_must_exist",
    _get_r_version = "get_r_version",
    _must_execute = "must_execute",
)

_BUILD = """
load("@com_grail_rules_r//R/toolchains:defs.bzl", "define_r_toolchain")

define_r_toolchain(
    name = "toolchain",
    tools = ["//bin:R", "//bin:Rscript"],
    r_version = "{r_version}",
    makevars_user = {makevars_user},
)
"""

_BUILD_BIN = """
package(default_visibility = ["//visibility:public"])

sh_binary(
    name = "R",
    srcs = ["R.sh"],
)

sh_binary(
    name = "Rscript",
    srcs = ["Rscript.sh"],
)
"""

def _darwin_available_versions(rctx):
    """Returns, on Mac OSX, a list of versions available locally"""
    output = _must_execute(rctx, ["ls", "/Library/Frameworks/R.framework/Versions"])
    return [version for version in output.split("\n") if not version in ["Current", ""]]

def _check_version(expected, actual):
    """Checks that versions match."""
    if expected.count(".") == 1:
        actual = actual[:actual.rindex(".")]
    if expected != actual:
        fail("expected R version '%s', got '%s'" % (expected, actual))

def _local_r_toolchain_impl(rctx):
    r_home = None
    if rctx.attr.version and rctx.os.name == "mac os x":
        darwin_version = rctx.attr.version
        if darwin_version.count(".") > 1:
            darwin_version = darwin_version[:darwin_version.rindex(".")]
        r_home = "/Library/Frameworks/R.framework/Versions/%s/Resources" % darwin_version
        if not rctx.path(r_home).exists:
            fail("No local R with version '%s' could be found; available: %s" % (
                darwin_version,
                _darwin_available_versions(rctx),
            ))
    elif rctx.attr.r_home:
        r_home = rctx.attr.r_home
        if not r_home.exists:
            fail("R_HOME '%s' does not exist" % r_home)

    if r_home:
        r_bin = _path_must_exist(rctx, r_home + "/bin/R")
        rscript_bin = _path_must_exist(rctx, r_home + "/bin/Rscript")
    else:
        r_bin = _find_executable(rctx, "R")
        rscript_bin = _find_executable(rctx, "Rscript")
        if not r_bin or not rscript_bin:
            fail("Cannot setup a local R toolchain: either R or Rscript could not be found")

    actual_version = _get_r_version(rctx, rscript_bin)
    if rctx.attr.version:
        _check_version(rctx.attr.version, actual_version)

    rctx.file("WORKSPACE", "workspace(name = \"{name}\")\n".format(name=rctx.name))
    rctx.file("BUILD", _BUILD.format(
        r_version=actual_version,
        makevars_user=("\"%s\"" % str(rctx.attr.makevars_user)) if rctx.attr.makevars_user else None,
    ))
    rctx.file("bin/BUILD", _BUILD_BIN)
    rctx.symlink(r_bin, "bin/R.sh")
    rctx.symlink(rscript_bin, "bin/Rscript.sh")

# Rule to define a local R toolchain (it is similar to what @local_cc does
# for the CC toolchain).  The local toolchain lives outside the execroot
# and breaks hermeticity.  To invalidate the toolchain, change the value of the
# environment variable `R_TOOLCHAIN_INVALIDATE`.
local_r_toolchain = repository_rule(
    attrs = {
        "r_home": attr.string(
            doc = ("A path to the local `R_HOME`.  If not specified, the rule guesses " + 
                   "the `R_HOME` by looking at the `R` executable in the `PATH`."),
        ),
        "version": attr.string(
            doc = ("The local version to look for.  On Mac OSX, where multiple versions of R " +
                   "are supported, the rule tries to find a suitable version.  If no " +
                   "compatible installation is found, on either Mac OSX or Linux, the " +
                   "rule fails."),
        ),
        "makevars_user": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "User level Makevars file",
        ),
    },
    implementation = _local_r_toolchain_impl,
    local = True,
    environ = ["R_TOOLCHAIN_INVALIDATE"],
)
