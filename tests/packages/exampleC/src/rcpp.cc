/*
Copyright 2021 The Bazel Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include "lib/rcpp.h"
#include "Rcpp.h"

extern "C" {
SEXP rcppHelloWrapped() {
  Rcpp::StringVector v = hello();
  v.push_back("from");
  v.push_back("me");
  v.push_back("too");
  // Have the closing parenthesis in the same line as the return statement
  // because coverage profile from gcc and llvm toolchains differ in how they
  // assign coverage to the closing parenthesis. This enables us to use the
  // same golden coverage file in our tests for both gcc and llvm, and just
  // fix this one line. See coverage_test.sh.
  // clang-format off
  return Rcpp::wrap(v); }
// clang-format on
}  // "C"
