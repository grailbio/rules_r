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
    "@rules_r//internal:shell.bzl",
    _sh_quote_args = "sh_quote_args",
)
load(
    "@rules_r//R/internal:common.bzl",
    _env_vars = "env_vars",
    _executables = "executables",
    _flatten_pkg_deps_list = "flatten_pkg_deps_list",
    _library_deps = "library_deps",
    _makevars_files = "makevars_files",
    _package_dir = "package_dir",
    _runfiles = "runfiles",
    _runtime_path_export = "runtime_path_export",
    _tests_dir = "tests_dir",
)
load("@rules_r//R:providers.bzl", "RLibrary", "RPackage")

def _test_impl(ctx):
    info = ctx.toolchains["@rules_r//R:toolchain_type"].RInfo

    pkg = ctx.attr.pkg
    pkg_deps = _flatten_pkg_deps_list(ctx.attr.suggested_deps)
    pkg_deps.append(pkg)

    collect_coverage = ctx.configuration.coverage_enabled
    coverage_files = []
    if collect_coverage:
        coverage_files.append(ctx.file._collect_coverage_R)
        pkg_deps.extend(ctx.attr._coverage_deps)

    library_deps = _library_deps(pkg_deps)

    pkg_tests_dir = _tests_dir(_package_dir(ctx))
    test_files = pkg[RPackage].test_files

    tools = depset(
        _executables(ctx.attr.tools + info.tools),
        transitive = [library_deps.transitive_tools],
    )
    data = depset(
        transitive = [d[DefaultInfo].files for d in ctx.attr.data],
    )

    lib_dirs = ["_EXEC_ROOT_" + d.short_path for d in library_deps.lib_dirs]
    ctx.actions.expand_template(
        template = ctx.file._test_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{pkg_tests_dir}": pkg_tests_dir,
            "{export_env_vars}": "; ".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools),
            "{lib_dirs}": ":".join(lib_dirs),
            "{Rscript}": " ".join(info.rscript),
            "{collect_coverage}": "true" if collect_coverage else "false",
            "{collect_coverage.R}": ctx.file._collect_coverage_R.short_path,
        },
        is_executable = True,
    )

    instrumented_files = depset(
        transitive = [
            depset(transitive = [
                pkg[InstrumentedFilesInfo].instrumented_files,
                pkg[InstrumentedFilesInfo].metadata_files,
            ])
            for pkg in pkg_deps
        ],
    )

    runfiles = ctx.runfiles(
        files = (library_deps.lib_dirs +
                 library_deps.gcno_files +
                 coverage_files +
                 test_files +
                 info.files + [info.state]),
        transitive_files = depset(
            transitive = [tools, data, instrumented_files],
        ),
    )
    runfiles = runfiles.merge(
        _runfiles(ctx, [ctx.attr.pkg] + ctx.attr.suggested_deps + ctx.attr.tools + ctx.attr.data),
    )

    return [
        DefaultInfo(runfiles = runfiles),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["pkg"],
        ),
    ]

r_unit_test = rule(
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            providers = [RPackage],
            doc = "R package (of type r_pkg) to test",
        ),
        "suggested_deps": attr.label_list(
            providers = [
                [RPackage],
                [RLibrary],
            ],
            doc = "R package dependencies of type r_pkg or r_library",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define before running the test",
        ),
        "tools": attr.label_list(
            doc = "Executables to be made available to the test",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Data to be made available to the test",
        ),
        "_test_sh_tpl": attr.label(
            allow_single_file = True,
            default = "@rules_r//R/scripts:test.sh.tpl",
        ),
        "_coverage_deps": attr.label_list(
            default = [
                "@R_covr",
                "@R_xml2",  # For cobertura xml output.
            ],
            providers = [RPackage],
            doc = "Dependencies for test coverage calculation",
        ),
        "_collect_coverage_R": attr.label(
            allow_single_file = True,
            default = "@rules_r//R/scripts:collect_coverage.R",
        ),
        "_lcov_merger": attr.label(
            allow_single_file = True,
            default = "@rules_r//R/scripts:lcov_merger.sh",
        ),
    },
    doc = ("Rule to keep all deps in the sandbox, and run the test " +
           "scripts of the specified package. The package itself must " +
           "be one of the deps."),
    test = True,
    toolchains = ["@rules_r//R:toolchain_type"],
    implementation = _test_impl,
)

def _check_impl(ctx):
    info = ctx.toolchains["@rules_r//R:toolchain_type"].RInfo

    pkg_name = ctx.attr.pkg[RPackage].pkg_name
    src_archive = ctx.attr.pkg[RPackage].src_archive
    pkg_deps = ctx.attr.pkg[RPackage].pkg_deps
    build_tools = ctx.attr.pkg[RPackage].build_tools
    cc_deps = ctx.attr.pkg[RPackage].cc_deps
    makevars = ctx.attr.pkg[RPackage].makevars

    library_deps = _library_deps(_flatten_pkg_deps_list(ctx.attr.suggested_deps) + pkg_deps)
    tools = depset(
        _executables(ctx.attr.tools + info.tools),
        transitive = [build_tools],
    )

    all_input_files = ([src_archive] + library_deps.lib_dirs +
                       tools.to_list() + ctx.files.data + info.files +
                       cc_deps.files +
                       _makevars_files(info.makevars_site, makevars) + [info.state])

    lib_dirs = ["_EXEC_ROOT_" + d.short_path for d in library_deps.lib_dirs]
    ctx.actions.expand_template(
        template = ctx.file._check_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{export_env_vars}": "\n".join(_env_vars(info.env_vars) + _env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools),
            "{c_libs_flags}": " ".join(cc_deps.c_libs_flags_short),
            "{c_cpp_flags}": " ".join(cc_deps.c_cpp_flags_short),
            "{c_so_files}": _sh_quote_args([f.short_path for f in cc_deps.c_so_files]),
            "{r_makevars_user}": makevars.short_path if makevars else "",
            "{r_makevars_site}": info.makevars_site.short_path if info.makevars_site else "",
            "{lib_dirs}": ":".join(lib_dirs),
            "{check_args}": _sh_quote_args(ctx.attr.check_args),
            "{pkg_name}": pkg_name,
            "{pkg_src_archive}": src_archive.short_path,
            "{R}": " ".join(info.r),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = all_input_files)
    return [DefaultInfo(runfiles = runfiles)]

r_pkg_test = rule(
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            providers = [RPackage],
            doc = "R package (of type r_pkg) to test",
        ),
        "suggested_deps": attr.label_list(
            providers = [
                [RPackage],
                [RLibrary],
            ],
            doc = "R package dependencies of type r_pkg or r_library",
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
        "data": attr.label_list(
            allow_files = True,
            doc = "Data to be made available to the test",
        ),
        "_check_sh_tpl": attr.label(
            allow_single_file = True,
            default = "@rules_r//R/scripts:check.sh.tpl",
        ),
    },
    doc = ("Rule to keep all deps of the package in the sandbox, build " +
           "a source archive of this package, and run R CMD check on " +
           "the package source archive in the sandbox."),
    test = True,
    toolchains = ["@rules_r//R:toolchain_type"],
    implementation = _check_impl,
)
