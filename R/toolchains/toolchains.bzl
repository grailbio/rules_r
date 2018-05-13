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
"""This modules can be used to define custom R toolchains."""

load(
    "@com_grail_rules_r//R/internal:common.bzl",
    _executables = "executables",
)

def _get_features(r_version):
    """Gathers substitutions for the root BUILD file of the toolchain repository."""
    vers = tuple([int(n) for n in r_version.split(".")])

    if vers < tuple([3, 3, 0]):
        fail("minimum R version: 3.3.0; got '%s'" % r_version)

    return struct(
        r_version = r_version,
        has_features_rds = vers >= tuple([3, 4, 0]),
    )

def _r_toolchain_impl(ctx):
    """Implementation of the `r_toolchain` rule."""
    tools = _executables(ctx.attr.tools)
    runfiles = ctx.runfiles()
    for tool in ctx.attr.tools:
        runfiles = runfiles.merge(tool.default_runfiles)
    return [platform_common.ToolchainInfo(
        tools = tools,
        runfiles = runfiles,
        files = runfiles.files + tools,
        makevars_user = ctx.file.makevars_user,
        features = _get_features(ctx.attr.r_version),
    )]

r_toolchain = rule(
    attrs = {
        "tools": attr.label_list(),
        "makevars_user": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "User level Makevars file",
        ),
        "r_version": attr.string(
            doc = "R version (e.g. 3.5.0, 3.4.0, ...)",
        ),
    },
    doc = "Rule to provide a ToolchainInfo provider for the R toolchain.",
    implementation = _r_toolchain_impl,
)

def define_r_toolchain(name, **kwargs):
    """Defines an R toolchain."""
    impl_name = name + "_impl"
    r_toolchain(
        name = impl_name,
        visibility = ["//visibility:public"],
        **kwargs
    )
    native.toolchain(
        name = name,
        toolchain_type = "@com_grail_rules_r//R/toolchains:r_toolchain_type",
        toolchain = impl_name,
        visibility = ["//visibility:public"],
    )
