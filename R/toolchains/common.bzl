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
"""This module defines common helper functions."""

def must_execute(rctx, arguments, timeout=600, environment={}, quiet=True):
    """Ensures that a command executes, and returns the stdout."""
    exec_result = rctx.execute(
        arguments,
        timeout = timeout,
        environment = environment,
        quiet = quiet,
    )
    if exec_result.return_code:
        fail("non-zero return code '%d':\n%s\n%s" % (
            exec_result.return_code, 
            exec_result.stderr,
            exec_result.stdout))
    return exec_result.stdout

def path_must_exist(rctx, str_path):
    """Gets a path from a string and ensure it exists."""
    path = rctx.path(str_path)
    if not path.exists:
        fail("'%s' does not exist" % str_path)
    return path

def find_executable(rctx, name):
    """Searches for an executable, either in the PATH or in a well-known location."""
    exe = rctx.which(name)
    if exe:
        return exe
    exe = rctx.path("/usr/local/bin/" + name)
    if exe.exists:
        return exe
    exe = rctx.path("/usr/bin/" + name)
    if exe.exists:
        return exe

    print("unable to find local '%s' executable" % name)
    return None

def get_r_version(rctx, rscript_bin, r_home = ""):
    """Gets the R version by running the `Rscript` binary."""
    return must_execute(
        rctx,
        [rscript_bin, "-e", "cat(sep='', version$major, '.', version$minor)"],
        environment = { "RHOME": r_home },
    )
