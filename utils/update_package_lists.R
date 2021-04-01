#!/usr/bin/env Rscript

git_root <- system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE)

source(file.path(git_root, "scripts/repo_management.R"))
options("RVersions" = c("3.4", "3.5", "3.6", "4.0"))
options("repos" = "https://cran.microsoft.com/snapshot/2021-04-01")

do <- function(path) {
  tmp_repo <- file.path(tempdir(), "/repo")
  unlink(tmp_repo, recursive = TRUE, force = TRUE)
  current <- read.csv(path)
  packages <- current[, 1]
  package_deps <- tools::package_dependencies(packages = packages, recursive = TRUE)
  packages <- unique(c(packages, unlist(package_deps)))
  addPackagesToRepo(packages, repo_dir = tmp_repo)
  packageList(tmp_repo, path)
}

do(file.path(git_root, "R/internal/coverage_deps_list.csv"))
do(file.path(git_root, "tests/cran/packages.csv"))
