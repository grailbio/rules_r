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
    "@com_grail_rules_r//internal:shell.bzl",
    _sh_quote_args = "sh_quote_args",
)
load(
    "@com_grail_rules_r//R/internal:common.bzl",
    _env_vars = "env_vars",
    _executables = "executables",
    _layer_library_deps = "layer_library_deps",
    _library_deps = "library_deps",
    _runtime_path_export = "runtime_path_export",
)
load("@com_grail_rules_r//R:providers.bzl", "RBinary", "RLibrary", "RPackage")

def _r_binary_impl(ctx):
    info = ctx.toolchains["@com_grail_rules_r//R:toolchain_type"].RInfo

    srcs = depset([ctx.file.src])
    exe = depset([ctx.outputs.executable])
    tools = depset(_executables(ctx.attr.tools))
    pkg_deps = []
    for dep in ctx.attr.deps:
        if RPackage in dep:
            pkg_deps += [dep]
        elif RLibrary in dep:
            pkg_deps += dep[RLibrary].pkgs
        elif RBinary in dep:
            srcs += dep[RBinary].srcs
            exe += dep[RBinary].exe
            tools += dep[RBinary].tools
            pkg_deps += dep[RBinary].pkg_deps
        else:
            fail("Unknown dependency for %s: %s" % (str(ctx.label), str(dep)))

    library_deps = _library_deps(pkg_deps)

    lib_dirs = ["_EXEC_ROOT_" + d.short_path for d in library_deps["lib_dirs"]]
    transitive_tools = tools + library_deps["transitive_tools"]
    ctx.actions.expand_template(
        template = ctx.file._binary_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{src}": ctx.file.src.short_path,
            "{lib_dirs}": ":".join(lib_dirs),
            "{export_env_vars}": "; ".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(transitive_tools),
            "{workspace_name}": ctx.workspace_name,
            "{Rscript}": " ".join(info.rscript),
            "{Rscript_args}": _sh_quote_args(ctx.attr.rscript_args),
        },
        is_executable = True,
    )

    layered_lib_files = _layer_library_deps(ctx, library_deps)

    runfiles = ctx.runfiles(
        files = library_deps["lib_dirs"],
        transitive_files = srcs + exe + transitive_tools,
        collect_data = True,
    )
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
            tools = transitive_tools,
        ),
    ]

_R_BINARY_ATTRS = {
    "src": attr.label(
        allow_single_file = True,
        mandatory = True,
        doc = "An Rscript interpreted file, or file with executable permissions",
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
    "_binary_sh_tpl": attr.label(
        allow_single_file = True,
        default = "@com_grail_rules_r//R/scripts:binary.sh.tpl",
    ),
}

r_binary = rule(
    attrs = _R_BINARY_ATTRS,
    doc = "Rule to run a binary with a configured R library.",
    executable = True,
    toolchains = ["@com_grail_rules_r//R:toolchain_type"],
    implementation = _r_binary_impl,
)

r_test = rule(
    attrs = _R_BINARY_ATTRS,
    doc = "Rule to run a binary with a configured R library.",
    executable = True,
    test = True,
    toolchains = ["@com_grail_rules_r//R:toolchain_type"],
    implementation = _r_binary_impl,
)
