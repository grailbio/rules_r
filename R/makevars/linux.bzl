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

def _local_linux_makevars_impl(rctx):
    process_script = "exec {processor} < {src} > {out}".format(
        processor = _sh_quote(rctx.path(rctx.attr._processor)),
        src = _sh_quote(rctx.path(rctx.attr.src)),
        out = _sh_quote(rctx.name),
    )

    rctx.file("process.sh", content = process_script)

    exec_result = rctx.execute(["./process.sh"], environment = rctx.attr.env)
    if exec_result.return_code:
        fail("Failed to process file: %s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)

    rctx.file("BUILD", content = ('exports_files(["%s"])' % rctx.name))
    return

local_linux_makevars = repository_rule(
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/makevars:Makevars.linux.tpl",
            doc = "Template Makevars file.",
        ),
        "env": attr.string_dict(
            doc = "Environment variables to provide to processor.",
        ),
        "_processor": attr.label(
            default = "@com_grail_rules_r//R/makevars:Makevars.linux.sh",
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
    environ = ["PATH", "BAZEL_R_HOME"],
    local = True,
    implementation = _local_linux_makevars_impl,
)
