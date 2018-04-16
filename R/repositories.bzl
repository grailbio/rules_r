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

load("@com_grail_rules_r//R/internal:shell.bzl", "sh_quote")

_razel = attr.label(
    default = "@com_grail_rules_r//scripts:razel.R",
    allow_single_file = True,
    doc = "R source file containing razel functions.",
)

def _r_repository_impl(rctx):
    rctx.download_and_extract(rctx.attr.urls, sha256=rctx.attr.sha256, type=rctx.attr.type,
                              stripPrefix=rctx.attr.strip_prefix)

    if rctx.attr.build_file:
        rctx.symlink(rctx.attr.build_file, "BUILD.bazel")
        return

    razel = sh_quote(rctx.path(rctx.attr._razel))
    exec_result = rctx.execute(["/usr/bin/env", "Rscript",
                                "-e", "source(%s)" % razel,
                                "-e", "buildify()"])
    if exec_result.return_code:
        fail("Failed to generate BUILD file: \n%s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)
    return

# R repository rule that will generate a BUILD file for the package.
r_repository = repository_rule(
    attrs = {
        "urls": attr.string_list(),
        "strip_prefix": attr.string(),
        "type": attr.string(),
        "sha256": attr.string(),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "Optional BUILD file for this repo. If not provided, one will be generated.",
        ),
        "_razel": _razel,
    },
    implementation = _r_repository_impl,
)

def _dict_to_r_vec(d):
    # Convert a skylark dict to an named character vector for R.
    return ", ".join([k + "='" + v + "'" for k, v in d.items()])

def _r_repository_list_impl(rctx):
    razel = sh_quote(rctx.path(rctx.attr._razel))
    repos = "c(%s)" % _dict_to_r_vec(rctx.attr.remote_repos)

    args = {
        "package_list_csv": str(rctx.path(rctx.attr.package_list)),
        }
    if rctx.attr.build_file_overrides:
        args += {
            "build_file_overrides_csv": str(rctx.path(rctx.attr.build_file_overrides)),
            }
    args += rctx.attr.other_args

    function_call = "generateWorkspaceMacro(%s)" % _dict_to_r_vec(args)
    cmd = ["/usr/bin/env", "Rscript",
           "-e", "source(%s)" % razel,
           "-e", "options(repos=%s)" % repos,
           "-e", function_call,
           ]
    exec_result = rctx.execute(cmd)
    if exec_result.return_code:
        fail("Failed to generate bzl file: \n%s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)

    rctx.file("BUILD", content="", executable=False)
    return

# Repository rule that will generate a bzl file containing a macro for
# r_repository definitions from a CSV with package definitions.
r_repository_list = repository_rule(
    attrs = {
        "package_list": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "CSV containing packages with name, version and sha256; with a header.",
        ),
        "build_file_overrides": attr.label(
            mandatory = False,
            allow_single_file = True,
            doc = "CSV containing package name and BUILD file path; with a header.",
        ),
        "remote_repos": attr.string_dict(
            default = {"CRAN": "https://cloud.r-project.org"},
            doc = "Repo URLs to use.",
        ),
        "other_args": attr.string_dict(
            doc = "Other arguments to supply to generateWorkspaceMacro function in razel.",
        ),
        "_razel": _razel,
    },
    implementation = _r_repository_list_impl,
)
