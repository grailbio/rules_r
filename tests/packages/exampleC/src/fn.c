/*
Copyright 2018 The Bazel Authors.

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

#include <R.h>
#include <Rinternals.h>

#include "fn.h"
#include "lib.h"

const char *getCharacter();

SEXP exampleC(SEXP a) {
  noop();  // To check coverage collection of a standalone header file.

  SEXP res = PROTECT(allocVector(STRSXP, 2));

  SET_STRING_ELT(res, 0, mkChar(getCharacter()));
  SET_STRING_ELT(res, 1, mkChar(exampleC_inline()));

  UNPROTECT(1);
  return res;
}
