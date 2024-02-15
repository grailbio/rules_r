# Copyright 2021 The Bazel Authors.
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

def _local_darwin_makevars_impl(rctx):
    processor_args = []
    if rctx.attr.check_homebrew_llvm:
        processor_args.append("-b")
    if rctx.attr.clang_installed_dir_path:
        processor_args.append("-c " + rctx.attr.clang_installed_dir_path)

    process_script = "exec {processor} {processor_args} < {src} > {out}".format(
        processor = _sh_quote(rctx.path(rctx.attr._processor)),
        processor_args = " ".join(processor_args),
        src = _sh_quote(rctx.path(rctx.attr.src)),
        out = _sh_quote(rctx.name),
    )

    rctx.file("process.sh", content = process_script)

    exec_result = rctx.execute(["./process.sh"], environment = rctx.attr.env)
    if exec_result.return_code:
        fail("Failed to process file: %s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)

    rctx.file("BUILD", content = ('exports_files(["%s", "llvm-cov"])' % rctx.name))
    return

local_darwin_makevars = repository_rule(
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/makevars:Makevars.darwin.tpl",
            doc = "Template Makevars file.",
        ),
        "env": attr.string_dict(
            doc = "Environment variables to provide to processor.",
        ),
        "clang_installed_dir_path": attr.string(
            default = "",
            doc = ("Use this path as the directory where clang is installed. " +
                   "Overrides check_homebrew_llvm if not empty."),
        ),
        "check_homebrew_llvm": attr.bool(
            default = True,
            doc = ("Use Homebrew LLVM if installed. Can be overridden by " +
                   "setting the environment variable BAZEL_R_HOMEBREW to " +
                   "true or false. Also used to check gcc to find gfortran."),
        ),
        "_processor": attr.label(
            default = "@com_grail_rules_r//R/makevars:Makevars.darwin.sh",
            doc = ("Processor script to perform template substitution. " +
                   "Takes input file as STDIN and returns the processed " +
                   "file as STDOUT. May perform side actions in the " +
                   "workspace directory to create more files."),
        ),
    },
    doc = ("Repository rule to create a Makevars file for macOS that can " +
           "check for Homebrew LLVM and set compiler paths accordingly. " +
           "Also symlinks llvm-cov to be used as a tool in the toolchain " +
           "so that it can be used when collecting coverage."),
    configure = True,
    environ = ["PATH", "BAZEL_R_HOMEBREW"],
    local = True,
    implementation = _local_darwin_makevars_impl,
)
