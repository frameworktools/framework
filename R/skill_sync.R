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

.skill_uuid <- function() {
  x <- as.character(openssl::rand_bytes(16)); x <- paste0(x, collapse = "")
  # Set the UUID version and variant bits without adding a dependency.
  paste0(substr(x, 1, 8), "-", substr(x, 9, 12), "-4", substr(x, 14, 16), "-a", substr(x, 18, 20), "-", substr(x, 21, 32))
}

# Undo installs: put each backup back. The copy an install wrote is never
# deleted: it moves to .framework/skills-backups/ (swap$displaced), since it
# may hold an edit made after it was written. Each swap is an environment,
# so an undone swap is marked and a second rollback of the same swap does
# nothing. Returns the swaps that could not be undone.
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
        if (dir.exists(aside)) .skill_displace(swap, aside)
      } else if (dir.exists(aside)) {
        file.rename(aside, swap$target)
      }
    } else if (isTRUE(swap$installed)) {
      ok <- .skill_displace(swap, swap$target)
      if (ok) swap$installed <- FALSE
    }
    if (!is.null(swap$stage)) { unlink(swap$stage, recursive = TRUE); swap$stage <- NULL }
    if (!ok) failed <- c(list(swap), failed)
  }
  failed
}

# Move a copy an install wrote into .framework/skills-backups/, recording
# where in swap$displaced
.skill_displace <- function(swap, folder) {
  relative <- paste0(".framework/skills-backups/", .skill_uuid())
  target <- file.path(swap$root, relative)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  ok <- isTRUE(file.rename(folder, target))
  if (ok) swap$displaced <- relative
  ok
}

# Lines naming where each undone copy's written files went
.skill_displaced_lines <- function(swaps) {
  swaps <- Filter(function(s) !is.null(s$displaced), swaps)
  vapply(swaps, function(s) paste0("  ", s$path, " (the copy written before the failure is in ", s$displaced, ")"), "")
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
.skill_install_failed <- function(cause, lost, swaps = list()) {
  force(lost)   # the rollback runs here, before its displaced copies are named
  reason <- if (inherits(cause, "interrupt")) "interrupted" else sub("\\.$", "", conditionMessage(cause))
  displaced <- .skill_displaced_lines(swaps)
  message <- if (length(lost)) {
    paste(c(paste0("Could not install skill (", reason, "), and these copies could not be restored:"),
            .skill_lost_lines(lost), displaced), collapse = "\n")
  } else if (length(displaced)) {
    paste(c(paste0(reason, ". The copies were put back; what was written is kept:"), displaced), collapse = "\n")
  } else reason
  stop(errorCondition(message, class = "fw_skill_install_error", reason = reason, lost = lost,
                      displaced = Filter(function(s) !is.null(s$displaced), swaps), call = NULL))
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
      swap$path <- relative; swap$target <- target; swap$existed <- existed; swap$root <- root
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
  if (!is.null(outcome)) .skill_install_failed(outcome, .skill_rollback(swaps), swaps)
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
  held <- .skill_acquire(root)
  on.exit(unlink(held, recursive = TRUE))
  state <- .skill_load(root)
  loaded <- state
  # The path as typed may not contain links (checked before any
  # resolution, which would follow them). Then the lock's spelling: a case
  # alias of a tracked path is that path, found by filesystem identity.
  .skill_path(root, path)
  disk <- .skill_disk(root)
  # The entry tracking the path; never an entry whose key merely matches it
  key <- .skill_owner(state, path, disk$alias)
  if (!is.null(key)) {
    entry <- state$skills[[key]]
    path <- .skill_lock_path(entry, path, disk$alias)
  } else {
    path <- .skill_copy_spelling(root, path)
    entry <- .skill_entry_new(.skill_identity("local", variant = variant))
    entry$copies[path] <- NA_character_
    key <- .skill_key(entry$identity, path); n <- 1L
    while (key %in% names(state$skills)) { n <- n + 1L; key <- paste0(.skill_key(entry$identity, path), "#", n) }
  }
  server <- .skill_server(root); token <- .fw_require_token(url = server)
  id <- entry$identity
  if (identical(id$kind, "cloud") && !identical(id$server, server)) stop("Skill tracks another server", call. = FALSE)
  # On Cloud: your own skill, or a built-in last delivered by Cloud
  on_cloud <- identical(id$kind, "cloud") || (identical(id$kind, "builtin") && identical(entry$base$channel, "cloud"))
  if (!is.null(skill_id) && on_cloud && !identical(skill_id, id$skill_id)) stop("Skill identity mismatch", call. = FALSE)
  variant <- id$variant; paths <- names(entry$copies)
  bundles <- lapply(paths, function(p) { target <- .skill_path(root, p); if (!identical(.skill_kind(target), "missing")) .skill_scan(target) else NULL })
  hashes <- vapply(bundles, function(b) if (is.null(b)) "" else .skill_hash(b), "")
  if (length(unique(hashes)) > 1) {
    # A missing copy is never the one to keep; an edited copy (one that
    # differs from its record) is offered first
    present <- paths[nzchar(hashes)]
    edited <- present[hashes[nzchar(hashes)] != unname(entry$copies[present]) | is.na(entry$copies[present])]
    keep <- c(edited, setdiff(present, edited))[1]
    other <- if (all(nzchar(hashes))) paths[which(hashes != hashes[match(keep, paths)])[1]] else paths[!nzchar(hashes)][1]
    stop(.skill_diverged_message(keep, other, missing = !all(nzchar(hashes)), root = root,
                                 others = setdiff(paths, keep)), call. = FALSE)
  }
  local_hash <- if (nzchar(hashes[1])) hashes[1] else NULL; files <- bundles[[1]]
  remote_id <- if (on_cloud) id$skill_id else skill_id
  remote <- NULL
  if (!is.null(remote_id)) {
    remote <- .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(remote_id, reserved = TRUE), "?variant=", variant), token, url = server)
  } else if (identical(id$kind, "builtin") && !is.null(entry$base)) {
    # Cloud answers 409 for a built-in copy it never published (the package
    # shipped its own text): an edited one is pushed as a new skill of your own
    remote <- tryCatch(
      .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(id$skill_id, reserved = TRUE), "?variant=", variant, "&hash=", entry$base$hash), token, url = server),
      httr2_http_409 = function(e) NULL)
  }
  if (!is.null(remote) && !identical(.skill_hash(remote$bundle), remote$hash)) stop("Cloud skill verification failed", call. = FALSE)
  base <- entry$base$hash
  action <- if (is.null(remote)) { if (is.null(files)) "missing" else if (!on_cloud && identical(local_hash, base)) "unchanged" else "push" }
  else if (identical(local_hash, remote$hash)) { if (!on_cloud) "adopt" else "unchanged" }
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
    expected <- if (identical(resolve, "local") && !is.null(remote) && !isTRUE(remote$system)) remote$version
      else (if (on_cloud) entry$base$version) %||% remote$version %||% 0L
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
    identity <- if (startsWith(remote$skill_id, "framework:")) .skill_identity("builtin", remote$skill_id, variant)
      else .skill_identity("cloud", remote$skill_id, variant, server)
    F <- entry
    F$identity <- identity
    F$base <- list(channel = "cloud", hash = remote$hash, version = as.integer(remote$version), server = server)
    F$copies[] <- remote$hash
    F$known <- if (.skill_same_identity(identity, entry$identity)) .skill_known(entry$known, remote$hash) else .skill_known(remote$hash)
    F$pending <- NULL
    new_key <- .skill_key(identity, paths[1])
    state$skills[[key]] <- NULL
    state$skills[[new_key]] <- if (!is.null(state$skills[[new_key]])) .skill_entry_merge(F, state$skills[[new_key]]) else F
    # A sync that changes nothing leaves a schema 1 lock as it is
    .skill_save_changed(root, loaded, state)
    result$skill_id <- remote$skill_id; result$version <- remote$version
  }
  result
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
