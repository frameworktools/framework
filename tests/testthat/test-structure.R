# Project structure artifacts: fw_structure() and publish_structure(). The
# shared fixture and its expected nodes are in framework-cloud
# docs/plans/2026-11-25-structure-artifacts.md; every client passes it.

# git with no global or system configuration, so a developer's global
# excludes file can't change what is ignored
local_plain_git <- function(env = parent.frame()) {
  home <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(GIT_CONFIG_GLOBAL = file.path(home, "gitconfig"), GIT_CONFIG_NOSYSTEM = "1",
                      XDG_CONFIG_HOME = home, HOME = home, .local_envir = env)
}

# The shared fixture, in a temporary folder that becomes the working
# directory. `git = FALSE` leaves out git init.
local_structure_fixture <- function(git = TRUE, env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  local_plain_git(env)
  dir <- withr::local_tempdir(.local_envir = env)
  writeLines(c("data/raw/", "*.rds", ".env"), file.path(dir, ".gitignore"))
  for (file in c(".env", "README.md", "R/clean.R", "data/raw/a.csv", "data/raw/b.csv",
                 "data/private/ids.csv", "outputs/fit.rds", "outputs/draws.rds", "outputs/table.csv")) {
    dir.create(dirname(file.path(dir, file)), recursive = TRUE, showWarnings = FALSE)
    writeLines("x", file.path(dir, file))
  }
  if (git) {
    status <- system2(Sys.which("git"), c("-C", shQuote(dir), "init", "-q"))
    if (!identical(status, 0L)) testthat::skip("git init failed")
  }
  withr::local_dir(dir, .local_envir = env)
  dir
}

skip_without_git <- function() {
  testthat::skip_if(!nzchar(Sys.which("git")), "git is not installed")
}

# Nodes as sorted one-line descriptions
node_lines <- function(nodes) {
  sort(vapply(nodes, function(node) {
    parts <- c(sprintf("%s|%s", node$path, node$type))
    if (!is.null(node$ignored)) {
      parts <- c(parts, sprintf("ignored %s %s:%s", node$ignored$rule, node$ignored$source, node$ignored$line))
    }
    if (isTRUE(node$private)) parts <- c(parts, "private")
    if (isTRUE(node$depth)) parts <- c(parts, "depth")
    if (!is.null(node$hidden)) parts <- c(parts, paste("hidden", node$hidden))
    paste(parts, collapse = " ")
  }, character(1)), method = "radix")
}

fixture_nodes <- sort(c(
  ".gitignore|file",
  "|ignored ignored .env .gitignore:3 hidden 1",
  "README.md|file",
  "R|dir",
  "R/clean.R|file",
  "data|dir",
  "data/raw|dir ignored data/raw/ .gitignore:1 hidden 2",
  "data/private|dir private hidden 1",
  "outputs|dir",
  "outputs|ignored ignored *.rds .gitignore:2 hidden 2",
  "outputs/table.csv|file"
), method = "radix")

leaked <- c("a.csv", "b.csv", "ids.csv", "fit.rds", "draws.rds")

test_that("the shared fixture publishes the expected nodes and no ignored or private names", {
  skip_without_git()
  local_structure_fixture()
  tree <- fw_structure()
  expect_s3_class(tree, "framework_structure")
  expect_identical(tree$method, "git")
  expect_identical(node_lines(tree$nodes), fixture_nodes)

  document <- framework:::.fw_structure_document(tree)
  expect_identical(document$schema, "framework.artifact/v1")
  expect_identical(document$kind, "tree")
  expect_identical(document$source, list(language = "r"))
  expect_identical(document$root, basename(getwd()))
  expect_identical(document$base, "")
  expect_null(document$open)
  expect_null(document$highlight)
  json <- as.character(jsonlite::toJSON(document, auto_unbox = TRUE))
  for (name in leaked) expect_false(grepl(name, json, fixed = TRUE), info = name)
})

test_that("without git, the root .gitignore gives the same nodes", {
  local_structure_fixture(git = FALSE)
  testthat::local_mocked_bindings(.fw_structure_git_line = function(...) NULL)
  tree <- fw_structure()
  expect_identical(tree$method, "gitignore")
  expect_identical(node_lines(tree$nodes), fixture_nodes)
  json <- as.character(jsonlite::toJSON(framework:::.fw_structure_document(tree), auto_unbox = TRUE))
  for (name in leaked) expect_false(grepl(name, json, fixed = TRUE), info = name)
})

test_that("without git or a .gitignore, nothing is ignored and private folders still stub", {
  local_structure_fixture(git = FALSE)
  unlink(".gitignore")
  testthat::local_mocked_bindings(.fw_structure_git_line = function(...) NULL)
  tree <- fw_structure()
  expect_identical(tree$method, "none")
  lines <- node_lines(tree$nodes)
  expect_true("outputs/fit.rds|file" %in% lines)
  expect_true("data/raw/a.csv|file" %in% lines)
  expect_true("data/private|dir private hidden 1" %in% lines)
  expect_false(any(grepl("ids.csv", lines, fixed = TRUE)))
})

test_that("the fallback matcher reads negation, anchors, folder rules, and globs", {
  rules <- lapply(c("*.log", "!keep.log", "/build", "docs/site/", "**/cache", "a/**/z", "tmp?",
                    "# comment", "", "lib/**"), framework:::.fw_structure_ignore_rule)
  rules <- Filter(Negate(is.null), rules)
  match <- function(path, is_dir = FALSE) {
    rule <- framework:::.fw_structure_ignore_match(rules, path, is_dir)
    if (is.null(rule)) NA_character_ else rule$rule
  }
  expect_identical(match("x.log"), "*.log")
  expect_identical(match("deep/down/x.log"), "*.log")
  expect_identical(match("keep.log"), NA_character_)
  expect_identical(match("build", TRUE), "/build")
  expect_identical(match("src/build", TRUE), NA_character_)
  expect_identical(match("docs/site", TRUE), "docs/site/")
  expect_identical(match("docs/site", FALSE), NA_character_)
  expect_identical(match("other/docs/site", TRUE), NA_character_)
  expect_identical(match("cache", TRUE), "**/cache")
  expect_identical(match("x/y/cache", TRUE), "**/cache")
  expect_identical(match("a/z"), "a/**/z")
  expect_identical(match("a/b/c/z"), "a/**/z")
  expect_identical(match("tmp1"), "tmp?")
  expect_identical(match("tmp12"), NA_character_)
  expect_identical(match("lib/x/y.R"), "lib/**")
  expect_identical(rules[[1]]$line, NA_integer_)
})

test_that("depth lists that many levels and stubs the folders below it", {
  skip_without_git()
  local_structure_fixture()
  lines <- node_lines(fw_structure(depth = 1)$nodes)
  expect_true("R|dir depth hidden 1" %in% lines)
  expect_true("data|dir depth hidden 3" %in% lines)
  expect_true("outputs|dir depth hidden 3" %in% lines)
  expect_false(any(startsWith(lines, "R/")))
  expect_false(any(startsWith(lines, "data/")))

  lines <- node_lines(fw_structure(depth = 2)$nodes)
  expect_true("R/clean.R|file" %in% lines)
  expect_true("data/raw|dir ignored data/raw/ .gitignore:1 hidden 2" %in% lines)
  expect_error(fw_structure(depth = 0))
})

test_that("exclude leaves paths out with no stub", {
  skip_without_git()
  local_structure_fixture()
  lines <- node_lines(fw_structure(exclude = c("data/", "*.csv"))$nodes)
  expect_false(any(grepl("^data", lines)))
  expect_false("outputs/table.csv|file" %in% lines)
  expect_true("outputs|ignored ignored *.rds .gitignore:2 hidden 2" %in% lines)
  expect_true("R/clean.R|file" %in% lines)
})

test_that("notes, open, and highlight ride along and are checked against the tree", {
  skip_without_git()
  local_structure_fixture()
  tree <- fw_structure(notes = c("R/" = "Reusable functions", "README.md" = "Start here"),
                       open = "data/", highlight = c("README.md", "data/raw"))
  document <- framework:::.fw_structure_document(tree)
  noted <- Filter(function(node) !is.null(node$note), document$nodes)
  expect_identical(vapply(noted, `[[`, character(1), "path"), c("R", "README.md"))
  expect_identical(as.character(document$open), "data")
  expect_identical(as.character(document$highlight), c("README.md", "data/raw"))
  json <- as.character(jsonlite::toJSON(document, auto_unbox = TRUE))
  expect_match(json, '"open":["data"]', fixed = TRUE)
  expect_match(json, '"note":"Reusable functions"', fixed = TRUE)

  expect_error(fw_structure(notes = c("src/" = "No such folder")), "notes names a path not in the tree: src.")
  expect_error(fw_structure(notes = c("outputs/fit.rds" = "Ignored")), "not in the tree: outputs/fit.rds")
  expect_error(fw_structure(notes = c("data/raw/a.csv" = "Inside a stub")), "not in the tree: data/raw/a.csv")
  expect_error(fw_structure(notes = c("README.md/" = "A file")), "names a file as a folder: README.md/")
  expect_error(fw_structure(notes = c("R" = strrep("x", 501))), "up to 500 characters: R")
  expect_error(fw_structure(notes = "Unnamed"), "notes takes text named by path")
  expect_error(fw_structure(notes = list(R = 1)), "Each note is one string")
  expect_error(fw_structure(open = "README.md"), "open names files, not folders: README.md")
  expect_error(fw_structure(open = c("nope", "gone")), "open names paths not in the tree: nope, gone.")
  expect_error(fw_structure(highlight = "data/private/ids.csv"), "highlight names a path not in the tree")
  expect_error(fw_structure(highlight = "R", ignored = "hide", notes = c("data/raw" = "Hidden")),
               "notes names a path not in the tree: data/raw")
})

test_that("ignored = 'hide' leaves out ignored stubs and groups and keeps private stubs", {
  skip_without_git()
  local_structure_fixture()
  lines <- node_lines(fw_structure(ignored = "hide")$nodes)
  expect_identical(lines, sort(c(".gitignore|file", "README.md|file", "R|dir", "R/clean.R|file", "data|dir",
                                 "data/private|dir private hidden 1", "outputs|dir", "outputs/table.csv|file"),
                               method = "radix"))
  expect_error(fw_structure(ignored = "none"))

  # A private folder that is also ignored is left out too
  cat("data/private/\n", file = ".gitignore", append = TRUE)
  lines <- node_lines(fw_structure(ignored = "hide")$nodes)
  expect_false(any(startsWith(lines, "data/private")))
  lines <- node_lines(fw_structure()$nodes)
  expect_true("data/private|dir ignored data/private/ .gitignore:4 private hidden 1" %in% lines)
})

test_that("several folders publish as one tree from the project root", {
  skip_without_git()
  local_structure_fixture()
  tree <- fw_structure(c("R", "outputs/"))
  expect_identical(tree$root, basename(getwd()))
  expect_identical(tree$base, "")
  expect_identical(node_lines(tree$nodes), sort(c(
    "R|dir", "R/clean.R|file", "outputs|dir", "outputs/table.csv|file",
    "outputs|ignored ignored *.rds .gitignore:2 hidden 2"
  ), method = "radix"))
  expect_error(fw_structure(c("R", ".")), "names the project root and other folders")

  # Nested folders keep their paths; private and ignored ones stub
  expect_identical(node_lines(fw_structure(c("R", "data/private", "data/raw"))$nodes), sort(c(
    "R|dir", "R/clean.R|file", "data/private|dir private hidden 1",
    "data/raw|dir ignored data/raw/ .gitignore:1 hidden 2"
  ), method = "radix"))
  dir.create("data/raw/sub")
  writeLines("x", "data/raw/sub/c.csv")
  expect_error(fw_structure(c("R", "data/raw/sub")), "data/raw/sub is ignored by git")
})

test_that("one subfolder is the root, with rule sources relative to it", {
  skip_without_git()
  local_structure_fixture()
  tree <- fw_structure("data")
  expect_identical(tree$root, "data")
  expect_identical(tree$base, "data")
  expect_identical(node_lines(tree$nodes), sort(c(
    "private|dir private hidden 1", "raw|dir ignored data/raw/ .gitignore:1 hidden 2"
  ), method = "radix"))
  expect_error(fw_structure("data/private"), "data/private is a private folder")
  expect_error(fw_structure("data/raw"), "data/raw is ignored by git")
  expect_error(fw_structure("nope"), "Not a folder in the project: nope")
  expect_error(fw_structure("../elsewhere"), "without '..'")
  expect_error(fw_structure("README.md"), "Not a folder in the project")
})

test_that("rules outside the tree name their source, never an absolute path", {
  source <- framework:::.fw_structure_rule_source
  expect_identical(source("/Users/someone/.gitignore_global", ""), "global")
  expect_identical(source("C:/Users/someone/.gitignore", ""), "global")
  expect_identical(source(".git/info/exclude", "data/"), "info/exclude")
  # Sources are relative to the project root; prefix is the root's place in the work tree
  expect_identical(source(".gitignore", ""), ".gitignore")
  expect_identical(source("data/.gitignore", ""), "data/.gitignore")
  expect_identical(source("proj/.gitignore", "proj/"), ".gitignore")
  expect_identical(source("proj/data/.gitignore", "proj/"), "data/.gitignore")
  # A rule file above the project root is outside it
  expect_identical(source(".gitignore", "proj/"), "global")

  skip_without_git()
  local_structure_fixture()
  cat("README.md\n", file = ".git/info/exclude", append = TRUE)
  excludes <- withr::local_tempfile(lines = "*.csv")
  system2(Sys.which("git"), c("config", "core.excludesFile", shQuote(excludes)))
  lines <- node_lines(fw_structure()$nodes)
  expect_true(any(grepl("^\\|ignored ignored README.md info/exclude:[0-9]+ hidden 1$", lines)))
  expect_true("outputs|ignored ignored *.csv global:1 hidden 1" %in% lines)
  json <- as.character(jsonlite::toJSON(framework:::.fw_structure_document(fw_structure()), auto_unbox = TRUE))
  expect_false(grepl(excludes, json, fixed = TRUE))
})

test_that("symbolic links publish as files and are never followed", {
  skip_without_git()
  skip_on_os("windows")
  local_structure_fixture()
  file.symlink(file.path(getwd(), "R"), "linked")
  lines <- node_lines(fw_structure()$nodes)
  expect_true("linked|file" %in% lines)
  expect_false(any(startsWith(lines, "linked/")))
})

test_that("file counts stop at 10,000", {
  dir <- withr::local_tempdir()
  for (i in 1:5) writeLines("x", file.path(dir, paste0(i, ".txt")))
  dir.create(file.path(dir, "sub"))
  writeLines("x", file.path(dir, "sub", "6.txt"))
  expect_identical(framework:::.fw_structure_count(dir), 6L)
  expect_identical(framework:::.fw_structure_count(dir, cap = 3L), 3L)
  files <- framework:::.fw_structure_files
  expect_identical(files(1L), "1 file")
  expect_identical(files(1520L), "1,520 files")
  expect_identical(files(10000L), "10,000+ files")
})

test_that("fw_structure() prints the local tree with ignored names and rules", {
  skip_without_git()
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]))
  local_structure_fixture()
  out <- utils::capture.output(print(fw_structure(notes = c("R/" = "Reusable functions", "README.md" = "Start here"))))
  expect_identical(out, c(
    paste0(basename(getwd()), "/"),
    "\u251c\u2500\u2500 data/",
    "\u2502   \u251c\u2500\u2500 private/   private \u00b7 1 file",
    "\u2502   \u2514\u2500\u2500 raw/       ignored by data/raw/ (.gitignore:1) \u00b7 2 files",
    "\u251c\u2500\u2500 outputs/",
    "\u2502   \u251c\u2500\u2500 table.csv",
    "\u2502   \u251c\u2500\u2500 draws.rds  ignored by *.rds (.gitignore:2)",
    "\u2502   \u2514\u2500\u2500 fit.rds    ignored by *.rds (.gitignore:2)",
    "\u251c\u2500\u2500 R/             Reusable functions",
    "\u2502   \u2514\u2500\u2500 clean.R",
    "\u251c\u2500\u2500 .gitignore",
    "\u251c\u2500\u2500 README.md      Start here",
    "\u2514\u2500\u2500 .env           ignored by .env (.gitignore:3)"
  ))
})

test_that("the local tree lists up to 20 ignored names per folder and rule", {
  skip_without_git()
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]))
  local_structure_fixture()
  for (i in 1:23) writeLines("x", sprintf("outputs/m%02d.rds", i))
  out <- utils::capture.output(print(fw_structure(exclude = c("data/", "R/", "*.md", ".*"))))
  expect_identical(sum(grepl("\\.rds  *ignored by", out)), 20L)
  expect_identical(out[length(out)], "    \u2514\u2500\u2500 \u2026 5 more   ignored by *.rds (.gitignore:2)")
})

test_that("publish_structure() prints the publish form and uploads <slug>.json with kind tree", {
  skip_without_git()
  skip_if_not_installed("httr2")
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]))
  local_structure_fixture()
  withr::local_envvar(FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  cat("settings.yml\n", file = ".gitignore", append = TRUE)

  sent <- list()
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      fields <- rlang::list2(...)
      sent[[length(sent) + 1L]] <<- list(fields = fields, name = basename(fields$file$path),
                                         json = jsonlite::read_json(fields$file$path, simplifyVector = FALSE),
                                         raw = readLines(fields$file$path, warn = FALSE))
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(version = 2L, url = "http://localhost:8080/d/abc",
                                              embed_link = "http://localhost:8080/d/abc",
                                              artifact_url = "http://localhost:8080/artifacts/7"),
    .package = "httr2"
  )
  messages <- character()
  out <- withCallingHandlers(
    utils::capture.output(url <- publish_structure(notes = c(R = "Reusable functions"), highlight = "README.md",
                                                   visibility = "unlisted", display = list(ignored = FALSE))),
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  root <- basename(getwd())
  expect_identical(out, c(
    paste0(root, "/"),
    "\u251c\u2500\u2500 data/",
    "\u2502   \u251c\u2500\u2500 private/  private \u00b7 1 file",
    "\u2502   \u2514\u2500\u2500 raw/      ignored by data/raw/ (.gitignore:1) \u00b7 2 files",
    "\u251c\u2500\u2500 outputs/",
    "\u2502   \u251c\u2500\u2500 table.csv",
    "\u2502   \u2514\u2500\u2500 *.rds     ignored by *.rds (.gitignore:2) \u00b7 2 files",
    "\u251c\u2500\u2500 R/            Reusable functions",
    "\u2502   \u2514\u2500\u2500 clean.R",
    "\u251c\u2500\u2500 .gitignore",
    "\u251c\u2500\u2500 README.md",
    "\u251c\u2500\u2500 .env          ignored by .env (.gitignore:3) \u00b7 1 file",
    "\u2514\u2500\u2500 settings.yml  ignored by settings.yml (.gitignore:4) \u00b7 1 file"
  ))
  expect_identical(messages, c("Published version 2.\n", "Share:  http://localhost:8080/d/abc\n",
                               "Manage: http://localhost:8080/artifacts/7\n"))
  expect_identical(as.character(url), "http://localhost:8080/d/abc")
  expect_identical(attr(url, "artifact_url"), "http://localhost:8080/artifacts/7")

  expect_length(sent, 1L)
  expect_identical(sent[[1]]$name, "structure.json")
  expect_identical(sent[[1]]$fields$kind, "tree")
  expect_identical(sent[[1]]$fields$slug, "structure")
  expect_identical(sent[[1]]$fields$title, paste(root, "structure"))
  expect_identical(sent[[1]]$fields$visibility, "unlisted")
  expect_identical(sent[[1]]$fields$display, '{"ignored":false}')
  json <- sent[[1]]$json
  expect_identical(json$kind, "tree")
  expect_identical(json$root, root)
  expect_identical(json$highlight, list("README.md"))
  for (name in leaked) expect_false(any(grepl(name, sent[[1]]$raw, fixed = TRUE)), info = name)

  # A subfolder gets its own slug and title
  utils::capture.output(suppressMessages(publish_structure("R")))
  expect_identical(sent[[2]]$name, "structure-r.json")
  expect_identical(sent[[2]]$fields$slug, "structure-r")
  expect_identical(sent[[2]]$fields$title, "R structure")
  expect_identical(sent[[2]]$json$base, "R")

  # A bad note stops before anything uploads
  expect_error(publish_structure(notes = c(nope = "x")), "not in the tree")
  expect_length(sent, 2L)
})

test_that("tree display settings are accepted", {
  expect_identical(framework:::.fw_display_settings(list(notes = FALSE, ignored = TRUE)),
                   list(notes = FALSE, ignored = TRUE))
})
