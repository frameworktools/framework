# publish(to = "github") copies into published/<slug>/, commits only that
# folder, and pushes. Matched with framework-py and fw.

local_pages_repo <- function(owner = "Ada", repo = "study", env = parent.frame()) {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir(.local_envir = env)
  bare <- withr::local_tempdir(.local_envir = env)
  git <- function(...) system2("git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = TRUE)
  system2("git", c("init", "-q", "--bare", "-b", "main", shQuote(bare)))
  system2("git", c("init", "-q", "-b", "main", shQuote(dir)))
  git("config", "user.email", "ada@example.com")
  git("config", "user.name", "Ada")
  git("config", "core.hooksPath", "/dev/null")
  # GitHub URL for fetching and the URL math, a local bare repo for pushes
  git("remote", "add", "origin", sprintf("https://github.com/%s/%s.git", owner, repo))
  # A relative path: an MSYS git on Windows reads D:\... as an ssh host
  git("remote", "set-url", "--push", "origin", shQuote(file.path("..", basename(bare))))
  withr::local_dir(dir, .local_envir = env)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  git("add", "settings.yml")
  git("commit", "-q", "-m", "init")
  git("push", "-q", "origin", "main")
  git("update-ref", "refs/remotes/origin/main", "HEAD")
  git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
  list(dir = dir, bare = bare, git = git)
}

write_report <- function() {
  dir.create("outputs/public/report_files/libs", recursive = TRUE)
  writeLines('<script src="report_files/libs/a.js"></script>', "outputs/public/report.html")
  writeLines("var a;", "outputs/public/report_files/libs/a.js")
}

test_that("publish(to = 'github') commits only published/<slug> and pushes", {
  r <- local_pages_repo()
  write_report()
  writeLines("draft", "notes.txt")
  r$git("add", "notes.txt")

  expect_message(
    url <- publish("outputs/public/report.html", to = "github"),
    "public, even when the repository is private"
  )
  expect_identical(url, "https://ada.github.io/study/report/")
  expect_true(file.exists("published/report/index.html"))
  expect_true(file.exists("published/report/report_files/libs/a.js"))

  expect_identical(r$git("log", "-1", "--format=%s"), "Publish report")
  committed <- r$git("show", "--name-only", "--format=", "HEAD")
  expect_setequal(committed, c("published/report/artifact.json", "published/report/index.html", "published/report/report.html", "published/report/report_files/libs/a.js", "published/index.html", "published/index.json", "published/report/v/1/artifact.json", "published/report/v/1/index.html", "published/report/v/1/report.html", "published/report/v/1/report_files/libs/a.js"))
  # The user's staged file stays staged and out of the commit
  expect_identical(r$git("diff", "--cached", "--name-only"), "notes.txt")
  remote_head <- system2("git", c("-C", shQuote(r$bare), "log", "-1", "--format=%s", "main"), stdout = TRUE)
  expect_identical(remote_head, "Publish report")

  # Every publish preserves a version, including identical content.
  suppressMessages(publish("outputs/public/report.html", to = "github"))
  expect_identical(length(r$git("log", "--format=%h")), 3L)
  expect_true(file.exists("published/report/v/2/artifact.json"))

  # The folder is replaced completely
  unlink("outputs/public/report_files", recursive = TRUE)
  suppressMessages(publish("outputs/public/report.html", to = "github", slug = "main-results"))
  expect_false(dir.exists("published/main-results/report_files"))
  writeLines("<p>v2</p>", "outputs/public/report.html")
  suppressMessages(publish("outputs/public/report.html", to = "github"))
  expect_false(dir.exists("published/report/report_files"))
  expect_identical(readLines("published/report/index.html"), "<p>v2</p>")
})

test_that("publish(to = 'github') needs a GitHub remote", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  writeLines("<p>x</p>", "x.html")
  expect_error(publish("x.html", to = "github"), "GitHub first")
  system2("git", c("init", "-q", "."))
  expect_error(publish("x.html", to = "github"), "GitHub first")
  system2("git", c("remote", "add", "origin", "https://gitlab.com/ada/study.git"))
  expect_error(publish("x.html", to = "github"), "GitHub first")
  expect_error(publish("x.html", to = "pages"), "github")
  expect_identical(framework:::.fw_bundle_slug("a b"), "a-b")
})

test_that("GitHub Pages slugs are lowercase, and hosted-only arguments are errors", {
  expect_identical(framework:::.fw_pages_slug("out/Final Report (v2).html"), "final-report-v2")
  expect_identical(framework:::.fw_pages_slug("site/"), "site")
  r <- local_pages_repo()
  writeLines("<p>x</p>", "Final Report (v2).html")
  expect_identical(suppressMessages(publish("Final Report (v2).html", to = "github")),
                   "https://ada.github.io/study/final-report-v2/")
  expect_identical(suppressMessages(publish("Final Report (v2).html", to = "github", slug = "Main")), "https://ada.github.io/study/main/")
  expect_error(publish("Final Report (v2).html", to = "github", slug = TRUE), "slug = TRUE/FALSE")
  expect_error(publish("Final Report (v2).html", to = "github", dest = "a"), "dest")

  dir.create("site")
  writeLines("<p>a</p>", "site/a.html")
  expect_error(suppressMessages(publish("site", to = "github")), "index.html")
  writeLines("<p>home</p>", "site/index.html")
  suppressMessages(publish("site", to = "github"))
  expect_true(file.exists("published/site/a.html"))

  # Interactive sessions confirm, since the site is public
  withr::local_options(rlang_interactive = TRUE)
  testthat::local_mocked_bindings(askYesNo = function(...) FALSE, .package = "utils")
  writeLines("<p>new</p>", "site/index.html")
  expect_error(suppressMessages(publish("site", to = "github")), "Cancelled")
  expect_identical(readLines("published/site/index.html"), "<p>home</p>")
})

test_that("published/ sits at the top of the repository and the upstream is set", {
  r <- local_pages_repo()
  dir.create("analysis")
  file.rename("settings.yml", "analysis/settings.yml")
  withr::local_dir("analysis")
  writeLines("<p>x</p>", "x.html")
  suppressMessages(publish("x.html", to = "github"))
  expect_true(file.exists(file.path(r$dir, "published", "x", "index.html")))
  expect_identical(r$git("rev-parse", "--abbrev-ref", shQuote("@{u}")), "origin/main")
})

test_that("publish(to = 'github') warns off the default branch and pushes anyway", {
  r <- local_pages_repo()
  r$git("checkout", "-q", "-b", "draft")
  writeLines("<p>x</p>", "x.html")
  expect_warning(suppressMessages(publish("x.html", to = "github")), "default branch \\('main'\\)")
  expect_identical(
    system2("git", c("-C", shQuote(r$bare), "log", "-1", "--format=%s", "draft"), stdout = TRUE),
    "Publish x"
  )
})

test_that("GitHub Pages URLs come from the cloud or the remote", {
  expect_identical(framework:::.fw_github_pages_base("Ada", "study"), "https://ada.github.io/study/")
  expect_identical(framework:::.fw_github_pages_base("Ada", "ada.github.io"), "https://ada.github.io/")
  expect_identical(framework:::.fw_github_remote("git@github.com:Ada/study.git"),
                   list(owner = "Ada", repo = "study"))
  expect_identical(framework:::.fw_github_remote("https://github.com/Ada/study"),
                   list(owner = "Ada", repo = "study"))
  expect_null(framework:::.fw_github_remote("https://gitlab.com/Ada/study.git"))

  r <- local_pages_repo()
  writeLines("<p>x</p>", "x.html")
  testthat::local_mocked_bindings(
    .fw_cloud_pages_url = function(root) list(known = TRUE, pages_url = "https://docs.example.org/", server = "https://framework.pub")
  )
  expect_identical(suppressMessages(publish("x.html", to = "github")), "https://docs.example.org/x/")

  testthat::local_mocked_bindings(
    .fw_cloud_pages_url = function(root) list(known = TRUE, pages_url = NULL, server = "https://framework.pub")
  )
  writeLines("<p>y</p>", "x.html")
  expect_warning(
    url <- suppressMessages(publish("x.html", to = "github")),
    "GitHub Pages is off.*https://framework.pub"
  )
  expect_identical(url, "https://ada.github.io/study/x/")
  expect_identical(r$git("log", "-1", "--format=%s"), "Publish x")
})

test_that("the Pages URL comes from /api/v1/me with the project token", {
  root <- withr::local_tempdir()
  expect_false(framework:::.fw_cloud_pages_url(root)$known)
  skip_if_not_installed("httr2")
  called <- NULL
  testthat::local_mocked_bindings(
    .fw_project_token = function(project_dir = ".") "fw_project",
    .fw_project_cloud_url = function(project_dir = ".") "https://framework.pub",
    .fw_api = function(path, token, ...) {
      called <<- c(path = path, token = token)
      list(kind = "project", project = "study", pages_url = "https://ada.github.io/study/")
    }
  )
  res <- framework:::.fw_cloud_pages_url(root)
  expect_identical(called, c(path = "/api/v1/me", token = "fw_project"))
  expect_true(res$known)
  expect_identical(res$pages_url, "https://ada.github.io/study/")
})
