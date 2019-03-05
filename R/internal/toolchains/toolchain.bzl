# Copyright 2019 The Bazel Authors.
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

RInfo = provider(
    doc = "Information about the system R installation.",
    fields = [
        # Command to invoke R.
        "r",
        # Command to invoke Rscript.
        "rscript",
        # Version to assert in build actions.
        "version",
        # Site-wide Makevars file.
        "makevars_site",
        # Additional tools to make available in PATH.
        "tools",
        # Additional files available to the build actions.
        "files",
        # Environment variables for build actions.
        "env_vars",
        # File for system state information.
        "state",
    ],
)

load("@com_grail_rules_r//R/internal:common.bzl", "executables")

def _r_toolchain_impl(ctx):
    args = ctx.attr.args

    if not ctx.attr.r or not ctx.attr.rscript:
        fail("R or Rscript not specified")

    Rscript_args = ["--no-init-file"] + args
    R_args = ["--slave", "--no-restore"] + Rscript_args

    R = [ctx.attr.r] + R_args
    Rscript = [ctx.attr.rscript] + Rscript_args

    state_file = ctx.actions.declare_file(ctx.label.name + "_state")
    ctx.actions.run(
        outputs = [state_file],
        inputs = [],
        executable = ctx.attr._system_state_computer.files_to_run.executable,
        arguments = [state_file.path],
        env = {
            "R": ctx.attr.r,
            "RSCRIPT": ctx.attr.rscript,
            "SITE_FILES_FLAG": "--no-site-files" if "-no-site-file" in R_args else "",
            "ARGS": " ".join(ctx.attr.args),
            "REQUIRED_VERSION": ctx.attr.version,
        },
        mnemonic = "RState",
        progress_message = "Computing R system state",
        # TODO: Unconditionally execute this action when needed.
        # https://groups.google.com/d/msg/bazel-discuss/V0aE0x6gE5Q/mdoRh5EmGQAJ
    )

    toolchain_info = platform_common.ToolchainInfo(
        RInfo = RInfo(
            env_vars = ctx.attr.env_vars,
            files = ctx.files.files,
            makevars_site = ctx.file.makevars_site,
            r = R,
            rscript = Rscript,
            state = state_file,
            tools = ctx.attr.tools,
            version = ctx.attr.version,
        ),
    )
    return [toolchain_info]

r_toolchain = rule(
    attrs = {
        "r": attr.string(
            default = "R",
            doc = "Path to R",
        ),
        "rscript": attr.string(
            default = "Rscript",
            doc = "Path to Rscript",
        ),
        "version": attr.string(
            doc = "If provided, ensure version of R matches this string in x.y form",
        ),
        "args": attr.string_list(
            default = [
                "--no-save",
                "--no-site-file",
                "--no-environ",
            ],
            doc = ("Arguments to R and Rscript, in addition to " +
                   "`--slave --no-restore --no-init-file`"),
        ),
        "makevars_site": attr.label(
            allow_single_file = True,
            doc = "Site-wide Makevars file",
        ),
        "env_vars": attr.string_dict(
            doc = "Environment variables for BUILD actions",
        ),
        "tools": attr.label_list(
            allow_files = True,
            doc = "Additional tools to make available in PATH",
        ),
        "files": attr.label_list(
            allow_files = True,
            doc = "Additional files available to the BUILD actions",
        ),
        "_system_state_computer": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "@com_grail_rules_r//R/scripts:system_state.sh",
            doc = "Executable to output R system state",
            executable = True,
        ),
    },
    provides = [platform_common.ToolchainInfo],
    implementation = _r_toolchain_impl,
)
