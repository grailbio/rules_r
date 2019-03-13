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

load("@com_grail_rules_r//internal:shell.bzl", "sh_quote")

_razel = attr.label(
    default = "@com_grail_rules_r//scripts:razel.R",
    allow_single_file = True,
    doc = "R source file containing razel functions.",
)

def _py_type_to_r_type(v):
    # Hack: We equate "TRUE" as True, because dict attributes can not have heterogenous values.
    if v == True or v == "TRUE":
        return "TRUE"
    elif v == False or v == "FALSE":
        return "FALSE"
    else:
        return "'" + v + "'"

def _dict_to_r_vec(d):
    # Convert a skylark dict to a named character vector for R.
    return ", ".join([k + "=" + _py_type_to_r_type(v) for k, v in d.items()])

def _r_repository_impl(rctx):
    if not rctx.attr.urls:
        fail(("No sources found for repository '@%s'. Perhaps this package is " % rctx.name) +
             "not available for your R version.")

    archive_basename = rctx.attr.urls[0].rsplit("/", maxsplit = 1)[1]

    if rctx.attr.pkg_type == "source":
        rctx.download_and_extract(
            rctx.attr.urls,
            sha256 = rctx.attr.sha256,
            type = rctx.attr.type,
            stripPrefix = rctx.attr.strip_prefix,
        )
    else:
        rctx.download(rctx.attr.urls, output = archive_basename, sha256 = rctx.attr.sha256)

    if rctx.attr.build_file:
        rctx.symlink(rctx.attr.build_file, "BUILD.bazel")
        return

    args = dict(rctx.attr.razel_args)
    if rctx.attr.pkg_type == "binary":
        args["pkg_bin_archive"] = archive_basename

    razel = sh_quote(rctx.path(rctx.attr._razel))
    exec_result = rctx.execute([
        "Rscript",
        "--vanilla",
        "-e",
        "source(%s)" % razel,
        "-e",
        "buildify(%s)" % _dict_to_r_vec(args),
    ])
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
        "pkg_type": attr.string(
            default = "source",
            doc = "Type of package archive (source or binary).",
            values = [
                "source",
                "binary",
            ],
        ),
        "razel_args": attr.string_dict(
            doc = "Other arguments to supply to buildify function in razel.",
        ),
        "_razel": _razel,
    },
    implementation = _r_repository_impl,
)

def _r_repository_list_impl(rctx):
    rctx.file("BUILD", content = "", executable = False)

    if not rctx.which("Rscript"):
        rctx.file("r_repositories.bzl", content = """
def r_repositories():
    return
""", executable = False)
        return

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
    cmd = [
        "Rscript",
        "--vanilla",
        "-e",
        "source(%s)" % razel,
        "-e",
        "options(repos=%s)" % repos,
        "-e",
        function_call,
    ]
    exec_result = rctx.execute(cmd)
    if exec_result.return_code:
        fail("Failed to generate bzl file: \n%s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)

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
