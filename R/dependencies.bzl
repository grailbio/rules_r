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
    "@com_grail_rules_r//internal:versions.bzl",
    _is_at_least = "is_at_least",
)
load(
    "@com_grail_rules_r//R/makevars:darwin.bzl",
    _local_darwin_makevars = "local_darwin_makevars",
)
load(
    "@com_grail_rules_r//R/makevars:linux.bzl",
    _local_linux_makevars = "local_linux_makevars",
)
load(
    "@com_grail_rules_r//R/internal/toolchains:local_toolchain.bzl",
    _local_r_toolchain = "local_r_toolchain",
)
load(
    "@com_grail_rules_r//R/internal:coverage_deps.bzl",
    _r_coverage_dependencies = "r_coverage_dependencies",
)

r_coverage_dependencies = _r_coverage_dependencies

def r_rules_dependencies():
    # Keep in sync with README.md and tests.yml.
    _is_at_least("3.5.0", native.bazel_version)

    # TODO: Use bazel-skylib directly instead of replicating functionality when
    # nested workspaces become a reality.  Otherwise, dependencies will need to
    # be loaded in two stages, first load skylib and then load this file.

    _maybe(
        _local_darwin_makevars,
        name = "com_grail_rules_r_makevars_darwin",
    )
    _maybe(
        _local_linux_makevars,
        name = "com_grail_rules_r_makevars_linux",
    )

def r_register_toolchains(**kwargs):
    _maybe(
        _local_r_toolchain,
        name = "com_grail_rules_r_toolchains",
        **kwargs
    )

    native.register_toolchains(
        "@com_grail_rules_r_toolchains//:toolchain",
    )

def _maybe(repo_rule, name, **kwargs):
    if not native.existing_rule(name):
        repo_rule(name = name, **kwargs)
