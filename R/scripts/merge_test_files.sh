#!/bin/bash
# Copyright 2021 The Bazel Authors.
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

set -euo pipefail

tar -xzf "${IN_TAR}" "${PKG_NAME}/DESCRIPTION"

# Uncompress the original tar.
new_tar="${IN_TAR}"
new_tar="${new_tar%.gz}"
gunzip -c "${IN_TAR}" > "${new_tar}"

# Copy the test files so we can reset their mtime so make the tarball reproducible.
dir=$(mktemp -d)
mkdir -p "${dir}"
rsync --recursive --copy-links --no-perms --chmod=u+w --executability --specials \
  "${PKG_SRC_DIR}/tests" "${dir}/${PKG_NAME}"
TZ=UTC find "${dir}" -exec touch -amt 197001010000 {} \+

# Append the files to the tar.
tar -rf "${new_tar}" -C "${dir}" "${PKG_NAME}/tests"
rm -rf "${dir}"

# Ask gzip to not store the timestamp.
gzip --no-name -c "${new_tar}" > "${OUT_TAR}"
