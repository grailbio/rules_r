# Copyright 2018 The Bazel Authors.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# covr is itself GPL-3, and we reuse some of the code.
licenses(["restricted"])  # GNU General Public License v3.0

load("@com_grail_rules_r//R:defs.bzl", "r_pkg")

r_pkg(
    name = "bazelCoverage",
    srcs = glob(
        ["**"],
        exclude = [
            "BUILD",
        ],
    ),
    deps = [
        "@R_covr//:covr",
    ],
    visibility = ["//visibility:public"],
)
