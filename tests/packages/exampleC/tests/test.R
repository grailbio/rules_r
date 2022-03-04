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

# This test, complimenting the testthat run, checks if multiple test scripts
# are all run, and if coverage is computed accurately from multiple test runs
# in an additive manner.

# Code from //exampleA and //exampleB will have 2 hits (once here and once from
# testthat) if instrumentation filters are set to include //exampleA and
# //exampleB, and should be absent otherwise.
stopifnot(identical(c("A", "B"), exampleB::exampleB()))

# See comment in rcpp.cc:init()
loadNamespace("Rcpp")

# Coverage from rcpp.R will have 2 hits.
stopifnot(identical(c("hello", "world"), exampleC::rcppHello()))

# Coverage from rcpp.R will have 2 hits.
stopifnot(identical(c("hello", "world", "from", "me", "too"), exampleC::rcppHelloWrapped()))

# Coverage from workspaceroot/fn.R will have 1 hit.
stopifnot(identical("hello", workspaceroot::hello()))

# Coverage from workspaceroot/src/fn.c will have 1 hit.
stopifnot(identical("helloC", workspaceroot::helloC()))
