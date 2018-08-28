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
    _R = "R",
    _Rscript = "Rscript",
    _build_path_export = "build_path_export",
    _env_vars = "env_vars",
    _executables = "executables",
    _library_deps = "library_deps",
    _package_dir = "package_dir",
)
load("@com_grail_rules_r//R:providers.bzl", "RPackage")

# From the global R Makeconf.
_NATIVE_SOURCE_EXTS = [
    "c",
    "cc",
    "cpp",
    "h",
    "hpp",
    "m",
    "mm",
    "M",
    "f",
    "f95",
    "f90",
]

# From https://cran.r-project.org/doc/manuals/r-release/R-exts.html#DOCF13.
_R_SOURCE_EXTS = [
    "R",
    "S",
    "q",
    "r",
    "s",
]

_SOURCE_EXTS = _NATIVE_SOURCE_EXTS + _R_SOURCE_EXTS

def _package_name(ctx):
    # Package name from attribute with fallback to label name.

    pkg_name = ctx.attr.pkg_name
    if pkg_name == "":
        pkg_name = ctx.label.name
    return pkg_name

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

def _cc_deps(ctx, instrumented):
    # Returns information for native code compilation.

    cc_deps = ctx.attr.cc_deps
    bin_dir = ctx.bin_dir.path
    gen_dir = ctx.genfiles_dir.path

    # Give absolute paths to R.
    root_path = "_EXEC_ROOT_"

    # bazel currently instruments all cc libraries if instrumentation is enabled.
    # TODO: Track this behavior and  when instrumentation filters work as
    # expected, change default to False, setting to True only if coverage is
    # enabled and any transitive dep is instrumented.
    instrumented_cc_deps = (cc_deps and ctx.configuration.coverage_enabled)

    libs = depset(order = "topological")
    link_flags = []
    hdrs = depset()
    c_cpp_flags = depset()
    c_cpp_flags_short = depset()
    for d in cc_deps:
        libs += d.cc.libs
        link_flags += d.cc.link_flags
        hdrs += d.cc.transitive_headers

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

    c_so_files = []
    c_libs_flags = list(link_flags)
    c_libs_flags_short = list(link_flags)
    for l in libs:
        # dylib is not supported because macOS does not support $ORIGIN in rpath.
        if l.extension == "so":
            c_so_files += [l]

            # We copy the file in srcs and set relative rpath for R CMD INSTALL.
            c_libs_flags += [l.basename]

            # We use LD_LIBRARY_PATH for R CMD check.
            c_libs_flags_short += [root_path + l.short_path]
            continue
        c_libs_flags += [root_path + l.path]
        c_libs_flags_short += [root_path + l.short_path]

    # Note that clang has multiple code coverage implementations. covr can only
    # use the gcc compatible implementation based on DebugInfo.  This might be
    # different from how your other C++ libraries are being instrumented if you
    # are using an LLVM toolchain. And so we ignore cc_deps when computing
    # coverage.
    # https://cran.r-project.org/web/packages/covr/vignettes/how_it_works.html
    # https://clang.llvm.org/docs/SourceBasedCodeCoverage.html
    if instrumented:
        c_cpp_flags += [
            "--coverage",
            # Ensure that, e.g., functions are not inlined (with optimization,
            # the inlined functions would not be "hit").
            "-O0",
        ]
        c_cpp_flags_short += ["--coverage"]

    if instrumented or instrumented_cc_deps:
        c_libs_flags += ["--coverage", "-O0"]
        c_libs_flags_short += ["--coverage", "-O0"]

    return {
        "files": hdrs + libs,
        "c_so_files": c_so_files,
        "c_libs_flags": c_libs_flags,
        "c_libs_flags_short": c_libs_flags_short,
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

def _build_impl(ctx):
    # Implementation for the r_pkg rule.

    pkg_name = _package_name(ctx)
    pkg_src_dir = _package_dir(ctx)
    pkg_lib_dir = ctx.actions.declare_directory("lib")
    pkg_bin_archive = ctx.outputs.bin_archive
    pkg_src_archive = ctx.outputs.src_archive
    flock = ctx.attr._flock.files_to_run.executable

    instrumented = ctx.coverage_instrumented()

    pkg_deps = list(ctx.attr.deps)

    library_deps = _library_deps(pkg_deps)
    cc_deps = _cc_deps(ctx, instrumented)
    transitive_tools = library_deps["transitive_tools"] + _executables(ctx.attr.tools)
    build_tools = _executables(ctx.attr.build_tools) + transitive_tools
    instrument_files = [ctx.file._instrument_R] if instrumented else []
    all_input_files = (library_deps["lib_dirs"] + ctx.files.srcs +
                       cc_deps["files"].to_list() +
                       build_tools.to_list() + [ctx.file.makevars_user, flock] + instrument_files)

    if ctx.file.config_override:
        all_input_files += [ctx.file.config_override]
        orig_config = pkg_src_dir + "/configure"
        all_input_files = _remove_file(all_input_files, orig_config)

    install_args = list(ctx.attr.install_args)
    pkg_src_files = ctx.files.srcs + cc_deps["c_so_files"]
    output_files = [pkg_lib_dir, pkg_bin_archive]
    pkg_gcno_dir = None

    if instrumented:
        # We need to keep the sources for code coverage to work.
        # NOTE: With these options, each installed object in package namespaces gets a
        # srcref attribute that has the source filenames as when installing the package.
        # For non-reproducible builds, these will be sandbox paths, and for reproducible
        # builds, these will be /tmp paths.
        install_args.extend(["--with-keep.source"])

        # We also need to collect the instrumented .gcno files from the package.
        pkg_gcno_dir = ctx.actions.declare_directory("src")
        output_files.append(pkg_gcno_dir)

    build_env = {
        "PKG_LIB_PATH": pkg_lib_dir.path,
        "PKG_SRC_DIR": pkg_src_dir,
        "PKG_NAME": pkg_name,
        "PKG_SRC_ARCHIVE": pkg_src_archive.path,
        "PKG_BIN_ARCHIVE": pkg_bin_archive.path,
        "R_MAKEVARS_USER": ctx.file.makevars_user.path if ctx.file.makevars_user else "",
        "CONFIG_OVERRIDE": ctx.file.config_override.path if ctx.file.config_override else "",
        "ROCLETS": ", ".join(["'%s'" % r for r in ctx.attr.roclets]),
        "C_LIBS_FLAGS": " ".join(cc_deps["c_libs_flags"]),
        "C_CPP_FLAGS": " ".join(cc_deps["c_cpp_flags"]),
        "C_SO_FILES": _sh_quote_args([f.path for f in cc_deps["c_so_files"]]),
        "R_LIBS": ":".join(["_EXEC_ROOT_" + d.path for d in library_deps["lib_dirs"]]),
        "BUILD_ARGS": _sh_quote_args(ctx.attr.build_args),
        "INSTALL_ARGS": _sh_quote_args(install_args),
        "EXPORT_ENV_VARS_CMD": "; ".join(_env_vars(ctx.attr.env_vars)),
        "BUILD_TOOLS_EXPORT_CMD": _build_path_export(build_tools),
        "FLOCK_PATH": flock.path,
        "INSTRUMENT_SCRIPT": ctx.file._instrument_R.path,
        "REPRODUCIBLE_BUILD": "true" if "rlang-reproducible" in ctx.features else "false",
        "INSTRUMENTED": "true" if instrumented else "false",
        "BAZEL_R_DEBUG": "true" if "rlang-debug" in ctx.features else "false",
        "BAZEL_R_VERBOSE": "true" if "rlang-verbose" in ctx.features else "false",
        "R": " ".join(_R),
        "RSCRIPT": " ".join(_Rscript),
    }
    ctx.actions.run(
        outputs = output_files,
        inputs = all_input_files,
        executable = ctx.executable._build_sh,
        env = build_env,
        mnemonic = "RBuild",
        use_default_shell_env = False,
        progress_message = "Building R package %s" % pkg_name,
    )

    # Lightweight action to build just the source archive.
    ctx.actions.run(
        outputs = [pkg_src_archive],
        inputs = pkg_src_files,
        executable = ctx.executable._build_sh,
        env = build_env + {"BUILD_SRC_ARCHIVE": "true"},
        mnemonic = "RSrcBuild",
        use_default_shell_env = False,
        progress_message = "Building R (source) package %s" % pkg_name,
    )

    return struct(
        instrumented_files = struct(
            # List the dependencies in which transitive instrumented files could be found.
            # NOTE: cc_deps and tools could be instrumented in a way that
            # is incompatible with covr, so we should not include them here.
            dependency_attributes = ["deps"],
            extensions = _SOURCE_EXTS,
            source_attributes = ["srcs"],
        ),
        providers = [
            DefaultInfo(
                files = depset(output_files),
                runfiles = ctx.runfiles([pkg_lib_dir], collect_default = True),
            ),
            RPackage(
                bin_archive = pkg_bin_archive,
                build_tools = build_tools,
                cc_deps = cc_deps,
                external_repo = ("external-r-repo" in ctx.attr.tags),
                makevars_user = ctx.file.makevars_user,
                pkg_deps = pkg_deps,
                pkg_gcno_dir = pkg_gcno_dir,
                pkg_lib_dir = pkg_lib_dir,
                pkg_name = pkg_name,
                src_archive = pkg_src_archive,
                src_files = ctx.files.srcs,
                transitive_pkg_deps = library_deps["transitive_pkg_deps"],
                transitive_tools = transitive_tools,
            ),
        ],
    )

def _build_binary_pkg_impl(ctx):
    pkg_name = _package_name(ctx)
    pkg_lib_dir = ctx.actions.declare_directory("lib")
    pkg_bin_archive = ctx.file.src
    library_deps = _library_deps(ctx.attr.deps)
    transitive_tools = library_deps["transitive_tools"] + _executables(ctx.attr.tools)

    build_env = {
        "PKG_LIB_PATH": pkg_lib_dir.path,
        "PKG_NAME": pkg_name,
        "PKG_BIN_ARCHIVE": pkg_bin_archive.path,
        "INSTALL_BIN_ARCHIVE": "true",
        "R_LIBS": ":".join(["_EXEC_ROOT_" + d.path for d in library_deps["lib_dirs"]]),
        "INSTALL_ARGS": _sh_quote_args(ctx.attr.install_args),
        "EXPORT_ENV_VARS_CMD": "; ".join(_env_vars(ctx.attr.env_vars)),
        "BAZEL_R_DEBUG": "true" if "rlang-debug" in ctx.features else "false",
        "BAZEL_R_VERBOSE": "true" if "rlang-verbose" in ctx.features else "false",
        "R": " ".join(_R),
        "RSCRIPT": " ".join(_Rscript),
    }
    ctx.actions.run(
        outputs = [pkg_lib_dir],
        inputs = [pkg_bin_archive],
        executable = ctx.executable._build_sh,
        env = build_env,
        mnemonic = "RBuildBinary",
        use_default_shell_env = False,
        progress_message = "Extracting R binary package %s" % pkg_name,
    )

    return [
        DefaultInfo(
            files = depset([pkg_lib_dir]),
            runfiles = ctx.runfiles([pkg_lib_dir], collect_default = True),
        ),
        RPackage(
            bin_archive = pkg_bin_archive,
            build_tools = None,
            cc_deps = None,
            external_repo = ("external-r-repo" in ctx.attr.tags),
            makevars_user = None,
            pkg_deps = ctx.attr.deps,
            pkg_gcno_dir = None,
            pkg_lib_dir = pkg_lib_dir,
            pkg_name = pkg_name,
            src_archive = None,
            src_files = None,
            transitive_pkg_deps = library_deps["transitive_pkg_deps"],
            transitive_tools = transitive_tools,
        ),
    ]

_COMMON_ATTRS = {
    "pkg_name": attr.string(
        doc = "Name of the package if different from the target name",
    ),
    "deps": attr.label_list(
        providers = [RPackage],
        doc = "R package dependencies of type r_pkg",
    ),
    "tools": attr.label_list(
        doc = "Executables that code in this package will try to find in the system",
    ),
    "install_args": attr.string_list(
        doc = "Additional arguments to supply to R CMD INSTALL",
    ),
    "env_vars": attr.string_dict(
        doc = "Extra environment variables to define for building the package",
    ),
    "_build_sh": attr.label(
        allow_single_file = True,
        default = "@com_grail_rules_r//R/scripts:build.sh",
        executable = True,
        cfg = "host",
    ),
}

r_pkg = rule(
    attrs = _COMMON_ATTRS + {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Source files to be included for building the package",
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
        "build_tools": attr.label_list(
            doc = "Executables that package build and load will try to find in the system",
        ),
        "_flock": attr.label(
            default = "@com_grail_rules_r//R/scripts:flock",
            executable = True,
            cfg = "host",
        ),
        "_instrument_R": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/scripts:instrument.R",
        ),
    },
    doc = ("Rule to install the package and its transitive dependencies " +
           "in the Bazel sandbox."),
    outputs = {
        "bin_archive": "%{name}.bin.tar.gz",
        "src_archive": "%{name}.tar.gz",
    },
    implementation = _build_impl,
)

r_binary_pkg = rule(
    attrs = _COMMON_ATTRS + {
        "src": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "Binary archive of the package",
        ),
    },
    doc = ("Rule to install the package and its transitive dependencies in " +
           "the Bazel sandbox from a binary archive."),
    implementation = _build_binary_pkg_impl,
)
