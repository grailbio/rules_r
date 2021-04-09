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

# Flags for reproducible builds.
CPPFLAGS += "-Wno-builtin-macro-redefined" \
  "-D__DATE__=\"redacted\"" \
  "-D__TIMESTAMP__=\"redacted\"" \
  "-D__TIME__=\"redacted\"" \
  "-fdebug-prefix-map=_EXEC_ROOT_=" \
  "-fmacro-prefix-map=_EXEC_ROOT_="

CPPFLAGS += @CPPFLAGS@
