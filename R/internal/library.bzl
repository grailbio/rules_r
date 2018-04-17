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
    _R = "R",
    _library_deps = "library_deps",
)
load("@com_grail_rules_r//R:providers.bzl", "RPackage", "RLibrary")

def _library_impl(ctx):
    library_deps = _library_deps(ctx.attr.pkgs)

    ctx.actions.run(outputs=[ctx.outputs.tar], inputs=library_deps["lib_files"],
                    executable=ctx.file._tar_sh, mnemonic="TAR",
                    env={"TAR_DIR": ctx.attr.tar_dir},
                    arguments = [ctx.outputs.tar.path] + library_deps["pkg_dir_paths"])

    tools_tar_srcs = [t.path for t in library_deps["transitive_tools"].to_list()]
    ctx.actions.run(outputs=[ctx.outputs.tools_tar], inputs=library_deps["transitive_tools"],
                    executable=ctx.file._tar_sh, mnemonic="TAR",
                    env={"TAR_DIR": ctx.attr.tools_tar_dir},
                    arguments = [ctx.outputs.tools_tar.path] + tools_tar_srcs)

    ctx.actions.expand_template(
        template = ctx.file._library_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{library_path}": ctx.attr.library_path,
            "{lib_dirs}": "\n".join([d.short_path for d in library_deps["lib_dirs"]]),
            "{R}": " ".join(_R),
            },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files=library_deps["lib_files"])
    return [DefaultInfo(runfiles=runfiles, files=depset([ctx.outputs.executable])),
            RLibrary(pkgs=ctx.attr.pkgs)]

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
        "tar_dir": attr.string(
            doc = ("Subdirectory within the tarball where all the " +
                   "packages are installed"),
        ),
        "tools_tar_dir": attr.string(
            default = "usr/local/bin",
            doc = ("Subdirectory within the tarball where all the " +
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
    },
    doc = ("Rule to install the given package and all dependencies to " +
           "a user provided or system default R library site."),
    executable = True,
    outputs = {
        "tar": "%{name}.tar",
        "tools_tar": "%{name}_tools.tar",
    },
    implementation = _library_impl,
)
