# Copyright 2017 GRAIL, Inc.
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

"""R package build, test and install Bazel rules.

r_pkg will build the package and its dependencies and install them in
Bazel's sandbox.

r_unit_test will install all the dependencies of the package in Bazel's
sandbox and generate a script to run the test scripts from the package.

r_pkg_test will install all the dependencies of the package in Bazel's
sandbox and generate a script to run R CMD CHECK on the package.

r_library will generate binary archives for the package and its
dependencies (as a side effect of installing them to Bazel's sandbox),
install all the binary archives into a folder, and make available the
folder as a single tar. The target can also be executed using bazel run.
See usage by running with -h flag.
"""

load("@com_grail_rules_r//R/internal:shell.bzl", "sh_quote", "sh_quote_args")

_R = [
    "R",
    "--vanilla",
    "--slave",
]

_Rscript = [
    "Rscript",
    "--vanilla",
]

RPackage = provider(
    doc = "Build information about an R package dependency",
    fields = {
        "pkg_name": "Name of the package",
        "lib_path": "Directory where this package is installed",
        "lib_files": "All installed files in this package",
        "src_files": "All source files in this package",
        "src_archive": "Source archive of this package",
        "bin_archive": "Binary archive of this package",
        "pkg_deps": "Direct deps of this package",
        "transitive_pkg_deps": "depset of all dependencies of this target",
        "transitive_tools": "depset of all system tools",
        "makevars_user": "user level makevars file for native code compilation",
        "cc_deps": "cc_deps struct for the package",
    },
)

def _package_name(ctx):
    # Package name from attribute with fallback to label name.

    pkg_name = ctx.attr.pkg_name
    if pkg_name == "":
        pkg_name = ctx.label.name
    return pkg_name

def _package_dir(ctx):
    # Relative path to target directory.

    workspace_root = ctx.label.workspace_root
    if workspace_root != "" and ctx.label.package != "":
        workspace_root += "/"
    package_dir = workspace_root + ctx.label.package
    return package_dir

def _strip_path_prefixes(iterable, p1, p2):
    # Given an iterable of paths and two path prefixes, removes the prefixes and
    # filter empty paths.

    res = []
    for s in iterable:
        if not s or s == p1 or s == p2:
            res.append(".")
        elif s.startswith(p1 + "/"):
            res.append(s[(len(p1) + 1):])
        elif s.startswith(p2 + "/"):
            res.append(s[(len(p2) + 1):])
        else:
            res.append(s)
    return res

def _package_files(ctx):
    # Returns files that are installed as an R package.

    pkg_name = _package_name(ctx)
    pkg_src_dir = _package_dir(ctx)

    has_R_code = False
    has_sysdata = False
    has_native_code = False
    has_data_files = False
    inst_files = []
    for src_file in ctx.files.srcs:
        if src_file.path == (pkg_src_dir + "/R/sysdata.rda"):
            has_sysdata = True
        elif src_file.path.startswith(pkg_src_dir + "/R/"):
            has_R_code = True
        elif src_file.path.startswith(pkg_src_dir + "/src/"):
            has_native_code = True
        elif src_file.path.startswith(pkg_src_dir + "/data/"):
            has_data_files = True
        elif src_file.path.startswith(pkg_src_dir + "/inst/"):
            inst_files += [src_file]

    pkg_files = [
        ctx.actions.declare_file("lib/{0}/DESCRIPTION".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/NAMESPACE".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/hsearch.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/links.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/nsInfo.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/package.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/Rd.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/AnIndex".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/aliases.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/{0}.rdb".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/{0}.rdx".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/paths.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/html/00Index.html".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/html/R.css".format(pkg_name)),
    ]

    if has_R_code:
        pkg_files += [
            ctx.actions.declare_file("lib/{0}/R/{0}".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/R/{0}.rdb".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/R/{0}.rdx".format(pkg_name)),
        ]

    if has_sysdata:
       pkg_files += [
           ctx.actions.declare_file("lib/{0}/R/sysdata.rdb".format(pkg_name)),
           ctx.actions.declare_file("lib/{0}/R/sysdata.rdx".format(pkg_name)),
       ]

    if has_native_code:
        shlib_name = ctx.attr.shlib_name
        if shlib_name == "":
            shlib_name = pkg_name
        pkg_files += [ctx.actions.declare_file("lib/{0}/libs/{1}.so"
                                               .format(pkg_name, shlib_name))]

    if has_data_files and ctx.attr.lazy_data:
        pkg_files += [
            ctx.actions.declare_file("lib/{0}/data/Rdata.rdb".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/data/Rdata.rds".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/data/Rdata.rdx".format(pkg_name)),
        ]

    for inst_file in inst_files:
        pkg_files += [ctx.actions.declare_file(
            "lib/{0}/{1}".format(
                pkg_name,
                inst_file.path[len(pkg_src_dir + "/inst/"):]))]

    for post_install_file in ctx.attr.post_install_files:
        pkg_files += [(ctx.actions.declare_file("lib/{0}/{1}"
                                                .format(pkg_name, post_install_file)))]

    return pkg_files

def _library_deps(target_deps):
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

def _cc_deps(cc_deps, pkg_src_dir, bin_dir, gen_dir):
    # Returns a subscript to execute and additional input files.

    # Give absolute paths to R.
    root_path = "_EXEC_ROOT_"

    files = depset()
    c_libs_flags = depset()
    c_libs_flags_short = depset()
    c_cpp_flags = depset()
    c_cpp_flags_short = depset()
    for d in cc_deps:
        files += (d.cc.libs.to_list()
                  + d.cc.transitive_headers.to_list())

        c_libs_flags += d.cc.link_flags
        for l in d.cc.libs:
            c_libs_flags += [root_path + l.path]
            c_libs_flags_short += [root_path + l.short_path]

        for i in d.cc.defines:
            c_cpp_flags += ["-D" + i]
            c_cpp_flags_short += ["-D" + i]
        for i in d.cc.quote_include_directories:
            c_cpp_flags += ["-iquote " + root_path + i]
        for i in d.cc.system_include_directories:
            c_cpp_flags += ["-isystem " + root_path + i]
        for i in d.cc.include_directories:
            c_cpp_flags += ["-I " + root_path + i]

        for i in _strip_path_prefixes(d.cc.quote_include_directories, bin_dir, gen_dir):
            c_cpp_flags_short += ["-iquote " + root_path + i]
        for i in _strip_path_prefixes(d.cc.system_include_directories, bin_dir, gen_dir):
            c_cpp_flags_short += ["-isystem " + root_path + i]
        for i in _strip_path_prefixes(d.cc.include_directories, bin_dir, gen_dir):
            c_cpp_flags_short += ["-I " + root_path + i]

    return {
        "files": files,
        "c_libs_flags": c_libs_flags.to_list(),
        "c_libs_flags_short": c_libs_flags_short.to_list(),
        "c_cpp_flags": c_cpp_flags.to_list(),
        "c_cpp_flags_short": c_cpp_flags_short.to_list(),
    }

def _remove_file(files, path_to_remove):
    # Removes a file from a depset of a list, and returns the new depset.

    new_depset = depset()
    for f in files:
        if f.path != path_to_remove:
            new_depset += [f]

    return new_depset

def _env_vars(env_vars):
    # Array of commands to export environment variables.

    return ["export %s=%s" % (name, sh_quote(value)) for name, value in env_vars.items()]

def _executables(labels):
    # depset of executable files for this list of labels.

    return depset([label.files_to_run.executable for label in labels])

def _runtime_path_export(executables):
    # ":" separated path to directories of desired tools, for use in executables.

    exe_dirs = ["$(cd $(dirname %s); echo \"${PWD}\")" %
                exe.short_path for exe in executables]
    if exe_dirs:
        return "export PATH=\"" + ":".join(exe_dirs + ["${PATH}"]) + "\""
    else:
        return ""

def _build_path_export(executables):
    # ":" separated path to directories of desired tools, for use in build actions.

    exe_dirs = ["$(cd $(dirname %s); echo \"${PWD}\")" %
                exe.path for exe in executables]
    if exe_dirs:
        return "export PATH=\"" + ":".join(exe_dirs + ["${PATH}"]) + "\""
    else:
        # This is required because bazel does not export the variable.
        return "export PATH"

def _build_impl(ctx):
    # Implementation for the r_pkg rule.

    pkg_name = _package_name(ctx)
    pkg_src_dir = _package_dir(ctx)
    pkg_lib_path = ctx.actions.declare_directory("lib")
    pkg_bin_archive = ctx.outputs.bin_archive
    pkg_src_archive = ctx.outputs.src_archive
    package_files = _package_files(ctx)
    output_files = package_files + [pkg_lib_path, pkg_bin_archive]

    library_deps = _library_deps(ctx.attr.deps)
    cc_deps = _cc_deps(ctx.attr.cc_deps, pkg_src_dir, ctx.bin_dir.path, ctx.genfiles_dir.path)
    transitive_tools = (library_deps["transitive_tools"] + _executables(ctx.attr.tools))
    build_tools = _executables(ctx.attr.build_tools) + transitive_tools
    all_input_files = (library_deps["lib_files"] + ctx.files.srcs
                       + cc_deps["files"].to_list()
                       + build_tools.to_list()
                       + [ctx.file.makevars_user])

    if ctx.file.config_override:
        all_input_files += [ctx.file.config_override]
        orig_config = pkg_src_dir + "/configure"
        all_input_files = _remove_file(all_input_files, orig_config)

    build_env = {
        "PKG_LIB_PATH": pkg_lib_path.path,
        "PKG_SRC_DIR": pkg_src_dir,
        "PKG_NAME": pkg_name,
        "PKG_SRC_ARCHIVE": pkg_src_archive.path,
        "PKG_BIN_ARCHIVE": pkg_bin_archive.path,
        "R_MAKEVARS_USER": ctx.file.makevars_user.path if ctx.file.makevars_user else "",
        "CONFIG_OVERRIDE": ctx.file.config_override.path if ctx.file.config_override else "",
        "ROCLETS": ", ".join(["'%s'" % r for r in ctx.attr.roclets]),
        "C_LIBS_FLAGS": " ".join(cc_deps["c_libs_flags"]),
        "C_CPP_FLAGS": " ".join(cc_deps["c_cpp_flags"]),
        "R_LIBS": ":".join(["_EXEC_ROOT_" + d.path for d in library_deps["lib_dirs"]]),
        "BUILD_ARGS": sh_quote_args(ctx.attr.build_args),
        "INSTALL_ARGS": sh_quote_args(ctx.attr.install_args),
        "EXPORT_ENV_VARS_CMD": "; ".join(_env_vars(ctx.attr.env_vars)),
        "BUILD_TOOLS_EXPORT_CMD": _build_path_export(build_tools),
        "REPRODUCIBLE_BUILD": "true" if "rlang-no-stamp" in ctx.features else "false",
        "R": " ".join(_R),
        "RSCRIPT": " ".join(_Rscript),
    }
    ctx.actions.run(outputs=output_files, inputs=all_input_files, executable=ctx.executable._build_sh,
                    env=build_env,
                    mnemonic="RBuild", use_default_shell_env=False,
                    progress_message="Building R package %s" % pkg_name)

    # Lightweight action to build just the source archive.
    ctx.actions.run(outputs=[pkg_src_archive], inputs=ctx.files.srcs, executable=ctx.executable._build_sh,
                    env=build_env + {"BUILD_SRC_ARCHIVE": "true"},
                    mnemonic="RSrcBuild", use_default_shell_env=False,
                    progress_message="Building R (source) package %s" % pkg_name)

    return [DefaultInfo(files=depset(output_files)),
            RPackage(pkg_name=pkg_name,
                     lib_path=pkg_lib_path,
                     lib_files=package_files,
                     src_files=ctx.files.srcs,
                     src_archive=pkg_src_archive,
                     bin_archive=pkg_bin_archive,
                     pkg_deps=ctx.attr.deps,
                     transitive_pkg_deps=library_deps["transitive_pkg_deps"],
                     transitive_tools=transitive_tools,
                     makevars_user=ctx.file.makevars_user,
                     cc_deps=cc_deps)
            ]

r_pkg = rule(
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Source files to be included for building the package",
        ),
        "pkg_name": attr.string(
            doc = "Name of the package if different from the target name",
        ),
        "deps": attr.label_list(
            providers = [RPackage],
            doc = "R package dependencies of type r_pkg",
        ),
        "cc_deps": attr.label_list(
            doc = "cc_library dependencies for this package",
        ),
        "build_args": attr.string_list(
            default = [
                "--no-build-vignettes",
                "--no-manual",
            ],
            doc = "Additional arguments to supply to R CMD build",
        ),
        "install_args": attr.string_list(
            doc = "Additional arguments to supply to R CMD INSTALL",
        ),
        "config_override": attr.label(
            allow_single_file = True,
            doc = "Replace the package configure script with this file",
        ),
        "roclets": attr.string_list(
            doc = ("roclets to run before installing the package. If this is " +
                   "non-empty, then roxygen2 must be a dependency of the package."),
        ),
        "makevars_user": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r_makevars//:Makevars",
            doc = "User level Makevars file",
        ),
        "shlib_name": attr.string(
            doc = "Shared library name, if different from package name",
        ),
        "lazy_data": attr.bool(
            default = False,
            doc = "Set to True if the package uses the LazyData feature",
        ),
        "post_install_files": attr.string_list(
            doc = "Extra files that the install process generates",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define for building the package",
        ),
        "tools": attr.label_list(
            doc = "Executables that code in this package will try to find in the system",
        ),
        "build_tools": attr.label_list(
            doc = "Executables that package build and load will try to find in the system",
        ),
        "_build_sh": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R:build.sh",
            executable = True,
            cfg = "host",
        ),
    },
    doc = ("Rule to install the package and its transitive dependencies" +
           "in the Bazel sandbox."),
    outputs = {
        "bin_archive": "%{name}.bin.tar.gz",
        "src_archive": "%{name}.tar.gz",
    },
    implementation = _build_impl,
)

def _test_impl(ctx):
    library_deps = _library_deps([ctx.attr.pkg] + ctx.attr.suggested_deps)

    pkg_name = ctx.attr.pkg[RPackage].pkg_name
    pkg_tests_dir = _package_dir(ctx) + "/tests"
    test_files = []
    for src_file in ctx.attr.pkg[RPackage].src_files:
        if src_file.path.startswith(pkg_tests_dir):
            test_files += [src_file]

    tools = _executables(ctx.attr.tools) + ctx.attr.pkg[RPackage].transitive_tools

    lib_dirs = ["_EXEC_ROOT_" + d.short_path for d in library_deps["lib_dirs"]]
    ctx.actions.expand_template(
        template = ctx.file._test_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{pkg_tests_dir}": pkg_tests_dir,
            "{export_env_vars}": "; ".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools),
            "{lib_dirs}": ":".join(lib_dirs),
            "{Rscript}": " ".join(_Rscript),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files=library_deps["lib_files"] + test_files,
                            transitive_files = tools)
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
            default = "@com_grail_rules_r//R:test.sh.tpl",
        ),
    },
    doc = ("Rule to keep all deps in the sandbox, and run the test " +
           "scripts of the specified package. The package itself must " +
           "be one of the deps."),
    test = True,
    implementation = _test_impl,
)

def _check_impl(ctx):
    src_archive = ctx.attr.pkg[RPackage].src_archive
    pkg_deps = ctx.attr.pkg[RPackage].pkg_deps
    transitive_tools = ctx.attr.pkg[RPackage].transitive_tools
    cc_deps = ctx.attr.pkg[RPackage].cc_deps
    makevars_user = ctx.attr.pkg[RPackage].makevars_user

    library_deps = _library_deps(ctx.attr.suggested_deps + pkg_deps)
    tools = _executables(ctx.attr.tools) + transitive_tools

    all_input_files = ([src_archive] + library_deps["lib_files"]
                       + tools.to_list()
                       + cc_deps["files"].to_list() + [makevars_user])

    lib_dirs = ["_EXEC_ROOT_" + d.short_path for d in library_deps["lib_dirs"]]
    ctx.actions.expand_template(
        template = ctx.file._check_sh_tpl,
        output = ctx.outputs.executable,
        substitutions = {
            "{export_env_vars}": "\n".join(_env_vars(ctx.attr.env_vars)),
            "{tools_export_cmd}": _runtime_path_export(tools),
            "{c_libs_flags}": " ".join(cc_deps["c_libs_flags_short"]),
            "{c_cpp_flags}": " ".join(cc_deps["c_cpp_flags_short"]),
            "{r_makevars_user}": makevars_user.short_path if makevars_user else "",
            "{lib_dirs}": ":".join(lib_dirs),
            "{check_args}": sh_quote_args(ctx.attr.check_args),
            "{pkg_src_archive}": src_archive.short_path,
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files=all_input_files)
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
            default = "@com_grail_rules_r//R:check.sh.tpl",
        ),
    },
    doc = ("Rule to keep all deps of the package in the sandbox, build " +
           "a source archive of this package, and run R CMD check on " +
           "the package source archive in the sandbox."),
    test = True,
    implementation = _check_impl,
)

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
    return [DefaultInfo(runfiles=runfiles, files=depset([ctx.outputs.executable]))]

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
            default = "@com_grail_rules_r//R:library.sh.tpl",
        ),
        "_tar_sh": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/internal:tar.sh",
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

def r_package(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps=[]):
    """Convenience macro to generate the r_pkg and r_library targets."""

    r_pkg(
        name = pkg_name,
        srcs = pkg_srcs,
        deps = pkg_deps,
    )

    r_library(
        name = "library",
        pkgs = [":" + pkg_name],
        tags = ["manual"],
    )

def r_package_with_test(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps=[], test_timeout="short"):
    """Convenience macro to generate the r_pkg, r_unit_test, r_pkg_test, and r_library targets."""

    r_pkg(
        name = pkg_name,
        srcs = pkg_srcs,
        deps = pkg_deps,
    )

    r_library(
        name = "library",
        pkgs = [pkg_name],
        tags = ["manual"],
    )

    r_unit_test(
        name = "test",
        timeout = test_timeout,
        pkg = pkg_name,
        suggested_deps = pkg_suggested_deps,
    )

    r_pkg_test(
        name = "check",
        timeout = test_timeout,
        pkg = pkg_name,
        suggested_deps = pkg_suggested_deps,
    )
