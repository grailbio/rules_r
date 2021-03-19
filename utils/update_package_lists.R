#!/usr/bin/env Rscript

git_root <- system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE)

source(file.path(git_root, "scripts/repo_management.R"))
options("RVersions" = c("3.4", "3.5", "3.6", "4.0"))
options("repos" = "https://cloud.r-project.org")

do <- function(path) {
  tmp_repo <- file.path(tempdir(), "/repo")
  unlink(tmp_repo, recursive = TRUE, force = TRUE)
  current <- read.csv(path)
  addPackagesToRepo(current[, 1], repo_dir = tmp_repo)
  packageList(tmp_repo, path)
}

do(file.path(git_root, "R/internal/coverage_deps_list.csv"))
do(file.path(git_root, "tests/cran/packages.csv"))
