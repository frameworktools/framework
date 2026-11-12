# A project's data registry (the catalog in the settings' data section),
# kept in step with Framework Cloud. pull_data_registry() brings Cloud's
# entries into the settings; push_data_registry() sends the project's entries
# back. Only the definitions travel: never the data files, and never their
# hashes, which stay in framework.db.
# framework-py: data_registry.py; fw: fw data pull / fw data push.

.data_registry_lock_file <- ".framework/data.lock.json"

# The fields an entry carries to and from Framework Cloud. Any other field in
# a local entry stays local.
.data_registry_fields <- c("path", "type", "delimiter", "locked", "private", "description", "stata_names")

.data_registry_types <- c(
  "csv", "tsv", "rds", "excel", "xlsx", "xls", "parquet", "stata", "dta",
  "spss", "sav", "zsav", "spss_por", "por", "sas", "sas7bdat", "sas7bcat", "sas_xpt", "xpt"
)
.data_registry_delimiters <- c("comma", "tab", "semicolon", "space")
.data_registry_name_pattern <- "^[A-Za-z0-9_][A-Za-z0-9_-]*([.][A-Za-z0-9_][A-Za-z0-9_-]*)*$"

# Problems with a spec's data section (name -> entry), as spec_check() and
# the schema's data_entry see them
#' @keywords internal
.data_registry_problems <- function(data) {
  if (is.null(data) || length(data) == 0) return(character())
  if (!is.list(data) || is.null(names(data)) || any(!nzchar(names(data)))) {
    return("data must be an object keyed by catalog name, not a list")
  }
  problems <- character()
  add <- function(...) problems <<- c(problems, sprintf(...))
  is_string <- function(x) is.character(x) && length(x) == 1 && !is.na(x)
  for (name in names(data)) {
    entry <- data[[name]]
    where <- paste0("data.", name)
    if (!grepl(.data_registry_name_pattern, name)) add("data: invalid catalog name '%s'", name)
    if (!is.list(entry)) {
      add("%s: must be an entry with a path", where)
      next
    }
    for (field in setdiff(names(entry), .data_registry_fields)) add("%s: unknown field '%s'", where, field)
    if (!is_string(entry$path) || !nzchar(entry$path)) {
      add("%s: missing path", where)
    } else if (!.spec_is_safe_path(entry$path)) {
      add("%s: path '%s' must be relative and stay inside the project", where, entry$path)
    }
    if (!is.null(entry$type) && !(is_string(entry$type) && entry$type %in% .data_registry_types)) {
      add("%s: type must be one of %s", where, paste(.data_registry_types, collapse = ", "))
    }
    if (!is.null(entry$delimiter) && !(is_string(entry$delimiter) && entry$delimiter %in% .data_registry_delimiters)) {
      add("%s: delimiter must be comma, tab, semicolon, or space", where)
    }
    for (flag in c("locked", "private")) {
      if (!is.null(entry[[flag]]) && !isTRUE(entry[[flag]]) && !isFALSE(entry[[flag]])) {
        add("%s.%s must be true or false", where, flag)
      }
    }
    if (!is.null(entry$description) && !is_string(entry$description)) add("%s.description must be text", where)
    if (!is.null(entry$stata_names) && length(entry$stata_names) > 0 &&
        (!is.list(entry$stata_names) || is.null(names(entry$stata_names)) ||
         !all(vapply(entry$stata_names, is_string, logical(1))))) {
      add("%s.stata_names must map column names to Stata names", where)
    }
  }
  # A name that is also a group of other names can't be written nested
  for (name in names(data)) {
    inside <- names(data)[startsWith(names(data), paste0(name, "."))]
    if (length(inside)) add("data: '%s' is an entry, so '%s' can't be inside it", name, inside[1])
  }
  problems
}

# A spec's data section (dot-notation names) as the nested catalog the
# settings hold: inputs.raw.survey becomes inputs: raw: survey:
#' @keywords internal
.data_catalog_nest <- function(data) {
  catalog <- list()
  for (name in names(data)) {
    entry <- data[[name]]
    if (is.null(entry)) next
    catalog <- .data_catalog_set(catalog, strsplit(name, ".", fixed = TRUE)[[1]], entry)
  }
  catalog
}

.data_catalog_set <- function(node, keys, value) {
  if (!is.list(node)) node <- list()
  node[[keys[1]]] <- if (length(keys) == 1) value else .data_catalog_set(node[[keys[1]]], keys[-1], value)
  node
}

# Every entry in a settings data section, by dot-notation name, as data_list()
# finds them: nested, mixed, and flat keys, and path shorthands. Entries
# without a path are left out.
#' @keywords internal
.data_catalog_entries <- function(catalog, prefix = "") {
  entries <- list()
  if (!is.list(catalog)) return(entries)
  for (key in names(catalog)) {
    item <- catalog[[key]]
    name <- if (nzchar(prefix)) paste(prefix, key, sep = ".") else key
    if (is.character(item) && length(item) == 1) {
      entries[[name]] <- list(path = item)
    } else if (is.list(item) && !is.null(item$path)) {
      entries[[name]] <- item
    } else if (is.list(item) && !.fw_pathless_entry(item)) {
      entries <- c(entries, .data_catalog_entries(item, name))
    }
  }
  entries
}

# An entry as a registry row: its name and the fields that travel
.data_registry_row <- function(name, entry) {
  row <- list(name = name)
  for (field in .data_registry_fields) {
    value <- entry[[field]]
    if (is.null(value) || (is.atomic(value) && length(value) == 1 && is.na(value))) next
    if (field %in% c("locked", "private")) value <- isTRUE(value)
    if (identical(field, "stata_names")) {
      if (length(value) == 0) next
      value <- as.list(value)
    }
    row[[field]] <- value
  }
  if (is.null(row$locked)) row$locked <- FALSE
  row
}

# What counts as a change: every field that travels
.data_registry_key <- function(row) {
  text <- function(x) if (is.null(x) || length(x) == 0) "" else as.character(x)[1]
  names_map <- row$stata_names %||% list()
  names_map <- if (length(names_map)) {
    names_map <- names_map[order(names(names_map))]
    paste(names(names_map), unlist(names_map), sep = "=", collapse = ";")
  } else ""
  c(text(row$path), text(row$type), text(row$delimiter), tolower(as.character(isTRUE(row$locked))),
    if (is.null(row$private)) "" else tolower(as.character(isTRUE(row$private))), text(row$description), names_map)
}

.data_registry_same <- function(a, b) identical(.data_registry_key(a), .data_registry_key(b))

# How `to` differs from `from`, one item per field: "path a -> b" for the
# short fields, "description changed" or "stata_names changed" for the long
# ones
.data_registry_diff <- function(from, to) {
  a <- .data_registry_key(from)
  b <- .data_registry_key(to)
  shown <- function(x) if (nzchar(x)) x else "none"
  parts <- vapply(which(a != b), function(i) {
    field <- .data_registry_fields[i]
    if (field %in% c("description", "stata_names")) paste(field, "changed")
    else paste0(field, " ", shown(a[i]), " -> ", shown(b[i]))
  }, "")
  paste(parts, collapse = ", ")
}

.data_registry_names <- function(rows) paste(vapply(rows, `[[`, "", "name"), collapse = ", ")

# The settings file and where its data section lives: inline (under
# default: when the file has environments) or in a split file such as
# settings/data.yml
.data_registry_location <- function(root) {
  settings_file <- .get_settings_file(root)
  if (is.null(settings_file)) stop("Not a Framework project (no settings.yml): ", root, call. = FALSE)
  raw <- .fw_read_yaml(settings_file)
  if (!is.list(raw)) raw <- list()
  env_key <- if (is.list(raw$default)) "default" else NULL
  config <- if (is.null(env_key)) raw else raw$default
  source <- config$data
  if (is.character(source) && length(source) == 1) {
    file <- if (.fw_is_absolute_path(source)) source else file.path(root, source)
    content <- if (file.exists(file)) .fw_read_yaml(file) else NULL
    keys <- if (is.list(content) && is.list(content$default) && "data" %in% names(content$default)) c("default", "data")
      else if (is.list(content) && "data" %in% names(content)) "data"
      else if (is.list(content) && length(content)) character()
      else "data"
    catalog <- if (length(keys)) content[[keys]] else content
    return(list(file = file, keys = keys, catalog = .data_registry_map(catalog)))
  }
  list(file = settings_file, keys = c(env_key, "data"), catalog = .data_registry_map(source))
}

# A data section as a map. An empty one may be read as a sequence (`data: []`).
.data_registry_map <- function(x) {
  if (!is.list(x) || !length(x)) return(list())
  x
}

# The project's entries as registry rows, by name
.data_registry_local <- function(root) {
  catalog <- tryCatch(.data_registry_location(root)$catalog, error = function(e) list())
  entries <- .data_catalog_entries(catalog)
  rows <- list()
  for (name in names(entries)) rows[[name]] <- .data_registry_row(name, entries[[name]])
  rows
}

# Write Cloud's rows into the settings' data section, each where its entry
# already is (nested, mixed, or flat keys), else nested by name. Fields that
# don't travel (anything local-only) are kept. Only the fields that change
# are rewritten, so comments elsewhere in the file, the data block included,
# stay. When an edit can't be made in place, the whole data block is
# rewritten instead.
.data_registry_write <- function(root, rows) {
  location <- .data_registry_location(root)
  catalog <- location$catalog
  edits <- list()
  edit <- function(keys, value) edits[[length(edits) + 1]] <<- list(keys = keys, value = value)
  for (row in rows) {
    parts <- strsplit(row$name, ".", fixed = TRUE)[[1]]
    keys <- .data_catalog_find(catalog, parts)
    before <- if (is.null(keys)) NULL else catalog[[keys]]
    entry <- if (is.list(before)) before[setdiff(names(before), .data_registry_fields)] else list()
    for (field in .data_registry_fields) {
      value <- row[[field]]
      if (identical(field, "locked") && !isTRUE(value)) value <- NULL
      if (!is.null(value)) entry[[field]] <- value
    }
    entry <- entry[c(intersect(.data_registry_fields, names(entry)), setdiff(names(entry), .data_registry_fields))]
    if (is.list(before)) {
      for (field in .data_registry_fields) {
        if (!identical(before[[field]], entry[[field]])) edit(c(keys, field), entry[[field]])
      }
    } else if (!is.null(keys)) {
      edit(keys, entry)
    } else {
      # A new entry goes into the deepest group that already exists
      depth <- 0L
      node <- catalog
      while (depth < length(parts) - 1L && is.list(node[[parts[depth + 1L]]]) &&
             is.null(node[[parts[depth + 1L]]]$path)) {
        node <- node[[parts[depth + 1L]]]
        depth <- depth + 1L
      }
      # parts after the existing groups; parts[-seq_len(0)] would be empty
      rest <- parts[seq.int(depth + 1L, length(parts))]
      edit(parts[seq_len(depth + 1L)], .data_catalog_set(list(), rest, entry)[[rest[1]]])
    }
    catalog <- .data_catalog_set(catalog, keys %||% parts, entry)
  }
  if (!length(location$keys)) {
    return(.fw_write_yaml(list(data = catalog), location$file))
  }
  # An empty data section, such as a new project's `data: []`, has nothing to
  # edit in place, so the whole block is written
  text <- if (file.exists(location$file) && length(location$catalog)) {
    readChar(location$file, file.info(location$file)$size, useBytes = TRUE)
  }
  for (e in edits) {
    if (is.null(text)) break
    text <- .fw_yaml_set_text(text, c(location$keys, e$keys), e$value, rewrite = FALSE)
  }
  if (is.null(text)) {
    .fw_yaml_set(location$file, location$keys, catalog)
  } else {
    .fw_write_text(text, location$file)
  }
}

.data_registry_lock_read <- function(root) {
  path <- file.path(root, .data_registry_lock_file)
  if (!file.exists(path)) return(list())
  tryCatch(jsonlite::read_json(path), error = function(e) list())
}

.data_registry_lock_write <- function(root, revision, server) {
  path <- file.path(root, .data_registry_lock_file)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  data <- list(schema = 1L, revision = revision, server = server,
               updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  writeLines(jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE), path, useBytes = TRUE)
}

.data_registry_request <- function(path, connection, method = "GET", body = NULL) {
  tryCatch(
    .fw_api(path, connection$token, method = method, body = body, url = connection$server),
    httr2_http_404 = function(e) {
      stop("This Framework Cloud server has no data registry endpoint yet. Nothing changed.", call. = FALSE)
    },
    httr2_http_401 = function(e) .setup_refused(e),
    httr2_http_403 = function(e) .setup_refused(e),
    httr2_http_422 = function(e) {
      stop(.setup_reason(e) %||% "Framework Cloud refused the data registry", ". Nothing changed.", call. = FALSE)
    },
    httr2_failure = function(e) {
      stop("Framework Cloud not reached (", sub("\\.$", "", conditionMessage(e)), "). Nothing changed.", call. = FALSE)
    }
  )
}

# What pulling the data registry would change: entries to add, entries that
# differ, and entries only in this project. `fn` is the call the overwrite
# advice names.
.data_registry_pull_plan <- function(root, connection, overwrite, fn = "pull_data_registry()") {
  registry <- .data_registry_request("/api/v1/projects/data", connection)
  revision <- as.character(registry$revision %||% "")
  local <- .data_registry_local(root)
  cloud <- list()
  for (row in registry$entries %||% list()) cloud[[row$name]] <- row
  added <- unname(cloud[setdiff(names(cloud), names(local))])
  both <- intersect(names(cloud), names(local))
  differ <- Filter(function(n) !.data_registry_same(local[[n]], cloud[[n]]), both)
  kept_local <- setdiff(names(local), names(cloud))

  lines <- character()
  if (length(added)) lines <- c(lines, paste0("  Entries to add: ", .data_registry_names(added)))
  if (length(differ)) {
    details <- paste(vapply(differ, function(n) {
      paste0(n, " (", .data_registry_diff(local[[n]], cloud[[n]]), ")")
    }, ""), collapse = "; ")
    tail <- if (overwrite) "Cloud's will be used" else paste0("kept; ", sub("()", "(overwrite = TRUE)", fn, fixed = TRUE), " uses Cloud's")
    lines <- c(lines, paste0("  Entries that differ (local -> Cloud): ", details, " \u2014 ", tail))
  }
  if (length(kept_local)) lines <- c(lines, paste0("  Only in this project (kept): ", paste(kept_local, collapse = ", ")))
  list(revision = revision, lines = lines, quiet = !length(lines),
       pending = length(added) > 0 || (length(differ) > 0 && overwrite),
       rows = c(added, if (overwrite) unname(cloud[differ])),
       entries = list(added = vapply(added, `[[`, "", "name"),
                      changed = if (overwrite) differ else character(),
                      differ_kept = if (overwrite) character() else differ,
                      kept_local = kept_local))
}

# Write a pull plan's entries and record the revision pulled
.data_registry_pull_apply <- function(root, plan, connection) {
  if (length(plan$rows)) .data_registry_write(root, plan$rows)
  .data_registry_lock_write(root, plan$revision, connection$server)
  n <- length(plan$rows)
  if (n) message("\u2713 Data registry: ", n, " ", if (n == 1) "entry" else "entries", " added or updated")
  invisible(TRUE)
}

# What pushing the data registry would change, from Cloud's dry run. A
# registry that changed on Cloud since the last pull stops with "Pull first",
# naming `pull_fn` and `push_fn`.
.data_registry_push_plan <- function(root, connection, remove, force,
                                     pull_fn = "pull_data_registry()", push_fn = "push_data_registry(force = TRUE)") {
  local <- .data_registry_local(root)
  # The base revision for a project that never pulled its registry
  base <- .data_registry_lock_read(root)$revision
  if (is.null(base)) base <- .data_registry_request("/api/v1/projects/data", connection)$revision

  send <- function(dry) {
    body <- list(base_revision = base, entries = unname(local), remove = remove, force = force, dry_run = dry)
    tryCatch(
      .data_registry_request("/api/v1/projects/data", connection, method = "POST", body = body),
      httr2_http_409 = function(e) {
        latest <- tryCatch(httr2::resp_body_json(e$resp)$revision, error = function(err) NULL)
        stop("Framework Cloud's data registry changed since this project last pulled it (revision ", latest %||% "unknown",
             "). Pull first: ", pull_fn, ". ", push_fn, " replaces Cloud's changes.", call. = FALSE)
      })
  }

  preview <- send(TRUE)
  changes <- preview$changes %||% list()
  added <- changes$added %||% list(); changed <- changes$changed %||% list()
  removed <- changes$removed %||% list(); kept <- changes$kept %||% list()

  lines <- character()
  if (length(added)) lines <- c(lines, paste0("  Entries to add: ", .data_registry_names(added)))
  if (length(changed)) {
    details <- paste(vapply(changed, function(c) {
      paste0(c$name, " (", .data_registry_diff(c$from, c$to), ")")
    }, ""), collapse = "; ")
    lines <- c(lines, paste0("  Entries to change: ", details))
  }
  if (length(removed)) lines <- c(lines, paste0("  Entries to remove: ", .data_registry_names(removed)))
  if (length(kept)) lines <- c(lines, paste0("  On Cloud only (kept): ", .data_registry_names(kept)))
  pending <- length(added) + length(changed) + length(removed) > 0
  warnings <- character()
  if (pending) {
    warnings <- paste0("This changes ", .setup_project_name(root), "'s data registry on Framework Cloud. ",
                       "New copies of the project, zips, and Update on GitHub will use it. ",
                       "Only definitions are sent: no data files and no hashes.")
    if (force && !is.null(preview$revision) && !identical(base, preview$revision)) {
      warnings <- c(warnings, "Cloud's newer data registry changes will be replaced by this project's entries.")
    }
  }
  list(revision = preview$revision, lines = lines, warnings = warnings, quiet = !pending, pending = pending, send = send,
       changes = list(added = added, changed = changed, removed = removed, kept = kept))
}

# Push a plan's entries and record the new revision
.data_registry_push_apply <- function(root, plan, connection) {
  reply <- plan$send(FALSE)
  revision <- as.character(reply$revision %||% "")
  .data_registry_lock_write(root, revision, connection$server)
  done <- reply$changes %||% plan$changes
  if (isTRUE(reply$applied)) {
    parts <- unlist(lapply(c("added", "changed", "removed"), function(k) {
      if (length(done[[k]])) paste(length(done[[k]]), k)
    }))
    message("Data registry pushed: revision ", revision, " (", paste(parts, collapse = ", "), ")")
  } else {
    message("Already up to date.")
  }
  list(applied = isTRUE(reply$applied), revision = revision)
}

#' Pull a Project's Data Registry from Framework Cloud
#'
#' Brings the project's data catalog (the `data` section of its settings)
#' up to date with its data registry on Framework Cloud. The registry is
#' read with the project token (`GET /api/v1/projects/data`), and the
#' changes are listed first: entries to add, entries whose path, type, or
#' options differ, and entries only in this project. Then it asks
#' `Apply these changes? [y/n]`.
#'
#' Only the definitions move. Data files are never downloaded, and file
#' hashes stay in the project's framework.db. Applying writes the new entries
#' into the settings' data section (inline, or in its split file such as
#' `settings/data.yml`), rewriting only that block. Local entries are never
#' removed, and an entry whose local definition differs keeps it unless
#' `overwrite = TRUE`. Fields Framework Cloud doesn't keep stay as they are.
#' The revision pulled is kept in `.framework/data.lock.json` for
#' [push_data_registry()].
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param overwrite Use Cloud's definitions for entries that differ.
#' @param confirm `TRUE` applies without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run List the changes and write nothing.
#' @return Invisibly, a list: `revision`, `entries` (`added`, `changed`,
#'   `differ_kept`, and `kept_local`, as names), `applied`, `dry_run`, and
#'   `message`.
#' @seealso [push_data_registry()], [data_list()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' pull_data_registry(dry_run = TRUE)
#' pull_data_registry()
#' }
#' }
pull_data_registry <- function(project_path = ".", overwrite = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  connection <- .setup_connection(root)
  plan <- .data_registry_pull_plan(root, connection, overwrite)

  lines <- if (plan$quiet) {
    paste0("Data registry is up to date with Framework Cloud (revision ", plan$revision, ").")
  } else {
    c(paste0("Data registry changes from Framework Cloud (revision ", plan$revision, "):"), plan$lines)
  }
  for (line in lines) message(line)

  result <- list(revision = plan$revision, entries = plan$entries,
                 applied = FALSE, dry_run = dry_run, message = paste(lines, collapse = "\n"))
  if (dry_run) return(invisible(result))
  if (!plan$pending) {
    .data_registry_lock_write(root, plan$revision, connection$server)
    return(invisible(result))
  }
  if (!.fw_confirm(confirm, "Apply these changes?", "pull_data_registry()", dry_run_hint = TRUE)) {
    message("Nothing changed.")
    return(invisible(result))
  }
  .data_registry_pull_apply(root, plan, connection)
  result$applied <- TRUE
  invisible(result)
}

#' Push a Project's Data Registry to Framework Cloud
#'
#' Sends the project's data catalog (the `data` section of its settings) to
#' its data registry on Framework Cloud. The entries go to
#' `POST /api/v1/projects/data`, first as a dry run whose changes are listed
#' with a warning: new copies of the project, zips, and Update on GitHub use
#' what is pushed. Then it asks `Push these changes? [y/n]`. Entries only on
#' Cloud stay there unless `remove = TRUE`.
#'
#' Only the definitions move: each entry's name, path, type, delimiter,
#' locked and private flags, description, and Stata names. Data files are
#' never uploaded, and file hashes stay in the project's framework.db.
#'
#' When Cloud's registry changed since this project last pulled it (the
#' revision in `.framework/data.lock.json`), the push is refused with "Pull
#' first"; `force = TRUE` replaces Cloud's newer changes. A push resolves the
#' project again from its blueprint's latest version.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param remove Remove entries from Cloud's registry that this project doesn't have.
#' @param force Push even when Cloud's registry changed since the last pull.
#' @param confirm `TRUE` pushes without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run List the changes and send nothing.
#' @return Invisibly, a list: `revision`, `changes` (Cloud's `added`,
#'   `changed`, `removed`, and `kept`), `applied`, `dry_run`, and `message`.
#' @seealso [pull_data_registry()], [data_list()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' push_data_registry(dry_run = TRUE)
#' push_data_registry()
#' }
#' }
push_data_registry <- function(project_path = ".", remove = FALSE, force = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(remove)
  checkmate::assert_flag(force)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  connection <- .setup_connection(root)
  plan <- .data_registry_push_plan(root, connection, remove, force)

  lines <- if (plan$pending) {
    c("Data registry changes for Framework Cloud:", plan$lines, plan$warnings)
  } else {
    c("Data registry on Framework Cloud already matches this project.", plan$lines)
  }
  for (line in lines) message(line)
  result <- list(revision = plan$revision, changes = plan$changes,
                 applied = FALSE, dry_run = dry_run, message = paste(lines, collapse = "\n"))
  if (!plan$pending || dry_run) return(invisible(result))

  if (!.fw_confirm(confirm, "Push these changes?", "push_data_registry()", dry_run_hint = TRUE)) {
    message("Data registry not pushed.")
    return(invisible(result))
  }
  reply <- .data_registry_push_apply(root, plan, connection)
  result$applied <- reply$applied; result$revision <- reply$revision
  invisible(result)
}
