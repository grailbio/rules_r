# Copyright Copyright 2018 The Bazel Authors.
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

_RUNFILES_CMDS = """
case "$0" in
 /*) self="$0" ;;
 *) self="$PWD/$0" ;;
esac

if [[ -n "${TEST_SRCDIR-}" ]]; then
  # Case 4, bazel has identified runfiles for us.
  RUNFILES="$TEST_SRCDIR"
else
  while true; do
    if [[ -e "$self.runfiles" ]]; then
      RUNFILES="$self.runfiles"
      break
    fi

    if [[ $self == *.runfiles/* ]]; then
      RUNFILES="${self%%.runfiles/*}.runfiles"
      # don't break; this is a last resort for case 6b
    fi

    if [[ ! -L "$self" ]]; then
      break;
    fi

    readlink="$(readlink "$self")"
    if [[ "$readlink" = /* ]]; then
      self="$readlink"
    else
      # resolve relative symlink
      self="${self%%/*}/$readlink"
    fi
  done

  if [[ -z "$RUNFILES" ]]; then
    echo " >>>> FAIL: RUNFILES environment variable is not set. <<<<" >&2
    exit 1
  fi
fi
export RUNFILES
"""

def runfiles_commands():
  return _RUNFILES_CMDS.split("\n")
