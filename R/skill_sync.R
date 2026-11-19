# Exact-byte skill snapshots. The manifest is shared with Python, Go, and Cloud.
.skill_excluded <- function(name) {
  tolower(name) %in% c(".git", ".framework", ".framework-skill.json", "__pycache__", "node_modules", ".env", "id_rsa") |
    grepl("^\\.env\\.|\\.(pem|key)$", tolower(name))
}

.skill_validate <- function(files) {
  if (length(files) > 256L) stop("A skill supports at most 256 files", call. = FALSE)
  seen <- character(); total <- 0
  for (f in files) {
    path <- f$path
    if (!is.character(path) || length(path) != 1 || nchar(path) > 240 ||
        !grepl("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", path)) stop("Invalid skill path", call. = FALSE)
    parts <- strsplit(path, "/", fixed = TRUE)[[1]]
    if (any(parts %in% c(".", "..")) || any(.skill_excluded(parts)) || tolower(path) %in% seen) stop("Excluded or duplicate skill path", call. = FALSE)
    seen <- c(seen, tolower(path))
    if (path == "SKILL.md" && isTRUE(f$executable)) stop("SKILL.md cannot be executable", call. = FALSE)
    raw <- jsonlite::base64_dec(f$content)
    total <- total + length(raw)
    if (length(raw) > 4 * 1024^2 || total > 16 * 1024^2) stop("Skill bundle exceeds the size limit", call. = FALSE)
  }
  if (!"SKILL.md" %in% vapply(files, `[[`, "", "path")) stop("SKILL.md is required", call. = FALSE)
  for (a in seen) if (any(startsWith(seen, paste0(a, "/")))) stop("File and directory path collision", call. = FALSE)
  files[order(vapply(files, `[[`, "", "path"), method = "radix")]
}

.skill_sha <- function(raw) unclass(as.character(openssl::sha256(raw)))
# Text files hash with LF line endings, so a CRLF checkout (git's
# core.autocrlf on Windows) matches its LF twin. A file with a NUL byte is
# binary and hashes raw. Python, Go, and Cloud normalize the same way.
.skill_hash_bytes <- function(raw) {
  if (any(raw == as.raw(0))) return(raw)
  raw[!(raw == as.raw(13) & c(utils::tail(raw, -1), as.raw(0)) == as.raw(10))]
}
.skill_hash <- function(files) {
  manifest <- "framework-skill-bundle-v1\n"
  for (f in .skill_validate(files)) {
    raw <- .skill_hash_bytes(jsonlite::base64_dec(f$content))
    manifest <- paste0(manifest, f$path, "\t", .skill_sha(raw), "\t", if (isTRUE(f$executable)) "755" else "644", "\t", length(raw), "\n")
  }
  .skill_sha(charToRaw(manifest))
}

.skill_on_windows <- function() .Platform$OS.type == "windows"

# What is at a path, without following a final link: "missing",
# "directory", "file", "symlink", or another fs type. A path that can't be
# looked up (permission denied) is an error, never "missing".
.skill_kind <- function(path) {
  force(path)
  info <- tryCatch(fs::file_info(path, follow = FALSE),
                   error = function(e) stop("Could not read ", path, ": ", conditionMessage(e), call. = FALSE))
  type <- as.character(info$type)
  if (is.na(type)) "missing" else type
}

# A symlink, or on Windows a junction: libuv's lstat reports both as links.
# Sys.readlink() covers platforms where lstat can't tell.
.skill_is_link <- function(path) {
  if (identical(.skill_kind(path), "symlink")) return(TRUE)
  link <- Sys.readlink(path)
  !is.na(link) && nzchar(link)
}

.skill_path <- function(root, relative) {
  if (!is.character(relative) || length(relative) != 1 || grepl("^[/\\\\]|^[A-Za-z]:", relative)) stop("Skill paths must be project-relative", call. = FALSE)
  parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
  if (!length(parts) || any(parts %in% c("", ".", ".."))) stop("Invalid skill path", call. = FALSE)
  # A colon names a drive or a stream on Windows
  if (any(grepl(":", parts, fixed = TRUE))) stop("Skill paths cannot contain \":\": ", relative, call. = FALSE)
  path <- root
  for (part in parts) {
    path <- file.path(path, part)
    if (.skill_is_link(path)) stop("Skill paths cannot contain symlinks", call. = FALSE)
  }
  path
}

# Executable paths on Windows, which has no executable bit. Older versions
# wrote a single path as a JSON string rather than an array.
.skill_exec_meta_read <- function(path) {
  meta <- file.path(path, ".framework-skill.json")
  kind <- .skill_kind(meta)
  if (identical(kind, "missing")) return(character())
  if (!identical(kind, "file")) stop("Skill symlinks are unsupported", call. = FALSE)
  paths <- unlist(jsonlite::fromJSON(meta, simplifyVector = FALSE)$executable_paths, use.names = FALSE)
  if (!is.null(paths) && !is.character(paths)) stop("Invalid .framework-skill.json", call. = FALSE)
  as.character(paths)
}
.skill_exec_meta_write <- function(folder, files) {
  meta <- file.path(folder, ".framework-skill.json")
  executable <- vapply(Filter(function(f) isTRUE(f$executable), files), `[[`, "", "path")
  # Always an array, even for one path
  if (length(executable)) writeLines(jsonlite::toJSON(list(executable_paths = executable)), meta)
  else if (file.exists(meta)) unlink(meta)
}

# A folder's entries, by their literal names. A folder that can't be read is
# an error: fs::dir_ls() reports it (list.files() returns nothing), but
# fs::dir_ls() turns a backslash in a name into a separator, so the names
# come from list.files(). A backslash in a name is an error.
# Names the caller skips (`ignore`) are not checked.
.skill_list <- function(folder, ignore = function(name) FALSE) {
  force(folder)
  tryCatch(fs::dir_ls(folder, all = TRUE),
           error = function(e) stop("Could not read ", folder, ": ", conditionMessage(e), call. = FALSE))
  names <- list.files(folder, all.files = TRUE, no.. = TRUE)
  bad <- names[grepl("\\", names, fixed = TRUE) & !ignore(names)]
  if (length(bad)) stop("Skill file names cannot contain a backslash: ", file.path(folder, bad[1]), call. = FALSE)
  file.path(folder, names)
}

.skill_scan <- function(path) {
  if (.skill_is_link(path)) stop("Skill symlinks are unsupported", call. = FALSE)
  files <- list()
  walk <- function(folder, prefix = "") {
    for (p in .skill_list(folder, ignore = .skill_excluded)) {
      name <- basename(p)
      if (.skill_is_link(p)) stop("Skill symlinks are unsupported: ", prefix, name, call. = FALSE)
      if (.skill_excluded(name)) next
      relative <- paste0(prefix, name)
      info <- fs::file_info(p, follow = FALSE)
      type <- as.character(info$type)
      if (identical(type, "directory")) { walk(p, paste0(relative, "/")); next }
      if (!identical(type, "file") || is.na(info$size) || info$size > 4 * 1024^2) stop("Invalid or oversized skill file", call. = FALSE)
      raw <- readBin(p, "raw", n = info$size)
      executable <- !.skill_on_windows() && bitwAnd(as.integer(file.info(p)$mode), 73L) != 0L
      files[[length(files) + 1L]] <<- list(path = relative, content = jsonlite::base64_enc(raw), executable = executable)
    }
  }
  walk(path)
  if (.skill_on_windows()) {
    executable_paths <- .skill_exec_meta_read(path)
    for (i in seq_along(files)) files[[i]]$executable <- files[[i]]$path %in% executable_paths
  }
  .skill_validate(files)
}

.skill_load <- function(root) {
  path <- .skill_path(root, ".framework/skills.lock.json")
  state <- if (file.exists(path)) jsonlite::fromJSON(path, simplifyVector = FALSE) else list(schema = 1L, skills = list())
  if (!identical(as.integer(state$schema), 1L) || !is.list(state$skills)) stop("Unsupported skill lock file", call. = FALSE)
  .skill_merge_entries(state)
}

# One entry per skill. Lock files from earlier versions can hold two
# entries for one skill (a package: entry for .claude/skills and an
# account: entry for .agents/skills). Entries that share a Cloud ID, or a
# skill name and origin, are merged into the entry with the highest
# version, with all their paths. A Cloud skill is identified by its server,
# ID, and variant: an R and a Python variant of one skill stay separate.
.skill_merge_entries <- function(state) {
  if (length(state$skills) < 2) return(state)
  identity <- vapply(state$skills, function(e) {
    if (!is.null(e$skill_id)) return(paste("id", e$server %||% "", e$skill_id, e$variant %||% "r", sep = "\t"))
    if (!is.null(e$origin$skill_id)) {
      names <- unique(basename(unlist(e$paths)))
      if (length(names) == 1) return(paste("origin", e$origin$skill_id, names, e$variant %||% "r", sep = "\t"))
    }
    NA_character_
  }, "")
  for (id in unique(identity[!is.na(identity) & duplicated(identity)])) {
    keys <- names(state$skills)[!is.na(identity) & identity == id]
    versions <- vapply(keys, function(k) as.integer(state$skills[[k]]$version %||% 0L), integer(1))
    base <- keys[which.max(versions)]
    merged <- state$skills[[base]]
    merged$paths <- as.list(unique(unlist(lapply(keys, function(k) unlist(state$skills[[k]]$paths)))))
    for (k in setdiff(keys, base)) state$skills[[k]] <- NULL
    state$skills[[base]] <- merged
  }
  state
}
.skill_save <- function(root, state) {
  path <- .skill_path(root, ".framework/skills.lock.json")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .skill_private(root)
  temp <- tempfile(tmpdir = dirname(path)); on.exit(unlink(temp))
  if (!length(state$skills)) state$skills <- structure(list(), names = character())
  writeLines(jsonlite::toJSON(state, auto_unbox = TRUE, pretty = TRUE, null = "null", force = TRUE), temp, useBytes = TRUE)
  fs::file_move(temp, path)
}
.skill_uuid <- function() {
  x <- as.character(openssl::rand_bytes(16)); x <- paste0(x, collapse = "")
  # Set the UUID version and variant bits without adding a dependency.
  paste0(substr(x, 1, 8), "-", substr(x, 9, 12), "-4", substr(x, 14, 16), "-a", substr(x, 18, 20), "-", substr(x, 21, 32))
}

# Undo installs: put each backup back, or remove a copy that is new. Each
# swap is an environment, so an undone swap is marked and a second rollback
# of the same swap does nothing. Returns the swaps that could not be undone.
.skill_rollback <- function(swaps) {
  failed <- list()
  for (swap in rev(swaps)) {
    ok <- TRUE
    # A rename an interrupt cut off before its flag was set: the files show
    # whether it happened
    if (!isTRUE(swap$moved) && isTRUE(swap$moving) && dir.exists(swap$backup_path) && !file.exists(swap$target)) swap$moved <- TRUE
    if (!isTRUE(swap$installed) && isTRUE(swap$installing) && !is.null(swap$stage) && !dir.exists(swap$stage) && dir.exists(swap$target)) {
      swap$installed <- TRUE
    }
    if (isTRUE(swap$moved)) {
      aside <- tempfile(".skill-undo-", tmpdir = dirname(swap$target))
      if (isTRUE(swap$installed)) ok <- isTRUE(file.rename(swap$target, aside))
      if (ok) ok <- isTRUE(suppressWarnings(file.rename(swap$backup_path, swap$target)))
      if (ok) {
        swap$moved <- FALSE; swap$installed <- FALSE
      } else if (dir.exists(aside)) {
        file.rename(aside, swap$target)
      }
      unlink(aside, recursive = TRUE)
    } else if (isTRUE(swap$installed)) {
      unlink(swap$target, recursive = TRUE)
      ok <- !file.exists(swap$target)
      if (ok) swap$installed <- FALSE
    }
    if (!is.null(swap$stage)) { unlink(swap$stage, recursive = TRUE); swap$stage <- NULL }
    if (!ok) failed <- c(list(swap), failed)
  }
  failed
}

# file.rename(), mockable in tests
.skill_rename <- function(from, to) file.rename(from, to)

# One line per swap a rollback could not undo, naming where the old copy is
.skill_lost_lines <- function(lost) {
  vapply(lost, function(s) {
    paste0("  ", s$path, if (is.null(s$backup)) " (new copy, not removed)" else paste0(" (old copy in ", s$backup, ")"))
  }, "")
}

# Stop after a failed install whose rollback has run. A copy that could not
# be restored is named with its backup.
.skill_install_failed <- function(cause, lost) {
  reason <- if (inherits(cause, "interrupt")) "interrupted" else sub("\\.$", "", conditionMessage(cause))
  message <- if (length(lost)) {
    paste(c(paste0("Could not install skill (", reason, "), and these copies could not be restored:"),
            .skill_lost_lines(lost)), collapse = "\n")
  } else reason
  stop(errorCondition(message, class = "fw_skill_install_error", reason = reason, lost = lost, call = NULL))
}

# Give each rebuilt folder in `to` the mode of the same folder in `from`,
# deepest first, so a 0700 folder is not recreated as 0755. Excluded
# folders are included.
.skill_keep_dir_modes <- function(from, to) {
  dirs <- ""
  walk <- function(folder, prefix) {
    # Excluded folders (node_modules, .env.local/) are carried over by the
    # copy, so their modes are restored too. Links are not followed.
    for (p in .skill_list(folder, ignore = function(name) TRUE)) {
      if (!identical(.skill_kind(p), "directory")) next
      relative <- paste0(prefix, basename(p))
      dirs <<- c(dirs, relative)
      walk(p, paste0(relative, "/"))
    }
  }
  walk(from, "")
  for (relative in rev(dirs)) {
    source <- if (nzchar(relative)) file.path(from, relative) else from
    dest <- if (nzchar(relative)) file.path(to, relative) else to
    # A folder that became a file in the new copy keeps the file's mode.
    # The mode includes setuid, setgid, and sticky bits.
    if (identical(.skill_kind(dest), "directory")) Sys.chmod(dest, file.info(source)$mode, use_umask = FALSE)
  }
}

# Install a bundle at each path. A replaced folder is moved to
# .framework/skills-backups/. On an error or an interrupt, the paths already
# swapped are restored; one that can't be is named with its backup. Returns,
# per path, a swap record with the target and its backup (backup and
# backup_path are NULL for a new copy). A `journal` environment collects the
# records as soon as the install completes, for a caller's rollback.
.skill_install <- function(root, paths, files, expected, journal = NULL) {
  files <- .skill_validate(files)
  swaps <- list()
  outcome <- tryCatch({
    for (relative in paths) {
      target <- .skill_path(root, relative)
      existed <- identical(.skill_kind(target), "directory")
      if (existed && !identical(.skill_hash(.skill_scan(target)), expected)) stop("Local skill changed during sync", call. = FALSE)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      # Registered before the staging folder exists, so any later failure removes it
      swap <- new.env()
      swap$path <- relative; swap$target <- target; swap$existed <- existed
      swap$stage <- tempfile(".skill-stage-", tmpdir = dirname(target))
      swap$backup <- NULL; swap$backup_path <- NULL; swap$moved <- FALSE; swap$installed <- FALSE
      swap$moving <- FALSE; swap$installing <- FALSE
      swaps[[length(swaps) + 1L]] <- swap
      if (!dir.create(swap$stage)) stop("Could not create a staging folder for ", relative, call. = FALSE)
      stage <- swap$stage
      if (existed) {
        swap$backup <- paste0(".framework/skills-backups/", .skill_uuid())
        swap$backup_path <- .skill_path(root, swap$backup)
        .skill_private(root); dir.create(dirname(swap$backup_path), recursive = TRUE, showWarnings = FALSE)
        fs::dir_copy(target, stage, overwrite = TRUE)
        keep <- vapply(files, `[[`, "", "path")
        for (old in .skill_scan(target)) if (!old$path %in% keep) {
          removed <- file.path(stage, old$path); unlink(removed); parent <- dirname(removed)
          while (!identical(parent, stage) && dir.exists(parent) && !length(list.files(parent, all.files = TRUE, no.. = TRUE))) {
            unlink(parent, recursive = TRUE); parent <- dirname(parent)
          }
        }
      }
      for (f in files) {
        dest <- .skill_path(stage, f$path); dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
        writeBin(jsonlite::base64_dec(f$content), dest)
        Sys.chmod(dest, if (isTRUE(f$executable)) "0755" else "0644")
      }
      if (.skill_on_windows()) .skill_exec_meta_write(stage, files)
      if (existed) .skill_keep_dir_modes(target, stage)
      if (!identical(.skill_hash(.skill_scan(stage)), .skill_hash(files))) stop("Staged skill verification failed", call. = FALSE)
    }
    for (swap in swaps) {
      if (swap$existed && !identical(.skill_hash(.skill_scan(swap$target)), expected)) stop("Local skill changed during sync", call. = FALSE)
      # Each rename and its flag form one step: interrupts wait until both
      # are done, and the intent is recorded first in case one gets through
      if (swap$existed) {
        swap$moving <- TRUE
        moved <- suspendInterrupts({ ok <- .skill_rename(swap$target, swap$backup_path); if (ok) swap$moved <- TRUE; ok })
        if (!moved) stop("Could not back up skill", call. = FALSE)
      }
      swap$installing <- TRUE
      installed <- suspendInterrupts({ ok <- .skill_rename(swap$stage, swap$target); if (ok) swap$installed <- TRUE; ok })
      if (!installed) stop("Could not install skill", call. = FALSE)
      swap$stage <- NULL
    }
    if (!is.null(journal)) journal$done <- c(journal$done, swaps)
    NULL
  }, error = identity, interrupt = identity)
  if (!is.null(outcome)) .skill_install_failed(outcome, .skill_rollback(swaps))
  invisible(swaps)
}

#' Synchronize a Skill Directory
#'
#' Synchronize a versioned skill bundle with Framework Cloud. Divergent changes
#' return a conflict without replacing files. Companion files and executable
#' modes are included. Untracked skills become private account skills. When
#' a skill's copies in several assistant folders differ, sync stops until
#' [skills_copy()] makes them match.
#' @param path Project-relative skill directory.
#' @param project_path Project root directory.
#' @param direction One of auto, push, pull, or status.
#' @param dry_run Report the action without writing files or Cloud versions.
#' @param skill_id Explicit Cloud skill identity for adoption or an initial pull.
#' @param variant Language variant: r, python, or stata.
#' @param resolve Optional conflict choice: local or remote. Replaced files are backed up.
#' @return A list with the action, skill identity, hashes, and version.
#' @export
skills_sync <- function(path, project_path = ".", direction = "auto", dry_run = FALSE,
                        skill_id = NULL, variant = "r", resolve = NULL) {
  if (!direction %in% c("auto", "push", "pull", "status") || !variant %in% c("r", "python", "stata")) stop("Invalid sync direction or variant", call. = FALSE)
  if (!is.null(resolve) && !resolve %in% c("local", "remote")) stop("Invalid conflict resolution", call. = FALSE)
  root <- normalizePath(project_path, mustWork = TRUE)
  lock <- .skill_path(root, ".framework/skills.sync.lock"); dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(lock, showWarnings = FALSE)) stop("Skill sync is locked. If the previous process stopped, remove .framework/skills.sync.lock and retry.", call. = FALSE)
  on.exit(unlink(lock, recursive = TRUE))
  state <- .skill_load(root)
  # The path as typed may not contain links (checked before any
  # resolution, which would follow them). Then the lock's spelling: a case
  # alias of a tracked path is that path, found by filesystem identity.
  .skill_path(root, path)
  path <- .skill_lock_spelling(root, state, path)
  # The entry listing the path; never an entry whose key merely matches it
  key <- names(Filter(function(e) path %in% unlist(e$paths), state$skills))[1]
  entry <- if (length(key) && !is.na(key)) state$skills[[key]] else NULL
  if (is.null(entry)) {
    # A new entry, under a key no other entry uses
    key <- path; n <- 1L
    while (key %in% names(state$skills)) { n <- n + 1L; key <- paste0(path, "#", n) }
    entry <- list(paths = list(path), variant = variant)
  }
  server <- .skill_server(root); token <- .fw_require_token(url = server)
  if (!is.null(entry$server) && !identical(entry$server, server)) stop("Skill tracks another server", call. = FALSE)
  if (!is.null(skill_id) && !is.null(entry$skill_id) && !identical(skill_id, entry$skill_id)) stop("Skill identity mismatch", call. = FALSE)
  variant <- entry$variant %||% variant; paths <- unlist(entry$paths, use.names = FALSE)
  bundles <- lapply(paths, function(p) { target <- .skill_path(root, p); if (!identical(.skill_kind(target), "missing")) .skill_scan(target) else NULL })
  hashes <- vapply(bundles, function(b) if (is.null(b)) "" else .skill_hash(b), "")
  if (length(unique(hashes)) > 1) {
    # A missing copy is never the one to keep
    present <- paths[nzchar(hashes)]
    other <- if (all(nzchar(hashes))) paths[which(hashes != hashes[1])[1]] else paths[!nzchar(hashes)][1]
    stop(.skill_diverged_message(present[1], other, missing = !all(nzchar(hashes)), root = root,
                                 others = setdiff(paths, present[1])), call. = FALSE)
  }
  local_hash <- if (nzchar(hashes[1])) hashes[1] else NULL; files <- bundles[[1]]
  identity <- entry$skill_id %||% skill_id; remote <- NULL
  if (!is.null(identity)) remote <- .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(identity, reserved = TRUE), "?variant=", variant), token, url = server)
  else if (!is.null(entry$origin)) {
    # Cloud answers 409 for a built-in copy it never published (the package
    # shipped its own text): an edited one is pushed as a new skill of your own
    remote <- tryCatch(
      .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(entry$origin$skill_id, reserved = TRUE), "?variant=", variant, "&hash=", entry$origin$hash), token, url = server),
      httr2_http_409 = function(e) NULL)
  }
  if (!is.null(remote) && !identical(.skill_hash(remote$bundle), remote$hash)) stop("Cloud skill verification failed", call. = FALSE)
  base <- if (!is.null(entry$skill_id)) entry$hash else entry$origin$hash
  action <- if (is.null(remote)) { if (is.null(files)) "missing" else if (is.null(entry$skill_id) && identical(local_hash, base)) "unchanged" else "push" }
  else if (identical(local_hash, remote$hash)) { if (is.null(entry$skill_id)) "adopt" else "unchanged" }
  else if (is.null(local_hash)) { if (is.null(base) && !is.null(skill_id)) "pull" else "conflict" }
  else if (is.null(base)) "conflict"
  else if (identical(local_hash, base)) "pull"
  else if (identical(remote$hash, base)) "push" else "conflict"
  if (identical(action, "conflict") && !is.null(resolve) && !is.null(remote)) {
    if (identical(resolve, "remote")) action <- "pull"
    else if (!is.null(files)) action <- "push"
  }
  if (direction %in% c("push", "pull") && action %in% c("push", "pull") && !identical(direction, action)) action <- "blocked"
  result <- list(action = action, skill_id = remote$skill_id, local_hash = local_hash, remote_hash = remote$hash, paths = paths)
  if (dry_run || identical(direction, "status") || action %in% c("conflict", "blocked", "missing")) return(result)
  if (identical(action, "push")) {
    expected <- if (identical(resolve, "local") && !is.null(remote) && !isTRUE(remote$system)) remote$version else entry$version %||% remote$version %||% 0L
    basis <- paste0(expected, ":", remote$skill_id %||% "", ":", variant)
    pending <- entry$pending
    if (is.null(pending) || !identical(pending$hash, local_hash) || !identical(pending$basis, basis)) pending <- list(request_id = .skill_uuid(), hash = local_hash, basis = basis)
    entry$pending <- pending; state$skills[[key]] <- entry; .skill_save(root, state)
    body <- list(
      request_id = pending$request_id, skill_id = remote$skill_id,
      expected_version = expected, variant = variant,
      bundle = files, client = list(app = "framework-r")
    )
    body$project_token <- .skill_project_token(root, server)
    remote <- .fw_api("/api/v1/skills/sync", token, method = "POST", url = server, body = body)
  }
  if (!is.null(remote)) {
    if (!identical(.skill_hash(remote$bundle), remote$hash)) stop("Cloud skill verification failed", call. = FALSE)
    if (identical(action, "pull")) .skill_install(root, paths, remote$bundle, local_hash)
    entry$server <- server; entry$skill_id <- remote$skill_id; entry$version <- remote$version
    entry$hash <- remote$hash; entry$variant <- variant; entry$pending <- NULL
    state$skills[[key]] <- entry; .skill_save(root, state)
    result$skill_id <- remote$skill_id; result$version <- remote$version
  }
  result
}

# A path in the lock's spelling: the tracked path it is on disk, else the
# filesystem's spelling
.skill_lock_spelling <- function(root, state, path) {
  spelled <- .skill_copy_spelling(root, path)
  for (p in unique(unlist(lapply(state$skills, function(e) unlist(e$paths))))) {
    if (identical(p, path) || identical(.skill_copy_spelling(root, p), spelled)) return(p)
  }
  spelled
}

# The server a project's skills sync with. A project with a token (in .env
# or the shell) or FW_CLOUD_URL in .env uses the project's server, as its
# packages and data registry do. Otherwise .fw_cloud_url() decides.
.skill_server <- function(root) {
  linked <- !is.null(.fw_project_token(root)) || !is.null(.fw_project_env_value("FW_CLOUD_URL", root))
  sub("/$", "", if (linked) .fw_project_cloud_url(root) else .fw_cloud_url(project_dir = root))
}

# The project's token when the project is on this server, else NULL. A push
# that names the project lets Cloud list a pushed copy of a built-in skill in
# the project's setup, so the next pull keeps it.
.skill_project_token <- function(root, server) {
  token <- .fw_project_token(root)
  if (is.null(token) || !nzchar(token)) return(NULL)
  project_server <- tryCatch(sub("/$", "", .fw_project_cloud_url(root)), error = function(e) NULL)
  if (identical(project_server, server)) token else NULL
}

# What installing a package skill would do: "create" (missing), "current"
# (up to date), "update" (an unedited older version: the lock's hash, or,
# without a lock entry, a SKILL.md the package has shipped), "edited"
# (changed locally), or "account" (tracks an account skill)
.skill_package_status <- function(source, root, relative, name) {
  target <- .skill_path(root, relative); state <- .skill_load(root)
  keys <- names(Filter(function(e) relative %in% unlist(e$paths), state$skills))
  entry <- if (length(keys)) state$skills[[keys[1]]] else list()
  if (!is.null(entry$skill_id) && !startsWith(entry$skill_id, "framework:")) return("account")
  fresh <- .skill_hash(.skill_scan(source))
  if (!dir.exists(target)) return("create")
  current <- .skill_hash(.skill_scan(target))
  if (identical(current, fresh)) return("current")
  if (!is.null(entry$hash)) return(if (identical(current, entry$hash)) "update" else "edited")
  if (.skill_released_copy(target, name)) "update" else "edited"
}

# Whether a skill folder holds only a SKILL.md the package has shipped, in
# any version (inst/templates/skill-history.json). Skills installed before
# .framework/skills.lock.json have no lock entry to compare with.
# framework-py: skills.is_released_copy().
.skill_released_copy <- function(target, name) {
  files <- list.files(target, all.files = TRUE, recursive = TRUE, no.. = TRUE)
  files <- files[!.skill_excluded(basename(files))]
  if (!identical(files, "SKILL.md")) return(FALSE)
  history <- .skill_history()[[name]]
  if (length(history) == 0) return(FALSE)
  raw <- readBin(file.path(target, "SKILL.md"), "raw", n = file.info(file.path(target, "SKILL.md"))$size)
  # A checkout with CRLF line endings is the same text
  lf <- .skill_hash_bytes(raw)
  any(c(.skill_sha(raw), .skill_sha(lf)) %in% unlist(history))
}

.skill_history <- function() {
  path <- system.file("templates", "skill-history.json", package = "framework")
  if (!nzchar(path)) return(list())
  tryCatch(jsonlite::read_json(path, simplifyVector = FALSE)$skills, error = function(e) list())
}

# force = TRUE replaces an edited copy too (backed up by .skill_install).
# lock = FALSE when the caller already holds the sync lock.
# planned: the copy's hash when the caller decided to install ("" for no
# copy). A copy that no longer matches is left alone and FALSE returned.
.skill_planned_changed <- function(current, planned) {
  !is.null(planned) && !identical(current %||% "", planned)
}

# The lock entry for a skill copy: the entry listing the path, else, for a
# Cloud install, the entry with the same skill ID. A path never joins an
# entry because of its folder name or its bytes; skills_copy() records the
# copies it makes.
.skill_entry_key <- function(state, relative, skill_id = NULL, server = NULL, variant = NULL) {
  match <- function(f) names(Filter(f, state$skills))
  keys <- match(function(e) relative %in% unlist(e$paths))
  if (!length(keys) && !is.null(skill_id)) keys <- match(function(e) .skill_same_cloud(e, skill_id, server, variant))
  if (length(keys)) keys[1] else NULL
}

# Whether a lock entry tracks this Cloud skill: same ID, server, and variant
.skill_same_cloud <- function(e, skill_id, server = NULL, variant = NULL) {
  identical(e$skill_id, skill_id) &&
    (is.null(server) || is.null(e$server) || identical(sub("/$", "", e$server), sub("/$", "", server))) &&
    identical(e$variant %||% "r", variant %||% e$variant %||% "r")
}

# prior: the lock as it was before a pull began. Decisions are judged
# against it, so writing one folder of a skill doesn't change how its other
# folders are judged; the write goes into the current lock.
.skill_package_install <- function(source, root, relative, name, force = FALSE, lock = TRUE, planned = NULL, prior = NULL) {
  if (lock) { held <- .skill_acquire(root); on.exit(unlink(held, recursive = TRUE)) }
  target <- .skill_path(root, relative); state <- .skill_load(root)
  key <- .skill_entry_key(state, relative) %||% paste0("package:", name)
  entry <- state$skills[[key]] %||% list(paths = list(), variant = "r")
  judged <- if (is.null(prior)) entry else {
    prior_key <- .skill_entry_key(prior, relative)
    if (is.null(prior_key)) list(paths = list()) else prior$skills[[prior_key]]
  }
  # A skill tracked on Cloud (your own, or a published version of a built-in)
  # keeps its content and identity: the package copy never replaces it, even
  # when forced
  if (!is.null(judged$skill_id) || !is.null(entry$skill_id)) return(FALSE)
  files <- .skill_scan(source); fresh <- .skill_hash(files)
  current <- if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL
  if (.skill_planned_changed(current, planned)) return(FALSE)
  # The lock's hash describes the copies at its paths; another copy of the
  # same skill (.agents/skills beside .claude/skills) has no entry yet
  expected <- if (relative %in% unlist(judged$paths)) judged$hash else NULL
  if (!force && !is.null(current) && !identical(current, expected %||% fresh)) {
    # No lock entry, but the folder holds a version the package shipped
    if (!is.null(expected) || !.skill_released_copy(target, name)) return(FALSE)
  }
  if (!identical(current, fresh)) .skill_install(root, relative, files, current)
  entry$paths <- as.list(unique(c(unlist(entry$paths), relative)))
  entry$hash <- fresh; entry$origin <- list(skill_id = paste0("framework:", name), hash = fresh)
  entry$skill_id <- NULL; entry$version <- NULL; entry$server <- NULL; entry$pending <- NULL
  state$skills[[key]] <- entry; .skill_save(root, state)
  TRUE
}

# force = TRUE replaces an edited copy too; clean names other hashes that
# count as unedited (the version the project's setup recorded).
.skill_cloud_install <- function(root, relative, entry, force = FALSE, clean = NULL, lock = TRUE, planned = NULL, prior = NULL) {
  if (lock) { held <- .skill_acquire(root); on.exit(unlink(held, recursive = TRUE)) }
  source <- entry$sync; files <- .skill_validate(entry$bundle)
  if (!identical(.skill_hash(files), source$hash)) stop("Cloud skill verification failed", call. = FALSE)
  state <- .skill_load(root)
  key <- .skill_entry_key(state, relative, source$skill_id, source$server, source$variant) %||%
    paste0("account:", source$server, ":", source$skill_id, ":", source$variant)
  tracked <- state$skills[[key]] %||% list(paths = list(), variant = source$variant)
  # Judged against the lock before the pull (see .skill_package_install())
  judged <- if (is.null(prior)) tracked else {
    prior_key <- .skill_entry_key(prior, relative, source$skill_id, source$server, source$variant)
    if (is.null(prior_key)) list(paths = list()) else prior$skills[[prior_key]]
  }
  # Never replace a copy's own or Cloud identity, and never move any
  # versioned skill (framework: IDs too) to an older version, even when forced
  # One identity is server, skill ID, and variant together
  if (!is.null(judged$skill_id)) {
    if (!.skill_same_cloud(judged, source$skill_id, source$server, source$variant)) return(FALSE)
    if (isTRUE(as.integer(judged$version %||% 0L) > as.integer(source$version %||% 0L))) return(FALSE)
  }
  target <- .skill_path(root, relative); current <- if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL
  if (.skill_planned_changed(current, planned)) return(FALSE)
  # A forced install resets an edited copy of your own skill to that same
  # skill's version (same or newer); the guards above refuse another
  # identity or an older version
  if (!force && !is.null(current) && !current %in% c(judged$hash %||% source$hash, clean)) return(FALSE)
  if (!identical(current, source$hash)) .skill_install(root, relative, files, current)
  tracked$paths <- as.list(unique(c(unlist(tracked$paths), relative)))
  for (name in names(source)) tracked[[name]] <- source[[name]]
  state$skills[[key]] <- tracked; .skill_save(root, state)
  TRUE
}

.skill_private <- function(root) {
  path <- .skill_path(root, ".framework/.gitignore")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  writeLines(unique(c(lines, "skills-backups/", "skills.sync.lock/")), path)
}
.skill_acquire <- function(root) {
  path <- .skill_path(root, ".framework/skills.sync.lock")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!dir.create(path, showWarnings = FALSE)) stop("Skill sync is locked. If the previous process stopped, remove .framework/skills.sync.lock and retry.", call. = FALSE)
  path
}
