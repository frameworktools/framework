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
.skill_hash <- function(files) {
  manifest <- "framework-skill-bundle-v1\n"
  for (f in .skill_validate(files)) {
    raw <- jsonlite::base64_dec(f$content)
    manifest <- paste0(manifest, f$path, "\t", .skill_sha(raw), "\t", if (isTRUE(f$executable)) "755" else "644", "\t", length(raw), "\n")
  }
  .skill_sha(charToRaw(manifest))
}

.skill_path <- function(root, relative) {
  if (!is.character(relative) || length(relative) != 1 || grepl("^[/\\\\]|^[A-Za-z]:", relative)) stop("Skill paths must be project-relative", call. = FALSE)
  parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
  if (!length(parts) || any(parts %in% c("", ".", ".."))) stop("Invalid skill path", call. = FALSE)
  path <- root
  for (part in parts) {
    path <- file.path(path, part)
    link <- Sys.readlink(path)
    if (!is.na(link) && nzchar(link)) stop("Skill paths cannot contain symlinks", call. = FALSE)
  }
  path
}

.skill_scan <- function(path) {
  files <- list()
  metadata_path <- file.path(path, ".framework-skill.json")
  executable_paths <- if (.Platform$OS.type == "windows" && file.exists(metadata_path)) {
    jsonlite::fromJSON(metadata_path, simplifyVector = FALSE)$executable_paths
  } else character()
  walk <- function(folder, prefix = "") {
    for (p in list.files(folder, all.files = TRUE, full.names = TRUE, no.. = TRUE)) {
      name <- basename(p)
      if (nzchar(Sys.readlink(p))) stop("Skill symlinks are unsupported", call. = FALSE)
      if (.skill_excluded(name)) next
      relative <- paste0(prefix, name)
      if (dir.exists(p)) walk(p, paste0(relative, "/")) else {
        info <- file.info(p)
        if (!identical(as.character(fs::file_info(p)$type), "file") || is.na(info$size) || info$size > 4 * 1024^2) stop("Invalid or oversized skill file", call. = FALSE)
        raw <- readBin(p, "raw", n = info$size)
        executable <- if (.Platform$OS.type == "windows") relative %in% unlist(executable_paths) else bitwAnd(as.integer(info$mode), 73L) != 0L
        files[[length(files) + 1L]] <<- list(path = relative, content = jsonlite::base64_enc(raw), executable = executable)
      }
    }
  }
  walk(path)
  .skill_validate(files)
}

.skill_load <- function(root) {
  path <- .skill_path(root, ".framework/skills.lock.json")
  state <- if (file.exists(path)) jsonlite::fromJSON(path, simplifyVector = FALSE) else list(schema = 1L, skills = list())
  if (!identical(as.integer(state$schema), 1L) || !is.list(state$skills)) stop("Unsupported skill lock file", call. = FALSE)
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

.skill_install <- function(root, paths, files, expected) {
  files <- .skill_validate(files); swaps <- list(); success <- FALSE
  on.exit({
    if (!success) for (swap in rev(swaps)) {
      if (dir.exists(swap$backup)) { unlink(swap$target, recursive = TRUE); file.rename(swap$backup, swap$target) }
      else if (!dir.exists(swap$stage) && !swap$existed) unlink(swap$target, recursive = TRUE)
      unlink(swap$stage, recursive = TRUE)
    }
  })
  for (relative in paths) {
    target <- .skill_path(root, relative)
    if (dir.exists(target) && !identical(.skill_hash(.skill_scan(target)), expected)) stop("Local skill changed during sync", call. = FALSE)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    stage <- tempfile(".skill-stage-", tmpdir = dirname(target)); dir.create(stage)
    backup <- .skill_path(root, paste0(".framework/skills-backups/", .skill_uuid()))
    if (dir.exists(target)) { .skill_private(root); dir.create(dirname(backup), recursive = TRUE, showWarnings = FALSE) }
    swaps[[length(swaps) + 1L]] <- list(target = target, stage = stage, backup = backup, existed = dir.exists(target))
    if (dir.exists(target)) {
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
    if (.Platform$OS.type == "windows") {
      mode_path <- file.path(stage, ".framework-skill.json")
      executable_paths <- lapply(Filter(function(f) isTRUE(f$executable), files), `[[`, "path")
      if (length(executable_paths)) writeLines(jsonlite::toJSON(list(executable_paths = executable_paths), auto_unbox = TRUE), mode_path)
      else if (file.exists(mode_path)) unlink(mode_path)
    }
    if (!identical(.skill_hash(.skill_scan(stage)), .skill_hash(files))) stop("Staged skill verification failed", call. = FALSE)
  }
  for (swap in swaps) {
    if (swap$existed && !identical(.skill_hash(.skill_scan(swap$target)), expected)) stop("Local skill changed during sync", call. = FALSE)
    if (swap$existed && !file.rename(swap$target, swap$backup)) stop("Could not back up skill", call. = FALSE)
    if (!file.rename(swap$stage, swap$target)) stop("Could not install skill", call. = FALSE)
  }
  success <- TRUE
}

#' Synchronize a Skill Directory
#'
#' Synchronize a versioned skill bundle with Framework Cloud. Divergent changes
#' return a conflict without replacing files. Companion files and executable
#' modes are included. Untracked skills become private account skills.
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
  key <- names(Filter(function(e) path %in% unlist(e$paths), state$skills))[1]
  if (!length(key) || is.na(key)) key <- path
  entry <- state$skills[[key]] %||% list(paths = list(path), variant = variant)
  server <- sub("/$", "", .fw_cloud_url()); token <- .fw_require_token(url = server)
  if (!is.null(entry$server) && !identical(entry$server, server)) stop("Skill tracks another server", call. = FALSE)
  if (!is.null(skill_id) && !is.null(entry$skill_id) && !identical(skill_id, entry$skill_id)) stop("Skill identity mismatch", call. = FALSE)
  variant <- entry$variant %||% variant; paths <- unlist(entry$paths, use.names = FALSE)
  bundles <- lapply(paths, function(p) { target <- .skill_path(root, p); if (dir.exists(target)) .skill_scan(target) else NULL })
  hashes <- vapply(bundles, function(b) if (is.null(b)) "" else .skill_hash(b), "")
  if (length(unique(hashes)) > 1) stop("Assistant skill copies diverged. Reconcile aliases before syncing.", call. = FALSE)
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
    remote <- .fw_api("/api/v1/skills/sync", token, method = "POST", url = server, body = list(
      request_id = pending$request_id, skill_id = remote$skill_id,
      expected_version = expected, variant = variant,
      bundle = files, client = list(app = "framework-r")
    ))
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
  lf <- raw[!(raw == as.raw(13) & c(utils::tail(raw, -1), as.raw(0)) == as.raw(10))]
  any(c(.skill_sha(raw), .skill_sha(lf)) %in% unlist(history))
}

.skill_history <- function() {
  path <- system.file("templates", "skill-history.json", package = "framework")
  if (!nzchar(path)) return(list())
  tryCatch(jsonlite::read_json(path, simplifyVector = FALSE)$skills, error = function(e) list())
}

# force = TRUE replaces an edited copy too (backed up by .skill_install).
# lock = FALSE when the caller already holds the sync lock.
.skill_package_install <- function(source, root, relative, name, force = FALSE, lock = TRUE) {
  if (lock) { held <- .skill_acquire(root); on.exit(unlink(held, recursive = TRUE)) }
  target <- .skill_path(root, relative); state <- .skill_load(root)
  keys <- names(Filter(function(e) relative %in% unlist(e$paths), state$skills)); key <- if (length(keys)) keys[1] else paste0("package:", name)
  entry <- state$skills[[key]] %||% list(paths = list(), variant = "r")
  if (!force && !is.null(entry$skill_id) && !startsWith(entry$skill_id, "framework:")) return(FALSE)
  files <- .skill_scan(source); fresh <- .skill_hash(files)
  current <- if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL
  # The lock's hash describes the copies at its paths; another copy of the
  # same skill (.agents/skills beside .claude/skills) has no entry yet
  expected <- if (relative %in% unlist(entry$paths)) entry$hash else NULL
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
.skill_cloud_install <- function(root, relative, entry, force = FALSE, clean = NULL, lock = TRUE) {
  if (lock) { held <- .skill_acquire(root); on.exit(unlink(held, recursive = TRUE)) }
  source <- entry$sync; files <- .skill_validate(entry$bundle)
  if (!identical(.skill_hash(files), source$hash)) stop("Cloud skill verification failed", call. = FALSE)
  state <- .skill_load(root)
  keys <- names(Filter(function(e) relative %in% unlist(e$paths), state$skills))
  key <- if (length(keys)) keys[1] else paste0("account:", source$server, ":", source$skill_id, ":", source$variant)
  tracked <- state$skills[[key]] %||% list(paths = list(), variant = source$variant)
  target <- .skill_path(root, relative); current <- if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL
  if (!force && !is.null(current) && !current %in% c(tracked$hash %||% source$hash, clean)) return(FALSE)
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
