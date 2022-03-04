#!/usr/bin/env Rscript
# Copyright 2020 The Bazel Authors.
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

descA <- packageDescription("exampleA")
descB <- packageDescription("exampleB")

assertEqual <- function(got, want) {
  if (got != want) {
    stop(sprintf("got %s, want %s", got, want))
  }
}

assertEqual(descA[["VAR"]], "foo")
assertEqual(descA[["STABLE_VAR"]], "STABLE_VAR") # not enclosed in {}.

assertEqual(descB[["VAR"]], "foo")
assertEqual(descB[["STABLE_VAR"]], "bar")
