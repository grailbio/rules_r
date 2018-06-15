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

load("@com_grail_rules_r//internal:os.bzl", "detect_os")

def _r_makevars_impl(rctx):
    if rctx.attr.makevars_darwin:
        rctx.symlink(rctx.attr.makevars_darwin, "Makevars.darwin")
    else:
        rctx.file("Makevars.darwin", executable = False)

    if rctx.attr.makevars_linux:
        rctx.symlink(rctx.attr.makevars_linux, "Makevars.linux")
    else:
        rctx.file("Makevars.linux", executable = False)

    if detect_os(rctx) == "darwin":
        rctx.symlink("Makevars.darwin", "Makevars")
    else:
        rctx.symlink("Makevars.linux", "Makevars")

    files = '["' + '", "'.join(["Makevars"]) + '"]'
    rctx.file("BUILD", content = ("exports_files(%s)" % files))
    return

r_makevars = repository_rule(
    attrs = {
        "makevars_darwin": attr.label(
            default = "@com_grail_rules_r_makevars_darwin",
            allow_single_file = True,
            doc = "Makevars file to use for macOS overrides.",
        ),
        "makevars_linux": attr.label(
            allow_single_file = True,
            doc = "Makevars file to use for Linux overrides.",
        ),
    },
    local = True,
    implementation = _r_makevars_impl,
)
