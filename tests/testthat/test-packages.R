test_that(".parse_package_spec normalizes CRAN shorthands", {
  spec <- framework:::.parse_package_spec("dplyr")
  expect_equal(spec$name, "dplyr")
  expect_equal(spec$source, "cran")
  expect_null(spec$version)
  expect_false(spec$auto_attach)
})

test_that(".parse_package_spec handles version pins and GitHub refs", {
  cran_pin <- framework:::.parse_package_spec("ggplot2@3.4.0")
  expect_equal(cran_pin$version, "3.4.0")
  expect_equal(cran_pin$source, "cran")

  gh_spec <- framework:::.parse_package_spec("tidyverse/dplyr@main")
  expect_equal(gh_spec$source, "github")
  expect_equal(gh_spec$repo, "tidyverse/dplyr")
  expect_equal(gh_spec$ref, "main")
  expect_equal(gh_spec$name, "dplyr")
})

test_that(".parse_package_spec supports Bioconductor shorthands", {
  bioc_spec <- framework:::.parse_package_spec("bioc::DESeq2")
  expect_equal(bioc_spec$source, "bioc")
  expect_equal(bioc_spec$name, "DESeq2")
  expect_null(bioc_spec$repo)
})

test_that("list-style package specs infer defaults and sources", {
  cran_list <- framework:::.parse_package_spec(list(name = "stringr", auto_attach = TRUE))
  expect_equal(cran_list$source, "cran")
  expect_true(cran_list$auto_attach)

  gh_list <- framework:::.parse_package_spec(list(name = "tidyverse/dplyr", source = "github", auto_attach = FALSE))
  expect_equal(gh_list$source, "github")
  expect_equal(gh_list$name, "dplyr")
  expect_equal(gh_list$repo, "tidyverse/dplyr")
  expect_equal(gh_list$ref, "HEAD")

  gh_with_ref <- framework:::.parse_package_spec(list(name = "tidyverse/dplyr@main", auto_attach = TRUE))
  expect_equal(gh_with_ref$source, "github")
  expect_equal(gh_with_ref$name, "dplyr")
  expect_equal(gh_with_ref$repo, "tidyverse/dplyr")
  expect_equal(gh_with_ref$ref, "main")
  expect_true(gh_with_ref$auto_attach)

  bioc_list <- framework:::.parse_package_spec(list(name = "DESeq2", source = "Bioconductor"))
  expect_equal(bioc_list$source, "bioc")
  expect_equal(bioc_list$name, "DESeq2")
})

test_that("installs use the cloud CRAN mirror when none is set", {
  withr::local_options(repos = c(CRAN = "@CRAN@"))
  expect_identical(framework:::.fw_cran_repos()[["CRAN"]], "https://cloud.r-project.org")
  withr::local_options(repos = NULL)
  expect_identical(framework:::.fw_cran_repos()[["CRAN"]], "https://cloud.r-project.org")
  withr::local_options(repos = c(CRAN = "https://cran.example.org", BioC = "https://bioc.example.org"))
  expect_identical(framework:::.fw_cran_repos(),
                   c(CRAN = "https://cran.example.org", BioC = "https://bioc.example.org"))
  seen <- NULL
  local_mocked_bindings(install.packages = function(pkgs, ...) seen <<- getOption("repos")[["CRAN"]],
                        .package = "utils")
  withr::local_options(repos = c(CRAN = "@CRAN@"))
  suppressMessages(framework:::.install_package_base(list(name = "x", source = "cran")))
  expect_identical(seen, "https://cloud.r-project.org")
  expect_identical(getOption("repos")[["CRAN"]], "@CRAN@")
})
