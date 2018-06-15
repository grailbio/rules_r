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

load("@com_grail_rules_r//internal:shell.bzl", "sh_quote", "sh_quote_args")

def _process_file_impl(rctx):
    process_script = "exec {processor} {processor_args} < {src} > {out}".format(
        processor = sh_quote(rctx.path(rctx.attr.processor)),
        processor_args = sh_quote_args(rctx.attr.processor_args),
        src = sh_quote(rctx.path(rctx.attr.src)),
        out = sh_quote(rctx.name),
    )

    rctx.file("process.sh", content = process_script)

    exec_result = rctx.execute(["./process.sh"], environment = rctx.attr.env)
    if exec_result.return_code:
        fail("Failed to process file: %s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)

    rctx.file("BUILD", content = ('exports_files(["%s"])' % rctx.name))
    return

# Repository rule that will process an input file and return the processed file
# with the same name as the repository.
process_file = repository_rule(
    attrs = {
        "processor": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "host",
            doc = ("Executable that will take the input file as STDIN and " +
                   "return the processed file as STDOUT"),
        ),
        "processor_args": attr.string_list(
            doc = "Arguments to supply to the processor.",
        ),
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Input file for the processor.",
        ),
        "env": attr.string_dict(
            doc = "Environment variables to provide to processor.",
        ),
    },
    environ = ["PATH"],
    local = True,
    implementation = _process_file_impl,
)
