# pull_skills() and push_skills() against a mocked Framework Cloud

skill_pull_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude]"),
             file.path(root, "settings.yml"))
  writeLines(c("# Project", "", "## Skills", "", "old table", "", "## Notes", "", "Mine."),
             file.path(root, "AGENTS.md"))
  root
}

skill_pull_bundle <- function(text, name = "lab-style") {
  content <- paste0("---\nname: ", name, "\ndescription: Our lab's figure style\n---\n", text, "\n")
  list(list(path = "SKILL.md", content = jsonlite::base64_enc(charToRaw(content)), executable = FALSE))
}

skill_pull_entry <- function(text, version, skill_id = "lab-id") {
  bundle <- skill_pull_bundle(text)
  list(content = rawToChar(jsonlite::base64_dec(bundle[[1]]$content)), bundle = bundle,
       sync = list(skill_id = skill_id, version = version, hash = .skill_hash(bundle),
                   variant = "r", server = "https://cloud.example"))
}

skill_pull_envelope <- function(skills) {
  list(spec_version = 1L, name = "Test Project",
       layers = list(list(kind = "project", key = "test-project", layer = list(skills = skills))))
}

skill_pull_mock <- function(envelope, env = parent.frame(), user_token = NULL, remote = NULL) {
  local_mocked_bindings(
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_cloud_token = function(...) user_token,
    .fw_api = function(path, token, ...) {
      if (identical(path, "/api/v1/projects/pull")) {
        expect_identical(token, "project-token")
        if (is.function(envelope)) return(envelope())
        return(envelope)
      }
      if (startsWith(path, "/api/v1/skills/sync/")) return(remote)
      stop("unexpected request: ", path)
    },
    .env = env
  )
}

read_skill <- function(root, name, dir = ".claude/skills") {
  readLines(file.path(root, dir, name, "SKILL.md"), warn = FALSE)
}

test_that("pull_skills() adds the setup's skills, reports others, and refreshes AGENTS.md", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  dir.create(file.path(root, ".claude/skills/old-skill"), recursive = TRUE)
  writeLines(c("---", "name: old-skill", "description: Gone", "---"), file.path(root, ".claude/skills/old-skill/SKILL.md"))
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L), `ggplot2-publishing` = NULL)))

  out <- capture.output(result <- pull_skills(root), type = "message")
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(result$source, "cloud")
  expect_identical(statuses[["lab-style"]], "added")
  expect_identical(statuses[["framework-data"]], "added")
  expect_identical(statuses[["old-skill"]], "removed")
  expect_false("ggplot2-publishing" %in% names(statuses))
  expect_true(dir.exists(file.path(root, ".claude/skills/old-skill")))
  expect_identical(tail(read_skill(root, "lab-style"), 1), "Version one")
  expect_true(sprintf("Skills: %d added, 1 no longer in the project's setup", result$counts$added) %in% out)
  expect_true("  No longer in the project's setup (kept): old-skill" %in% out)
  agents <- readLines(file.path(root, "AGENTS.md"))
  expect_true(any(grepl("`.claude/skills/lab-style/SKILL.md`", agents, fixed = TRUE)))
  expect_true(any(grepl("Our lab's figure style", agents, fixed = TRUE)))
  expect_false("old table" %in% agents)
  expect_true("Mine." %in% agents)
  lock <- .skill_load(root)
  expect_true(any(vapply(lock$skills, function(e) identical(e$skill_id, "lab-id"), logical(1))))
})

test_that("pull_skills() updates unedited skills, keeps edited ones, and overwrite replaces them", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  version <- 1L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))

  version <- 2L
  writeLines("my edits", file.path(root, ".claude/skills/framework-data/SKILL.md"))
  out <- capture.output(result <- pull_skills(root), type = "message")
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["lab-style"]], "updated")
  expect_identical(statuses[["framework-data"]], "edited")
  expect_identical(tail(read_skill(root, "lab-style"), 1), "Version 2")
  expect_identical(read_skill(root, "framework-data"), "my edits")
  expect_true(any(grepl("^Skills: 1 updated, \\d+ up to date, 1 locally edited \\(kept\\)$", out)))
  expect_true(any(grepl("Kept (locally edited): framework-data", out, fixed = TRUE)))

  # Edited Cloud skills are kept too
  writeLines("lab edits", file.path(root, ".claude/skills/lab-style/SKILL.md"))
  version <- 3L
  result <- suppressMessages(pull_skills(root))
  expect_identical(read_skill(root, "lab-style"), "lab edits")

  backups <- length(list.files(file.path(root, ".framework/skills-backups")))
  out <- capture.output(result <- pull_skills(root, overwrite = TRUE), type = "message")
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["lab-style"]], "replaced")
  expect_identical(statuses[["framework-data"]], "replaced")
  expect_identical(tail(read_skill(root, "lab-style"), 1), "Version 3")
  expect_false(identical(read_skill(root, "framework-data"), "my edits"))
  expect_identical(length(list.files(file.path(root, ".framework/skills-backups"))), backups + 2L)
  expect_true(any(grepl("2 replaced (backed up)", out, fixed = TRUE)))
})

test_that("pull_skills() takes a Cloud skill's latest version when signed in", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  latest <- skill_pull_entry("Version five", 5L)
  remote <- list(skill_id = "lab-id", version = 5L, hash = latest$sync$hash, bundle = latest$bundle)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))),
                  user_token = "user-token", remote = remote)
  suppressMessages(pull_skills(root))
  expect_identical(tail(read_skill(root, "lab-style"), 1), "Version five")

  # Signed out: the setup's version, and a note saying so
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  out <- capture.output(pull_skills(root, dry_run = TRUE), type = "message")
  expect_true(any(grepl("Not signed in", out)))
})

test_that("pull_skills() keeps a newer version than the setup's when signed out", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  suppressMessages(pull_skills(root))

  # push_skills() made version 2; the project's setup still names version 1
  pushed <- skill_pull_entry("Version two", 2L)
  # The pushed bytes exactly: writeLines() would write CRLF on Windows
  writeBin(jsonlite::base64_dec(pushed$bundle[[1]]$content), file.path(root, ".claude/skills/lab-style/SKILL.md"))
  state <- .skill_load(root)
  key <- names(Filter(function(e) ".claude/skills/lab-style" %in% unlist(e$paths), state$skills))
  state$skills[[key]]$version <- 2L; state$skills[[key]]$hash <- pushed$sync$hash
  .skill_save(root, state)

  result <- suppressMessages(pull_skills(root))
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["lab-style"]], "current")
  expect_identical(tail(read_skill(root, "lab-style"), 1), "Version two")
  expect_identical(.skill_load(root)$skills[[key]]$version, 2L)
})

test_that("pull_skills() falls back to the package skills offline, and dry runs write nothing", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(function() stop("Could not resolve host: cloud.example"))
  out <- capture.output(result <- pull_skills(root, dry_run = TRUE), type = "message")
  expect_identical(result$source, "package")
  expect_match(out[1], "Framework Cloud not reached (Could not resolve host: cloud.example); using the package skills for this project type.", fixed = TRUE)
  expect_match(tail(out, 1), "^Skills \\(dry run, nothing written\\): \\d+ added$")
  expect_false(dir.exists(file.path(root, ".claude/skills")))
  expect_false(dir.exists(file.path(root, ".framework")))
  expect_true("old table" %in% readLines(file.path(root, "AGENTS.md")))

  result <- suppressMessages(pull_skills(root))
  expect_true(file.exists(file.path(root, ".claude/skills/framework-data/SKILL.md")))
  expect_false(any(vapply(result$skills, function(s) identical(s$status, "removed"), logical(1))))
})

# A project with one Cloud skill and one package skill pulled, and a Cloud
# that answers skill sync requests
skill_push_setup <- function(env = parent.frame()) {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token", .local_envir = env)
  root <- skill_pull_project(env)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))), env = env)
  suppressMessages(pull_skills(root))
  root
}

skill_push_mock <- function(cloud, env = parent.frame()) {
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_require_token = function(...) "user-token",
    .fw_interactive = function() FALSE,
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "POST")) {
        cloud$posts <- c(cloud$posts, body$skill_id %||% "new")
        id <- if (startsWith(body$skill_id, "framework:")) "own-copy" else body$skill_id
        cloud$remote[[id]] <- list(skill_id = id, version = body$expected_version + 1L,
                                   bundle = body$bundle, hash = .skill_hash(body$bundle))
        return(cloud$remote[[id]])
      }
      id <- utils::URLdecode(sub("\\?.*$", "", sub("^/api/v1/skills/sync/", "", path)))
      cloud$remote[[id]]
    },
    .env = env
  )
}

test_that("push_skills() pushes an edited Cloud skill after a warning, and refuses a changed one", {
  root <- skill_push_setup()
  entry <- skill_pull_entry("Version one", 1L)
  cloud <- new.env()
  cloud$remote <- list(`lab-id` = list(skill_id = "lab-id", version = 1L, bundle = entry$bundle, hash = entry$sync$hash))
  skill_push_mock(cloud)

  out <- capture.output(result <- push_skills(root), type = "message")
  expect_identical(result$message, "Skills pushed: nothing to push")

  writeLines(c("---", "name: lab-style", "description: Our lab's figure style", "---", "Edited here"),
             file.path(root, ".claude/skills/lab-style/SKILL.md"))
  expect_error(suppressMessages(push_skills(root)), "Without a console, pass confirm = TRUE")
  expect_null(cloud$posts)

  out <- capture.output(result <- push_skills(root, dry_run = TRUE), type = "message")
  expect_true("This replaces the current version of lab-style, used wherever it's attached." %in% out)
  expect_identical(result$message, "Skills (dry run, nothing sent): 1 to push")
  expect_null(cloud$posts)

  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 pushed")
  expect_identical(cloud$posts, "lab-id")
  expect_identical(cloud$remote$`lab-id`$version, 2L)

  # Cloud moves on while the project edits again: pull first, unless forced
  writeLines(c("---", "name: lab-style", "description: x", "---", "Edited again"),
             file.path(root, ".claude/skills/lab-style/SKILL.md"))
  web <- skill_pull_bundle("Web edit")
  cloud$remote$`lab-id` <- list(skill_id = "lab-id", version = 3L, bundle = web, hash = .skill_hash(web))
  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 refused (pull first)")
  expect_true(any(grepl("Pull first: lab-style changed on Cloud", out, fixed = TRUE)))
  expect_length(cloud$posts, 1L)

  out <- capture.output(result <- push_skills(root, force = TRUE, confirm = TRUE), type = "message")
  expect_true(any(grepl("Cloud has a newer version of lab-style", out, fixed = TRUE)))
  expect_identical(result$message, "Skills pushed: 1 pushed")
  expect_identical(cloud$remote$`lab-id`$version, 4L)
})

test_that("push_skills() saves an edited built-in skill as your own copy", {
  root <- skill_push_setup()
  shipped <- system.file("templates", "skills", "framework-data", package = "framework")
  cloud <- new.env()
  files <- .skill_scan(shipped)
  cloud$remote <- list(`framework:framework-data` = list(skill_id = "framework:framework-data", version = 1L,
                                                         bundle = files, hash = .skill_hash(files), system = TRUE))
  skill_push_mock(cloud)
  cat("Our addition\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)

  out <- capture.output(result <- push_skills(root, confirm = FALSE), type = "message")
  expect_true("This saves framework-data as your own skill; the built-in Framework skill stays as it is." %in% out)
  expect_identical(result$message, "Skills pushed: 1 cancelled")

  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 pushed")
  expect_identical(cloud$posts, "framework:framework-data")
  lock <- .skill_load(root)
  expect_true(any(vapply(lock$skills, function(e) identical(e$skill_id, "own-copy"), logical(1))))
})

test_that("push_skills() saves an edited built-in skill Cloud never published as a new skill", {
  root <- skill_push_setup()
  posts <- list()
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_require_token = function(...) "user-token",
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "POST")) {
        posts[[length(posts) + 1L]] <<- body
        return(list(skill_id = "own-copy", version = 1L, bundle = body$bundle, hash = .skill_hash(body$bundle)))
      }
      if (grepl("hash=", path, fixed = TRUE)) {
        rlang::abort("The installed source version is unavailable.", class = c("httr2_http_409", "httr2_http", "httr2_error"))
      }
      stop("unexpected request: ", path)
    }
  )
  # Unedited, it has nothing to push
  expect_identical(suppressMessages(push_skills(root, confirm = TRUE))$message, "Skills pushed: nothing to push")

  cat("Our addition\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)
  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 pushed")
  expect_length(posts, 1L)
  expect_null(posts[[1]]$skill_id)
  expect_identical(posts[[1]]$expected_version, 0L)
  lock <- .skill_load(root)
  expect_true(any(vapply(lock$skills, function(e) identical(e$skill_id, "own-copy"), logical(1))))
})

test_that("push_skills() lists untracked skills", {
  root <- skill_push_setup()
  cloud <- new.env()
  skill_push_mock(cloud)
  dir.create(file.path(root, ".claude/skills/scratch"))
  writeLines(c("---", "name: scratch", "description: x", "---"), file.path(root, ".claude/skills/scratch/SKILL.md"))
  out <- capture.output(result <- push_skills(root), type = "message")
  expect_identical(result$message, "Skills pushed: 1 not tracked")
  expect_true("  Not tracked: scratch \u2014 use skills_sync() to add it" %in% out)
})
