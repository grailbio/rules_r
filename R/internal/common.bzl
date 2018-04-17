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
    _sh_quote = "sh_quote",
)
load("@com_grail_rules_r//R:providers.bzl", "RPackage")

R = [
    "R",
    "--vanilla",
    "--slave",
]

Rscript = [
    "Rscript",
    "--vanilla",
]

def package_dir(ctx):
    # Relative path to target directory.

    workspace_root = ctx.label.workspace_root
    if workspace_root != "" and ctx.label.package != "":
        workspace_root += "/"
    package_dir = workspace_root + ctx.label.package
    return package_dir

def library_deps(target_deps):
    # Returns information about all dependencies of this package.

    # Transitive closure of all package dependencies.
    transitive_pkg_deps = depset()
    transitive_tools = depset()
    for target_dep in target_deps:
        transitive_pkg_deps += (target_dep[RPackage].transitive_pkg_deps +
                                depset([target_dep[RPackage]]))
        transitive_tools += target_dep[RPackage].transitive_tools

    # Individual R library directories.
    lib_dirs = []

    # Installed package directory paths.
    pkg_dir_paths = []

    # Files in the aggregated library of all dependency packages.
    lib_files = []

    # Binary archives of all dependency packages.
    bin_archives = []

    for pkg_dep in transitive_pkg_deps:
        lib_files += pkg_dep.lib_files
        lib_dirs += [pkg_dep.lib_path]
        pkg_dir_paths += ["%s/%s" % (pkg_dep.lib_path.path, pkg_dep.pkg_name)]
        bin_archives += [pkg_dep.bin_archive]

    return {
        "transitive_pkg_deps": transitive_pkg_deps,
        "lib_dirs": lib_dirs,
        "lib_files": lib_files,
        "pkg_dir_paths": pkg_dir_paths,
        "bin_archives": bin_archives,
        "transitive_tools": transitive_tools,
    }

def env_vars(env_vars):
    # Array of commands to export environment variables.

    return ["export %s=%s" % (name, _sh_quote(value)) for name, value in env_vars.items()]

def executables(labels):
    # depset of executable files for this list of labels.

    return depset([label.files_to_run.executable for label in labels])

def runtime_path_export(executables):
    # ":" separated path to directories of desired tools, for use in executables.

    exe_dirs = ["$(cd $(dirname %s); echo \"${PWD}\")" %
                exe.short_path for exe in executables]
    if exe_dirs:
        return "export PATH=\"" + ":".join(exe_dirs + ["${PATH}"]) + "\""
    else:
        return ""

def build_path_export(executables):
    # ":" separated path to directories of desired tools, for use in build actions.

    exe_dirs = ["$(cd $(dirname %s); echo \"${PWD}\")" %
                exe.path for exe in executables]
    if exe_dirs:
        return "export PATH=\"" + ":".join(exe_dirs + ["${PATH}"]) + "\""
    else:
        # This is required because bazel does not export the variable.
        return "export PATH"
