# The skills lock, .framework/skills.lock.json, schema 2: one entry per skill
# identity, a record per copy, and the hashes known for the identity. See
# docs/architecture/skills-lock-v2.md. A schema 1 lock is read and migrated in
# memory; it is written as schema 2 only when a command changes it.
# framework-py: skills_lock.py; fw: internal/skills/lock.go.

.skill_lock_file <- ".framework/skills.lock.json"
.skill_lock_schema <- 2L

# An error a skill command stops with before writing anything. `code` is the
# language-neutral error code the scenarios compare.
.skill_stop <- function(code, message, ...) {
  stop(errorCondition(message, class = c(paste0("fw_skill_", code), "fw_skill_error"), code = code, ..., call = NULL))
}

# Hashes sorted by byte value, unique, without NA
.skill_known <- function(...) {
  x <- unlist(list(...), use.names = FALSE)
  x <- unique(as.character(x[!is.na(x) & nzchar(x)]))
  sort(x, method = "radix")
}

.skill_identity <- function(kind, skill_id = NULL, variant = "r", server = NULL) {
  identity <- list(kind = kind)
  if (!is.null(skill_id)) identity$skill_id <- skill_id
  identity$variant <- variant %||% "r"
  if (identical(kind, "cloud")) identity$server <- sub("/$", "", server %||% "")
  identity
}

# The lock key for an identity. A local entry's key names the path it
# started from.
.skill_key <- function(identity, path = NULL) {
  switch(identity$kind,
    builtin = , inline = paste0(identity$skill_id, "@", identity$variant),
    cloud = paste0(identity$server, "/", identity$skill_id, "@", identity$variant),
    local = paste0("local:", path),
    stop("Unknown skill identity kind: ", identity$kind, call. = FALSE))
}

.skill_same_identity <- function(a, b) {
  identical(a$kind, b$kind) && identical(a$skill_id, b$skill_id) && identical(a$variant, b$variant) &&
    (!identical(a$kind, "cloud") || identical(a$server, b$server))
}

.skill_entry_new <- function(identity) {
  list(identity = identity, base = NULL, known = character(), copies = stats::setNames(character(), character()))
}

# The base a source gives an entry: what push sends as its base
.skill_base_of <- function(source) {
  cloud <- identical(source$channel, "cloud")
  list(channel = source$channel, hash = source$hash,
       version = if (cloud) as.integer(source$version) else NULL,
       server = if (cloud) sub("/$", "", source$server %||% "") else NULL)
}

.skill_same_base <- function(a, b) {
  norm <- function(x) if (is.null(x)) NULL else
    list(x$channel, x$hash, if (is.null(x$version)) NA_integer_ else as.integer(x$version), x$server %||% NA_character_)
  identical(norm(a), norm(b))
}

# Read the lock. Returns schema 2, migrated from schema 1 when needed. A
# missing file is an empty lock. A schema above 2 stops with an upgrade
# message (code lock_schema_unsupported).
.skill_load <- function(root) {
  path <- .skill_path(root, .skill_lock_file)
  if (!file.exists(path)) return(list(schema = .skill_lock_schema, skills = list()))
  raw <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
                  error = function(e) stop("Unsupported skill lock file (", conditionMessage(e), ")", call. = FALSE))
  schema <- suppressWarnings(as.integer(raw$schema %||% NA))
  if (length(schema) == 1 && !is.na(schema) && schema > .skill_lock_schema) {
    .skill_stop("lock_schema_unsupported", paste0(
      "This project's skills lock (.framework/skills.lock.json) uses schema ", schema,
      ". Update framework to a version that reads it."))
  }
  if (length(schema) != 1 || is.na(schema) || !schema %in% c(1L, 2L) || !is.list(raw$skills)) {
    stop("Unsupported skill lock file", call. = FALSE)
  }
  if (identical(schema, 1L)) .skill_migrate(raw) else .skill_lock_normalize(raw)
}

# A schema 2 lock as read: fields in their R types, keys rebuilt from
# identities, and a path in at most one entry
.skill_lock_normalize <- function(raw) {
  skills <- list(); seen <- character()
  for (old_key in names(raw$skills)) {
    e <- raw$skills[[old_key]]
    id <- e$identity
    if (!is.list(id) || is.null(id$kind)) stop("Unsupported skill lock file", call. = FALSE)
    identity <- .skill_identity(id$kind, id$skill_id, id$variant %||% "r", id$server)
    copies <- e$copies %||% list()
    records <- vapply(copies, function(r) as.character(r$hash %||% NA_character_), "")
    records <- records[!names(records) %in% seen]
    seen <- c(seen, names(records))
    entry <- .skill_entry_new(identity)
    if (is.list(e$base)) {
      entry$base <- list(channel = e$base$channel, hash = e$base$hash,
                         version = if (is.null(e$base$version)) NULL else as.integer(e$base$version),
                         server = e$base$server)
    }
    entry$known <- .skill_known(e$known)
    entry$copies <- records
    if (is.list(e$pending)) entry$pending <- e$pending
    key <- if (identical(identity$kind, "local")) {
      if (startsWith(old_key, "local:")) old_key else .skill_key(identity, names(records)[1] %||% old_key)
    } else .skill_key(identity)
    skills[[key]] <- if (is.null(skills[[key]])) entry else .skill_entry_merge(skills[[key]], entry)
  }
  list(schema = .skill_lock_schema, skills = skills)
}

# Two entries for one identity become one: every copy, every known hash
.skill_entry_merge <- function(a, b) {
  extra <- b$copies[!names(b$copies) %in% names(a$copies)]
  a$copies <- c(a$copies, extra)
  a$known <- .skill_known(a$known, b$known)
  a$base <- a$base %||% b$base
  a$pending <- a$pending %||% b$pending
  a
}

# Schema 1 to schema 2, in memory. Pure; a schema 1 lock is never rejected
# for its age. Each schema 1 entry maps to one identity and keeps its own
# record for each of its paths. Entries that map to one identity merge when
# they agree on the version they last synced; two that disagree (a package
# copy and a Cloud copy of one built-in, or two Cloud versions) stop with
# lock_migrate_conflict, naming both, and nothing is written.
.skill_migrate <- function(state) {
  skills <- list(); from <- list(); seen <- character()
  for (old_key in names(state$skills)) {
    e <- state$skills[[old_key]]
    variant <- e$variant %||% "r"
    id <- e$skill_id; origin <- e$origin
    if (!is.null(id)) {
      server <- sub("/$", "", e$server %||% "")
      identity <- if (startsWith(id, "framework:")) .skill_identity("builtin", id, variant)
        else .skill_identity("cloud", id, variant, server)
      base <- if (is.null(e$hash)) NULL
        else list(channel = "cloud", hash = e$hash, version = as.integer(e$version %||% 0L), server = server)
    } else if (!is.null(origin$skill_id) && startsWith(origin$skill_id, "framework:")) {
      identity <- .skill_identity("builtin", origin$skill_id, variant)
      base <- if (is.null(origin$hash)) NULL else list(channel = "package", hash = origin$hash, version = NULL, server = NULL)
    } else {
      identity <- .skill_identity("local", variant = variant)
      base <- NULL
    }
    paths <- unlist(e$paths, use.names = FALSE)
    paths <- paths[!paths %in% seen]
    seen <- c(seen, paths)
    record <- e$hash %||% origin$hash %||% NA_character_
    entry <- .skill_entry_new(identity)
    entry$base <- base
    entry$known <- .skill_known(e$hash, origin$hash)
    entry$copies <- stats::setNames(rep(as.character(record), length(paths)), paths)
    if (is.list(e$pending)) entry$pending <- e$pending
    key <- .skill_key(identity, paths[1])
    if (!is.null(skills[[key]])) {
      other <- skills[[key]]
      if (!.skill_same_base(other$base, entry$base) || (!is.null(other$pending) && !is.null(entry$pending))) {
        .skill_stop("lock_migrate_conflict", paste0(
          "Entries \"", from[[key]], "\" and \"", old_key, "\" in .framework/skills.lock.json both track ", key,
          " at different versions. Delete the entry for the copy you don't keep from the file, then run the command again."))
      }
      entry <- .skill_entry_merge(other, entry)
    } else {
      from[[key]] <- old_key
    }
    skills[[key]] <- entry
  }
  list(schema = .skill_lock_schema, skills = skills)
}

# The lock as JSON: schema 2, keys and paths sorted, known as arrays
.skill_lock_json <- function(state) {
  keys <- sort(as.character(names(state$skills)), method = "radix")
  skills <- lapply(state$skills[keys], function(e) {
    id <- e$identity
    identity <- list(kind = id$kind)
    if (!is.null(id$skill_id)) identity$skill_id <- id$skill_id
    identity$variant <- id$variant
    if (identical(id$kind, "cloud")) identity$server <- id$server
    base <- if (is.null(e$base)) NULL else
      list(channel = e$base$channel, hash = e$base$hash, version = e$base$version, server = e$base$server)
    paths <- sort(as.character(names(e$copies)), method = "radix")
    copies <- lapply(paths, function(p) list(hash = if (is.na(e$copies[[p]])) NULL else e$copies[[p]]))
    names(copies) <- paths
    if (!length(copies)) copies <- structure(list(), names = character())
    out <- list(identity = identity, base = base, known = as.list(.skill_known(e$known)), copies = copies)
    if (!is.null(e$pending)) out$pending <- e$pending
    out
  })
  if (!length(skills)) skills <- structure(list(), names = character())
  jsonlite::toJSON(list(schema = .skill_lock_schema, skills = skills),
                   auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
}

.skill_save <- function(root, state) {
  path <- .skill_path(root, .skill_lock_file)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .skill_private(root)
  temp <- tempfile(tmpdir = dirname(path)); on.exit(unlink(temp))
  writeLines(.skill_lock_json(state), temp, useBytes = TRUE)
  fs::file_move(temp, path)
}

# Save `after` only when it differs from `before` (both as read and
# migrated), so a command that changes nothing leaves a schema 1 file as it is
.skill_save_changed <- function(root, before, after) {
  if (identical(as.character(.skill_lock_json(before)), as.character(.skill_lock_json(after)))) return(invisible(FALSE))
  .skill_save(root, after)
  invisible(TRUE)
}

# The key of the entry tracking a path, matched by spelling or, through
# `alias`, by filesystem identity; NULL when no entry tracks it
.skill_owner <- function(state, path, alias = identity) {
  for (key in names(state$skills)) if (path %in% names(state$skills[[key]]$copies)) return(key)
  target <- alias(path)
  for (key in names(state$skills)) {
    for (p in names(state$skills[[key]]$copies)) if (identical(alias(p), target)) return(key)
  }
  NULL
}

# Known bundle hashes of each built-in this package has shipped, for a
# variant: inst/templates/skill-history.json (schema 2), generated by
# data-raw/skill_history.R
.skill_history <- function(name, variant = "r") {
  path <- system.file("templates", "skill-history.json", package = "framework")
  if (!nzchar(path)) return(character())
  history <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) list())
  if (!identical(as.integer(history$schema %||% 0L), 2L)) return(character())
  .skill_known(history$skills[[name]][[variant]])
}
