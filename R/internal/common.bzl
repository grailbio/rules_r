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

def package_dir(ctx):
    # Relative path to target directory.

    workspace_root = ctx.label.workspace_root
    if workspace_root != "" and ctx.label.package != "":
        return workspace_root + "/" + ctx.label.package
    elif workspace_root == "" and ctx.label.package == "":
        return "."
    else:
        return workspace_root or ctx.label.package

def tests_dir(pkg_dir):
    # Standard tests directory within a package.

    return pkg_dir + "/tests"

def env_vars(env_vars):
    # Array of commands to export environment variables.

    return ["export %s=%s" % (name, _sh_quote(value)) for name, value in env_vars.items()]

def executables(labels):
    # depset of executable files for this list of labels.

    return [label.files_to_run.executable for label in labels]

def runtime_path_export(executables):
    # ":" separated path to directories of desired tools, for use in executables.

    exe_dirs = ["$(cd $(dirname %s); echo \"${PWD}\")" %
                exe.short_path for exe in executables.to_list()]
    if exe_dirs:
        return "export PATH=\"" + ":".join(exe_dirs + ["${PATH}"]) + "\""
    else:
        return ""

def build_path_export(executables):
    # ":" separated path to directories of desired tools, for use in build actions.

    exe_dirs = ["$(cd $(dirname %s); echo \"${PWD}\")" %
                exe.path for exe in executables.to_list()]
    if exe_dirs:
        return "export PATH=\"" + ":".join(exe_dirs + ["${PATH}"]) + "\""
    else:
        # This is required because bazel does not export the variable.
        return "export PATH"

def library_deps(target_deps):
    # Returns information about all dependencies of this package.

    # Transitive closure of all package dependencies.
    direct_deps = []
    transitive_pkg_deps = []
    transitive_tools = []
    for target_dep in target_deps:
        direct_deps.append(target_dep[RPackage])
        transitive_pkg_deps.append(target_dep[RPackage].transitive_pkg_deps)
        transitive_tools.append(target_dep[RPackage].transitive_tools)
    transitive_pkg_deps = depset(direct_deps, transitive = transitive_pkg_deps)
    transitive_tools = depset(transitive = transitive_tools)

    # Individual R library directories.
    lib_dirs = []
    gcno_dirs = []

    for pkg_dep in transitive_pkg_deps.to_list():
        lib_dirs.append(pkg_dep.pkg_lib_dir)
        if pkg_dep.pkg_gcno_dir:
            gcno_dirs.append(pkg_dep.pkg_gcno_dir)

    return struct(
        gcno_dirs = gcno_dirs,
        lib_dirs = lib_dirs,
        transitive_pkg_deps = transitive_pkg_deps,
        transitive_tools = transitive_tools,
    )

def layer_library_deps(ctx, library_deps):
    # We partition the library runfiles on the basis of whether origin repo of
    # packages is external or internal. These are exposed as non-default output
    # groups or tarballs, and are generated on demand. Mostly used for
    # efficient layering in containers.

    lib_files = {"external": [], "internal": []}

    for pkg_dep in library_deps.transitive_pkg_deps.to_list():
        pkg_container_layer = "external" if pkg_dep.external_repo else "internal"
        pkg_dir_path = ["%s/%s" % (pkg_dep.pkg_lib_dir.path, pkg_dep.pkg_name)]
        lib_files[pkg_container_layer].append(pkg_dep.pkg_lib_dir)

    return lib_files

def makevars_files(makevars_site, makevars_user):
    files = []
    if makevars_site:
        files.append(makevars_site)
    if makevars_user:
        files.append(makevars_user)
    return files

def dict_to_r_vec(d):
    """Convert a skylark dict to a named character vector for R."""

    return ", ".join([k + "=" + v for k, v in d.items()])

def quote_dict_values(d):
    """Quote the values in the dictionary."""

    return {k: quote_literal(v) for k, v in d.items()}

def quote_literal(s):
    """Quote a literal string constant."""

    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"
