test_that("renv_enabled() detects marker file", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Clean up any existing marker
  if (file.exists(".framework_renv_enabled")) {
    file.remove(".framework_renv_enabled")
  }

  expect_false(renv_enabled())

  writeLines("timestamp", ".framework_renv_enabled")
  expect_true(renv_enabled())

  file.remove(".framework_renv_enabled")
})

test_that("renv_enabled() returns FALSE when marker doesn't exist", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".framework_renv_enabled")) {
    file.remove(".framework_renv_enabled")
  }

  expect_false(renv_enabled())
})

test_that(".parse_package_spec() handles simple package names", {
  result <- framework:::.parse_package_spec("dplyr")

  expect_equal(result$name, "dplyr")
  expect_null(result$version)
  expect_equal(result$source, "cran")
  expect_null(result$repo)
  expect_null(result$ref)
})

test_that(".parse_package_spec() handles version pins", {
  result <- framework:::.parse_package_spec("dplyr@1.1.0")

  expect_equal(result$name, "dplyr")
  expect_equal(result$version, "1.1.0")
  expect_equal(result$source, "cran")
})

test_that(".parse_package_spec() handles GitHub repos without ref", {
  result <- framework:::.parse_package_spec("tidyverse/dplyr")

  expect_equal(result$name, "dplyr")
  expect_equal(result$repo, "tidyverse/dplyr")
  expect_equal(result$ref, "HEAD")
  expect_equal(result$source, "github")
  expect_null(result$version)
})

test_that(".parse_package_spec() handles GitHub repos with ref", {
  result <- framework:::.parse_package_spec("tidyverse/dplyr@main")

  expect_equal(result$name, "dplyr")
  expect_equal(result$repo, "tidyverse/dplyr")
  expect_equal(result$ref, "main")
  expect_equal(result$source, "github")
})

test_that(".parse_package_spec() handles GitHub repos with branch", {
  result <- framework:::.parse_package_spec("user/repo@feature-branch")

  expect_equal(result$name, "repo")
  expect_equal(result$repo, "user/repo")
  expect_equal(result$ref, "feature-branch")
  expect_equal(result$source, "github")
})

test_that(".parse_package_spec() trims whitespace", {
  result <- framework:::.parse_package_spec("  dplyr  ")

  expect_equal(result$name, "dplyr")
  expect_equal(result$source, "cran")
})

test_that(".mark_scaffolded() records history on first run", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".framework_scaffolded")) {
    file.remove(".framework_scaffolded")
  }
  if (file.exists("framework.db")) {
    unlink("framework.db")
  }

  framework:::.mark_scaffolded()

  history <- framework:::.get_scaffold_history(getwd())
  expect_true(inherits(history$first, "POSIXct"))
  expect_true(inherits(history$last, "POSIXct"))
  
  if (file.exists("framework.db")) {
    unlink("framework.db")
  }
})

test_that(".mark_scaffolded() updates existing history", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".framework_scaffolded")) {
    file.remove(".framework_scaffolded")
  }
  if (file.exists("framework.db")) {
    unlink("framework.db")
  }

  # First run
  framework:::.mark_scaffolded()
  history1 <- framework:::.get_scaffold_history(getwd())
  expect_true(inherits(history1$first, "POSIXct"))
  expect_true(inherits(history1$last, "POSIXct"))

  # Second run
  Sys.sleep(0.1) # Ensure different timestamp
  framework:::.mark_scaffolded()
  history2 <- framework:::.get_scaffold_history(getwd())
  expect_equal(history1$first, history2$first)
  expect_true(history2$last >= history1$last)

  if (file.exists("framework.db")) {
    unlink("framework.db")
  }
})

test_that("packages_snapshot() requires renv to be enabled", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".framework_renv_enabled")) {
    file.remove(".framework_renv_enabled")
  }

  expect_error(
    packages_snapshot(),
    "renv is not enabled"
  )
})

test_that("packages_restore() requires renv to be enabled", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".framework_renv_enabled")) {
    file.remove(".framework_renv_enabled")
  }

  expect_error(
    packages_restore(),
    "renv is not enabled"
  )
})

test_that("packages_status() reports installed packages when renv is off", {
  test_dir <- withr::local_tempdir()
  withr::local_dir(test_dir)
  yaml::write_yaml(list(default = list(packages = list(
    use_renv = FALSE,
    default_packages = list("yaml", list(name = "notapkgxyz", auto_attach = FALSE))
  ))), "settings.yml")

  expect_message(status <- packages_status(), "renv is off")
  expect_identical(status$package, c("yaml", "notapkgxyz"))
  expect_identical(status$installed, c(TRUE, FALSE))
  expect_message(packages_status(), "Not installed: notapkgxyz")
})

test_that("packages_update() requires renv to be enabled", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".framework_renv_enabled")) {
    file.remove(".framework_renv_enabled")
  }

  expect_error(
    packages_update(),
    "renv is not enabled"
  )
})

test_that(".update_gitignore_for_renv() creates .gitignore if missing", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  if (file.exists(".gitignore")) file.remove(".gitignore")

  framework:::.update_gitignore_for_renv()

  expect_true(file.exists(".gitignore"))
  content <- readLines(".gitignore")
  expect_true(any(grepl("^# renv$", content)))
  expect_true(any(grepl("renv/library/", content)))

  file.remove(".gitignore")
})

test_that(".update_gitignore_for_renv() appends to existing .gitignore", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create existing .gitignore
  writeLines(c("*.Rproj", ".Rhistory"), ".gitignore")

  framework:::.update_gitignore_for_renv()

  content <- readLines(".gitignore")
  expect_true(any(grepl("^\\*\\.Rproj$", content)))
  expect_true(any(grepl("^# renv$", content)))
  expect_true(any(grepl("renv/library/", content)))

  file.remove(".gitignore")
})

test_that(".update_gitignore_for_renv() doesn't duplicate entries", {
  test_dir <- tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create .gitignore with renv entries already
  writeLines(c("*.Rproj", "# renv", "renv/library/"), ".gitignore")

  framework:::.update_gitignore_for_renv()

  content <- readLines(".gitignore")
  renv_headers <- sum(grepl("^# renv$", content))
  expect_equal(renv_headers, 1) # Should only have one header

  file.remove(".gitignore")
})
