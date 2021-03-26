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
  return v;
}

// Function meant to be used in R Package R code.
extern "C" {
SEXP rcppHello() { return Rcpp::wrap(hello()); }
}  // "C"
