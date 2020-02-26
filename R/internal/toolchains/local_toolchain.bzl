# Copyright 2019 The Bazel Authors.
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

load("@com_grail_rules_r//internal:os.bzl", "detect_os")

_home_env_var = "BAZEL_R_HOME"

def _must_execute(rctx, cmd, fail_msg):
    exec_result = rctx.execute(cmd)
    if exec_result.return_code != 0:
        fail("%s: %d\n%s\n%s" %
             (fail_msg, exec_result.return_code, exec_result.stdout, exec_result.stderr))

    return exec_result.stdout

def _path_must_exist(rctx, str_path):
    path = rctx.path(str_path)
    if not path.exists:
        fail("'%s' does not exist" % str_path)
    return path

def _get_r_version(rctx, rscript):
    return _must_execute(
        rctx,
        [rscript, "-e", "cat(sep='', version$major, '.', version$minor)"],
        "Unable to obtain R version",
    )

def _check_version(expected, actual):
    if expected != actual:
        fail("Expected R version '%s', got '%s'" % (expected, actual))

_BUILD = """load("@com_grail_rules_r//R/internal/toolchains:toolchain.bzl", "r_toolchain")

exports_files(
    ["{state_file}"]
)

r_toolchain(
    name = "r_toolchain_generic",
    r = "{r}",
    rscript = "{rscript}",
    version = {version},
    args = [{args}],
    makevars_site = {makevars_site},
    tools = [{tools}],
    system_state_file = "{state_file}",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain",
    toolchain = "@com_grail_rules_r_toolchains//:r_toolchain_generic",
    toolchain_type = "@com_grail_rules_r//R:toolchain_type",
    visibility = ["//visibility:public"],
)
"""

def _local_r_toolchain_impl(rctx):
    r_home = rctx.attr.r_home
    version = rctx.attr.version

    exec_result = rctx.execute(["printenv", _home_env_var])
    if exec_result.return_code == 0:
        r_home = exec_result.stdout.strip()

    if r_home:
        r = rctx.path("%s/bin/R" % r_home)
        rscript = rctx.path("%s/bin/Rscript" % r_home)
    else:
        r = rctx.which("R")
        rscript = rctx.which("Rscript")

    if rctx.attr.strict:
        if not r or not rctx.path(r).exists:
            fail("R not found")
        if not rscript or not rctx.path(rscript).exists:
            fail("Rscript not found")

    makevars_site_str = "None"
    if detect_os(rctx) == "darwin":
        makevars_site_str = "\"@com_grail_rules_r_makevars_darwin\""

    state_file = "system_state.txt"
    exec_result = rctx.execute(
        [rctx.path(rctx.attr._system_state_computer), rctx.path(state_file)],
        environment = {
            "R": str(r),
            "RSCRIPT": str(rscript),
            "SITE_FILES_FLAG": "--no-site-files" if "-no-site-file" in rctx.attr.args else "",
            "ARGS": " ".join(rctx.attr.args),
            "REQUIRED_VERSION": rctx.attr.version,
        },
    )
    if exec_result.return_code != 0:
        fail("system_state_computer failed (%d):\n%s\n%s" % (
            exec_result.return_code,
            exec_result.stdout,
            exec_result.stderr,
        ))

    rctx.file("WORKSPACE", """workspace(name = %s)""" % rctx.name)
    rctx.file("BUILD.bazel", _BUILD.format(
        r = r,
        rscript = rscript,
        version = "\"%s\"" % rctx.attr.version if rctx.attr.version else "None",
        args = ", ".join(["\"%s\"" % arg for arg in rctx.attr.args]),
        makevars_site = makevars_site_str if rctx.attr.makevars_site else "None",
        tools = ", ".join(["\"%s\"" % tool for tool in rctx.attr.tools]),
        state_file = state_file,
    ))

# A generator for r_toolchain type that uses environment variables to locate R
local_r_toolchain = repository_rule(
    attrs = {
        "r_home": attr.string(
            doc = ("A path to `R_HOME` (as returned from `R RHOME`). If not specified, " +
                   "the rule looks for R and Rscript in `PATH`. The environment variable " +
                   "`%s` takes precendence over this value." % _home_env_var),
        ),
        "strict": attr.bool(
            default = True,
            doc = "Fail if R is not found on the host system.",
        ),
        "makevars_site": attr.bool(
            default = True,
            doc = "Generate a site-wide Makevars file",
        ),
        "version": attr.string(
            doc = "version attribute value for r_toolchain",
        ),
        "args": attr.string_list(
            default = [
                "--no-save",
                "--no-site-file",
                "--no-environ",
            ],
            doc = "args attribute value for r_toolchain",
        ),
        "tools": attr.string_list(
            doc = "tools attribute value for r_toolchain",
        ),
        "_system_state_computer": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R/scripts:system_state.sh",
            doc = "Executable to output R system state",
        ),
    },
    configure = True,
    environ = [_home_env_var],
    implementation = _local_r_toolchain_impl,
)
