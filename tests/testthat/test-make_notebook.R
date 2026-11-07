test_that("make_notebook() detects correct directories", {
  # Create isolated temp directory
  tmp <- tempfile("test_detect_")
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  # Test 1: notebooks/ directory exists
  dir.create("notebooks", showWarnings = FALSE)
  result <- framework:::.get_notebook_dir_from_config()
  expect_equal(result, "notebooks")
  unlink("notebooks", recursive = TRUE)

  # Test 2: work/ directory exists (legacy)
  dir.create("work", showWarnings = FALSE)
  result <- framework:::.get_notebook_dir_from_config()
  expect_equal(result, "work")
  unlink("work", recursive = TRUE)

  # Test 3: both exist - notebooks/ takes precedence
  dir.create("notebooks", showWarnings = FALSE)
  dir.create("work", showWarnings = FALSE)
  result <- framework:::.get_notebook_dir_from_config()
  expect_equal(result, "notebooks")
  unlink("notebooks", recursive = TRUE)
  unlink("work", recursive = TRUE)

  # Test 4: neither exists - defaults to current dir
  result <- framework:::.get_notebook_dir_from_config()
  expect_equal(result, ".")
})

test_that("config.yml directory settings are respected", {
  # Create isolated temp directory
  tmp <- tempfile("test_config_")
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  # Create config with explicit notebook_dir (using new directories structure)
  config_content <- "default:
  directories:
    notebooks: my_notebooks
"
  writeLines(config_content, "config.yml")

  # Test notebook dir from config
  result <- framework:::.get_notebook_dir_from_config()
  expect_equal(result, "my_notebooks")
})

test_that("slugify converts names correctly", {
  # Test basic slugification
  expect_equal(framework:::.slugify("My Cool Analysis"), "my-cool-analysis")

  # Test special characters
  expect_equal(framework:::.slugify("Data: Processing & Cleaning!"), "data-processing-cleaning")

  # Test consecutive hyphens
  expect_equal(framework:::.slugify("Multiple   Spaces"), "multiple-spaces")

  # Test leading/trailing hyphens
  expect_equal(framework:::.slugify("  trimmed  "), "trimmed")

  # Test already lowercase
  expect_equal(framework:::.slugify("already-slugified"), "already-slugified")

  # Test mixed case
  expect_equal(framework:::.slugify("CamelCaseText"), "camelcasetext")
})

test_that("make_notebook slugifies filenames but preserves titles", {
  # Create temp directory with minimal setup
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Create minimal config
  config_content <- "default:
  author:
    name: Test User
  directories:
    notebooks: notebooks
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Test 1: Name with spaces
  suppressMessages(make_notebook("My Cool Analysis"))
  expect_true(file.exists("notebooks/my-cool-analysis.qmd"))

  content <- readLines("notebooks/my-cool-analysis.qmd")
  title_line <- grep("^title:", content, value = TRUE)
  expect_true(grepl("My Cool Analysis", title_line))

  # Test 2: Special characters
  suppressMessages(make_notebook("Data: Processing!"))
  expect_true(file.exists("notebooks/data-processing.qmd"))

  content2 <- readLines("notebooks/data-processing.qmd")
  title_line2 <- grep("^title:", content2, value = TRUE)
  expect_true(grepl("Data: Processing!", title_line2))
})

test_that("make_notebook creates notebooks with author config reference", {
  # Create temp directory with minimal setup
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Create config with author info
  config_content <- "default:
  author:
    name: Dr. Jane Smith
    email: jane@example.com
    affiliation: University
  directories:
    notebooks: notebooks
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Create notebook
  suppressMessages(make_notebook("Test Notebook"))

  # Check file was created
  expect_true(file.exists("notebooks/test-notebook.qmd"))

  # Check content
  content <- readLines("notebooks/test-notebook.qmd")

  # Check author line is hardcoded (not config reference)
  author_line <- grep("^author:", content, value = TRUE)
  expect_true(grepl("Dr. Jane Smith", author_line))

  # Check title is correct (uses original name, not slug)
  title_line <- grep("^title:", content, value = TRUE)
  expect_true(grepl("Test Notebook", title_line))

  # Check setup chunk exists with scaffold()
  expect_true(any(grepl("library\\(framework\\)", content)))
  expect_true(any(grepl("scaffold\\(\\)", content)))
})

test_that("make_notebook respects default_notebook_format config", {
  # Create temp directory
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Test with rmarkdown default
  config_content <- "default:
  author:
    name: Test User
  directories:
    notebooks: notebooks
  default_notebook_format: rmarkdown
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Create notebook without specifying type
  suppressMessages(make_notebook("format-test"))
  expect_true(file.exists("notebooks/format-test.Rmd"))
  expect_false(file.exists("notebooks/format-test.qmd"))
})

test_that("make_notebook defaults to quarto when config missing format", {
  # Create temp directory
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Config without default_notebook_format
  config_content <- "default:
  author:
    name: Test User
  directories:
    notebooks: notebooks
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Create notebook without specifying type
  suppressMessages(make_notebook("no-format-test"))
  expect_true(file.exists("notebooks/no-format-test.qmd"))
  expect_false(file.exists("notebooks/no-format-test.Rmd"))
})

test_that("make_qmd() always creates Quarto notebooks", {
  # Create temp directory
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Config with rmarkdown default (should be ignored by make_qmd)
  config_content <- "default:
  author:
    name: Test User
  directories:
    notebooks: notebooks
  default_notebook_format: rmarkdown
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Create notebook with make_qmd - should create .qmd despite config
  suppressMessages(make_qmd("qmd-alias-test"))
  expect_true(file.exists("notebooks/qmd-alias-test.qmd"))
  expect_false(file.exists("notebooks/qmd-alias-test.Rmd"))
})

test_that("make_rmd() always creates RMarkdown notebooks", {
  # Create temp directory
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Config with quarto default (should be ignored by make_rmd)
  config_content <- "default:
  author:
    name: Test User
  directories:
    notebooks: notebooks
  default_notebook_format: quarto
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Create notebook with make_rmd - should create .Rmd despite config
  suppressMessages(make_rmd("rmd-alias-test"))
  expect_true(file.exists("notebooks/rmd-alias-test.Rmd"))
  expect_false(file.exists("notebooks/rmd-alias-test.qmd"))
})

test_that("aliases work with custom stubs and directories", {
  # Create temp directory
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "work"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("work", showWarnings = FALSE)

  # Minimal config
  config_content <- "default:
  author:
    name: Test User
"
  writeLines(config_content, "settings.yml")
  writeLines("", ".env")

  # Test make_qmd with explicit directory
  suppressMessages(make_qmd("custom-dir", dir = "work"))
  expect_true(file.exists("work/custom-dir.qmd"))

  # Test make_rmd with explicit directory
  suppressMessages(make_rmd("custom-dir-rmd", dir = "work"))
  expect_true(file.exists("work/custom-dir-rmd.Rmd"))
})

test_that("make_notebook type parameter overrides config", {
  # Create temp directory
  tmp <- tempdir()
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(file.path(tmp, "notebooks"), recursive = TRUE)
    unlink(file.path(tmp, "settings.yml"))
    unlink(file.path(tmp, ".env"))
  })

  dir.create("notebooks", showWarnings = FALSE)

  # Config with quarto default
  config_content <- "default:
  author:
    name: Test User
  directories:
    notebooks: notebooks
  default_notebook_format: quarto
"
  writeLines(config_content, "config.yml")
  writeLines("", ".env")

  # Explicit type parameter should override config
  suppressMessages(make_notebook("override-test", type = "rmarkdown"))
  expect_true(file.exists("notebooks/override-test.Rmd"))
  expect_false(file.exists("notebooks/override-test.qmd"))
})

test_that("new notebooks get a readable title and accurate messages", {
  expect_identical(framework:::.notebook_title("bp-summary"), "Bp Summary")
  expect_identical(framework:::.notebook_title("01_load_data"), "01 Load Data")
  expect_identical(framework:::.notebook_title("My cool analysis"), "My cool analysis")
  expect_identical(framework:::.notebook_title("analysis"), "Analysis")

  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  writeLines("default:\n  directories:\n    notebooks: notebooks", "settings.yml")

  msgs <- capture.output(make_notebook("bp-summary"), type = "message")
  expect_true(any(grepl('^title: "Bp Summary"', readLines("notebooks/bp-summary.qmd"))))
  expect_identical(msgs[length(msgs)], "Created Quarto notebook: notebooks/bp-summary.qmd")

  msgs <- capture.output(make_presentation("study-talk"), type = "message")
  expect_identical(msgs, "Created reveal.js presentation: notebooks/study-talk.qmd")
  expect_true(any(grepl('^title: "Study Talk"', readLines("notebooks/study-talk.qmd"))))

  msgs <- capture.output(make_notebook("quick", stub = "minimal"), type = "message")
  expect_identical(msgs, "Created Quarto notebook: notebooks/quick.qmd (stub: minimal)")
})

test_that("dir and configured folders start at the project root, not the working directory", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  writeLines("default:\n  directories:\n    notebooks: notebooks\n    scripts: scripts", "settings.yml")
  dir.create("notebooks")
  withr::local_dir("notebooks")

  msgs <- capture.output(make_notebook("from-inside"), type = "message")
  expect_true(file.exists(file.path(dir, "notebooks", "from-inside.qmd")))
  expect_false(dir.exists(file.path(dir, "notebooks", "notebooks")))
  expect_identical(msgs[length(msgs)], "Created Quarto notebook: notebooks/from-inside.qmd")

  suppressMessages(make_notebook("assignment-01", dir = "assignments"))
  expect_true(file.exists(file.path(dir, "assignments", "assignment-01.qmd")))
  suppressMessages(make_script("clean"))
  expect_true(file.exists(file.path(dir, "scripts", "clean.R")))

  elsewhere <- withr::local_tempdir()
  suppressMessages(make_notebook("abs", dir = elsewhere))
  expect_true(file.exists(file.path(elsewhere, "abs.qmd")))
})
