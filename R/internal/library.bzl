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
    _Rscript = "Rscript",
    _layer_library_deps = "layer_library_deps",
    _library_deps = "library_deps",
)
load("@com_grail_rules_r//R:providers.bzl", "RPackage", "RLibrary")

def _library_tar(ctx, output, files, src_paths, tar_dir):
    ctx.actions.run(outputs=[output], inputs=files,
                    executable=ctx.file._tar_sh, mnemonic="TAR",
                    env={"TAR_DIR": tar_dir},
                    arguments = [output.path] + src_paths)

def _library_impl(ctx):
    library_deps = _library_deps(ctx.attr.pkgs)

    ctx.actions.expand_template(
        template = ctx.file._library_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{library_path}": ctx.attr.library_path,
            "{lib_dirs}": "\n".join([d.short_path for d in library_deps["lib_dirs"]]),
            "{Rscript}": " ".join(_Rscript),
            },
        is_executable = True,
    )

    (pkg_dirs, lib_files, lib_file_map, collection_files) = _layer_library_deps(
        ctx, library_deps, ctx.attr.container_library_path, ctx.file._collect_copy_sh)

    all_pkg_dirs = pkg_dirs["external"] + pkg_dirs["internal"]
    all_files = library_deps["lib_files"]

    tar_dir = ctx.attr.container_library_path
    _library_tar(ctx, ctx.outputs.tar, all_files, all_pkg_dirs, tar_dir)
    _library_tar(ctx, ctx.outputs.layered_tar_external, lib_files["external"], pkg_dirs["external"],
                 tar_dir)
    _library_tar(ctx, ctx.outputs.layered_tar_internal, lib_files["internal"], pkg_dirs["internal"],
                 tar_dir)

    files_tools = library_deps["transitive_tools"]
    tools_tar_srcs = [t.path for t in library_deps["transitive_tools"].to_list()]
    _library_tar(ctx, ctx.outputs.tools_tar, files_tools, tools_tar_srcs,
                 ctx.attr.container_tools_install_path)
    tools_file_map = {
        ctx.attr.container_tools_install_path + "/" + f.basename: f
        for f in files_tools
    }
    container_file_map = lib_file_map + {"tools": tools_file_map}

    runfiles = ctx.runfiles(files=library_deps["lib_files"])
    return [
        DefaultInfo(runfiles=runfiles, files=depset([ctx.outputs.executable])),
        RLibrary(pkgs=ctx.attr.pkgs,
                 container_file_map=container_file_map,
                 container_library_path=ctx.attr.container_library_path,
                 ),
        OutputGroupInfo(
            external=lib_files["external"],
            internal=lib_files["internal"],
            external_collected=collection_files["external"],
            internal_collected=collection_files["internal"],
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
        "container_library_path": attr.string(
            doc = ("Subdirectory within a tar or container where all the " +
                   "packages are installed"),
        ),
        "container_tools_install_path": attr.string(
            default = "usr/local/bin",
            doc = ("Subdirectory within a tar or container where all the " +
                   "tools are installed"),
        ),
        "_library_sh_tpl": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/scripts:library.sh.tpl",
        ),
        "_tar_sh": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//internal:tar.sh",
        ),
        "_collect_copy_sh": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//internal:collect_copy.sh",
        ),
        "_collect_links_R": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//internal:collect_links.R",
        ),
    },
    doc = ("Rule to install the given package and all dependencies to " +
           "a user provided or system default R library site."),
    executable = True,
    outputs = {
        "tar": "%{name}.tar",
        "tools_tar": "%{name}_tools.tar",
        "layered_tar_external": "%{name}_layered_external.tar",
        "layered_tar_internal": "%{name}_layered_internal.tar",
    },
    implementation = _library_impl,
)
