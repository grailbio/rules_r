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
    "@com_grail_rules_r//internal:paths.bzl",
    _paths = "paths",
)
load(
    "@com_grail_rules_r//R/internal:common.bzl",
    _env_vars = "env_vars",
    _executables = "executables",
    _library_deps = "library_deps",
    _package_dir = "package_dir",
    _runtime_path_export = "runtime_path_export",
    _package_lib_short_path = "package_lib_short_path",
)
load("@com_grail_rules_r//R:providers.bzl", "RPackage")

def _test_impl(ctx):
    tc = ctx.toolchains["@com_grail_rules_r//R/toolchains:r_toolchain_type"]

    library_deps = _library_deps([ctx.attr.pkg] + ctx.attr.suggested_deps)

    pkg_name = ctx.attr.pkg[RPackage].pkg_name
    pkg_tests_dir = _package_dir(ctx) + "/tests"
    test_files = []
    for src_file in ctx.attr.pkg[RPackage].src_files:
        if src_file.path.startswith(pkg_tests_dir):
            test_files += [src_file]

    tools = _executables(ctx.attr.tools) + ctx.attr.pkg[RPackage].transitive_tools

    lib_dirs = ["_EXEC_ROOT_" + _package_lib_short_path(d) for d in library_deps["description_files"]]
    ctx.actions.expand_template(
        template = ctx.file._test_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{pkg_tests_dir}": pkg_tests_dir,
            "{export_env_vars}": "; ".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools + tc.tools),
            "{lib_dirs}": ":".join(lib_dirs),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files=library_deps["lib_files"] + test_files,
                            transitive_files = tools).merge(tc.runfiles)
    return [DefaultInfo(runfiles=runfiles)]

r_unit_test = rule(
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            providers = [RPackage],
            doc = "R package (of type r_pkg) to test",
        ),
        "suggested_deps": attr.label_list(
            providers = [RPackage],
            doc = "R package dependencies of type r_pkg",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define before running the test",
        ),
        "tools": attr.label_list(
            doc = "Executables to be made available to the test",
        ),
        "_test_sh_tpl": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/scripts:test.sh.tpl",
        ),
    },
    doc = ("Rule to keep all deps in the sandbox, and run the test " +
           "scripts of the specified package. The package itself must " +
           "be one of the deps."),
    test = True,
    implementation = _test_impl,
    toolchains = ["@com_grail_rules_r//R/toolchains:r_toolchain_type"],
)

def _check_impl(ctx):
    tc = ctx.toolchains["@com_grail_rules_r//R/toolchains:r_toolchain_type"]

    src_archive = ctx.attr.pkg[RPackage].src_archive
    pkg_deps = ctx.attr.pkg[RPackage].pkg_deps
    build_tools = ctx.attr.pkg[RPackage].build_tools
    cc_deps = ctx.attr.pkg[RPackage].cc_deps
    makevars_user = ctx.attr.pkg[RPackage].makevars_user

    library_deps = _library_deps(ctx.attr.suggested_deps + pkg_deps)
    tools = _executables(ctx.attr.tools) + build_tools

    all_input_files = ([src_archive] + library_deps["lib_files"]
                       + tools.to_list()
                       + cc_deps["files"].to_list() + [makevars_user])

    lib_dirs = ["_EXEC_ROOT_" + _package_lib_short_path(d) for d in library_deps["description_files"]]
    ctx.actions.expand_template(
        template = ctx.file._check_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{export_env_vars}": "\n".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools + tc.tools),
            "{c_libs_flags}": " ".join(cc_deps["c_libs_flags_short"]),
            "{c_cpp_flags}": " ".join(cc_deps["c_cpp_flags_short"]),
            "{c_so_files}": _sh_quote_args([f.short_path for f in cc_deps["c_so_files"]]),
            "{r_makevars_user}": makevars_user.short_path if makevars_user else "",
            "{lib_dirs}": ":".join(lib_dirs),
            "{check_args}": _sh_quote_args(ctx.attr.check_args),
            "{pkg_src_archive}": src_archive.short_path,
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files=all_input_files).merge(tc.runfiles)
    return [DefaultInfo(runfiles=runfiles)]

r_pkg_test = rule(
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            providers = [RPackage],
            doc = "R package (of type r_pkg) to test",
        ),
        "suggested_deps": attr.label_list(
            providers = [RPackage],
            doc = "R package dependencies of type r_pkg",
        ),
        "check_args": attr.string_list(
            default = [
                "--no-build-vignettes",
                "--no-manual",
            ],
            doc = "Additional arguments to supply to R CMD check",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define before running the test",
        ),
        "tools": attr.label_list(
            doc = "Executables to be made available to the test",
        ),
        "_check_sh_tpl": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/scripts:check.sh.tpl",
        ),
    },
    doc = ("Rule to keep all deps of the package in the sandbox, build " +
           "a source archive of this package, and run R CMD check on " +
           "the package source archive in the sandbox."),
    test = True,
    implementation = _check_impl,
    toolchains = ["@com_grail_rules_r//R/toolchains:r_toolchain_type"],
)
