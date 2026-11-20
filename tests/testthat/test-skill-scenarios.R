# Runs every language-neutral skill sync scenario in inst/conformance/skills/
# (see its README) through the real commands, with Cloud mocked: the steps,
# rows, files, backups, and lock each command leaves.

scenario_dir <- function() {
  dir <- system.file("conformance", "skills", package = "framework")
  if (!nzchar(dir)) dir <- testthat::test_path("..", "..", "inst", "conformance", "skills")
  dir
}

scenario_text <- function(label) {
  paste0("---\nname: fixture\ndescription: Skill scenario fixture.\n---\n\n", label, "\n")
}

scenario_bundle <- function(label) {
  list(list(path = "SKILL.md", content = jsonlite::base64_enc(charToRaw(scenario_text(label))), executable = FALSE))
}

# Every label a case names: content labels and @label hash references
scenario_labels <- function(case) {
  text <- jsonlite::toJSON(case, auto_unbox = TRUE, null = "null")
  refs <- regmatches(text, gregexpr("\"@[A-Za-z0-9]+\"", text))[[1]]
  contents <- c(unlist(case$disk), unlist(case$expected$disk),
                unlist(lapply(c(case$offer$skills, unname(case$offer$by_identity)), `[[`, "content")))
  labels <- unique(c(gsub("^\"@|\"$", "", refs), contents))
  labels[!startsWith(labels, "!")]
}

# Replace each "@label" string with the label's bundle hash
scenario_resolve <- function(x, hashes) {
  if (is.character(x) && length(x) == 1 && startsWith(x, "@")) return(hashes[[substring(x, 2)]])
  if (is.list(x)) {
    named <- names(x)
    x <- lapply(x, scenario_resolve, hashes = hashes)
    names(x) <- named
  }
  x
}

scenario_write <- function(root, path, label) {
  folder <- file.path(root, path)
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  if (identical(label, "!unreadable")) writeLines("not a skill", file.path(folder, "README.txt"))
  else writeBin(charToRaw(scenario_text(label)), file.path(folder, "SKILL.md"))
}

scenario_source <- function(s) {
  if (is.null(s)) return(NULL)
  list(name = s$name, identity = .skill_identity(s$identity$kind, s$identity$skill_id, s$identity$variant, s$identity$server),
       channel = s$channel, version = if (is.null(s$version)) NULL else as.integer(s$version),
       server = s$server, hash = s$hash, known = .skill_known(unlist(s$known)),
       bundle = if (!is.null(s$content)) scenario_bundle(s$content))
}

# The project: settings naming the assistants for its dirs, folders, skill
# copies, and the lock file as given
scenario_project <- function(case, env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  assistants <- c(".claude/skills" = "claude", ".agents/skills" = "codex")[unlist(case$project$dirs)]
  writeLines(c("default:", "  project_type: project", "  ai:", paste0("    assistants: [", paste(assistants, collapse = ", "), "]")),
             file.path(root, "settings.yml"))
  for (d in unlist(case$folders)) dir.create(file.path(root, d), recursive = TRUE, showWarnings = FALSE)
  for (p in names(case$disk)) scenario_write(root, p, case$disk[[p]])
  if (!is.null(case$lock)) {
    dir.create(file.path(root, ".framework"), showWarnings = FALSE)
    writeLines(jsonlite::toJSON(case$lock, auto_unbox = TRUE, null = "null", pretty = TRUE, digits = NA),
               file.path(root, ".framework/skills.lock.json"))
  }
  root
}

# Every skill folder in the project, as content labels
scenario_disk <- function(root, case, labels) {
  dirs <- unique(c(unlist(case$project$dirs), dirname(names(case$disk)), dirname(names(case$expected$disk)),
                   unlist(case$folders)))
  out <- structure(list(), names = character())
  for (d in dirs) {
    for (name in .skill_pull_folders(root, d)) {
      p <- paste0(d, "/", name)
      h <- .skill_disk_hash(root, p)
      out[[p]] <- if (identical(h, .skill_unreadable)) "!unreadable" else names(labels)[match(h, labels)]
    }
  }
  out[order(names(out), method = "radix")]
}

# Parsed JSON in one comparable form: object keys sorted, and the arrays
# compared as sets (paths, to, known) sorted
scenario_canon <- function(x, key = NULL) {
  if (is.list(x) && !is.null(names(x)) && length(x)) {
    x <- x[order(names(x), method = "radix")]
    out <- lapply(names(x), function(k) scenario_canon(x[[k]], k))
    names(out) <- names(x)
    return(out)
  }
  if (!is.null(key) && key %in% c("paths", "to", "known", "failed", "backups")) {
    values <- unlist(x)
    return(as.list(sort(as.character(values), method = "radix")))
  }
  if (is.list(x)) return(lapply(x, scenario_canon))
  x
}

scenario_json <- function(x) {
  as.character(jsonlite::toJSON(scenario_canon(x), auto_unbox = TRUE, null = "null", na = "null", digits = NA))
}

# A plan step as the scenarios write it
scenario_step <- function(s, labels) {
  out <- list(path = s$path, entry = s$entry, name = s$name, action = s$action, status = s$status,
              reason_code = s$reason_code, hint = scenario_hint(s$hint))
  if (identical(s$action, "write")) out$content <- names(labels)[match(s$source$hash, labels)]
  if (s$action %in% c("copy", "move") || identical(s$status, "moved")) out$from <- s$from
  if (isTRUE(s$backup)) out$backup <- TRUE
  out
}

scenario_hint <- function(hint) {
  if (is.null(hint)) return(NULL)
  if (identical(hint$key, "copy")) hint$to <- as.list(unlist(hint$to))
  if (identical(hint$key, "retarget")) hint$identity <- hint$identity[c("kind", "skill_id", "variant", if (!is.null(hint$identity$server)) "server")]
  hint
}

scenario_row <- function(r) {
  hint <- if (!is.null(r$hint_key)) c(list(key = r$hint_key), r$hint_args)
  list(name = r$name, status = r$status, paths = as.list(r$paths), reason_code = r$reason_code, hint = scenario_hint(hint))
}

scenario_expect_equal <- function(actual, expected, what, case) {
  expect_identical(scenario_json(actual), scenario_json(expected), label = paste0(case$id, ": ", what))
}

scenario_sort <- function(xs, by) xs[order(vapply(xs, function(x) paste(x[[by]], collapse = "\t"), ""), method = "radix")]

# Run the case's command with Cloud mocked. Returns the steps, rows, and
# pull_all/push_all failed names; or the error.
scenario_run <- function(case, root, sources, by_identity, options, env = parent.frame()) {
  offer <- case$offer
  testthat::local_mocked_bindings(
    .skill_pull_offer = function(root, settings) {
      list(source = offer$source, offline = isTRUE(options$offline), notes = character(), skills = sources)
    },
    .skill_fetch_identity = function(key, entry, name) by_identity[[key]],
    .skill_server = function(root) "https://cloud.test",
    .fw_require_token = function(...) "token",
    .fw_cloud_token = function(...) "token",
    .fw_interactive = function() FALSE,
    .skill_project_token = function(...) NULL,
    .skill_push_remote = function(key, entry, server, token) {
      r <- offer$remote[[key]]
      if (is.null(r)) NULL else list(version = as.integer(r$version), hash = r$hash, skill_id = entry$identity$skill_id)
    },
    .skill_push_post = function(body, server, token) {
      replies <- offer$push_response
      key <- names(replies)[vapply(names(replies), function(k) {
        is.null(body$skill_id) || grepl(paste0("/", body$skill_id, "@"), k, fixed = TRUE) || startsWith(k, paste0(body$skill_id, "@"))
      }, logical(1))][1]
      reply <- replies[[key]]
      c(reply, list(bundle = body$bundle))
    },
    .env = env
  )
  command <- case$command
  folder <- function(x) if (x %in% names(.skill_copy_names())) list(name = x) else list(dir = x)
  tryCatch(suppressMessages(switch(command,
    pull = {
      r <- pull_skills(root, overwrite = isTRUE(options$overwrite), dry_run = isTRUE(options$dry_run))
      list(steps = r$steps, rows = lapply(r$skills, scenario_row))
    },
    pull_all = {
      part <- .skills_pull_plan(root, isTRUE(options$overwrite))
      r <- if (!isTRUE(options$dry_run) && part$pending) part$apply() else part$plan
      list(steps = r$steps, rows = lapply(r$skills, scenario_row),
           failed = scenario_failed_names(.skills_failed_rows(r)))
    },
    upgrade = {
      run <- .skill_sync_run(root, list(source = offer$source, skills = sources, by_identity = list()),
                             list(command = "upgrade", dirs = unlist(case$project$dirs), scope = "builtin",
                                  overwrite = FALSE, dry_run = isTRUE(options$dry_run)), fn = "upgrade()")
      rows <- Filter(function(r) !identical(r$status, "removed"), run$rows)
      list(steps = Filter(function(s) !identical(s$status, "removed"), run$steps),
           rows = lapply(.skill_rows_out(rows, list(lock = run$lock, disk = run$disk)), scenario_row))
    },
    push = {
      r <- push_skills(root, force = isTRUE(options$force), confirm = options$confirm, dry_run = isTRUE(options$dry_run))
      list(steps = r$steps, rows = lapply(r$skills, scenario_row))
    },
    push_all = {
      part <- .skills_push_plan(root, isTRUE(options$force))
      rows <- if (!isTRUE(options$dry_run) && part$pending) part$apply() else part$plans
      list(steps = NULL, rows = lapply(rows, scenario_row), failed = scenario_failed_names(.skills_push_failed_rows(rows)))
    },
    copy = {
      from <- folder(options$from); to <- folder(options$to)
      r <- skills_copy(from = from$name, to = to$name, from_dir = from$dir, to_dir = to$dir,
                       skills = if (!is.null(options$skills)) unlist(options$skills), project_path = root,
                       dry_run = isTRUE(options$dry_run))
      list(steps = r$steps, rows = lapply(r$skills, function(s) {
        list(name = s$name, status = s$status, paths = list(s$to), reason_code = NULL, hint = NULL)
      }))
    },
    move = {
      r <- skills_move(options$from, to = options$to, skill_id = options$skill_id, variant = options$variant,
                       builtin = options$builtin, project_path = root, dry_run = isTRUE(options$dry_run))
      list(steps = r$steps, rows = lapply(r$skills, scenario_row))
    },
    stop("Unknown scenario command: ", command))), fw_skill_error = function(e) list(error = e$code))
}

scenario_failed_names <- function(failed) {
  as.list(sub("^Skill (.*) \\(.*\\)$", "\\1", names(failed)))
}

scenario_check <- function(case, dry_run = FALSE) {
  labels <- vapply(stats::setNames(nm = scenario_labels(case)), function(l) .skill_hash(scenario_bundle(l)), "")
  case <- scenario_resolve(case, as.list(labels))
  options <- case$options %||% list()
  if (dry_run) options$dry_run <- TRUE
  root <- scenario_project(case)
  lock_file <- file.path(root, ".framework/skills.lock.json")
  before <- if (file.exists(lock_file)) readBin(lock_file, "raw", n = 1e6)
  sources <- lapply(case$offer$skills, scenario_source)
  by_identity <- lapply(case$offer$by_identity, scenario_source)
  what <- if (dry_run) "dry run " else ""
  got <- scenario_run(case, root, sources, by_identity, options)
  expected <- case$expected

  expect_identical(got$error, expected$error, label = paste0(case$id, ": ", what, "error"))
  if (is.null(expected$error)) {
    if (!is.null(got$steps)) {
      steps <- scenario_sort(lapply(got$steps, scenario_step, labels = labels), "path")
      scenario_expect_equal(steps, scenario_sort(expected$steps, "path"), paste0(what, "steps"), case)
    }
    rows <- function(rs) rs[order(vapply(rs, function(r) paste(r$name, paste(sort(unlist(r$paths)), collapse = "\t")), ""),
                                  method = "radix")]
    scenario_expect_equal(rows(got$rows), rows(expected$rows), paste0(what, "rows"), case)
    if (!is.null(expected$failed) && !dry_run) scenario_expect_equal(got$failed, expected$failed, "failed", case)
  }

  unchanged <- dry_run || identical(expected$lock, "unchanged")
  after_disk <- scenario_disk(root, case, labels)
  scenario_expect_equal(after_disk, if (dry_run) case$disk else expected$disk, paste0(what, "disk"), case)
  backups <- list.dirs(file.path(root, ".framework/skills-backups"), recursive = FALSE)
  backed <- vapply(backups, function(b) names(labels)[match(.skill_hash(.skill_scan(b)), labels)], "")
  expected_backups <- if (dry_run) character() else vapply(unlist(expected$backups), function(p) case$disk[[p]], "")
  expect_identical(sort(unname(backed)), sort(unname(expected_backups)), label = paste0(case$id, ": ", what, "backups"))
  if (unchanged) {
    after <- if (file.exists(lock_file)) readBin(lock_file, "raw", n = 1e6)
    expect_identical(after, before, label = paste0(case$id, ": ", what, "lock unchanged"))
  } else {
    lock <- jsonlite::fromJSON(lock_file, simplifyVector = FALSE)
    scenario_expect_equal(lock, expected$lock, "lock", case)
  }
}

for (file in sort(list.files(scenario_dir(), pattern = "\\.json$", full.names = TRUE))) {
  case <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  test_that(paste0("skill scenario ", case$id, ": ", case$description), {
    scenario_check(case)
  })
  # A dry run plans the same steps and rows and writes nothing
  confirm_false <- identical(case$options$confirm, FALSE)
  if (is.null(case$expected$error) && !isTRUE(case$options$dry_run) && !confirm_false &&
      case$command %in% c("pull", "upgrade", "push", "copy", "move")) {
    test_that(paste0("skill scenario ", case$id, " as a dry run"), {
      scenario_check(case, dry_run = TRUE)
    })
  }
}

test_that("the scenario folder holds every case the spec counts", {
  expect_length(list.files(scenario_dir(), pattern = "\\.json$"), 86L)
})

test_that("a Cloud setup's sync.known_hashes are the source's known hashes", {
  bundle <- scenario_bundle("m2")
  older <- .skill_hash(scenario_bundle("m1"))
  entry <- list(bundle = bundle, sync = list(skill_id = "uuid-mine", version = 2L, hash = .skill_hash(bundle), variant = "r",
                                             server = "https://cloud.test/", known_hashes = list(older)))
  source <- .skill_source_setup("mine", entry)
  expect_setequal(source$known, c(older, .skill_hash(bundle)))
  expect_identical(source$server, "https://cloud.test")
  # An unedited copy of the older version, installed before the lock, is updated
  root <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude]"), file.path(root, "settings.yml"))
  scenario_write(root, ".claude/skills/mine", "m1")
  status <- suppressMessages(.skill_install_sources(root, list(source), ".claude/skills"))
  expect_identical(status$mine, "updated")
})

test_that("a Cloud snapshot's known_hashes join a source's known hashes", {
  b1 <- scenario_bundle("m1"); b2 <- scenario_bundle("m2")
  entry <- list(bundle = b1, sync = list(skill_id = "uuid-mine", version = 1L, hash = .skill_hash(b1), variant = "r",
                                         server = "https://cloud.test"))
  older <- .skill_hash(scenario_bundle("m0"))
  local_mocked_bindings(
    .fw_cloud_token = function(...) "token",
    .fw_api = function(...) list(skill_id = "uuid-mine", version = 2L, bundle = b2, hash = .skill_hash(b2), known_hashes = list(older)))
  got <- .skill_pull_latest(list(mine = entry), "https://cloud.test", character())
  source <- .skill_source_setup("mine", got$skills$mine)
  expect_setequal(source$known, c(older, .skill_hash(b1), .skill_hash(b2)))
  lock <- list(skills = list())
  by_id <- .skill_fetch_identity("k", list(identity = .skill_identity("cloud", "uuid-mine", "r", "https://cloud.test")), "mine")
  expect_true(older %in% by_id$known)
})
