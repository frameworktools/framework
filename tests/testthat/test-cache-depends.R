# cache_remember(depends_on = ...) and cache(depends_on = ...): records shared
# with framework-py in framework.db's meta table

deps_project <- function() {
  dir <- create_test_project()
  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))
  settings$default$data <- list(inputs = list(raw = list(survey = "inputs/raw/survey.csv")))
  yaml::write_yaml(settings, file.path(dir, "settings.yml"))
  writeLines(c("a", "1"), file.path(dir, "inputs/raw/survey.csv"))
  writeLines("K <- 1", file.path(dir, "functions/fit.R"))
  dir
}

with_deps_project <- function(code, env = parent.frame()) {
  dir <- deps_project()
  old <- setwd(dir)
  on.exit({
    setwd(old)
    cleanup_test_dir(dir)
  }, add = TRUE)
  force(code)
}

stored_record <- function(name) {
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT value FROM meta WHERE key = ?", list(paste0("cache_depends:", name)))$value
}

test_that("folder hashes and entry keys match framework-py byte for byte", {
  # The fixture and expected values were computed with framework-py's
  # _depends.folder_hash(), key(), and json.dumps()
  root <- tempfile("fx_root_")
  fx <- file.path(root, "fx")
  dir.create(file.path(fx, "sub", "__pycache__"), recursive = TRUE)
  dir.create(file.path(fx, ".git"))
  on.exit(unlink(root, recursive = TRUE))
  write_bytes <- function(path, text) writeBin(charToRaw(text), file.path(fx, path))
  write_bytes("data.csv", "a,b\n1,2\n")
  write_bytes("sub/fit.R", "x <- 1\n")
  write_bytes("B.txt", "B")
  write_bytes("sub/__pycache__/m.pyc", "junk")
  write_bytes(".hidden", "h")
  write_bytes(".git/config", "g")
  writeBin(charToRaw("u"), file.path(fx, "sub", "café.txt"))
  file.create(file.path(fx, "sub", "empty"))

  folder <- "392de5262cf3df5ba674c9efb2d0e0239d62bb0419ccceeb1ee1f5b3b6f3e116"
  expect_equal(.fw_folder_hash(fx), folder)

  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  deps <- .fw_depends_resolve(c("fx", "fx/data.csv"))
  expect_equal(deps[[1]], list(kind = "folder", ref = "fx", hash = folder))
  deps <- c(deps, list(list(kind = "value", ref = "value 3", hash = strrep("ab", 32))))
  expect_equal(.fw_depends_json(deps), paste0(
    '{"key": "d803b64bb23449c5f82b477bf00c471a2cdd07bea9fa479efebdbd39abe7715b", ',
    '"dependencies": [{"kind": "folder", "ref": "fx", "hash": "', folder, '"}, ',
    '{"kind": "file", "ref": "fx/data.csv", ',
    '"hash": "492d5ea496056f1a6a6592241032fab764c321596317930b4fa0e1e8bc3b7470"}, ',
    '{"kind": "value", "ref": "value 3", "hash": "', strrep("ab", 32), '"}]}'
  ))
  # Order does not matter
  expect_equal(.fw_depends_key(rev(deps)), .fw_depends_key(deps))
  expect_equal(.fw_json_string("café \U0001F600"), '"caf\\u00e9 \\ud83d\\ude00"')
})

test_that("depends_on recomputes when a dependency changes", {
  with_deps_project({
    calls <- 0
    fit <- function() {
      calls <<- calls + 1
      calls
    }
    deps <- list("inputs.raw.survey", "functions/fit.R", "functions", list(cutoff = 0))
    run <- function(d) suppressMessages(cache_remember("fit", fit(), depends_on = d))
    expect_equal(run(deps), 1)
    expect_equal(run(deps), 1)

    writeLines(c("a", "2"), "inputs/raw/survey.csv")
    expect_message(cache_remember("fit", fit(), depends_on = deps),
                   "Cache 'fit' is out of date: inputs.raw.survey changed")
    writeLines("K <- 2", "functions/fit.R")
    expect_equal(run(deps), 3)
    writeLines("", "functions/new.R")
    expect_equal(run(deps), 4)
    expect_equal(run(deps), 4)
    # A changed value, and a changed list, are new keys too
    expect_equal(run(c(deps[1:3], list(list(cutoff = 1)))), 5)
    expect_equal(run(deps[1:2]), 6)
    expect_equal(run(rev(deps[1:2])), 6)
    expect_equal(run(c("functions/fit.R", "inputs.raw.survey")), 6)

    record <- jsonlite::fromJSON(stored_record("fit"), simplifyVector = FALSE)
    expect_equal(vapply(record$dependencies, `[[`, "", "kind"), c("data", "file"))
    expect_equal(record$key, .fw_depends_key(.fw_depends_resolve(c("inputs.raw.survey", "functions/fit.R"))))
  })
})

test_that("out-of-date messages name the entries that changed", {
  with_deps_project({
    run <- function(d) cache_remember("fit", 1, depends_on = d)
    suppressMessages(run(list("inputs.raw.survey", formula = "y ~ x", 3)))
    expect_message(run(list("inputs.raw.survey", formula = "y ~ x + z", 3)),
                   "Cache 'fit' is out of date: formula changed", fixed = TRUE)
    expect_message(run(list("inputs.raw.survey", formula = "y ~ x + z", 4)),
                   "Cache 'fit' is out of date: dependency 3 (a value) changed", fixed = TRUE)
    writeLines(c("a", "9"), "inputs/raw/survey.csv")
    expect_message(run(list("inputs.raw.survey", formula = "y ~ x", 4)),
                   "Cache 'fit' is out of date: inputs.raw.survey and formula changed", fixed = TRUE)
    writeLines(c("a", "8"), "inputs/raw/survey.csv")
    expect_message(run(list("inputs.raw.survey", formula = "y ~ x + z", 5, "functions/fit.R")),
                   paste("Cache 'fit' is out of date: inputs.raw.survey, formula,",
                         "dependency 3 (a value) and functions/fit.R changed"), fixed = TRUE)
    # The catalog name in a list with named elements is a reference
    writeLines(c("a", "7"), "inputs/raw/survey.csv")
    expect_message(run(list("inputs.raw.survey", formula = "y ~ x + z", 5, "functions/fit.R")),
                   "Cache 'fit' is out of date: inputs.raw.survey changed", fixed = TRUE)
    # A list with one named element is named by it; a fully named list with
    # more is one value
    suppressMessages(run(list("functions/fit.R", list(cutoff = 0))))
    expect_message(run(list("functions/fit.R", list(cutoff = 1))),
                   "Cache 'fit' is out of date: cutoff changed", fixed = TRUE)
    suppressMessages(run(list(cutoff = 0, k = 4)))
    expect_message(run(list(cutoff = 1, k = 4)),
                   "Cache 'fit' is out of date: dependency 1 (a value) changed", fixed = TRUE)
  })
})

test_that("an entry without dependencies is out of date once they are given", {
  with_deps_project({
    suppressMessages(cache_remember("plain", "old"))
    expect_equal(suppressMessages(cache_remember("plain", "new", depends_on = "inputs.raw.survey")), "new")
  })
})

test_that("reading an entry older than its dependencies warns and misses", {
  with_deps_project({
    suppressMessages(cache_remember("model", "v1", depends_on = list("inputs.raw.survey", list(k = 4))))
    expect_equal(suppressMessages(cache_get("model")), "v1")

    writeLines(c("a", "3"), "inputs/raw/survey.csv")
    expect_warning(
      expect_null(suppressMessages(cache_get("model"))),
      paste0(
        "Cache 'model' is older than its dependencies: inputs.raw.survey changed since it was ",
        "stored, so it is treated as a miss. Pass depends_on= to cache_remember() to recompute ",
        "it without this warning."
      ),
      fixed = TRUE
    )
    expect_warning(
      expect_equal(suppressMessages(cache_remember("model", "v2")), "v2"),
      "older than its dependencies"
    )
    # The recomputed value kept its dependencies, now up to date
    expect_equal(suppressMessages(cache_get("model")), "v2")
    record <- jsonlite::fromJSON(stored_record("model"), simplifyVector = FALSE)
    expect_equal(vapply(record$dependencies, `[[`, "", "ref"), c("inputs.raw.survey", "value 2"))
    writeLines(c("a", "4"), "inputs/raw/survey.csv")
    expect_warning(suppressMessages(cache_get("model")), "older than its dependencies")
  })
})

test_that("depends_on strings must resolve", {
  with_deps_project({
    expect_error(
      cache_remember("x", 1, depends_on = "inputs.raw.survy"),
      "depends_on: 'inputs.raw.survy' is not a catalog name, file, or folder.",
      fixed = TRUE
    )
    expect_error(cache("x", 1, depends_on = "functions/missing.R"), "not a catalog name, file, or folder")
    unlink("inputs/raw/survey.csv")
    expect_error(cache("x", 1, depends_on = "inputs.raw.survey"), "the file for 'inputs.raw.survey' is missing")
  })
})

test_that("dependencies go with their entry", {
  with_deps_project({
    suppressMessages(cache("a", 1, depends_on = "inputs.raw.survey"))
    suppressMessages(cache("b", 2, depends_on = list("functions", data.frame(x = 1))))
    record <- .fw_depends_recorded("b")
    expect_equal(
      lapply(record$dependencies, function(d) c(d$kind, d$ref)),
      list(c("folder", "functions"), c("value", "value 2"))
    )
    # A named list is one value, and a named element in a list of items is
    # the value list(name = value); refs stay "value <n>"
    suppressMessages(cache("v", 2, depends_on = list(rule = ">= 0")))
    expect_equal(.fw_depends_recorded("v")$dependencies[[1]]$ref, "value 1")
    suppressMessages(cache("w", 2, depends_on = list("inputs.raw.survey", k = 4, 5)))
    recorded <- .fw_depends_recorded("w")$dependencies
    expect_equal(
      lapply(recorded, function(d) c(d$kind, d$ref)),
      list(c("data", "inputs.raw.survey"), c("value", "value 2"), c("value", "value 3"))
    )
    expect_identical(recorded[[2]]$hash, .fw_value_hash(list(k = 4)))
    expect_identical(
      .fw_depends_key(.fw_depends_resolve(list("inputs.raw.survey", k = 4, 5))),
      .fw_depends_key(.fw_depends_resolve(list("inputs.raw.survey", list(k = 4), 5)))
    )

    suppressMessages(cache("a", 3))
    expect_null(.fw_depends_recorded("a"))
    suppressMessages(cache_forget("b"))
    expect_null(.fw_depends_recorded("b"))
    suppressMessages(cache("c", 1, depends_on = "inputs.raw.survey"))
    suppressMessages(cache_flush())
    expect_null(.fw_depends_recorded("c"))
    expect_null(.fw_depends_recorded("v"))
  })
})
