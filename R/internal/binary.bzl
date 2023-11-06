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

load(
    "@com_rules_r//internal:shell.bzl",
    _sh_quote_args = "sh_quote_args",
)
load(
    "@com_rules_r//R/internal:common.bzl",
    _dict_to_r_vec = "dict_to_r_vec",
    _env_vars = "env_vars",
    _executables = "executables",
    _flatten_pkg_deps_list = "flatten_pkg_deps_list",
    _layer_library_deps = "layer_library_deps",
    _library_deps = "library_deps",
    _runfiles = "runfiles",
    _runtime_path_export = "runtime_path_export",
)
load("@com_rules_r//R:providers.bzl", "RBinary", "RLibrary", "RPackage")

def _r_markdown_stub(ctx):
    stub = ctx.actions.declare_file(ctx.label.name + "_stub.R")
    args = _dict_to_r_vec(ctx.attr.render_args)
    ctx.actions.expand_template(
        template = ctx.file._render_R_tpl,
        output = stub,
        substitutions = {
            "{src}": ctx.file.src.short_path,
            "{render_function}": ctx.attr.render_function,
            "{input_argument}": ctx.attr.input_argument,
            "{output_dir_argument}": ctx.attr.output_dir_argument,
            "{render_args}": args,
        },
        is_executable = False,
    )
    return stub

def _r_binary_impl(ctx):
    info = ctx.toolchains["@com_rules_r//R:toolchain_type"].RInfo

    if "render_function" in dir(ctx.attr):
        src = _r_markdown_stub(ctx)
        srcs = [ctx.file.src, src]

        # bazel has a bug wherein an expanded template always has executable permissions.
        ignore_execute_permissions = True
    else:
        src = ctx.file.src
        srcs = [src]
        ignore_execute_permissions = False

    pkg_deps = _flatten_pkg_deps_list(ctx.attr.deps)
    library_deps = _library_deps(pkg_deps)

    srcs = depset(
        srcs,
        transitive = [d[RBinary].srcs for d in ctx.attr.deps if RBinary in d],
    )
    exe = depset(
        [ctx.outputs.executable],
        transitive = [d[RBinary].exe for d in ctx.attr.deps if RBinary in d],
    )
    tools = depset(
        _executables(ctx.attr.tools),
        transitive = ([d[RBinary].tools for d in ctx.attr.deps if RBinary in d] + [library_deps.transitive_tools]),
    )
    data = depset(
        transitive = [d[DefaultInfo].files for d in ctx.attr.data],
    )

    lib_dirs = ["_EXEC_ROOT_" + d.short_path for d in library_deps.lib_dirs]
    ctx.actions.expand_template(
        template = ctx.file._binary_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{src}": src.short_path,
            "{lib_dirs}": ":".join(lib_dirs),
            "{build_package_path}": ctx.label.package,
            "{build_label_name}": ctx.label.name,
            "{export_env_vars}": "; ".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools),
            "{workspace_name}": ctx.workspace_name,
            "{ignore_execute_permissions}": "true" if ignore_execute_permissions else "false",
            "{R}": " ".join(info.r),
            "{Rscript}": " ".join(info.rscript),
            "{Rscript_args}": _sh_quote_args(ctx.attr.rscript_args),
            "{script_args}": _sh_quote_args(ctx.attr.script_args),
            "{required_version}": info.version,
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = library_deps.lib_dirs,
        transitive_files = depset(transitive = [srcs, exe, tools, data]),
    )
    runfiles = runfiles.merge(_runfiles(ctx, ctx.attr.deps + ctx.attr.data + ctx.attr.tools))

    layered_lib_files = _layer_library_deps(ctx, library_deps)
    return [
        DefaultInfo(runfiles = runfiles),
        RBinary(
            srcs = srcs,
            exe = exe,
            pkg_deps = pkg_deps,
            tools = tools,
        ),
        OutputGroupInfo(
            external = layered_lib_files["external"],
            internal = layered_lib_files["internal"],
            tools = tools,
        ),
    ]

_R_BINARY_ATTRS = {
    "src": attr.label(
        allow_single_file = True,
        mandatory = True,
        doc = ("An Rscript interpreted file, or file with executable permissions. " +
               "For r_markdown rule, this must be a valid input file to the render function."),
    ),
    "deps": attr.label_list(
        providers = [
            [RBinary],
            [RPackage],
            [RLibrary],
        ],
        doc = "Dependencies of type r_binary, r_pkg or r_library",
    ),
    "data": attr.label_list(
        allow_files = True,
        doc = "Files needed by this rule at runtime",
    ),
    "env_vars": attr.string_dict(
        doc = "Extra environment variables to define before running the binary",
    ),
    "tools": attr.label_list(
        cfg = "target",
        doc = "Executables to be made available to the binary",
    ),
    "rscript_args": attr.string_list(
        doc = ("If src file does not have executable permissions, " +
               "arguments for the Rscript interpreter. We recommend " +
               "using the shebang line and giving your script " +
               "execute permissions instead of using this."),
    ),
    "script_args": attr.string_list(
        doc = "A list of arguments to pass to the src script",
    ),
    "_binary_sh_tpl": attr.label(
        allow_single_file = True,
        default = "@com_rules_r//R/scripts:binary.sh.tpl",
    ),
}

_R_MARKDOWN_ATTRS = dict(_R_BINARY_ATTRS)

_R_MARKDOWN_ATTRS.update({
    "render_function": attr.string(
        default = "rmarkdown::render",
        doc = "Name of the render function",
    ),
    "input_argument": attr.string(
        default = "input",
        doc = "Name of the input argument",
    ),
    "output_dir_argument": attr.string(
        default = "output_dir",
        doc = "Name of the output dir argument",
    ),
    "render_args": attr.string_dict(
        doc = "Other arguments for the render function",
    ),
    "_render_R_tpl": attr.label(
        allow_single_file = True,
        default = "@com_rules_r//R/scripts:render.R.tpl",
    ),
})

r_binary = rule(
    attrs = _R_BINARY_ATTRS,
    doc = "Rule to run a binary with a configured R library.",
    executable = True,
    toolchains = ["@com_rules_r//R:toolchain_type"],
    implementation = _r_binary_impl,
)

r_test = rule(
    attrs = _R_BINARY_ATTRS,
    doc = "Rule to run a binary with a configured R library.",
    executable = True,
    test = True,
    toolchains = ["@com_rules_r//R:toolchain_type"],
    implementation = _r_binary_impl,
)

r_markdown = rule(
    attrs = _R_MARKDOWN_ATTRS,
    doc = "Rule to render a markdown.",
    executable = True,
    toolchains = ["@com_rules_r//R:toolchain_type"],
    implementation = _r_binary_impl,
)
