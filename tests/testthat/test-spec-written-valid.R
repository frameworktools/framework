# Every spec R writes matches inst/schema/spec.v1.json, which Framework Cloud
# validates against (it refuses other keys with HTTP 422)

spec_v1_path <- function() {
  path <- system.file("schema", "spec.v1.json", package = "framework")
  if (!nzchar(path)) path <- testthat::test_path("..", "..", "inst", "schema", "spec.v1.json")
  path
}

# The spec file's problems: R's own check, and ajv's when jsonvalidate is
# installed, so the two can't drift apart
expect_spec_file_valid <- function(file, label) {
  spec <- jsonlite::read_json(file, simplifyVector = FALSE)
  expect_identical(framework:::.spec_schema_problems(spec), character(), info = label)
  if (requireNamespace("jsonvalidate", quietly = TRUE)) {
    v <- jsonvalidate::json_schema$new(spec_v1_path(), engine = "ajv")
    expect_true(v$validate(paste(readLines(file, warn = FALSE), collapse = "\n")), info = label)
  }
}

test_that("the R check finds what the schema refuses", {
  spec <- spec_resolve(list(list(type = "project")), name = "Check")
  expect_identical(framework:::.spec_schema_problems(spec), character())

  bad <- spec
  bad$scaffold$positron <- FALSE
  bad$source <- list(origin = "r", upgraded_from = "framework 1.x")
  problems <- framework:::.spec_schema_problems(bad)
  expect_true(any(grepl("scaffold: 'positron' is not allowed", problems, fixed = TRUE)))
  expect_true(any(grepl("source: 'upgraded_from' is not allowed", problems, fixed = TRUE)))

  pruned <- framework:::.spec_schema_prune(bad)
  expect_setequal(pruned$dropped, c("scaffold.positron", "source.upgraded_from"))
  expect_identical(framework:::.spec_schema_problems(pruned$spec), character())

  wrong <- spec
  wrong$scaffold$seed <- 123
  wrong$security$sensitive <- "yes"
  wrong$directories$data <- "../outside"
  problems <- framework:::.spec_schema_problems(wrong)
  expect_true(any(grepl("^scaffold.seed: must be string", problems)))
  expect_true(any(grepl("^security.sensitive: must be boolean", problems)))
  expect_true(any(grepl("^directories.data:", problems)))

  if (requireNamespace("jsonvalidate", quietly = TRUE)) {
    v <- jsonvalidate::json_schema$new(spec_v1_path(), engine = "ajv")
    to_json <- function(s) {
      attr(s, "conflicts") <- NULL
      jsonlite::toJSON(framework:::.spec_mark_maps(s), auto_unbox = TRUE, null = "null")
    }
    expect_true(v$validate(to_json(spec)))
    expect_false(v$validate(to_json(bad)))
    expect_false(v$validate(to_json(wrong)))
  }
})

test_that("project_create() writes a valid spec for every type", {
  root <- withr::local_tempdir()
  for (type in c("project", "project_sensitive", "course", "presentation", "bare")) {
    spec <- spec_resolve(list(list(type = type, git = list(use_git = FALSE))), name = paste("Schema", type))
    dir <- file.path(root, type)
    suppressMessages(project_create(spec, dir))
    expect_spec_file_valid(file.path(dir, ".framework", "spec.json"), type)
  }
})

test_that("adopt() writes a valid spec, sensitive or not", {
  for (sensitive in c(FALSE, TRUE)) {
    dir <- withr::local_tempdir()
    for (f in c("R", "data/raw", "notebooks", "reports")) dir.create(file.path(dir, f), recursive = TRUE)
    writeLines("x", file.path(dir, "notebooks", "a.qmd"))
    suppressWarnings(suppressMessages(adopt(dir, yes = TRUE, sensitive = sensitive)))
    expect_spec_file_valid(file.path(dir, ".framework", "spec.json"), paste("adopt, sensitive:", sensitive))
  }
})

test_that("upgrade() writes a valid spec from old settings, and drops keys an earlier upgrade wrote", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "settings"))
  writeLines(c("default:", "  project_name: Old", "  project_type: project",
               "  directories:", "    notebooks: notebooks", "  scaffold: settings/scaffold.yml",
               "  connections: settings/connections.yml"), file.path(dir, "settings.yml"))
  writeLines(c("scaffold:", "  seed_on_scaffold: no", "  seed: 123", "  positron: yes",
               "  ide: vscode", "  notebook_format: quarto"), file.path(dir, "settings", "scaffold.yml"))
  writeLines(c("connections:", "  db:", "    driver: postgres", "    password: env(\"DB_PASSWORD\")"),
             file.path(dir, "settings", "connections.yml"))
  suppressMessages(upgrade(dir, dry_run = FALSE, backup = FALSE))
  file <- file.path(dir, ".framework", "spec.json")
  expect_spec_file_valid(file, "upgrade")
  spec <- jsonlite::read_json(file)
  expect_null(spec$scaffold$positron)
  expect_identical(spec$scaffold$seed, "123")
  expect_identical(spec$scaffold$ide, "vscode")
  expect_null(spec$source$upgraded_from)

  # A spec written by an earlier upgrade(), with the keys Cloud refuses
  spec$scaffold$positron <- TRUE
  spec$source$upgraded_from <- "framework before 2.0 (no spec.json)"
  jsonlite::write_json(spec, file, auto_unbox = TRUE, pretty = 2, null = "null")
  plan <- suppressMessages(upgrade(dir))
  change <- plan$actions$change[plan$actions$path == ".framework/spec.json"]
  expect_match(change, "drop scaffold.positron, source.upgraded_from")
  suppressMessages(upgrade(dir, dry_run = FALSE, backup = FALSE))
  expect_spec_file_valid(file, "upgrade, second pass")
  expect_identical(nrow(suppressMessages(upgrade(dir))$actions), 0L)
})

test_that("cloud_register() refuses a spec Cloud would refuse, before sending anything", {
  dir <- withr::local_tempdir()
  spec <- spec_resolve(list(list(type = "project", git = list(use_git = FALSE))), name = "Refused")
  suppressMessages(project_create(spec, file.path(dir, "p")))
  file <- file.path(dir, "p", ".framework", "spec.json")
  record <- jsonlite::read_json(file)
  record$source$upgraded_from <- "framework 1.x"
  jsonlite::write_json(record, file, auto_unbox = TRUE, pretty = 2, null = "null")
  expect_error(cloud_register(file.path(dir, "p"), dry_run = TRUE), "upgraded_from.*upgrade\\(")
})
