# skills_copy(): copy skills between assistant skills folders

skill_copy_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude, codex]"),
             file.path(root, "settings.yml"))
  root
}

skill_copy_write <- function(root, dir, name, text = "First", extra = TRUE) {
  folder <- file.path(root, dir, name)
  dir.create(file.path(folder, "scripts"), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(paste0("---\nname: ", name, "\ndescription: Example\n---\n", text, "\n")),
           file.path(folder, "SKILL.md"))
  if (extra) {
    writeBin(charToRaw("#!/bin/sh\necho hi\n"), file.path(folder, "scripts", "run.sh"))
    Sys.chmod(file.path(folder, "scripts", "run.sh"), "0755")
  }
  folder
}

skill_copy_hash <- function(root, path) .skill_hash(.skill_scan(file.path(root, path)))

skill_copy_quiet <- function(...) suppressMessages(skills_copy(...))

skill_copy_text <- function(root, path) paste(readLines(file.path(root, path, "SKILL.md")), collapse = "\n")

test_that("folder names map to skills folders, with codex and copilot as aliases for agents", {
  names <- .skill_copy_names()
  expect_identical(unname(names[["claude"]]), ".claude/skills")
  for (alias in c("agents", "codex", "copilot")) expect_identical(unname(names[[alias]]), ".agents/skills")
  expect_identical(.skill_copy_name("copilot", "to"), ".agents/skills")
  expect_error(.skill_copy_name("cursor", "from"), "`from` must be one of")
})

test_that("skills_copy() rejects mixed, doubled, and empty arguments", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "example")
  expect_error(skills_copy(project_path = root), "Pass `from`")
  expect_error(skills_copy("claude", from_dir = ".claude/skills", project_path = root), "`from` or `from_dir`, not both")
  expect_error(skills_copy("claude", "agents", to_dir = "x", project_path = root), "`to` or `to_dir`, not both")
  expect_error(skills_copy("claude", to_dir = "other/skills", project_path = root), "not both kinds")
  expect_error(skills_copy(from_dir = ".claude/skills", to = "agents", project_path = root), "not both kinds")
  expect_error(skills_copy("claude", "agents", skills = character(), project_path = root), "`skills` is empty")
  expect_error(skills_copy("claude", "agents", skills = c("nope", "example", "also-nope"), project_path = root),
               "Not in .claude/skills: nope, also-nope", fixed = TRUE)
  expect_error(skills_copy("claude", project_path = root), "No other assistant skills folder")
  expect_false(dir.exists(file.path(root, ".agents")))
})

test_that("skills_copy() rejects absolute, drive, and parent paths as supplied", {
  root <- skill_copy_project()
  skill_copy_write(root, "src", "a")
  for (bad in c("/abs/skills", "\\\\server\\skills", "D:skills", "D:/skills", "~/skills")) {
    expect_error(skills_copy(from_dir = "src", to_dir = bad, project_path = root), "project-relative", info = bad)
  }
  for (bad in c("../outside", "a/../b", "a\\..\\b", "src/..")) {
    expect_error(skills_copy(from_dir = "src", to_dir = bad, project_path = root), "cannot contain", info = bad)
  }
  expect_error(skills_copy(from_dir = "src", to_dir = "./.", project_path = root), "must name a folder")
})

test_that("skills_copy() checks the source before the targets", {
  root <- skill_copy_project()
  expect_error(skills_copy(from_dir = "nope", to_dir = ".framework/skills-backups", project_path = root),
               "Source skills folder not found: nope")
  expect_error(skills_copy("agents", "claude", project_path = root), "Source skills folder not found: .agents/skills")
})

test_that("skills_copy() rejects the same, nested, and case-alias folders", {
  root <- skill_copy_project()
  skill_copy_write(root, "src", "a")
  expect_error(skills_copy(from_dir = "src/", to_dir = "./src", project_path = root), "same folder")
  expect_error(skills_copy(from_dir = "src", to_dir = "src/a/nested", project_path = root), "overlap")
  expect_error(skills_copy(from_dir = "src/a", to_dir = "src", project_path = root), "overlap")
  expect_false(dir.exists(file.path(root, "src/a/nested")))
  if (.skill_case_insensitive_at(root)) {
    expect_error(skills_copy(from_dir = "src", to_dir = "SRC", project_path = root), "same folder")
    expect_error(skills_copy(from_dir = "src", to_dir = "SRC/A/nested", project_path = root), "overlap")
  }
  skill_copy_write(root, ".claude/skills", "x")
  expect_error(skills_copy("claude", "claude", project_path = root), "same folder")
})

test_that("skills_copy() refuses targets in or over .framework", {
  root <- skill_copy_project()
  skill_copy_write(root, "src", "a")
  for (bad in c(".framework/skills-backups", ".framework/skills-backups/x", ".framework", ".framework/other",
                ".framework/skills.lock.json", ".framework/skills.sync.lock/inner", "./.framework/")) {
    expect_error(skill_copy_quiet(from_dir = "src", to_dir = bad, project_path = root), "Framework's .framework folder", info = bad)
    expect_error(skill_copy_quiet(from_dir = "src", to_dir = bad, dry_run = TRUE, project_path = root), ".framework folder", info = bad)
  }
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
})

test_that("skills_copy() copies SKILL.md, companion files, and executable modes to the other folders", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "example")
  skill_copy_write(root, ".claude/skills", "second", extra = FALSE)
  dir.create(file.path(root, ".claude/skills/not-a-skill"))
  writeLines("notes", file.path(root, ".claude/skills/README.md"))
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)

  out <- capture.output(result <- skills_copy(from = "claude", project_path = root), type = "message")
  expect_identical(result$message, "Skills from .claude/skills: 2 copied")
  expect_true("  Copied: .claude/skills/example -> .agents/skills/example" %in% out)
  expect_false(any(grepl("Backup:", out)))
  expect_identical(result$from, ".claude/skills")
  expect_identical(result$to, ".agents/skills")
  expect_identical(result$skills[[1]],
                   list(name = "example", status = "copied", from = ".claude/skills/example",
                        to = ".agents/skills/example", backup = NULL))
  expect_identical(skill_copy_hash(root, ".agents/skills/example"), skill_copy_hash(root, ".claude/skills/example"))
  expect_false(dir.exists(file.path(root, ".agents/skills/not-a-skill")))
  if (.Platform$OS.type != "windows") {
    expect_true(file.access(file.path(root, ".agents/skills/example/scripts/run.sh"), 1) == 0)
  }
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
  expect_false(dir.exists(file.path(root, ".framework/skills.sync.lock")))

  out <- capture.output(result <- skills_copy(from = "claude", project_path = root), type = "message")
  expect_identical(result$message, "Skills from .claude/skills: 2 up to date")
  expect_identical(out, "Skills from .claude/skills: 2 up to date")
})

test_that("skills_copy() copies to the other assistant folders in path order", {
  root <- skill_copy_project()
  local_mocked_bindings(.ai_assistant_table = function() list(
    claude = list(skills_dir = ".claude/skills"), zed = list(skills_dir = ".zed/skills"),
    codex = list(skills_dir = ".agents/skills")))
  skill_copy_write(root, ".claude/skills", "example")
  for (d in c(".zed/skills", ".agents/skills")) dir.create(file.path(root, d), recursive = TRUE)
  result <- skill_copy_quiet(from = "claude", project_path = root)
  expect_identical(result$to, c(".agents/skills", ".zed/skills"))
  expect_identical(vapply(result$skills, `[[`, "", "to"), c(".agents/skills/example", ".zed/skills/example"))
})

test_that("skills_copy() backs up replaced copies, skips identical ones, and deletes nothing", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "example", "Kept version")
  skill_copy_write(root, ".claude/skills", "same")
  skill_copy_write(root, ".agents/skills", "example", "Old version")
  skill_copy_write(root, ".agents/skills", "same")
  skill_copy_write(root, ".agents/skills", "agents-only")
  writeLines("stale", file.path(root, ".agents/skills/example/notes.md"))
  writeLines("SECRET=1", file.path(root, ".agents/skills/example/.env"))

  out <- capture.output(result <- skills_copy(from = "claude", to = "codex", project_path = root), type = "message")
  expect_identical(result$message, "Skills from .claude/skills: 1 copied, 1 up to date, 1 not in .claude/skills (kept)")
  expect_true("  Not in .claude/skills (kept): .agents/skills/agents-only" %in% out)
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses, c(example = "copied", same = "current", `agents-only` = "missing"))
  expect_null(result$skills[[3]]$from)

  backup <- result$skills[[1]]$backup
  expect_match(backup, "^\\.framework/skills-backups/[0-9a-f-]+$")
  expect_true(paste0("    Backup: ", backup) %in% out)
  expect_match(skill_copy_text(root, backup), "Old version")
  expect_true(file.exists(file.path(root, backup, "notes.md")))
  expect_length(list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE), 1L)

  expect_match(skill_copy_text(root, ".agents/skills/example"), "Kept version")
  # Other target-only files leave the active copy; excluded files stay
  expect_false(file.exists(file.path(root, ".agents/skills/example/notes.md")))
  expect_true(file.exists(file.path(root, ".agents/skills/example/.env")))
  expect_true(file.exists(file.path(root, ".agents/skills/agents-only/SKILL.md")))
  # Backups stay out of Git
  expect_true("skills-backups/" %in% readLines(file.path(root, ".framework/.gitignore")))
  expect_length(list.files(file.path(root, ".agents/skills"), pattern = "^\\.skill-", all.files = TRUE), 0L)
})

test_that("skills_copy() copies only the named skills, once each, between any project folders", {
  root <- skill_copy_project()
  skill_copy_write(root, "custom/skills", "one")
  skill_copy_write(root, "custom/skills", "two")
  out <- capture.output(
    result <- skills_copy(from_dir = "custom/skills", to_dir = "other/skills", skills = c("two", "two"),
                          dry_run = TRUE, project_path = root),
    type = "message")
  expect_identical(result$message, "Skills (dry run, nothing written) from custom/skills: 1 to copy")
  result <- skill_copy_quiet(from_dir = "custom/skills", to_dir = "other/skills", skills = c("two", "one", "two"),
                             project_path = root)
  expect_identical(vapply(result$skills, `[[`, "", "name"), c("two", "one"))
  expect_identical(result$message, "Skills from custom/skills: 2 copied")
})

test_that("skills_copy() dry runs take no lock and write nothing", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "example", "New")
  skill_copy_write(root, ".agents/skills", "example", "Old")
  skill_copy_write(root, ".claude/skills", "added")
  before <- skill_copy_hash(root, ".agents/skills/example")
  out <- capture.output(result <- skills_copy("claude", dry_run = TRUE, project_path = root), type = "message")
  expect_identical(out, c("Skills (dry run, nothing written) from .claude/skills: 2 to copy",
                          "  Would copy: .claude/skills/added -> .agents/skills/added",
                          "  Would copy: .claude/skills/example -> .agents/skills/example"))
  expect_true(result$dry_run)
  expect_null(result$skills[[2]]$backup)
  expect_identical(skill_copy_hash(root, ".agents/skills/example"), before)
  expect_false(dir.exists(file.path(root, ".agents/skills/added")))
  expect_false(dir.exists(file.path(root, ".framework")))
})

test_that("skills_copy() stops on an unreadable source folder and leaves the target intact", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "example", "New")
  skill_copy_write(root, ".agents/skills", "example", "Old")
  locked <- file.path(root, ".claude/skills/example/scripts")
  Sys.chmod(locked, "0000")
  withr::defer(Sys.chmod(locked, "0755"))
  skip_if(file.access(locked, 4) == 0, "running with permission to read any folder")
  expect_error(skill_copy_quiet("claude", project_path = root), "Could not read")
  expect_match(skill_copy_text(root, ".agents/skills/example"), "Old")
  expect_true(file.exists(file.path(root, ".agents/skills/example/scripts/run.sh")))
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
})

test_that("skills_copy() refuses symlinked skill folders and companion files", {
  skip_on_os("windows")
  root <- skill_copy_project()
  elsewhere <- skill_copy_write(root, "elsewhere", "linked")
  dir.create(file.path(root, ".claude/skills"), recursive = TRUE)
  file.symlink(elsewhere, file.path(root, ".claude/skills/linked"))
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  expect_error(skill_copy_quiet("claude", project_path = root), "symlinks are unsupported")

  unlink(file.path(root, ".claude/skills/linked"))
  folder <- skill_copy_write(root, ".claude/skills", "example")
  file.symlink(file.path(elsewhere, "SKILL.md"), file.path(folder, "scripts/linked.md"))
  expect_error(skill_copy_quiet("claude", project_path = root), "symlinks are unsupported")
  expect_false(dir.exists(file.path(root, ".agents/skills/example")))
})

test_that("skills_copy() undoes earlier copies when a later one fails", {
  root <- skill_copy_project()
  for (name in c("a", "b")) {
    skill_copy_write(root, ".claude/skills", name, "New")
    skill_copy_write(root, ".agents/skills", name, "Old")
  }
  skill_copy_write(root, ".claude/skills", "c", "New")
  real <- .skill_install
  calls <- 0L
  local_mocked_bindings(.skill_install = function(...) {
    calls <<- calls + 1L
    if (calls == 3L) stop("Disk full", call. = FALSE)
    real(...)
  })
  expect_error(skill_copy_quiet("claude", project_path = root),
               "Skill copy failed while copying .claude/skills/c -> .agents/skills/c: Disk full. No skills were changed.", fixed = TRUE)
  for (name in c("a", "b")) expect_match(skill_copy_text(root, file.path(".agents/skills", name)), "Old")
  expect_false(dir.exists(file.path(root, ".agents/skills/c")))
  expect_length(list.files(file.path(root, ".agents/skills"), pattern = "^\\.skill-", all.files = TRUE), 0L)
  expect_false(dir.exists(file.path(root, ".framework/skills.sync.lock")))
})

test_that("skills_copy() names each copy it could not undo and its backup", {
  root <- skill_copy_project()
  for (name in c("a", "b")) {
    skill_copy_write(root, ".claude/skills", name, "New")
    skill_copy_write(root, ".agents/skills", name, "Old")
  }
  real <- .skill_install
  calls <- 0L
  local_mocked_bindings(
    .skill_install = function(...) {
      calls <<- calls + 1L
      if (calls == 2L) stop("Disk full", call. = FALSE)
      real(...)
    },
    .skill_rollback = function(swaps) swaps
  )
  error <- tryCatch(skill_copy_quiet("claude", project_path = root), error = function(e) conditionMessage(e))
  backup <- list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE, full.names = FALSE)
  expect_length(backup, 1L)
  expect_identical(error, paste0(
    "Skill copy failed while copying .claude/skills/b -> .agents/skills/b: Disk full. ",
    "These copies were replaced and could not be restored:\n",
    "  .agents/skills/a (old copy in .framework/skills-backups/", backup, ")"))
})

test_that("a failed install removes its staging folder", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  skill_copy_write(root, ".agents/skills", "a", "Old")
  local_mocked_bindings(.skill_private = function(...) stop("No space", call. = FALSE))
  expect_error(skill_copy_quiet("claude", project_path = root), "No skills were changed")
  expect_length(list.files(file.path(root, ".agents/skills"), pattern = "^\\.skill-", all.files = TRUE), 0L)
  expect_match(skill_copy_text(root, ".agents/skills/a"), "Old")
})

test_that("the Windows executable list is always an array and reads a legacy string", {
  local_mocked_bindings(.skill_on_windows = function() TRUE)
  root <- withr::local_tempdir()
  files <- list(
    list(path = "SKILL.md", content = jsonlite::base64_enc(charToRaw("---\nname: x\ndescription: x\n---\n")), executable = FALSE),
    list(path = "scripts/run.sh", content = jsonlite::base64_enc(charToRaw("echo hi\n")), executable = TRUE))
  .skill_install(root, ".agents/skills/x", files, NULL)
  meta <- file.path(root, ".agents/skills/x/.framework-skill.json")
  expect_identical(readLines(meta), "{\"executable_paths\":[\"scripts/run.sh\"]}")
  scanned <- .skill_scan(file.path(root, ".agents/skills/x"))
  expect_identical(vapply(scanned, function(f) isTRUE(f$executable), logical(1)), c(FALSE, TRUE))
  expect_identical(.skill_hash(scanned), .skill_hash(files))

  writeLines("{\"executable_paths\":\"scripts/run.sh\"}", meta)
  expect_identical(.skill_hash(.skill_scan(file.path(root, ".agents/skills/x"))), .skill_hash(files))
})

test_that("the divergence error names both copies and the skills_copy() call for that skill", {
  expect_identical(
    .skill_diverged_message(".claude/skills/x", ".agents/skills/x"),
    paste0(".claude/skills/x and .agents/skills/x differ. Pick one and copy it over the other: ",
           "skills_copy(from = \"claude\", to = \"agents\", skills = \"x\") (to keep .agents/skills/x, swap from and to)"))
  expect_identical(
    .skill_diverged_message("custom/skills/x", ".agents/skills/x"),
    paste0("custom/skills/x and .agents/skills/x differ. Pick one and copy it over the other: ",
           "skills_copy(from_dir = \"custom/skills\", to_dir = \".agents/skills\", skills = \"x\") ",
           "(to keep .agents/skills/x, swap from and to)"))
})

test_that("skills_copy() reconciles diverged copies so skills_sync() and push_skills() can run", {
  root <- skill_copy_project()
  source <- withr::local_tempdir()
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source, "SKILL.md"))
  expect_true(.skill_package_install(source, root, ".claude/skills/example", "example"))
  expect_true(.skill_package_install(source, root, ".agents/skills/example", "example"))
  files <- .skill_scan(source)
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_project_token = function(...) NULL,
    .fw_require_token = function(...) "token",
    .fw_api = function(path, token, method = "GET", ...) {
      expect_identical(method, "GET")
      list(skill_id = "framework:example", version = 1L, bundle = files, hash = .skill_hash(files), system = TRUE)
    }
  )
  expect_identical(skills_sync(".claude/skills/example", root, direction = "status")$action, "adopt")

  cat("Edited in Claude Code\n", file = file.path(root, ".claude/skills/example/SKILL.md"), append = TRUE)
  expect_error(skills_sync(".claude/skills/example", root, direction = "status"),
               "skills_copy(from = \"claude\", to = \"agents\", skills = \"example\")", fixed = TRUE)

  lock <- file.path(root, ".framework/skills.lock.json")
  lock_before <- readBin(lock, "raw", n = file.info(lock)$size)
  result <- skill_copy_quiet(from = "claude", project_path = root)
  expect_identical(result$message, "Skills from .claude/skills: 1 copied")
  expect_identical(readBin(lock, "raw", n = file.info(lock)$size), lock_before)
  expect_identical(skill_copy_hash(root, ".agents/skills/example"), skill_copy_hash(root, ".claude/skills/example"))
  # The copies still differ from the lock's hash, so the skill pushes as edited
  expect_identical(skills_sync(".claude/skills/example", root, direction = "status")$action, "push")
})

# Round 3 regressions

test_that("empty and colon folders are errors", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a")
  expect_error(skills_copy(from_dir = "", to_dir = "x", project_path = root), "at least 1 char")
  expect_error(skills_copy(from_dir = ".claude/skills", to_dir = "", project_path = root), "at least 1 char")
  expect_error(skills_copy(from = "", project_path = root), "`from` must be one of")
  for (bad in c("folder/D:skills", "ab:c", "x/y:z/w")) {
    expect_error(skills_copy(from_dir = ".claude/skills", to_dir = bad, project_path = root), "cannot contain \":\"", info = bad)
  }
  expect_error(.skill_path(root, "folder/D:skills"), "cannot contain")
})

test_that("a real run takes the sync lock before it looks at any folder", {
  root <- skill_copy_project()
  local_mocked_bindings(.skill_acquire = function(...) stop("Skill sync is locked", call. = FALSE))
  expect_error(skills_copy(from_dir = "nope", to_dir = "x", project_path = root), "Skill sync is locked")
  expect_error(skills_copy("claude", project_path = root), "Skill sync is locked")
  expect_error(skills_copy(from_dir = "nope", to_dir = "x", dry_run = TRUE, project_path = root), "not found: nope")
})

test_that("a target that is not a folder fails, in a dry run too", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a")
  writeLines("x", file.path(root, "plain"))
  dir.create(file.path(root, ".agents"))
  writeLines("x", file.path(root, ".agents/skills"))
  for (dry in c(TRUE, FALSE)) {
    expect_error(skill_copy_quiet(from_dir = ".claude/skills", to_dir = "plain", dry_run = dry, project_path = root),
                 "Target is not a folder: plain")
    expect_error(skill_copy_quiet(from_dir = ".claude/skills", to_dir = "plain/skills", dry_run = dry, project_path = root),
                 "Target is not a folder: plain")
    expect_error(skill_copy_quiet("claude", "agents", dry_run = dry, project_path = root),
                 "Target is not a folder: .agents/skills")
  }
  dir.create(file.path(root, "other"))
  writeLines("x", file.path(root, "other/a"))
  expect_error(skill_copy_quiet(from_dir = ".claude/skills", to_dir = "other", dry_run = TRUE, project_path = root),
               "Target is not a folder: other/a")
  expect_identical(readLines(file.path(root, "plain")), "x")
})

test_that("folders that can't be looked up are errors, never missing", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, "src", "a")
  Sys.chmod(file.path(root, "src"), "0444")
  withr::defer(Sys.chmod(file.path(root, "src"), "0755"))
  skip_if(file.access(file.path(root, "src"), 1) == 0, "running with permission to read any folder")
  expect_error(skill_copy_quiet(from_dir = "src", to_dir = "out", dry_run = TRUE, project_path = root), "Could not read")
  expect_false(dir.exists(file.path(root, "out")))
  Sys.chmod(file.path(root, "src"), "0755")

  # Default target discovery
  skill_copy_write(root, ".claude/skills", "a")
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  Sys.chmod(file.path(root, ".agents"), "0444")
  withr::defer(Sys.chmod(file.path(root, ".agents"), "0755"))
  expect_error(skill_copy_quiet("claude", dry_run = TRUE, project_path = root), "Could not read")
})

test_that("broken symlinks in a skills folder are errors", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a")
  file.symlink(file.path(root, "nowhere"), file.path(root, ".claude/skills/broken"))
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  expect_error(skill_copy_quiet("claude", dry_run = TRUE, project_path = root), "symlinks are unsupported: .claude/skills/broken")
})

test_that("a file name with a backslash is an error, not a separator", {
  skip_on_os("windows")
  root <- skill_copy_project()
  folder <- skill_copy_write(root, ".claude/skills", "a")
  writeLines("odd", file.path(folder, "d\\f"))
  expect_error(.skill_scan(folder), "cannot contain a backslash")
  skill_copy_write(root, ".agents/skills", "a", "Old")
  expect_error(skill_copy_quiet("claude", project_path = root), "cannot contain a backslash")
  expect_match(skill_copy_text(root, ".agents/skills/a"), "Old")
  expect_false(file.exists(file.path(root, ".agents/skills/a/f")))
})

test_that("a skill whose target folder differs in case gets one row", {
  root <- skill_copy_project()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  skill_copy_write(root, ".claude/skills", "foo", "New")
  skill_copy_write(root, ".agents/skills", "Foo", "Old")
  skill_copy_write(root, ".agents/skills", "only-here")
  result <- skill_copy_quiet("claude", dry_run = TRUE, project_path = root)
  expect_identical(vapply(result$skills, `[[`, "", "status"), c("copied", "missing"))
  expect_identical(result$skills[[2]]$to, ".agents/skills/only-here")
  expect_null(result$skills[[2]]$from)
  result <- skill_copy_quiet("claude", project_path = root)
  expect_identical(result$message, "Skills from .claude/skills: 1 copied, 1 not in .claude/skills (kept)")
  expect_match(skill_copy_text(root, ".agents/skills/foo"), "New")
})

test_that("a replaced copy keeps its folder permissions", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  target <- skill_copy_write(root, ".agents/skills", "a", "Old")
  Sys.chmod(c(target, file.path(target, "scripts")), "0700", use_umask = FALSE)
  skill_copy_quiet("claude", project_path = root)
  expect_identical(format(file.info(target)$mode), "700")
  expect_identical(format(file.info(file.path(target, "scripts"))$mode), "700")
  expect_match(skill_copy_text(root, ".agents/skills/a"), "New")
})

skill_copy_interrupt <- function() {
  signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
}

test_that("an interrupted batch undoes the copies already made", {
  root <- skill_copy_project()
  for (name in c("a", "b")) {
    skill_copy_write(root, ".claude/skills", name, "New")
    skill_copy_write(root, ".agents/skills", name, "Old")
  }
  real <- .skill_install
  calls <- 0L
  local_mocked_bindings(.skill_install = function(...) {
    calls <<- calls + 1L
    if (calls == 2L) skill_copy_interrupt()
    real(...)
  })
  expect_error(skill_copy_quiet("claude", project_path = root),
               "Skill copy failed while copying .claude/skills/b -> .agents/skills/b: interrupted. No skills were changed.", fixed = TRUE)
  for (name in c("a", "b")) expect_match(skill_copy_text(root, file.path(".agents/skills", name)), "Old")
  expect_false(dir.exists(file.path(root, ".framework/skills.sync.lock")))
})

test_that("an interrupted install removes its staging folder", {
  root <- withr::local_tempdir()
  skill_copy_write(root, ".agents/skills", "a", "Old")
  files <- .skill_scan(skill_copy_write(root, "src", "a", "New"))
  local_mocked_bindings(.skill_private = function(...) skill_copy_interrupt())
  expect_error(.skill_install(root, ".agents/skills/a", files, skill_copy_hash(root, ".agents/skills/a")), "interrupted")
  expect_length(list.files(file.path(root, ".agents/skills"), pattern = "^\\.skill-", all.files = TRUE), 0L)
  expect_match(skill_copy_text(root, ".agents/skills/a"), "Old")
})

test_that("an install that can't restore a copy names it and its backup", {
  skip_on_os("windows")
  root <- withr::local_tempdir()
  for (d in c(".claude/skills", ".agents/skills")) skill_copy_write(root, d, "a", "Old")
  expected <- skill_copy_hash(root, ".claude/skills/a")
  files <- .skill_scan(skill_copy_write(root, "src", "a", "New"))
  backups <- file.path(root, ".framework/skills-backups")
  second <- .skill_path(root, ".agents/skills/a")
  real <- .skill_scan
  local_mocked_bindings(.skill_scan = function(path) {
    # After the first copy is swapped in, make the second fail and the restore fail
    if (identical(path, second) && length(list.dirs(backups, recursive = FALSE))) {
      Sys.chmod(backups, "0555")
      stop("Disk full", call. = FALSE)
    }
    real(path)
  })
  withr::defer(Sys.chmod(backups, "0755"))
  error <- tryCatch(.skill_install(root, c(".claude/skills/a", ".agents/skills/a"), files, expected), error = identity)
  expect_s3_class(error, "fw_skill_install_error")
  skip_if(length(error$lost) == 0, "running with permission to write any folder")
  backup <- list.dirs(backups, recursive = FALSE, full.names = FALSE)
  expect_identical(conditionMessage(error), paste0(
    "Could not install skill (Disk full), and these copies could not be restored:\n",
    "  .claude/skills/a (old copy in .framework/skills-backups/", backup, ")"))
  expect_match(skill_copy_text(root, file.path(".framework/skills-backups", backup)), "Old")
})

test_that("a batch error names the copy being installed when its restore failed", {
  root <- skill_copy_project()
  for (name in c("a", "b")) {
    skill_copy_write(root, ".claude/skills", name, "New")
    skill_copy_write(root, ".agents/skills", name, "Old")
  }
  real <- .skill_install
  calls <- 0L
  local_mocked_bindings(.skill_install = function(root, paths, ...) {
    calls <<- calls + 1L
    if (calls == 2L) {
      lost <- new.env(); lost$path <- paths; lost$backup <- ".framework/skills-backups/kept-b"
      stop(errorCondition("x", class = "fw_skill_install_error", reason = "Disk full", lost = list(lost), call = NULL))
    }
    real(root, paths, ...)
  })
  error <- tryCatch(skill_copy_quiet("claude", project_path = root), error = conditionMessage)
  expect_identical(error, paste0(
    "Skill copy failed while copying .claude/skills/b -> .agents/skills/b: Disk full. ",
    "These copies were replaced and could not be restored:\n",
    "  .agents/skills/b (old copy in .framework/skills-backups/kept-b)"))
  # The earlier copy was undone
  expect_match(skill_copy_text(root, ".agents/skills/a"), "Old")
})

test_that("the divergence hint copies from the only existing copy and names the missing side", {
  expect_identical(
    .skill_diverged_message(".agents/skills/x", ".claude/skills/x", missing = TRUE),
    paste0(".claude/skills/x is missing. Copy .agents/skills/x over it: ",
           "skills_copy(from = \"agents\", to = \"claude\", skills = \"x\")"))
  expect_identical(
    .skill_diverged_message(".agents/skills/x", "custom/skills/x", missing = TRUE),
    paste0("custom/skills/x is missing. Copy .agents/skills/x over it: ",
           "skills_copy(from_dir = \".agents/skills\", to_dir = \"custom/skills\", skills = \"x\")"))
})

skill_copy_cloud <- function(root, env = parent.frame()) {
  source <- withr::local_tempdir(.local_envir = env)
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source, "SKILL.md"))
  expect_true(.skill_package_install(source, root, ".claude/skills/example", "example"))
  expect_true(.skill_package_install(source, root, ".agents/skills/example", "example"))
  files <- .skill_scan(source)
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_project_token = function(...) NULL,
    .fw_require_token = function(...) "token",
    .fw_interactive = function() FALSE,
    .fw_api = function(path, token, method = "GET", ...) {
      expect_identical(method, "GET")
      list(skill_id = "framework:example", version = 1L, bundle = files, hash = .skill_hash(files), system = TRUE)
    },
    .env = env
  )
}

test_that("skills_sync() points a missing copy's repair at the copy that exists", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  cat("Edited\n", file = file.path(root, ".agents/skills/example/SKILL.md"), append = TRUE)
  unlink(file.path(root, ".claude/skills/example"), recursive = TRUE)
  expect_error(skills_sync(".claude/skills/example", root, direction = "status"),
               "skills_copy(from = \"agents\", to = \"claude\", skills = \"example\")", fixed = TRUE)
  skill_copy_quiet(from = "agents", to = "claude", skills = "example", project_path = root)
  expect_identical(skills_sync(".claude/skills/example", root, direction = "status")$action, "push")
})

test_that("push_skills() checks every tracked copy and reports a diverged one as failed", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  # Only the second copy changes
  cat("Edited in Codex\n", file = file.path(root, ".agents/skills/example/SKILL.md"), append = TRUE)
  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 failed")
  expect_true(any(grepl("Failed: example \u2014 .claude/skills/example and .agents/skills/example differ. Pick one",
                        out, fixed = TRUE)))
  failed <- Filter(function(s) identical(s$status, "failed"), result$skills)[[1]]
  expect_identical(failed$hint, "skills_copy(from = \"claude\", to = \"agents\", skills = \"example\")")
})

# Round 4 regressions

test_that("an interrupt just after the backup rename still restores the copy", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  skill_copy_write(root, ".agents/skills", "a", "Old")
  real <- .skill_rename
  local_mocked_bindings(.skill_rename = function(from, to) {
    ok <- real(from, to)
    # The rename happened, but its flag was never set
    if (grepl("skills-backups", to, fixed = TRUE)) skill_copy_interrupt()
    ok
  })
  expect_error(skill_copy_quiet("claude", project_path = root), "interrupted. No skills were changed.", fixed = TRUE)
  expect_match(skill_copy_text(root, ".agents/skills/a"), "Old")
  expect_length(list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE), 0L)
})

test_that("an interrupt just after the install rename removes the new copy", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  real <- .skill_rename
  local_mocked_bindings(.skill_rename = function(from, to) {
    ok <- real(from, to)
    if (grepl(".skill-stage-", from, fixed = TRUE)) skill_copy_interrupt()
    ok
  })
  expect_error(skill_copy_quiet("claude", project_path = root), "interrupted. No skills were changed.", fixed = TRUE)
  expect_false(dir.exists(file.path(root, ".agents/skills/a")))
})

test_that("dot names are skipped before any other check", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a")
  dir.create(file.path(root, ".claude/skills/.ignore\\me"))
  writeLines("x", file.path(root, ".claude/skills/.odd\\name"))
  result <- skill_copy_quiet(from_dir = ".claude/skills", to_dir = "out", project_path = root)
  expect_identical(result$message, "Skills from .claude/skills: 1 copied")
  # Excluded companion names are skipped too
  folder <- skill_copy_write(root, "src", "b")
  dir.create(file.path(folder, "node_modules"))
  writeLines("x", file.path(folder, "node_modules", "odd\\name"))
  writeLines("x", file.path(folder, ".env.odd\\x"))
  expect_identical(skill_copy_quiet(from_dir = "src", to_dir = "out2", project_path = root)$message,
                   "Skills from src: 1 copied")
})

test_that("a folder that becomes a file does not keep the folder's mode", {
  skip_on_os("windows")
  root <- skill_copy_project()
  source <- skill_copy_write(root, ".claude/skills", "x", "New", extra = FALSE)
  writeLines("tool", file.path(source, "tool"))
  target <- skill_copy_write(root, ".agents/skills", "x", "Old", extra = FALSE)
  dir.create(file.path(target, "tool"))
  writeLines("inner", file.path(target, "tool", "inner.sh"))
  Sys.chmod(file.path(target, "tool"), "0700", use_umask = FALSE)
  skill_copy_quiet("claude", project_path = root)
  expect_identical(.skill_kind(file.path(target, "tool")), "file")
  expect_identical(format(file.info(file.path(target, "tool"))$mode), "644")
  expect_identical(skill_copy_hash(root, ".agents/skills/x"), skill_copy_hash(root, ".claude/skills/x"))
})

test_that("folder modes keep the sticky bit", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  target <- skill_copy_write(root, ".agents/skills", "a", "Old")
  Sys.chmod(target, "1750", use_umask = FALSE)
  skip_if(!identical(format(file.info(target)$mode), "1750"), "sticky bit not kept by this volume")
  skill_copy_quiet("claude", project_path = root)
  expect_identical(format(file.info(target)$mode), "1750")
})

test_that("folder modes keep the setgid bit", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  target <- skill_copy_write(root, ".agents/skills", "a", "Old")
  Sys.chmod(target, "2750", use_umask = FALSE)
  skip_if(!identical(format(file.info(target)$mode), "2750"), "setgid not kept by this volume")
  skill_copy_quiet("claude", project_path = root)
  expect_identical(format(file.info(target)$mode), "2750")
})

test_that("restoring folder modes doesn't follow links in excluded folders", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  target <- skill_copy_write(root, ".agents/skills", "a", "Old")
  outside <- withr::local_tempdir()
  Sys.chmod(outside, "0750", use_umask = FALSE)
  dir.create(file.path(target, "node_modules"))
  file.symlink(outside, file.path(target, "node_modules", "linked"))
  Sys.chmod(target, "0700", use_umask = FALSE)
  skill_copy_quiet("claude", project_path = root)
  expect_identical(format(file.info(outside)$mode), "750")
  expect_identical(format(file.info(target)$mode), "700")
  expect_match(skill_copy_text(root, ".agents/skills/a"), "New")
})

# Round 5 regressions

test_that("excluded folders carried over keep their modes", {
  skip_on_os("windows")
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  target <- skill_copy_write(root, ".agents/skills", "a", "Old")
  private <- file.path(target, ".env.local")
  dir.create(file.path(private, "nested"), recursive = TRUE)
  writeLines("SECRET=1", file.path(private, "values"))
  Sys.chmod(c(file.path(private, "nested"), private), "0700", use_umask = FALSE)
  dir.create(file.path(target, "node_modules", "pkg"), recursive = TRUE)
  Sys.chmod(file.path(target, "node_modules", "pkg"), "0750", use_umask = FALSE)
  skill_copy_quiet("claude", project_path = root)
  expect_match(skill_copy_text(root, ".agents/skills/a"), "New")
  expect_identical(format(file.info(private)$mode), "700")
  expect_identical(format(file.info(file.path(private, "nested"))$mode), "700")
  expect_identical(format(file.info(file.path(target, "node_modules", "pkg"))$mode), "750")
  expect_identical(readLines(file.path(private, "values")), "SECRET=1")
})

test_that("a source in or over .framework is refused", {
  root <- skill_copy_project()
  skill_copy_write(root, ".framework/skills-backups", "a")
  for (bad in c(".framework", ".framework/skills-backups", ".framework/other")) {
    expect_error(skill_copy_quiet(from_dir = bad, to_dir = "out", dry_run = TRUE, project_path = root),
                 "copied from, into, or over Framework's .framework folder", info = bad)
    expect_error(skill_copy_quiet(from_dir = bad, to_dir = "out", project_path = root), ".framework folder", info = bad)
  }
  expect_false(dir.exists(file.path(root, "out")))
})

test_that("push_skills() reports a missing tracked copy as diverged", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  unlink(file.path(root, ".agents/skills/example"), recursive = TRUE)
  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 failed")
  expect_true(any(grepl(paste0("Failed: example \u2014 .agents/skills/example is missing. Copy .claude/skills/example over it: ",
                               "skills_copy(from = \"claude\", to = \"agents\", skills = \"example\")"), out, fixed = TRUE)))
})

test_that("push_skills() fails only the skill with an invalid file name", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  other <- withr::local_tempdir()
  writeLines(c("---", "name: other", "description: Other", "---", "First"), file.path(other, "SKILL.md"))
  for (d in c(".claude/skills", ".agents/skills")) expect_true(.skill_package_install(other, root, file.path(d, "other"), "other"))
  for (d in c(".claude/skills", ".agents/skills")) {
    cat("Edited\n", file = file.path(root, d, "other/SKILL.md"), append = TRUE)
    writeLines("x", file.path(root, d, "example/draft notes.md"))
  }
  result <- suppressMessages(push_skills(root, confirm = TRUE))
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["example"]], "failed")
  expect_match(Filter(function(s) identical(s$name, "example"), result$skills)[[1]]$reason, "Invalid skill path")
  # The other skill is still planned (Cloud's copy differs from its origin here, so it is refused)
  expect_true("other" %in% names(statuses))
  expect_false(identical(statuses[["other"]], "failed"))
})

test_that("push_skills() reports a skill whose every tracked copy is missing", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  for (d in c(".claude/skills", ".agents/skills")) unlink(file.path(root, d, "example"), recursive = TRUE)
  out <- capture.output(result <- push_skills(root, confirm = TRUE), type = "message")
  expect_identical(result$message, "Skills pushed: 1 missing (every copy gone)")
  expect_true("  Missing: example — Every tracked copy is gone, so there is nothing to push." %in% out)
})

# Rule J: skills_copy() records the copies of a tracked skill

test_that("skills_copy() records copies of a tracked skill, and only on a real run", {
  root <- skill_copy_project()
  source <- withr::local_tempdir()
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source, "SKILL.md"))
  expect_true(.skill_package_install(source, root, ".claude/skills/example", "example"))
  skill_copy_write(root, ".claude/skills", "untracked")
  lock <- file.path(root, ".framework/skills.lock.json")
  before <- readBin(lock, "raw", n = file.info(lock)$size)
  skill_copy_quiet(from_dir = ".claude/skills", to_dir = "custom/skills", dry_run = TRUE, project_path = root)
  expect_identical(readBin(lock, "raw", n = file.info(lock)$size), before)

  skill_copy_quiet(from_dir = ".claude/skills", to_dir = "custom/skills", project_path = root)
  state <- .skill_load(root)
  expect_length(state$skills, 1L)
  expect_setequal(unlist(state$skills[[1]]$paths), c(".claude/skills/example", "custom/skills/example"))
  # The last synced hash is kept
  expect_identical(state$skills[[1]]$hash, .skill_hash(.skill_scan(source)))
  expect_false("custom/skills/untracked" %in% unlist(lapply(state$skills, `[[`, "paths")))
})

test_that("a renamed or shadowed copy gets an explanation, not a command", {
  message <- .skill_diverged_message(".claude/skills/x", ".agents/skills/y", missing = TRUE)
  expect_false(grepl("skills_copy(", message, fixed = TRUE))
  expect_match(message, "under different names")
  message <- .skill_diverged_message(".claude/skills/x", "custom/skills/y")
  expect_false(grepl("skills_copy(", message, fixed = TRUE))

  root <- withr::local_tempdir()
  dir.create(file.path(root, ".agents/skills/X"), recursive = TRUE)
  message <- .skill_diverged_message(".claude/skills/x", ".agents/skills/x", missing = TRUE, root = root)
  expect_false(grepl("skills_copy(", message, fixed = TRUE))
  expect_match(message, ".agents/skills/X is a different folder", fixed = TRUE)
})

test_that("skills_sync() of a renamed copy explains without a command", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  file.rename(file.path(root, ".agents/skills/example"), file.path(root, ".agents/skills/renamed"))
  state <- .skill_load(root)
  state$skills[[1]]$paths <- list(".claude/skills/example", ".agents/skills/renamed")
  .skill_save(root, state)
  cat("Edited\n", file = file.path(root, ".agents/skills/renamed/SKILL.md"), append = TRUE)
  error <- tryCatch(skills_sync(".claude/skills/example", root, direction = "status"), error = conditionMessage)
  expect_match(error, "under different names")
  expect_false(grepl("skills_copy(", error, fixed = TRUE))
})

test_that("skills_copy() records a copy made through a case alias of the source or target", {
  root <- skill_copy_project()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  source <- withr::local_tempdir()
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source, "SKILL.md"))
  expect_true(.skill_package_install(source, root, ".claude/skills/example", "example"))
  dir.create(file.path(root, "custom/skills"), recursive = TRUE)
  skill_copy_quiet(from_dir = ".Claude/Skills", to_dir = "Custom/skills", project_path = root)
  paths <- unlist(.skill_load(root)$skills[[1]]$paths)
  expect_setequal(paths, c(".claude/skills/example", "custom/skills/example"))
  # Copying again through another alias adds nothing
  skill_copy_quiet(from_dir = ".claude/skills", to_dir = "CUSTOM/skills", project_path = root)
  expect_setequal(unlist(.skill_load(root)$skills[[1]]$paths), c(".claude/skills/example", "custom/skills/example"))
})

test_that("skills_copy() reports the lock's spelling, and skills_sync() resolves a case alias", {
  root <- skill_copy_project()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  skill_copy_cloud(root)
  dir.create(file.path(root, "custom/skills"), recursive = TRUE)
  out <- capture.output(result <- skills_copy(from_dir = ".Claude/skills", to_dir = "Custom/skills", project_path = root),
                        type = "message")
  expect_identical(result$from, ".claude/skills")
  expect_identical(result$to, "custom/skills")
  expect_identical(result$skills[[1]]$to, "custom/skills/example")
  expect_true("  Copied: .claude/skills/example -> custom/skills/example" %in% out)
  posts <- 0L
  local_mocked_bindings(.fw_api = function(path, token, method = "GET", ...) {
    if (identical(method, "POST")) posts <<- posts + 1L
    files <- .skill_scan(file.path(root, ".claude/skills/example"))
    list(skill_id = "framework:example", version = 1L, bundle = files, hash = .skill_hash(files), system = TRUE)
  })
  sync <- skills_sync("Custom/Skills/example", root, direction = "status")
  expect_identical(sync$paths, unlist(.skill_load(root)$skills[[1]]$paths))
  expect_identical(posts, 0L)
  expect_null(.skill_load(root)$skills[["Custom/Skills/example"]])
})

# Round 11

test_that("skills_sync() matches a lock path written in an alias spelling", {
  root <- skill_copy_project()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  skill_copy_cloud(root)
  state <- .skill_load(root)
  state$skills[[1]]$paths <- list(".Claude/Skills/example", ".agents/skills/example")
  .skill_save(root, state)
  result <- skills_sync(".claude/skills/EXAMPLE", root, direction = "status")
  expect_identical(result$paths, c(".Claude/Skills/example", ".agents/skills/example"))
  expect_length(.skill_load(root)$skills, 1L)
})

test_that("skills_sync() refuses a symlinked skill path, as typed", {
  skip_on_os("windows")
  root <- skill_copy_project()
  real <- skill_copy_write(root, "elsewhere", "example")
  dir.create(file.path(root, ".claude/skills"), recursive = TRUE)
  file.symlink(real, file.path(root, ".claude/skills/example"))
  local_mocked_bindings(.fw_cloud_url = function(...) "https://cloud.example", .fw_require_token = function(...) "token",
                        .fw_api = function(...) stop("no request expected"))
  expect_error(skills_sync(".claude/skills/example", root), "symlinks")
  if (.skill_case_insensitive_at(root)) {
    expect_error(skills_sync(".CLAUDE/skills/example", root), "symlinks")
  }
  expect_length(.skill_load(root)$skills, 0L)
})

test_that("skills_copy() reads the lock before writing anything", {
  root <- skill_copy_project()
  skill_copy_write(root, ".claude/skills", "a", "New")
  skill_copy_write(root, ".agents/skills", "a", "Old")
  dir.create(file.path(root, ".framework"))
  writeLines("{ not json", file.path(root, ".framework/skills.lock.json"))
  expect_error(skill_copy_quiet("claude", project_path = root), "Could not read .framework/skills.lock.json")
  expect_match(skill_copy_text(root, ".agents/skills/a"), "Old")
  expect_false(dir.exists(file.path(root, ".framework/skills-backups")))
})

test_that("skills_copy() reports and records the skill folder as the filesystem spells it", {
  root <- skill_copy_project()
  skip_if_not(.skill_case_insensitive_at(root), "case-sensitive volume")
  source <- withr::local_tempdir()
  writeLines(c("---", "name: example", "description: Example", "---", "First"), file.path(source, "SKILL.md"))
  expect_true(.skill_package_install(source, root, ".claude/skills/example", "example"))
  # The target already holds an identical copy spelled Example
  dir.create(file.path(root, ".agents/skills"), recursive = TRUE)
  file.copy(file.path(root, ".claude/skills/example"), file.path(root, ".agents/skills"), recursive = TRUE)
  file.rename(file.path(root, ".agents/skills/example"), file.path(root, ".agents/skills/Example"))
  result <- skill_copy_quiet("claude", project_path = root)
  expect_identical(vapply(result$skills, `[[`, "", "status"), "current")
  expect_identical(result$skills[[1]]$to, ".agents/skills/Example")
  expect_setequal(unlist(.skill_load(root)$skills[[1]]$paths), c(".claude/skills/example", ".agents/skills/Example"))
})

test_that("with three copies, running the printed hint once reconciles the whole entry", {
  root <- skill_copy_project()
  skill_copy_cloud(root)
  suppressMessages(skills_copy(from = "claude", to_dir = NULL, from_dir = NULL, project_path = root, to = "agents"))
  suppressMessages(skills_copy(from_dir = ".claude/skills", to_dir = "custom/skills", project_path = root))
  expect_length(unlist(.skill_load(root)$skills[[1]]$paths), 3L)
  cat("Claude edit\n", file = file.path(root, ".claude/skills/example/SKILL.md"), append = TRUE)
  cat("Custom edit\n", file = file.path(root, "custom/skills/example/SKILL.md"), append = TRUE)
  error <- tryCatch(skills_sync(".claude/skills/example", root, direction = "status"), error = conditionMessage)
  calls <- regmatches(error, gregexpr("skills_copy\\([^)]*\\)", error))[[1]]
  # The calls before "To keep another copy": one per other copy
  calls <- calls[seq_len(2)]
  expect_identical(calls, c("skills_copy(from = \"claude\", to = \"agents\", skills = \"example\")",
                            "skills_copy(from_dir = \".claude/skills\", to_dir = \"custom/skills\", skills = \"example\")"))
  for (text in calls) { call <- str2lang(text); call$project_path <- root; suppressMessages(eval(call)) }
  hashes <- vapply(c(".claude/skills/example", ".agents/skills/example", "custom/skills/example"),
                   function(p) skill_copy_hash(root, p), "")
  expect_length(unique(hashes), 1L)
  expect_identical(skills_sync(".claude/skills/example", root, direction = "status")$action, "push")
})
