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
    "@com_grail_rules_r//R/internal:common.bzl",
    _layer_library_deps = "layer_library_deps",
    _library_deps = "library_deps",
    _package_lib_short_path = "package_lib_short_path",
)
load(
    "@com_grail_rules_r//internal:shell.bzl",
    _sh_quote_args = "sh_quote_args",
)
load(
    "@com_grail_rules_r//R/internal:common.bzl",
    _runtime_path_export = "runtime_path_export",
)
load("@com_grail_rules_r//R:providers.bzl", "RPackage", "RLibrary")

def _library_impl(ctx):
    tc = ctx.toolchains["@com_grail_rules_r//R/toolchains:r_toolchain_type"]

    library_deps = _library_deps(ctx.attr.pkgs)

    ctx.actions.expand_template(
        template = ctx.file._library_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{library_path}": ctx.attr.library_path,
            "{lib_dirs}": "\n".join([_package_lib_short_path(d) for d in library_deps["description_files"]]),
            "{tools_export_cmd}": _runtime_path_export(tc.tools),
            },
        is_executable = True,
    )

    (lib_files, lib_file_map) = _layer_library_deps(
        ctx, library_deps, file_map=True)

    files_tools = library_deps["transitive_tools"]
    tools_file_map = {
        f.basename: f
        for f in files_tools
    }
    container_file_map = lib_file_map + {"tools": tools_file_map}

    runfiles = ctx.runfiles(files=library_deps["lib_files"]).merge(tc.runfiles)
    return [
        DefaultInfo(
            runfiles=runfiles, files=depset([ctx.outputs.executable])),
        RLibrary(
            pkgs=ctx.attr.pkgs,
            container_file_map=container_file_map,
        ),
        OutputGroupInfo(
            external=lib_files["external"],
            internal=lib_files["internal"],
            tools=files_tools,
        ),
    ]

r_library = rule(
    attrs = {
        "pkgs": attr.label_list(
            providers = [RPackage],
            mandatory = True,
            doc = "Package (and dependencies) to install",
        ),
        "library_path": attr.string(
            default = "",
            doc = ("If different from system default, default library " +
                   "location for installation. For runtime overrides, " +
                   "use bazel run [target] -- -l [path]"),
        ),
        "_library_sh_tpl": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/scripts:library.sh.tpl",
        ),
    },
    doc = ("Rule to install the given package and all dependencies to " +
           "a user provided or system default R library site."),
    executable = True,
    implementation = _library_impl,
    toolchains = ["@com_grail_rules_r//R/toolchains:r_toolchain_type"],
)

def _r_library_tar_impl(ctx):
    provider = ctx.attr.library[RLibrary]
    file_inputs = []
    args = ctx.actions.args()
    args.add("--output=" + ctx.outputs.out.path)
    args.use_param_file("--flagfile=%s")
    for layer in ctx.attr.layers:
        path_prefix = (ctx.attr.library_path if layer != "tools"
                       else ctx.attr.tools_install_path)
        file_inputs += provider.container_file_map[layer].values()
        for (p, f) in provider.container_file_map[layer].items():
            args.add("--file=%s=%s" % (f.path, path_prefix + "/" + p))

    if ctx.attr.extension:
        dotPos = ctx.attr.extension.find('.')
        if dotPos > 0:
            dotPos += 1
            args.add("--compression=%s" % ctx.attr.extension[dotPos:])

    ctx.actions.run(
        outputs = [ctx.outputs.out],
        inputs = file_inputs,
        executable = ctx.executable._build_tar,
        arguments = [args],
        mnemonic = "RLibraryTar",
    )

    return [DefaultInfo(data_runfiles=ctx.runfiles([ctx.outputs.out]))]

r_library_tar = rule(
    attrs = {
        "library": attr.label(
            providers = [RLibrary],
            doc = "The r_library target that this tar will capture.",
        ),
        "library_path": attr.string(
            doc = ("Subdirectory within the container where all the " +
                   "packages are installed"),
        ),
        "tools_install_path": attr.string(
            doc = ("Subdirectory within the container where all the " +
                   "tools are installed"),
        ),
        "layers": attr.string_list(
            default = [
                "external",
                "internal",
                "tools",
            ],
            doc = "Library layers to include in the tar.",
        ),
        "extension": attr.string(default = "tar"),
        "_build_tar": attr.label(
            default = Label("@bazel_tools//tools/build_defs/pkg:build_tar"),
            cfg = "host",
            executable = True,
            allow_files = True,
        ),
    },
    doc = "Rule to create a tar archive of the files in this library.",
    outputs = {
        "out": "%{name}.%{extension}",
    },
    implementation = _r_library_tar_impl,
)
