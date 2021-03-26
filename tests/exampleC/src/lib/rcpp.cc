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
