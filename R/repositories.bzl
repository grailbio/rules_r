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
    "@rules_r//R/internal:common.bzl",
    _dict_to_r_vec = "dict_to_r_vec",
    _get_r_version = "get_r_version",
    _quote_dict_values = "quote_dict_values",
    _quote_literal = "quote_literal",
    _unquote_string = "unquote_string",
)
load("@rules_r//internal:shell.bzl", _sh_quote = "sh_quote")

_rscript = attr.string(
    default = "Rscript",
    doc = "Name, path or label of the interpreter to use for running the razel script.",
)
_razel = attr.label(
    default = "@rules_r//scripts:razel.R",
    allow_single_file = True,
    doc = "R source file containing razel functions.",
)

_razel_tmp_script_name = "razel_script.R"

def _rscript_path(rctx):
    str_path = rctx.attr.rscript
    if str_path.startswith("@") or str_path.startswith("//"):
        return rctx.path(Label(str_path))
    elif str_path.find("/") != -1:
        return str_path
    else:
        return rctx.which(str_path)

def _r_repository_impl(rctx):
    if not rctx.attr.urls:
        fail(("No sources found for repository '@%s'. Perhaps this package is " % rctx.name) +
             "not available for your R version.")

    archive_basename = rctx.attr.urls[0].rsplit("/", 1)[1]

    extracted = False
    if rctx.attr.pkg_type == "source":
        extracted = True
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
    if rctx.attr.pkg_type == "source_archive":
        args["pkg_directory"] = rctx.attr.strip_prefix
        args["pkg_src_archive"] = archive_basename
    elif rctx.attr.pkg_type == "binary_archive":
        args["pkg_directory"] = rctx.attr.strip_prefix
        args["pkg_bin_archive"] = archive_basename

    script_content = """
source({razel})
buildify({args})
""".format(
        razel = _quote_literal(str(rctx.path(rctx.attr._razel))),
        args = _dict_to_r_vec(_quote_dict_values(args)),
    )
    rctx.file(_razel_tmp_script_name, content = script_content)

    exec_result = rctx.execute([
        _rscript_path(rctx),
        "--vanilla",
        _razel_tmp_script_name,
    ])
    if exec_result.return_code:
        fail("Failed to generate BUILD file: \n%s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)
    rctx.delete(_razel_tmp_script_name)

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
                "source_archive",
                "binary_archive",
            ],
        ),
        "razel_args": attr.string_dict(
            doc = "Other arguments to supply to buildify function in razel.",
        ),
        "rscript": _rscript,
        "_razel": _razel,
    },
    implementation = _r_repository_impl,
)

def _failing_repository_impl(rctx):
    fail(rctx.attr.msg)

failing_repository = repository_rule(
    attrs = {
        "msg": attr.string(mandatory = True),
    },
    implementation = _failing_repository_impl,
)

def _failing_r_repository_list(rctx, msg_suffix):
    version_str = " (version %s)" % rctx.attr.r_version if rctx.attr.r_version else ""
    repo_name_prefix = rctx.attr.other_args.get("repo_name_prefix", default = "R_")

    package_list = rctx.read(rctx.attr.package_list)
    package_lines = package_list.split("\n")[1:]  # Discard header line.
    package_names = [line.split(",")[0] for line in package_lines]
    repository_tpl = """
    failing_repository(
        name = "{name}",
        msg = "R{version_str} not found on host machine{msg_suffix}",
    )
"""
    repository_defs = [
        repository_tpl.format(
            name = "%s%s" % (repo_name_prefix, _unquote_string(package_name)),
            version_str = version_str,
            msg_suffix = msg_suffix,
        )
        for package_name in package_names
        if package_name != ""
    ]

    content = """
load("@rules_r//R:repositories.bzl", "failing_repository")

# R{version_str} not found on host machine; substituting package repositories
# with rules that will fail on first load.

def r_repositories():
{repository_defs_lines}
    return
""".format(version_str = version_str, repository_defs_lines = "\n".join(repository_defs))
    rctx.file("r_repositories.bzl", content = content, executable = False)

    return

def _r_repository_list_impl(rctx):
    rctx.file("BUILD", content = "", executable = False)

    _rscript = _rscript_path(rctx)
    do_fail = False
    fail_msg_suffix = ""
    if not _rscript:
        do_fail = True
    elif rctx.attr.r_version and _get_r_version(rctx, _rscript) != rctx.attr.r_version:
        do_fail = True
        fail_msg_suffix = "; found R (version %s)" % _get_r_version(rctx, _rscript)
    if do_fail:
        _failing_r_repository_list(rctx, fail_msg_suffix)
        return

    args = {
        "package_list_csv": str(rctx.path(rctx.attr.package_list)),
        "rscript": _quote_literal(rctx.attr.rscript),
    }
    if rctx.attr.build_file_overrides:
        args.update({
            "build_file_overrides_csv": str(rctx.path(rctx.attr.build_file_overrides)),
        })
    args.update(rctx.attr.other_args)
    script_content = """
source({razel})
options(repos = c({repos}))
generateWorkspaceMacro({args})
""".format(
        razel = _quote_literal(str(rctx.path(rctx.attr._razel))),
        repos = _dict_to_r_vec(_quote_dict_values(rctx.attr.remote_repos)),
        args = _dict_to_r_vec(_quote_dict_values(args)),
    )
    rctx.file(_razel_tmp_script_name, content = script_content)

    cmd = [
        _rscript,
        "--vanilla",
        _razel_tmp_script_name,
    ]
    exec_result = rctx.execute(cmd)
    if exec_result.return_code:
        fail("Failed to generate bzl file: \n%s\n%s" % (exec_result.stdout, exec_result.stderr))
    if exec_result.stderr:
        print(exec_result.stderr)
    rctx.delete(_razel_tmp_script_name)

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
        "rscript": _rscript,
        "r_version": attr.string(
            doc = "If provided, ensure version of R matches this string in x.y form.",
        ),
        "_razel": _razel,
    },
    configure = True,
    implementation = _r_repository_list_impl,
)
