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

# Make a script file for sed that can substitute status vars enclosed in {}, with their values.
status_substitution_commands="$(mktemp --tmpdir=bazel-out)"
add_substitute_commands() {
  local status_file="$1"
  sed -e 's/@/\\@/' -e 's/^/s@{/' -e 's/ /}@/' -e 's/$/@/' "${status_file}" >> \
      "${status_substitution_commands}"
}

add_metadata() {
  local IFS=","
  for status_file in ${STATUS_FILES}; do
    add_substitute_commands "${status_file}"
  done
  for key_value in ${METADATA_MAP:-}; do
    IFS=":" read -r key value <<< "${key_value}"
    value=$(echo "${value}" | sed -f "${status_substitution_commands}")
    printf "%s: %s\\n" "${key}" "${value}" >> "${PKG_NAME}/DESCRIPTION"
  done
}
add_metadata
rm "${status_substitution_commands}"

# Uncompress the original tar.
new_tar="${IN_TAR}"
new_tar="${new_tar%.gz}"
gunzip -c "${IN_TAR}" > "${new_tar}"

# Reset mtime so that tarball is reproducible.
TZ=UTC touch -amt 197001010000 "${PKG_NAME}/DESCRIPTION"
# Repackage the DESCRIPTION into the tar.
tar -rf "${new_tar}" "${PKG_NAME}/DESCRIPTION"

# Compress the tar and ask gzip to not store the timestamp.
mkdir -p "$(dirname "${OUT_TAR}")"
gzip --no-name -c "${new_tar}" > "${OUT_TAR}"
