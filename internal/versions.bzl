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

# These functions have been copied from
# github.com/bazelbuild/bazel-skylib/lib/versions.bzl (tag 0.3.1)

def _extract_version_number(bazel_version):
    """Extracts the semantic version number from a version string

    Args:
      bazel_version: the version string that begins with the semantic version
        e.g. "1.2.3rc1 abc1234" where "abc1234" is a commit hash.

    Returns:
      The semantic version string, like "1.2.3".
    """
    for i in range(len(bazel_version)):
        c = bazel_version[i]
        if not (c.isdigit() or c == "."):
            return bazel_version[:i]
    return bazel_version

# Parse the bazel version string from `native.bazel_version`.
# e.g.
# "0.10.0rc1 abc123d" => (0, 10, 0)
# "0.3.0" => (0, 3, 0)
def _parse_bazel_version(bazel_version):
    """Parses a version string into a 3-tuple of ints
    int tuples can be compared directly using binary operators (<, >).

    Args:
      bazel_version: the Bazel version string

    Returns:
      An int 3-tuple of a (major, minor, patch) version.
    """

    version = _extract_version_number(bazel_version)
    return tuple([int(n) for n in version.split(".")])

def is_at_least(threshold, version):
    """Check that a version is higher or equals to a threshold.
    Args:
      threshold: the minimum version string
      version: the version string to be compared to the threshold
    Returns:
      True if version >= threshold.
    """

    return _parse_bazel_version(version) >= _parse_bazel_version(threshold)
