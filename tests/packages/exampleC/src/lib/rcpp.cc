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

// Function meant to be used in R Package C++ code.
Rcpp::StringVector hello() {
  Rcpp::StringVector v = {"hello", "world"};
  // Have the closing parenthesis in the same line as the return statement
  // because coverage profile from gcc and llvm toolchains differ in how they
  // assign coverage to the closing parenthesis. This enables us to use the
  // same golden coverage file in our tests for both gcc and llvm, and just
  // fix this one line. See coverage_test.sh.
  // clang-format off
  return v; }
// clang-format on

// Function meant to be used in R Package R code.
extern "C" {
SEXP rcppHello() { return Rcpp::wrap(hello()); }
}  // "C"

// This is hacky but needed to initialize the loaded DLL to a bare minimum
// level. In addition to this, we also have to ensure that the Rcpp package is
// loaded in R, so that its functions are registered, because some functions in
// libRcpp call through the R package namespace.
bool init() {
  Rcpp::Rcpp_precious_init();
  return true;
}
static bool doInit = init();
