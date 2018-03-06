# Test that rscript_args are passed along
testthat::expect(
  setequal(
    utils::sessionInfo()$basePkgs,
    c("base")),
  "unexpected base packages")

library(testthat)

# Current working directory is $RUNFILES/<workspace_name>
expect(Sys.getenv("RUNFILES") != "", "missing RUNFILES env")
expect_equal(
  normalizePath(Sys.getenv("RUNFILES")),
  normalizePath(".."))
expect_equal(
  basename(normalizePath(".")),
  "com_grail_rules_r_tests")

# Data is accessible
expect_equal(readLines("binary/data.txt"), c("Test"))

# Environment variable is set
expect_equal(Sys.getenv("FOO"), "bar")

# Package exampleA is accessible
expect_equal(exampleA(), "A")

cat("yDja77yb\n")