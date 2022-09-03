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

def detect_os(rctx):
    """Detects the host operating system.

    Returns one of "darwin", "linux" or "windows", or raises an error.
    """
    os_name = rctx.os.name.lower()
    if os_name.startswith("mac os"):
        return "darwin"
    elif os_name == "linux":
        return "linux"
    elif os_name.startswith("windows"):
        return "windows"
    else:
        fail("unsupported %s" % os_name)
