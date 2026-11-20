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

# Enable assistants in settings.yml; pull only uses enabled assistants' folders

skill_pull_assistants <- function(root, assistants) {
  writeLines(c("default:", "  project_type: project", "  ai:", paste0("    assistants: [", paste(assistants, collapse = ", "), "]")),
             file.path(root, "settings.yml"))
}

skill_pull_rows <- function(result, name = "lab-style") Filter(function(s) identical(s$name, name), result$skills)

skill_pull_lock_entry <- function(root, relative) skill_lock_entry(root, relative)
skill_pull_other <- function(root) .skill_load(root)$skills[["https://cloud.example/other-id@r"]]

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
  expect_true("  Removed: old-skill \u2014 It's no longer in the project's setup, so it was left in place." %in% out)
  agents <- readLines(file.path(root, "AGENTS.md"))
  expect_true(any(grepl("`.claude/skills/lab-style/SKILL.md`", agents, fixed = TRUE)))
  expect_true(any(grepl("Our lab's figure style", agents, fixed = TRUE)))
  expect_false("old table" %in% agents)
  expect_true("Mine." %in% agents)
  lock <- .skill_load(root)
  expect_true(any(vapply(lock$skills, function(e) identical(e$identity$skill_id, "lab-id"), logical(1))))
  expect_identical(jsonlite::read_json(file.path(root, ".framework/skills.lock.json"))$schema, 2L)
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
  expect_true(any(grepl("Edited: framework-data \u2014 .claude/skills/framework-data has local edits, which were kept. pull_skills(overwrite = TRUE) replaces them", out, fixed = TRUE)))

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
  key <- .skill_owner(state, ".claude/skills/lab-style")
  state$skills[[key]]$base$version <- 2L; state$skills[[key]]$base$hash <- pushed$sync$hash
  state$skills[[key]]$copies[] <- pushed$sync$hash
  .skill_save(root, state)

  result <- suppressMessages(pull_skills(root))
  row <- skill_pull_rows(result)[[1]]
  expect_identical(row$status, "current")
  expect_identical(row$reason_code, "newer_in_project")
  expect_identical(tail(read_skill(root, "lab-style"), 1), "Version two")
  expect_identical(.skill_load(root)$skills[[key]]$base$version, 2L)
})

test_that("pull_skills() falls back to the package skills offline, and dry runs write nothing", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(function() {
    stop(errorCondition("Could not resolve host: cloud.example", class = c("httr2_failure", "httr2_error")))
  })
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
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_require_token = function(...) "user-token",
    .fw_interactive = function() FALSE,
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "POST")) {
        cloud$posts <- c(cloud$posts, body$skill_id %||% "new")
        cloud$project_tokens <- c(cloud$project_tokens, body$project_token %||% "none")
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
  entry <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  expect_identical(entry$base$version, 2L)
  expect_identical(unname(entry$copies), cloud$remote$`lab-id`$hash)
  expect_null(entry$pending)

  # Cloud moves on while the project edits again: pull first, unless forced
  writeLines(c("---", "name: lab-style", "description: x", "---", "Edited again"),
             file.path(root, ".claude/skills/lab-style/SKILL.md"))
  web <- skill_pull_bundle("Web edit")
  cloud$remote$`lab-id` <- list(skill_id = "lab-id", version = 3L, bundle = web, hash = .skill_hash(web))
  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 refused (pull first)")
  expect_true(any(grepl("Refused: lab-style \u2014 lab-style changed on Cloud", out, fixed = TRUE)))
  expect_identical(result$skills[[1]]$reason_code, "cloud_changed")
  expect_identical(result$skills[[1]]$hint, "push_skills(force = TRUE)")
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
  # The project's token names the project, so Cloud lists the copy in its setup
  expect_identical(cloud$project_tokens, "project-token")
  # The built-in's entry becomes your own skill's
  lock <- .skill_load(root)
  expect_null(lock$skills[["framework:framework-data@r"]])
  own <- lock$skills[["https://cloud.example/own-copy@r"]]
  expect_identical(own$identity$kind, "cloud")
  expect_identical(names(own$copies), ".claude/skills/framework-data")
  expect_identical(own$known, cloud$remote$`own-copy`$hash)
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
  expect_true(any(vapply(lock$skills, function(e) identical(e$identity$skill_id, "own-copy"), logical(1))))
})

test_that("push_skills() lists untracked skills", {
  root <- skill_push_setup()
  cloud <- new.env()
  skill_push_mock(cloud)
  dir.create(file.path(root, ".claude/skills/scratch"))
  writeLines(c("---", "name: scratch", "description: x", "---"), file.path(root, ".claude/skills/scratch/SKILL.md"))
  out <- capture.output(result <- push_skills(root), type = "message")
  expect_identical(result$message, "Skills pushed: 1 not tracked")
  expect_true("  Untracked: scratch \u2014 .claude/skills/scratch isn't tracked. skills_sync(\".claude/skills/scratch\") pushes it as a new skill." %in% out)
})

# A project with an older Framework skill in both assistant folders, offline

skill_pull_two_folders <- function(env = parent.frame()) {
  withr::local_envvar(FW_PROJECT_TOKEN = NA, .local_envir = env)
  root <- withr::local_tempdir(.local_envir = env)
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude, codex]"),
             file.path(root, "settings.yml"))
  old <- withr::local_tempdir(.local_envir = env)
  writeLines(c("---", "name: framework-data", "description: x", "---", "Old"), file.path(old, "SKILL.md"))
  # "Old" is a version this package shipped
  real <- .skill_history
  old_hash <- .skill_hash(.skill_scan(old))
  local_mocked_bindings(.fw_project_token = function(...) NULL,
                        .skill_history = function(name, variant = "r") .skill_known(real(name, variant), old_hash),
                        .env = env)
  for (dir in c(".claude/skills", ".agents/skills")) {
    expect_true(skill_install_builtin(old, root, file.path(dir, "framework-data"), "framework-data"))
  }
  root
}

test_that("pull_skills() updates an unedited skill in every assistant folder", {
  root <- skill_pull_two_folders()
  result <- suppressMessages(pull_skills(root))
  skill <- Filter(function(s) identical(s$name, "framework-data"), result$skills)[[1]]
  expect_identical(skill$status, "updated")
  shipped <- .skill_hash(.skill_scan(system.file("templates", "skills", "framework-data", package = "framework")))
  for (dir in c(".claude/skills", ".agents/skills")) {
    expect_identical(.skill_hash(.skill_scan(file.path(root, dir, "framework-data"))), shipped)
  }
})

test_that("pull_skills() plans every skill before writing and names what it wrote when a write fails", {
  root <- skill_pull_two_folders()
  before <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  real <- .skill_install
  local_mocked_bindings(.skill_install = function(root, paths, ...) {
    if (identical(paths, ".claude/skills/framework-data")) stop("Disk full", call. = FALSE)
    real(root, paths, ...)
  })
  error <- tryCatch(suppressMessages(pull_skills(root)), error = conditionMessage)
  expect_match(error, "^pull_skills\\(\\) stopped at \\.claude/skills/framework-data: Disk full\\. Already written: ")
  expect_match(error, ".agents/skills/framework-data", fixed = TRUE)
  expect_false(grepl(".claude/skills/framework-data,", error, fixed = TRUE))
  # The lock records what was written and nothing else
  entry <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  shipped <- .skill_hash(.skill_scan(system.file("templates", "skills", "framework-data", package = "framework")))
  expect_identical(unname(entry$copies[".agents/skills/framework-data"]), shipped)
  expect_identical(unname(entry$copies[".claude/skills/framework-data"]), unname(before$copies[".claude/skills/framework-data"]))
  expect_identical(entry$base, before$base)
})

test_that("pull_skills() keeps an edit made between planning and writing", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  version <- 1L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))
  version <- 2L
  skill_md <- file.path(root, ".claude/skills/lab-style/SKILL.md")
  before <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  real <- .skill_apply
  local_mocked_bindings(.skill_apply = function(root, plan, ...) {
    cat("Edited during the pull\n", file = skill_md, append = TRUE)
    real(root, plan, ...)
  })
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result)[[1]]
  expect_identical(row$status, "edited")
  expect_identical(row$reason_code, "changed_during_pull")
  expect_true("Edited during the pull" %in% readLines(skill_md))
  expect_true("Version 1" %in% readLines(skill_md))
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$base, before$base)
})

test_that("pull_skills() names the skills it wrote when it can't save the lock", {
  root <- skill_pull_two_folders()
  local_mocked_bindings(.skill_save = function(...) stop("Disk full", call. = FALSE))
  error <- tryCatch(suppressMessages(pull_skills(root)), error = conditionMessage)
  expect_match(error, paste0("^pull_skills\\(\\) could not save \\.framework/skills\\.lock\\.json: Disk full\\. ",
                             "Already written: .*\\.claude/skills/framework-workflow"))
  expect_true(file.exists(file.path(root, ".claude/skills/framework-workflow/SKILL.md")))
})

# Round 5: diverged copies, new assistant folders, and Cloud identity


test_that("pull_skills() reports differing copies as diverged and writes neither", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  version <- 2L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))
  v2 <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  expect_identical(v2$base$version, 2L)
  # The .agents copy goes back to version 1 by hand: an edit; the setup names version 1
  writeLines(c("---", "name: lab-style", "description: Our lab's figure style", "---", "Version 1"),
             file.path(root, ".agents/skills/lab-style/SKILL.md"))
  version <- 1L
  before <- c(.skill_disk_hash(root, ".claude/skills/lab-style"), .skill_disk_hash(root, ".agents/skills/lab-style"))
  out <- capture.output(result <- pull_skills(root), type = "message")
  skill <- skill_pull_rows(result)[[1]]
  expect_identical(skill$status, "diverged")
  expect_identical(skill$reason_code, "copies_differ")
  expect_true(any(grepl(paste0("Diverged: lab-style \u2014 .agents/skills/lab-style and .claude/skills/lab-style differ, ",
                               "and only .agents/skills/lab-style is edited. Copy it over the other: ",
                               "skills_copy(from = \"agents\", to = \"claude\", skills = \"lab-style\")"), out, fixed = TRUE)))
  expect_identical(skill$hint, "skills_copy(from = \"agents\", to = \"claude\", skills = \"lab-style\")")
  expect_identical(c(.skill_disk_hash(root, ".claude/skills/lab-style"), .skill_disk_hash(root, ".agents/skills/lab-style")), before)
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style"), v2)
})

test_that("pull_skills() restores a missing copy from the project's newer copy, never an older version", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  version <- 2L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))
  v2 <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  unlink(file.path(root, ".agents/skills/lab-style"), recursive = TRUE)
  version <- 1L
  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result)[[1]]
  expect_identical(skill$status, "restored")
  expect_true("Version 2" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style"), v2)
})

test_that("pull_skills(overwrite = TRUE) never moves a skill to an older version", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L))))
  suppressMessages(pull_skills(root))
  cat("Edited\n", file = file.path(root, ".claude/skills/lab-style/SKILL.md"), append = TRUE)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  result <- suppressMessages(pull_skills(root, overwrite = TRUE))
  row <- skill_pull_rows(result)[[1]]
  expect_identical(row$status, "edited")
  expect_identical(row$reason_code, "newer_in_project")
  expect_true("Edited" %in% read_skill(root, "lab-style"))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$base$version, 2L)
})

test_that("a new assistant folder gets the setup's skills, and a folder tracking another skill is kept", {
  root <- skill_push_setup()
  shipped <- system.file("templates", "skills", "framework-data", package = "framework")
  files <- .skill_scan(shipped)
  cloud <- new.env()
  cloud$remote <- list(`framework:framework-data` = list(skill_id = "framework:framework-data", version = 1L,
                                                         bundle = files, hash = .skill_hash(files), system = TRUE))
  skill_push_mock(cloud)
  cat("Our addition\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)
  suppressMessages(push_skills(root, confirm = TRUE))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data")$identity$skill_id, "own-copy")

  # A new assistant folder; the setup still names the built-in
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  result <- suppressMessages(pull_skills(root))
  rows <- skill_pull_rows(result, "framework-data")
  statuses <- setNames(vapply(rows, `[[`, "", "status"), vapply(rows, function(r) r$paths[1], ""))
  expect_identical(statuses[[".claude/skills/framework-data"]], "kept")
  expect_identical(statuses[[".agents/skills/framework-data"]], "added")
  kept <- Filter(function(r) identical(r$status, "kept"), rows)[[1]]
  expect_identical(kept$reason_code, "other_identity")
  expect_identical(kept$hint, "skills_move(\".claude/skills/framework-data\", builtin = \"framework-data\", variant = \"r\")")
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data")$identity$skill_id, "own-copy")
  expect_true("Our addition" %in% read_skill(root, "framework-data"))
  expect_identical(.skill_disk_hash(root, ".agents/skills/framework-data"), .skill_hash(files))
  # An unedited Cloud skill and an unedited built-in fill the new folder
  expect_identical(skill_pull_rows(result)[[1]]$status, "added")
  expect_true("Version one" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(skill_pull_rows(result, "framework-cache")[[1]]$status, "added")
})

test_that("pull_skills(overwrite = TRUE) replaces an edited built-in and fills a new folder with it", {
  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  local_mocked_bindings(.fw_project_token = function(...) NULL)
  root <- withr::local_tempdir()
  skill_pull_assistants(root, "claude")
  suppressMessages(pull_skills(root))
  cat("My edit\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))

  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(skill$status, "diverged")
  expect_identical(skill$reason_code, "copy_absent")
  expect_identical(skill$hint, "skills_copy(from = \"claude\", to = \"agents\", skills = \"framework-data\")")
  expect_false(dir.exists(file.path(root, ".agents/skills/framework-data")))

  result <- suppressMessages(pull_skills(root, overwrite = TRUE))
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(skill$status, "replaced")
  expect_false(any(vapply(result$skills, function(s) identical(s$status, "diverged"), logical(1))))
  shipped <- .skill_hash(.skill_scan(system.file("templates", "skills", "framework-data", package = "framework")))
  for (dir in c(".claude/skills", ".agents/skills")) {
    expect_identical(.skill_disk_hash(root, file.path(dir, "framework-data")), shipped)
  }
  expect_false("My edit" %in% readLines(file.path(root, ".claude/skills/framework-data/SKILL.md")))
  expect_length(list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE), 1L)
})

# Round 6

# A project whose framework-data was edited and pushed as your own skill

# ("own-copy", version 1). Returns the root and the Cloud state.

skill_pull_own_setup <- function(env = parent.frame()) {
  root <- skill_push_setup(env)
  shipped <- system.file("templates", "skills", "framework-data", package = "framework")
  files <- .skill_scan(shipped)
  cloud <- new.env()
  cloud$remote <- list(`framework:framework-data` = list(skill_id = "framework:framework-data", version = 1L,
                                                         bundle = files, hash = .skill_hash(files), system = TRUE))
  skill_push_mock(cloud, env = env)
  cat("Our addition\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)
  suppressMessages(push_skills(root, confirm = TRUE))
  list(root = root, cloud = cloud)
}

# The setup naming your own skill for framework-data

skill_pull_own_envelope <- function(cloud) {
  own <- cloud$remote$`own-copy`
  skill_pull_envelope(list(
    `lab-style` = skill_pull_entry("Version one", 1L),
    `framework-data` = list(content = rawToChar(jsonlite::base64_dec(own$bundle[[1]]$content)), bundle = own$bundle,
                            sync = list(skill_id = "own-copy", version = own$version, hash = own$hash,
                                        variant = "r", server = "https://cloud.example"))))
}

test_that("an edited skill with a new folder is diverged, and nothing is written", {
  setup <- skill_pull_own_setup(); root <- setup$root
  cat("Another edit\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)
  before <- .skill_disk_hash(root, ".claude/skills/framework-data")
  lock <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  skill_pull_mock(skill_pull_own_envelope(setup$cloud))
  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(skill$status, "diverged")
  expect_identical(skill$reason_code, "copy_absent")
  expect_identical(.skill_disk_hash(root, ".claude/skills/framework-data"), before)
  expect_false(dir.exists(file.path(root, ".agents/skills/framework-data")))
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data"), lock)
})

test_that("a copy joining a skill joins its lock entry", {
  setup <- skill_pull_own_setup(); root <- setup$root
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  skill_pull_mock(skill_pull_own_envelope(setup$cloud))
  result <- suppressMessages(pull_skills(root))
  # Unedited: the new folder gets your skill
  expect_identical(skill_pull_rows(result, "framework-data")[[1]]$status, "added")
  skills_copy(from = "claude", to = "agents", skills = "framework-data", project_path = root) |> suppressMessages()
  suppressMessages(pull_skills(root))
  entries <- Filter(function(e) identical(e$identity$skill_id, "own-copy"), .skill_load(root)$skills)
  expect_length(entries, 1L)
  expect_setequal(names(entries[[1]]$copies), c(".claude/skills/framework-data", ".agents/skills/framework-data"))
  # A one-sided edit is a divergence, not a push
  cat("Codex only\n", file = file.path(root, ".agents/skills/framework-data/SKILL.md"), append = TRUE)
  skill_push_mock(setup$cloud)
  published <- setup$cloud$remote$`own-copy`$version
  result <- suppressMessages(push_skills(root, confirm = TRUE))
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["framework-data"]], "failed")
  expect_identical(setup$cloud$remote$`own-copy`$version, published)
})

test_that("a forced pull never moves a framework: skill to an older version", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L, skill_id = "framework:lab-style"))))
  suppressMessages(pull_skills(root))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$identity$kind, "builtin")
  cat("Edited\n", file = file.path(root, ".claude/skills/lab-style/SKILL.md"), append = TRUE)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L, skill_id = "framework:lab-style"))))
  suppressMessages(pull_skills(root, overwrite = TRUE))
  entry <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  expect_identical(entry$base$version, 2L)
  expect_true("Version 2" %in% read_skill(root, "lab-style"))
})

test_that("an offline pull leaves a skill tracked on Cloud as it is", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  files <- .skill_scan(system.file("templates", "skills", "framework-data", package = "framework"))
  synced <- list(content = "x", bundle = files,
                 sync = list(skill_id = "framework:framework-data", version = 2L, hash = .skill_hash(files),
                             variant = "r", server = "https://cloud.example"))
  skill_pull_mock(skill_pull_envelope(list(`framework-data` = synced)))
  suppressMessages(pull_skills(root))
  before <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  expect_identical(before$identity$skill_id, "framework:framework-data")
  expect_identical(before$base$channel, "cloud")

  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  local_mocked_bindings(.fw_project_token = function(...) NULL)
  out <- capture.output(result <- pull_skills(root), type = "message")
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(skill$status, "unavailable")
  expect_identical(skill$reason_code, "offline")
  expect_true(any(grepl("Unavailable: framework-data \u2014 Framework Cloud wasn't reached, so framework-data was left as it is.", out, fixed = TRUE)))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data"), before)
})

test_that("pull_skills() reports a skill whose every copy was missing as restored", {
  root <- skill_pull_two_folders()
  for (d in c(".claude/skills", ".agents/skills")) unlink(file.path(root, d, "framework-data"), recursive = TRUE)
  out <- capture.output(result <- pull_skills(root), type = "message")
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(skill$status, "restored")
  expect_true("  Restored: framework-data \u2014 A tracked copy was missing, so it was installed again." %in% out)
  expect_match(result$message, "1 restored")
  for (d in c(".claude/skills", ".agents/skills")) expect_true(dir.exists(file.path(root, d, "framework-data")))
})

test_that("your own skill is reported as yours, and overwrite doesn't claim to replace it", {
  setup <- skill_pull_own_setup(); root <- setup$root
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  for (overwrite in c(FALSE, TRUE)) {
    out <- capture.output(result <- pull_skills(root, overwrite = overwrite), type = "message")
    expect_true(any(startsWith(out, paste0("  Kept: framework-data \u2014 .claude/skills/framework-data belongs to a different ",
                                           "skill (own-copy), so pull left it alone. To switch it to the setup's skill: ",
                                           "skills_move(\".claude/skills/framework-data\", builtin = \"framework-data\""))))
    expect_false(any(grepl("framework-data — pull_skills(overwrite = TRUE) replaces it", out, fixed = TRUE)))
    expect_true("Our addition" %in% read_skill(root, "framework-data"))
  }
})

test_that("inline setup content never replaces your own skill of the same name", {
  setup <- skill_pull_own_setup(); root <- setup$root
  lock <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  skill_pull_mock(skill_pull_envelope(list(`framework-data` = list(content = "---\nname: framework-data\ndescription: x\n---\nInline\n"))))
  result <- suppressMessages(pull_skills(root, overwrite = TRUE))
  row <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(row$status, "kept")
  expect_identical(row$hint_args$identity$skill_id, "inline:framework-data")
  expect_true("Our addition" %in% read_skill(root, "framework-data"))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data"), lock)
})

test_that("an edited copy from before skill tracking isn't paired with the shipped text in a new folder", {
  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  local_mocked_bindings(.fw_project_token = function(...) NULL)
  root <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude, codex]"), file.path(root, "settings.yml"))
  dir.create(file.path(root, ".claude/skills/framework-data"), recursive = TRUE)
  writeLines(c("---", "name: framework-data", "description: x", "---", "Our own text"),
             file.path(root, ".claude/skills/framework-data/SKILL.md"))
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  result <- suppressMessages(pull_skills(root))
  skill <- Filter(function(s) identical(s$name, "framework-data"), result$skills)[[1]]
  expect_identical(skill$status, "diverged")
  expect_match(skill$hint, "skills_copy(from = \"claude\", to = \"agents\", skills = \"framework-data\")", fixed = TRUE)
  expect_false(dir.exists(file.path(root, ".agents/skills/framework-data")))
  expect_true("Our own text" %in% read_skill(root, "framework-data"))
})

test_that("overwrite resets an edited copy of your own skill to that skill's Cloud version", {
  setup <- skill_pull_own_setup(); root <- setup$root
  skill_md <- file.path(root, ".claude/skills/framework-data/SKILL.md")
  own <- setup$cloud$remote$`own-copy`

  # A different identity (the built-in) never replaces it, overwrite or not
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  cat("Edited again\n", file = skill_md, append = TRUE)
  for (overwrite in c(FALSE, TRUE)) {
    out <- capture.output(result <- pull_skills(root, overwrite = overwrite), type = "message")
    expect_true(any(startsWith(out, "  Kept: framework-data \u2014 .claude/skills/framework-data belongs to a different skill (own-copy)")))
    expect_true("Edited again" %in% readLines(skill_md))
  }

  # The same skill at the same version: kept, and the printed hint resets it
  skill_pull_mock(skill_pull_own_envelope(setup$cloud))
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(row$status, "edited")
  line <- grep("Edited: framework-data", out, fixed = TRUE, value = TRUE)
  expect_identical(line, paste0("  Edited: framework-data \u2014 .claude/skills/framework-data has local edits, which were kept. ",
                                "pull_skills(overwrite = TRUE) replaces them with the Cloud version."))
  expect_identical(row$hint, "pull_skills(overwrite = TRUE)")
  call <- str2lang(row$hint); call$project_path <- root
  result <- suppressMessages(eval(call))
  expect_identical(skill_pull_rows(result, "framework-data")[[1]]$status, "replaced")
  expect_identical(.skill_disk_hash(root, ".claude/skills/framework-data"), own$hash)
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data")$identity$skill_id, "own-copy")
  backup <- list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE)
  expect_length(backup, 1L)
  expect_true("Edited again" %in% readLines(file.path(backup, "SKILL.md")))

  # A newer version: kept without overwrite; the printed hint replaces it
  cat("Edited once more\n", file = skill_md, append = TRUE)
  newer <- skill_pull_bundle("Newer on Cloud", name = "framework-data")
  setup$cloud$remote$`own-copy` <- list(skill_id = "own-copy", version = own$version + 1L, bundle = newer, hash = .skill_hash(newer))
  skill_pull_mock(skill_pull_own_envelope(setup$cloud))
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(row$status, "edited")
  expect_identical(row$hint, "pull_skills(overwrite = TRUE)")
  call <- str2lang(row$hint); call$project_path <- root
  suppressMessages(eval(call))
  expect_true("Newer on Cloud" %in% readLines(skill_md))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data")$base$version, own$version + 1L)
  expect_length(list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE), 2L)
})

# Round 7

# skill_pull_own_setup() with framework-data also in .agents/skills,

# tracked in the same lock entry

skill_pull_own_two_folders <- function(env = parent.frame()) {
  setup <- skill_pull_own_setup(env)
  root <- setup$root
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  suppressMessages(skills_copy(from = "claude", to = "agents", skills = "framework-data", project_path = root))
  skill_pull_mock(skill_pull_own_envelope(setup$cloud), env = env)
  suppressMessages(pull_skills(root))
  expect_setequal(names(skill_pull_lock_entry(root, ".agents/skills/framework-data")$copies),
                  c(".claude/skills/framework-data", ".agents/skills/framework-data"))
  setup
}

test_that("a forced update of your own skill updates every folder", {
  setup <- skill_pull_own_two_folders(); root <- setup$root
  for (d in c(".claude/skills", ".agents/skills")) cat("Same edit\n", file = file.path(root, d, "framework-data/SKILL.md"), append = TRUE)
  own <- setup$cloud$remote$`own-copy`
  newer <- skill_pull_bundle("Newer on Cloud", name = "framework-data")
  setup$cloud$remote$`own-copy` <- list(skill_id = "own-copy", version = own$version + 1L, bundle = newer, hash = .skill_hash(newer))
  skill_pull_mock(skill_pull_own_envelope(setup$cloud))
  result <- suppressMessages(pull_skills(root, overwrite = TRUE))
  expect_identical(skill_pull_rows(result, "framework-data")[[1]]$status, "replaced")
  for (d in c(".claude/skills", ".agents/skills")) {
    expect_true("Newer on Cloud" %in% readLines(file.path(root, d, "framework-data/SKILL.md")), info = d)
  }
  expect_identical(skill_pull_lock_entry(root, ".agents/skills/framework-data")$base$version, own$version + 1L)
})

test_that("two clean copies of a Cloud skill both move to the new version", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  version <- 1L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))
  version <- 2L
  result <- suppressMessages(pull_skills(root))
  expect_identical(skill_pull_rows(result)[[1]]$status, "updated")
  for (d in c(".claude/skills", ".agents/skills")) expect_true("Version 2" %in% read_skill(root, "lab-style", d), info = d)
  expect_identical(skill_pull_lock_entry(root, ".agents/skills/lab-style")$base$version, 2L)
})

test_that("a copy whose folder is gone is missing, and the others are restored", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  suppressMessages(pull_skills(root))
  # Codex is disabled again; its tracked copy stays in the lock
  skill_pull_assistants(root, "claude")
  unlink(file.path(root, ".claude/skills/lab-style"), recursive = TRUE)
  unlink(file.path(root, ".agents"), recursive = TRUE)
  out <- capture.output(result <- pull_skills(root), type = "message")
  skill <- skill_pull_rows(result)[[1]]
  expect_identical(skill$status, "missing")
  expect_identical(skill$reason_code, "folder_gone")
  expect_true("  Missing: lab-style \u2014 .agents/skills/lab-style's folder is gone, so it can't be restored." %in% out)
  expect_true(dir.exists(file.path(root, ".claude/skills/lab-style")))

  # A tracked folder that exists is restored too, even when not configured
  unlink(file.path(root, ".claude/skills/lab-style"), recursive = TRUE)
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  out <- capture.output(result <- pull_skills(root), type = "message")
  expect_identical(skill_pull_rows(result)[[1]]$status, "restored")
  for (d in c(".claude/skills", ".agents/skills")) expect_true(dir.exists(file.path(root, d, "lab-style")), info = d)
})

test_that("a schema 1 lock with two entries for one Cloud skill is read as one", {
  setup <- skill_pull_own_two_folders(); root <- setup$root
  entry <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  # The lock as earlier versions wrote it: one entry per folder
  v1 <- function(path) {
    list(paths = list(path), variant = "r", server = "https://cloud.example", skill_id = "own-copy",
         version = entry$base$version, hash = entry$base$hash)
  }
  writeLines(jsonlite::toJSON(list(schema = 1L, skills = list(
    `account:https://cloud.example:own-copy:r` = v1(".claude/skills/framework-data"),
    `.agents/skills/framework-data` = v1(".agents/skills/framework-data"))), auto_unbox = TRUE, pretty = TRUE),
    file.path(root, ".framework/skills.lock.json"))

  entries <- Filter(function(e) identical(e$identity$skill_id, "own-copy"), .skill_load(root)$skills)
  expect_length(entries, 1L)
  expect_setequal(names(entries[[1]]$copies), c(".claude/skills/framework-data", ".agents/skills/framework-data"))

  # A one-sided edit is a divergence, not a push
  cat("Codex only\n", file = file.path(root, ".agents/skills/framework-data/SKILL.md"), append = TRUE)
  skill_push_mock(setup$cloud)
  published <- setup$cloud$remote$`own-copy`$version
  result <- suppressMessages(push_skills(root, confirm = TRUE))
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["framework-data"]], "failed")
  expect_identical(setup$cloud$remote$`own-copy`$version, published)
  # Nothing changed, so the schema 1 file is left as it is
  expect_identical(jsonlite::read_json(file.path(root, ".framework/skills.lock.json"))$schema, 1L)
})

test_that("a pull with matching bytes updates the version, never to an older one", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  entry <- skill_pull_entry("Version one", 1L)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = entry)))
  suppressMessages(pull_skills(root))
  same <- entry; same$sync$version <- 2L
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = same)))
  result <- suppressMessages(pull_skills(root))
  expect_identical(skill_pull_rows(result)[[1]]$status, "current")
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$base$version, 2L)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = entry)))
  result <- suppressMessages(pull_skills(root))
  expect_identical(skill_pull_rows(result)[[1]]$status, "current")
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$base$version, 2L)
})

test_that("skills_sync() of a copy made with skills_copy() joins its skill", {
  setup <- skill_pull_own_setup(); root <- setup$root
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  suppressMessages(skills_copy(from = "claude", to = "agents", skills = "framework-data", project_path = root))
  posts <- length(setup$cloud$posts)
  result <- skills_sync(".agents/skills/framework-data", root)
  expect_identical(result$action, "unchanged")
  expect_length(setup$cloud$posts, posts)
  expect_length(Filter(function(e) identical(e$identity$skill_id, "own-copy"), .skill_load(root)$skills), 1L)
  expect_null(.skill_load(root)$skills[["local:.agents/skills/framework-data"]])
})

# Rule J: explicit joins

test_that("the printed hint, then pull, then push keeps the copies as one skill", {
  setup <- skill_pull_own_setup(); root <- setup$root
  cat("Edited\n", file = file.path(root, ".claude/skills/framework-data/SKILL.md"), append = TRUE)
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  skill_pull_mock(skill_pull_own_envelope(setup$cloud))
  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(skill$status, "diverged")
  expect_identical(skill$hint, "skills_copy(from = \"claude\", to = \"agents\", skills = \"framework-data\")")
  call <- str2lang(skill$hint); call$project_path <- root
  suppressMessages(eval(call))
  result <- suppressMessages(pull_skills(root))
  expect_identical(skill_pull_rows(result, "framework-data")[[1]]$status, "edited")
  entries <- Filter(function(e) identical(e$identity$skill_id, "own-copy"), .skill_load(root)$skills)
  expect_length(entries, 1L)
  expect_setequal(names(entries[[1]]$copies), c(".claude/skills/framework-data", ".agents/skills/framework-data"))
  cat("Codex only\n", file = file.path(root, ".agents/skills/framework-data/SKILL.md"), append = TRUE)
  skill_push_mock(setup$cloud)
  published <- setup$cloud$remote$`own-copy`$version
  result <- suppressMessages(push_skills(root, confirm = TRUE))
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["framework-data"]], "failed")
  expect_identical(setup$cloud$remote$`own-copy`$version, published)
})

test_that("a copy in a custom folder moves to the new version with the others", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  version <- 1L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))
  suppressMessages(skills_copy(from_dir = ".claude/skills", to_dir = "custom/skills", skills = "lab-style", project_path = root))
  expect_true("custom/skills/lab-style" %in% names(skill_pull_lock_entry(root, ".claude/skills/lab-style")$copies))
  version <- 2L
  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result)[[1]]
  expect_identical(skill$status, "updated")
  expect_true("custom/skills/lab-style" %in% skill$paths)
  for (d in c(".claude/skills", "custom/skills")) expect_true("Version 2" %in% read_skill(root, "lab-style", d), info = d)
  expect_identical(skill_pull_lock_entry(root, "custom/skills/lab-style")$base$version, 2L)
})

test_that("a standalone skill with the same name keeps its own identity under skills_sync()", {
  setup <- skill_pull_own_setup(); root <- setup$root
  before <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  dir.create(file.path(root, "custom/skills/framework-data"), recursive = TRUE)
  writeLines(c("---", "name: framework-data", "description: Mine", "---", "A different skill"),
             file.path(root, "custom/skills/framework-data/SKILL.md"))
  posts <- list()
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_require_token = function(...) "user-token",
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "POST")) {
        posts[[length(posts) + 1L]] <<- body
        return(list(skill_id = "standalone", version = 1L, bundle = body$bundle, hash = .skill_hash(body$bundle)))
      }
      NULL
    })
  result <- skills_sync("custom/skills/framework-data", root)
  expect_identical(result$action, "push")
  expect_length(posts, 1L)
  expect_null(posts[[1]]$skill_id)
  expect_identical(skill_pull_lock_entry(root, "custom/skills/framework-data")$identity$skill_id, "standalone")
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data"), before)
})

# Round 9

# Add a Cloud skill's entry to the lock, tracking `paths` at `hash`
skill_pull_add_entry <- function(root, skill_id, paths, version, hash, server = "https://cloud.example") {
  state <- .skill_load(root)
  identity <- .skill_identity("cloud", skill_id, "r", server)
  entry <- .skill_entry_new(identity)
  entry$base <- list(channel = "cloud", hash = hash, version = as.integer(version), server = server)
  entry$known <- hash
  entry$copies <- stats::setNames(rep(hash, length(paths)), paths)
  state$skills[[.skill_key(identity)]] <- entry
  .skill_save(root, state)
  entry
}

test_that("two independent skills with one name are not compared with each other", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  suppressMessages(pull_skills(root))
  # A separate skill of the same name in .agents/skills, with its own ID
  other <- file.path(root, ".agents/skills/lab-style")
  dir.create(other, recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  writeLines(c("---", "name: lab-style", "description: Another lab", "---", "Theirs"), file.path(other, "SKILL.md"))
  theirs <- skill_pull_add_entry(root, "other-id", ".agents/skills/lab-style", 4L, .skill_disk_hash(root, ".agents/skills/lab-style"))

  result <- suppressMessages(pull_skills(root))
  rows <- skill_pull_rows(result)
  expect_setequal(vapply(rows, `[[`, "", "status"), c("kept", "current"))
  expect_true("Theirs" %in% readLines(file.path(other, "SKILL.md")))
  expect_identical(skill_pull_other(root), theirs)
})

test_that("variants and servers of one Cloud skill are never merged when the lock is read", {
  state <- list(schema = 1L, skills = list(
    r = list(paths = list(".claude/skills/x"), skill_id = "x-id", server = "https://c", variant = "r", version = 2L, hash = "h2"),
    py = list(paths = list(".agents/skills/x"), skill_id = "x-id", server = "https://c", variant = "python", version = 1L, hash = "h1"),
    split = list(paths = list("custom/skills/x"), skill_id = "x-id", server = "https://c", variant = "r", version = 2L, hash = "h2"),
    elsewhere = list(paths = list("other/skills/x"), skill_id = "x-id", server = "https://other", variant = "r", version = 1L, hash = "h1")))
  migrated <- .skill_migrate(state)
  expect_setequal(names(migrated$skills), c("https://c/x-id@r", "https://c/x-id@python", "https://other/x-id@r"))
  expect_setequal(names(migrated$skills[["https://c/x-id@r"]]$copies), c(".claude/skills/x", "custom/skills/x"))
  expect_identical(names(migrated$skills[["https://c/x-id@python"]]$copies), ".agents/skills/x")
})

# A skill tracked only in custom/skills, in a project switched from Claude

# Code to Codex

skill_pull_switched <- function(root) {
  suppressMessages(skills_copy(from_dir = ".claude/skills", to_dir = "custom/skills", project_path = root))
  state <- .skill_load(root)
  for (k in names(state$skills)) {
    copies <- state$skills[[k]]$copies
    state$skills[[k]]$copies <- copies[!startsWith(names(copies), ".claude/skills/")]
  }
  .skill_save(root, state)
  unlink(file.path(root, ".claude"), recursive = TRUE)
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [codex]"), file.path(root, "settings.yml"))
}

test_that("after switching assistants, a tracked custom copy moves with its skill", {
  root <- skill_pull_two_folders()
  unlink(file.path(root, ".agents"), recursive = TRUE)
  state <- .skill_load(root)
  for (k in names(state$skills)) {
    copies <- state$skills[[k]]$copies
    state$skills[[k]]$copies <- copies[startsWith(names(copies), ".claude")]
  }
  .skill_save(root, state)
  skill_pull_switched(root)
  expect_identical(names(skill_pull_lock_entry(root, "custom/skills/framework-data")$copies), "custom/skills/framework-data")

  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result, "framework-data")[[1]]
  expect_setequal(skill$paths, c(".agents/skills/framework-data", "custom/skills/framework-data"))
  shipped <- .skill_hash(.skill_scan(system.file("templates", "skills", "framework-data", package = "framework")))
  for (p in c(".agents/skills/framework-data", "custom/skills/framework-data")) expect_identical(.skill_disk_hash(root, p), shipped, info = p)
  entry <- skill_pull_lock_entry(root, "custom/skills/framework-data")
  expect_setequal(names(entry$copies), c(".agents/skills/framework-data", "custom/skills/framework-data"))
  expect_identical(unique(unname(entry$copies)), shipped)
})

test_that("after switching assistants, an unedited Cloud skill fills the new folder and updates", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  version <- 1L
  skill_pull_mock(function() skill_pull_envelope(list(`lab-style` = skill_pull_entry(paste("Version", version), version))))
  suppressMessages(pull_skills(root))
  skill_pull_switched(root)
  version <- 3L
  result <- suppressMessages(pull_skills(root))
  skill <- skill_pull_rows(result)[[1]]
  expect_setequal(skill$paths, c(".agents/skills/lab-style", "custom/skills/lab-style"))
  expect_identical(skill$status, "updated")
  for (d in c("custom/skills", ".agents/skills")) expect_true("Version 3" %in% read_skill(root, "lab-style", d), info = d)
  expect_identical(skill_pull_lock_entry(root, ".agents/skills/lab-style")$base$version, 3L)
})

# Round 10: per-entry planning

# lab-style from the setup (lab-id) in .claude/skills, and an independent

# lab-style (other-id) in .agents/skills

skill_pull_two_skills <- function(env = parent.frame()) {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token", .local_envir = env)
  root <- skill_pull_project(env)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))), env = env)
  suppressMessages(pull_skills(root))
  other <- file.path(root, ".agents/skills/lab-style")
  dir.create(other, recursive = TRUE)
  skill_pull_assistants(root, c("claude", "codex"))
  writeLines(c("---", "name: lab-style", "description: Another lab", "---", "Theirs"), file.path(other, "SKILL.md"))
  skill_pull_add_entry(root, "other-id", ".agents/skills/lab-style", 4L, .skill_disk_hash(root, ".agents/skills/lab-style"))
  root
}



test_that("deleting one of two same-named skills restores it without touching the other", {
  root <- skill_pull_two_skills()
  theirs <- skill_pull_other(root)
  unlink(file.path(root, ".claude/skills/lab-style"), recursive = TRUE)
  out <- capture.output(result <- pull_skills(root), type = "message")
  rows <- skill_pull_rows(result)
  statuses <- vapply(rows, `[[`, "", "status")
  expect_true("restored" %in% statuses)
  expect_false("diverged" %in% statuses)
  expect_false(any(grepl("skills_copy(", out, fixed = TRUE)))
  expect_true("Version 1" %in% read_skill(root, "lab-style"))
  expect_true("Theirs" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(skill_pull_other(root), theirs)
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$identity$skill_id, "lab-id")
})

test_that("a diverged entry doesn't block an update to a same-named skill", {
  root <- skill_pull_two_skills()
  # The other skill is also tracked in custom/skills, edited there
  dir.create(file.path(root, "custom/skills/lab-style"), recursive = TRUE)
  writeLines(c("---", "name: lab-style", "description: Another lab", "---", "Theirs, edited"),
             file.path(root, "custom/skills/lab-style/SKILL.md"))
  state <- .skill_load(root)
  key <- "https://cloud.example/other-id@r"
  state$skills[[key]]$copies["custom/skills/lab-style"] <- state$skills[[key]]$copies[[".agents/skills/lab-style"]]
  .skill_save(root, state)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L))))
  out <- capture.output(result <- pull_skills(root), type = "message")
  rows <- skill_pull_rows(result)
  updated <- Filter(function(r) identical(r$status, "updated"), rows)
  expect_identical(updated[[1]]$paths, ".claude/skills/lab-style")
  diverged <- Filter(function(r) identical(r$status, "diverged"), rows)[[1]]
  expect_identical(diverged$paths, c(".agents/skills/lab-style", "custom/skills/lab-style"))
  # The hint copies within the other skill's own entry, from its edited copy
  expect_identical(diverged$hint, "skills_copy(from_dir = \"custom/skills\", to_dir = \".agents/skills\", skills = \"lab-style\")")
  expect_true("Version 2" %in% read_skill(root, "lab-style"))
  expect_true("Theirs" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$base$version, 2L)
})

test_that("updating one of two same-named skills leaves the other alone", {
  root <- skill_pull_two_skills()
  theirs <- skill_pull_other(root)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L))))
  result <- suppressMessages(pull_skills(root))
  rows <- skill_pull_rows(result)
  expect_true("updated" %in% vapply(rows, `[[`, "", "status"))
  expect_true("Version 2" %in% read_skill(root, "lab-style"))
  expect_true("Theirs" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(skill_pull_other(root), theirs)
})

test_that("a hand-made copy beside a tracked skill is never written or joined", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  suppressMessages(pull_skills(root))
  # Version 1's text, made by hand in .agents/skills
  dir.create(file.path(root, ".agents/skills/lab-style"), recursive = TRUE)
  file.copy(file.path(root, ".claude/skills/lab-style/SKILL.md"), file.path(root, ".agents/skills/lab-style"))
  skill_pull_assistants(root, c("claude", "codex"))
  before <- .skill_disk_hash(root, ".agents/skills/lab-style")
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L))))
  out <- capture.output(result <- pull_skills(root), type = "message")
  rows <- skill_pull_rows(result)
  statuses <- setNames(vapply(rows, `[[`, "", "status"), vapply(rows, function(r) r$paths[1], ""))
  expect_identical(statuses[[".claude/skills/lab-style"]], "updated")
  expect_identical(statuses[[".agents/skills/lab-style"]], "untracked")
  row <- Filter(function(r) identical(r$status, "untracked"), rows)[[1]]
  expect_identical(row$reason, paste0(".agents/skills/lab-style isn't tracked, so pull left it alone. To track it with this skill: ",
                                      "skills_copy(from = \"claude\", to = \"agents\", skills = \"lab-style\")"))
  expect_identical(.skill_disk_hash(root, ".agents/skills/lab-style"), before)
  expect_false(".agents/skills/lab-style" %in% names(skill_pull_lock_entry(root, ".claude/skills/lab-style")$copies))
  # The hint, run as printed, joins the copy to the skill
  call <- str2lang(row$hint); call$project_path <- root; suppressMessages(eval(call))
  expect_setequal(names(skill_pull_lock_entry(root, ".claude/skills/lab-style")$copies),
                  c(".claude/skills/lab-style", ".agents/skills/lab-style"))
  expect_true("Version 2" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_length(Filter(function(e) identical(e$identity$skill_id, "lab-id"), .skill_load(root)$skills), 1L)
})

test_that("one broken entry fails alone and the others are pulled", {
  root <- skill_pull_two_skills()
  unlink(file.path(root, ".agents/skills/lab-style/SKILL.md"))
  writeLines("notes", file.path(root, ".agents/skills/lab-style/notes.md"))
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L))))
  out <- capture.output(result <- pull_skills(root), type = "message")
  rows <- skill_pull_rows(result)
  failed <- Filter(function(r) identical(r$status, "failed"), rows)
  expect_length(failed, 1L)
  expect_identical(failed[[1]]$paths, ".agents/skills/lab-style")
  expect_identical(failed[[1]]$reason_code, "unreadable")
  expect_identical(Filter(function(r) ".claude/skills/lab-style" %in% r$paths, rows)[[1]]$status, "updated")
  expect_true(any(grepl("Failed: lab-style — .*SKILL.md is required", out)))
  expect_true("Version 2" %in% read_skill(root, "lab-style"))
  expect_match(result$message, "1 failed")
})

test_that("built-in origins of different variants are never merged when the lock is read", {
  state <- list(schema = 1L, skills = list(
    r = list(paths = list(".claude/skills/x"), origin = list(skill_id = "framework:x", hash = "h"), variant = "r", hash = "h"),
    py = list(paths = list(".agents/skills/x"), origin = list(skill_id = "framework:x", hash = "h"), variant = "python", hash = "h"),
    again = list(paths = list("custom/skills/x"), origin = list(skill_id = "framework:x", hash = "h"), variant = "r", hash = "h")))
  migrated <- .skill_migrate(state)
  expect_length(migrated$skills, 2L)
  expect_identical(names(migrated$skills[["framework:x@python"]]$copies), ".agents/skills/x")
})

# Round 11

test_that("after .claude is renamed to .agents, pull points to skills_move() and writes nothing", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  suppressMessages(pull_skills(root))
  file.rename(file.path(root, ".claude"), file.path(root, ".agents"))
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [codex]"), file.path(root, "settings.yml"))
  before <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  out <- capture.output(result <- pull_skills(root), type = "message")
  rows <- skill_pull_rows(result)
  statuses <- setNames(vapply(rows, `[[`, "", "status"), vapply(rows, function(r) r$paths[1], ""))
  expect_identical(statuses[[".claude/skills/lab-style"]], "missing")
  expect_identical(statuses[[".agents/skills/lab-style"]], "untracked")
  move <- "skills_move(\".claude/skills/lab-style\", \".agents/skills/lab-style\")"
  for (row in rows) expect_identical(row$hint, move)
  expect_true(paste0("  Missing: lab-style \u2014 .claude/skills/lab-style's folder is gone, so it can't be restored. ",
                     "If the skill moved to .agents/skills/lab-style: ", move) %in% out)
  expect_false(any(grepl("skills_sync(", out, fixed = TRUE)))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style"), before)
  # The hint, run as printed, moves the lock record
  call <- str2lang(move); call$project_path <- root; suppressMessages(eval(call))
  entry <- skill_pull_lock_entry(root, ".agents/skills/lab-style")
  expect_identical(entry$identity$skill_id, "lab-id")
  expect_identical(names(entry$copies), ".agents/skills/lab-style")
  result <- suppressMessages(pull_skills(root))
  expect_identical(skill_pull_rows(result)[[1]]$status, "current")
})

test_that("a copy tracking a different Cloud skill than the setup names is kept with the reason", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L, skill_id = "acct-1"))))
  suppressMessages(pull_skills(root))
  # The setup now names another Cloud skill with the same bytes and name
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L, skill_id = "acct-2"))))
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result)[[1]]
  expect_identical(row$status, "kept")
  expect_identical(row$reason_code, "other_identity")
  expect_identical(row$reason, paste0(".claude/skills/lab-style belongs to a different skill (acct-1), so pull left it alone. ",
                                      "To switch it to the setup's skill: ",
                                      "skills_move(\".claude/skills/lab-style\", skill_id = \"acct-2\", variant = \"r\")"))
  expect_true(any(grepl("Kept: lab-style \u2014 .claude/skills/lab-style belongs to a different skill (acct-1)", out, fixed = TRUE)))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$identity$skill_id, "acct-1")
})

test_that("the only copy of your own fork comes back from its own Cloud identity, or is reported missing", {
  setup <- skill_pull_own_setup(); root <- setup$root
  lock <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  unlink(file.path(root, ".claude/skills/framework-data"), recursive = TRUE)
  # Signed out: missing, and the hint says what restores it
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(row$status, "missing")
  expect_identical(row$reason, paste0("Every tracked copy is gone. Sign in with cloud_login(), then pull again ",
                                      "to restore it from Cloud skill own-copy."))
  expect_identical(row$hint, "cloud_login()")
  expect_false(dir.exists(file.path(root, ".claude/skills/framework-data")))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data"), lock)

  # Signed in: restored from own-copy, not from the built-in
  own <- setup$cloud$remote$`own-copy`
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))),
                  user_token = "user-token", remote = own)
  result <- suppressMessages(pull_skills(root))
  row <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(row$status, "restored")
  expect_identical(.skill_disk_hash(root, ".claude/skills/framework-data"), own$hash)
  expect_true("Our addition" %in% read_skill(root, "framework-data"))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data")$identity$skill_id, "own-copy")
})

test_that("a folder pulled under another spelling is never also reported removed", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  dir.create(file.path(root, ".claude/skills/Lab-Style"), recursive = TRUE)
  writeLines(c("---", "name: lab-style", "description: x", "---", "Mine"), file.path(root, ".claude/skills/Lab-Style/SKILL.md"))
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  result <- suppressMessages(pull_skills(root))
  expect_false(any(vapply(result$skills, function(s) identical(s$status, "removed") && identical(tolower(s$name), "lab-style"), logical(1))))
})

# Round 12

test_that("a folder tracked through a case alias isn't claimed by the setup's entry", {
  root <- skill_pull_two_skills()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  skill_pull_assistants(root, c("claude", "codex"))
  state <- .skill_load(root)
  key <- "https://cloud.example/other-id@r"
  names(state$skills[[key]]$copies) <- ".Agents/Skills/lab-style"
  .skill_save(root, state)
  theirs <- state$skills[[key]]
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L))))
  suppressMessages(pull_skills(root, overwrite = TRUE))
  expect_true("Theirs" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(skill_pull_other(root), theirs)
  expect_true("Version 2" %in% read_skill(root, "lab-style"))
})

test_that("a tracked skill outside the setup with every copy gone is reported missing, truthfully", {
  setup <- skill_pull_own_setup(); root <- setup$root
  # A standalone personal skill, pushed and then deleted
  skill_pull_add_entry(root, "solo-id", ".claude/skills/solo", 1L, "x")
  skill_push_mock(setup$cloud)
  out <- capture.output(push_skills(root, confirm = TRUE), type = "message")
  expect_true("  Missing: solo \u2014 Every tracked copy is gone, so there is nothing to push." %in% out)
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version one", 1L))))
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result, "solo")[[1]]
  expect_identical(row$status, "missing")
  expect_identical(row$reason_code, "all_gone")
  expect_true(paste0("  Missing: solo \u2014 Every tracked copy is gone. Sign in with cloud_login(), then pull again ",
                     "to restore it from Cloud skill solo-id.") %in% out)
})

test_that("an offline pull reports your own skill as unavailable, even with every copy gone", {
  setup <- skill_pull_own_setup(); root <- setup$root
  own <- setup$cloud$remote$`own-copy`
  unlink(file.path(root, ".claude/skills/framework-data"), recursive = TRUE)
  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  local_mocked_bindings(
    .fw_project_token = function(...) NULL,
    .fw_cloud_token = function(...) "user-token",
    .fw_api = function(path, ...) stop("unexpected: ", path))
  out <- capture.output(result <- pull_skills(root), type = "message")
  row <- skill_pull_rows(result, "framework-data")[[1]]
  expect_identical(row$status, "unavailable")
  expect_identical(row$reason_code, "offline")
  expect_false(dir.exists(file.path(root, ".claude/skills/framework-data")))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data")$identity$skill_id, "own-copy")
})

test_that("a file at a disabled assistant's path doesn't block the enabled one", {
  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  local_mocked_bindings(.fw_project_token = function(...) NULL)
  root <- withr::local_tempdir()
  skill_pull_assistants(root, "codex")
  dir.create(file.path(root, ".claude/skills"), recursive = TRUE)
  writeLines("not a skill", file.path(root, ".claude/skills/framework-data"))
  result <- suppressMessages(pull_skills(root))
  row <- Filter(function(s) identical(s$name, "framework-data"), result$skills)[[1]]
  expect_identical(row$status, "added")
  expect_identical(row$paths, ".agents/skills/framework-data")
  expect_true(file.exists(file.path(root, ".agents/skills/framework-data/SKILL.md")))
})

test_that("a copy tracking a published framework: skill is never replaced by a different Cloud skill", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 5", 5L, skill_id = "framework:lab-style"))))
  suppressMessages(pull_skills(root))
  before <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Account B", 1L, skill_id = "account-B"))))
  for (overwrite in c(FALSE, TRUE)) {
    out <- capture.output(result <- pull_skills(root, overwrite = overwrite), type = "message")
    expect_identical(skill_pull_rows(result)[[1]]$status, "kept", info = as.character(overwrite))
    expect_true(any(grepl(".claude/skills/lab-style belongs to a different skill (framework:lab-style), so pull left it alone.",
                          out, fixed = TRUE)), info = as.character(overwrite))
    expect_true("Version 5" %in% read_skill(root, "lab-style"))
    expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style"), before)
  }
})

test_that("another variant of the same skill ID is a different identity, kept with the reason", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 1", 1L))))
  suppressMessages(pull_skills(root))
  before <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  stata <- skill_pull_entry("Stata version", 2L); stata$sync$variant <- "stata"
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = stata)))
  for (overwrite in c(FALSE, TRUE)) {
    out <- capture.output(result <- pull_skills(root, overwrite = overwrite), type = "message")
    row <- skill_pull_rows(result)[[1]]
    expect_identical(row$status, "kept", info = as.character(overwrite))
    expect_identical(row$reason_code, "other_variant")
    expect_identical(row$hint, "skills_move(\".claude/skills/lab-style\", skill_id = \"lab-id\", variant = \"stata\")")
    expect_true(any(grepl("belongs to a different skill (lab-id, r variant on https://cloud.example), so pull left it alone.",
                          out, fixed = TRUE)), info = as.character(overwrite))
    expect_true("Version 1" %in% read_skill(root, "lab-style"))
    expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style"), before)
  }
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style")$identity$variant, "r")
})

test_that("skills_copy() refuses a target another skill tracks, in dry runs too", {
  root <- skill_pull_two_skills()
  lock <- readBin(file.path(root, ".framework/skills.lock.json"), "raw", n = 1e6)
  for (dry in c(TRUE, FALSE)) {
    expect_error(suppressMessages(skills_copy(from = "claude", to = "agents", skills = "lab-style", dry_run = dry, project_path = root)),
                 "Target .agents/skills/lab-style belongs to another skill", info = as.character(dry))
  }
  expect_true("Theirs" %in% read_skill(root, "lab-style", ".agents/skills"))
  expect_identical(readBin(file.path(root, ".framework/skills.lock.json"), "raw", n = 1e6), lock)
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
})

test_that("skills_sync() never lands on an entry whose key only matches the path", {
  root <- withr::local_tempdir()
  folder <- file.path(root, ".claude/skills/x")
  dir.create(folder, recursive = TRUE)
  writeLines(c("---", "name: x", "description: x", "---", "Mine"), file.path(folder, "SKILL.md"))
  # A schema 1 entry keyed by the path, which now tracks another folder
  dir.create(file.path(root, ".framework"))
  writeLines(jsonlite::toJSON(list(schema = 1L, skills = list(`.claude/skills/x` = list(
    paths = list("custom/skills/x"), variant = "r", server = "https://cloud.example", skill_id = "unrelated", version = 3L,
    hash = "h"))), auto_unbox = TRUE), file.path(root, ".framework/skills.lock.json"))
  posts <- list()
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_require_token = function(...) "token",
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "POST")) {
        posts[[length(posts) + 1L]] <<- body
        return(list(skill_id = "new-id", version = 1L, bundle = body$bundle, hash = .skill_hash(body$bundle)))
      }
      stop("no lookup expected: ", path)
    })
  result <- skills_sync(".claude/skills/x", root)
  expect_identical(result$action, "push")
  expect_null(posts[[1]]$skill_id)
  state <- .skill_load(root)
  expect_identical(names(state$skills[["https://cloud.example/unrelated@r"]]$copies), "custom/skills/x")
  expect_identical(names(state$skills[["https://cloud.example/new-id@r"]]$copies), ".claude/skills/x")
})

test_that("inline setup content never replaces a built-in tracked on Cloud", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  files <- .skill_scan(system.file("templates", "skills", "framework-data", package = "framework"))
  synced <- list(content = "x", bundle = files,
                 sync = list(skill_id = "framework:framework-data", version = 2L, hash = .skill_hash(files),
                             variant = "r", server = "https://cloud.example"))
  skill_pull_mock(skill_pull_envelope(list(`framework-data` = synced)))
  suppressMessages(pull_skills(root))
  lock <- skill_pull_lock_entry(root, ".claude/skills/framework-data")
  before <- read_skill(root, "framework-data")

  skill_pull_mock(skill_pull_envelope(list(`framework-data` = list(content = "---\nname: framework-data\ndescription: x\n---\nInline\n"))))
  result <- suppressMessages(pull_skills(root, overwrite = TRUE))
  expect_identical(Filter(function(s) identical(s$name, "framework-data"), result$skills)[[1]]$status, "kept")
  expect_identical(read_skill(root, "framework-data"), before)
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/framework-data"), lock)
})

test_that("an offline pull reports a custom Cloud skill as unavailable and leaves it alone", {
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
  root <- skill_pull_project()
  skill_pull_mock(skill_pull_envelope(list(`lab-style` = skill_pull_entry("Version 2", 2L, skill_id = "lab-style"))))
  suppressMessages(pull_skills(root))
  before <- skill_pull_lock_entry(root, ".claude/skills/lab-style")
  expect_identical(before$skill_id, "lab-style")

  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  local_mocked_bindings(.fw_project_token = function(...) NULL)
  out <- capture.output(result <- pull_skills(root), type = "message")
  skill <- Filter(function(s) identical(s$name, "lab-style"), result$skills)
  expect_length(skill, 1L)
  expect_identical(skill[[1]]$status, "unavailable")
  expect_true(any(grepl("Unavailable: lab-style — Framework Cloud wasn't reached, so lab-style was left as it is.", out, fixed = TRUE)))
  expect_true("Version 2" %in% read_skill(root, "lab-style"))
  expect_identical(skill_pull_lock_entry(root, ".claude/skills/lab-style"), before)
})
