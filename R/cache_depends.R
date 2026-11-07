# Cache dependencies: what cache_remember(depends_on = ...) hashes into an
# entry's key. Shared with framework-py (framework/_depends.py), so either
# language can read and write the other's records.
#
# Each dependency is one of:
# - data: a catalog name, hashed as its file (SHA-256, as data integrity does)
# - file: a file path, from the project root, then the working directory
# - folder: a folder path, hashed as the sorted list of its files' paths and
#   hashes. Files and folders whose names start with "." and folders named
#   __pycache__ are skipped.
# - value: any other value, hashed in this language only
#
# The entry's key is the SHA-256 of "<kind>\t<ref>\t<hash>\n" for every
# dependency, sorted bytewise. It is stored in framework.db's meta table under
# cache_depends:<name> as JSON: {"key": ..., "dependencies": [{kind, ref, hash}]}.

.fw_depends_prefix <- "cache_depends:"

#' @keywords internal
.fw_sha256_text <- function(text) {
  .fw_hex(openssl::sha256(charToRaw(enc2utf8(paste(text, collapse = "")))))
}

# A file's SHA-256, as data integrity computes it, as plain lowercase hex
#' @keywords internal
.fw_file_sha256 <- function(path) {
  .fw_hex(.calculate_file_hash(path))
}

# openssl's hash object as a plain character string
#' @keywords internal
.fw_hex <- function(hash) {
  hex <- as.character(hash)
  attributes(hex) <- NULL
  hex
}

# SHA-256 of every file below a folder: one "<path>\t<hash>\n" line per file,
# sorted bytewise (radix sorting is in the C locale), "/" separators
#' @keywords internal
.fw_folder_hash <- function(folder) {
  files <- list.files(folder, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  keep <- vapply(strsplit(files, "/", fixed = TRUE), function(parts) {
    folders <- parts[-length(parts)]
    !any(startsWith(parts, ".")) && !any(folders == "__pycache__")
  }, logical(1))
  files <- files[keep]
  if (length(files) == 0) {
    return(.fw_sha256_text(""))
  }
  hashes <- unname(vapply(file.path(folder, files), .fw_file_sha256, character(1)))
  lines <- paste0(enc2utf8(files), "\t", hashes, "\n")
  .fw_sha256_text(sort(lines, method = "radix"))
}

# A value's hash. Only meaningful within R (digest skips the serialization
# header, so the hash survives R upgrades).
#' @keywords internal
.fw_value_hash <- function(value) {
  digest::digest(value, algo = "sha256")
}

#' @keywords internal
.fw_dependency <- function(kind, ref, hash) {
  list(kind = kind, ref = ref, hash = hash)
}

#' @keywords internal
.fw_depends_error <- function(ref) {
  stop(sprintf(paste0(
    "depends_on: '%s' is not a catalog name, file, or folder. Strings name what the ",
    "entry depends on; to hash a string value, wrap it, as in list(rule = \">= 0\")."
  ), ref), call. = FALSE)
}

# A string as a folder, file, or catalog name (in that order)
#' @keywords internal
.fw_depends_reference <- function(ref) {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  candidate <- path.expand(ref)
  absolute <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", candidate)
  if (!absolute) {
    found <- NULL
    for (base in c(root, getwd())) {
      if (file.exists(file.path(base, candidate))) {
        found <- file.path(base, candidate)
        break
      }
    }
    candidate <- found
  }
  if (!is.null(candidate) && dir.exists(candidate)) {
    return(.fw_dependency("folder", ref, .fw_folder_hash(candidate)))
  }
  if (!is.null(candidate) && file.exists(candidate)) {
    return(.fw_dependency("file", ref, .fw_file_sha256(candidate)))
  }
  if (!grepl("[/\\\\]", ref)) {
    catalog <- tryCatch(settings_read()$data, error = function(e) NULL)
    entry <- if (is.list(catalog)) .data_catalog_lookup(catalog, strsplit(ref, ".", fixed = TRUE)[[1]])
    if (!is.null(entry)) {
      info <- tryCatch(data_info(ref), error = function(e) NULL)
      if (!is.null(info$path)) {
        if (!file.exists(info$path) || dir.exists(info$path)) {
          stop(sprintf("depends_on: the file for '%s' is missing: %s", ref, info$path), call. = FALSE)
        }
        return(.fw_dependency("data", ref, .fw_file_sha256(info$path)))
      }
    }
  }
  .fw_depends_error(ref)
}

# The items of depends_on: a character vector is one reference per element,
# an unnamed list is a list of items, and anything else (a named list, a
# data frame, a number) is one value
#' @keywords internal
.fw_depends_items <- function(depends_on) {
  if (is.character(depends_on)) {
    return(as.list(depends_on))
  }
  if (is.list(depends_on) && !is.data.frame(depends_on) && !is.object(depends_on) &&
      (is.null(names(depends_on)) || !any(nzchar(names(depends_on))))) {
    items <- list()
    for (item in depends_on) {
      if (is.character(item) && length(item) > 1) {
        items <- c(items, as.list(item))
      } else {
        items <- c(items, list(item))
      }
    }
    return(items)
  }
  list(depends_on)
}

# The dependencies of depends_on
#' @keywords internal
.fw_depends_resolve <- function(depends_on) {
  items <- .fw_depends_items(depends_on)
  lapply(seq_along(items), function(position) {
    item <- items[[position]]
    if (is.character(item) && length(item) == 1 && !is.na(item)) {
      .fw_depends_reference(item)
    } else {
      .fw_dependency("value", sprintf("value %d", position), .fw_value_hash(item))
    }
  })
}

#' @keywords internal
.fw_depends_key <- function(dependencies) {
  lines <- vapply(dependencies, function(d) {
    paste0(enc2utf8(d$kind), "\t", enc2utf8(d$ref), "\t", d$hash, "\n")
  }, character(1))
  .fw_sha256_text(sort(lines, method = "radix"))
}

# A JSON string as Python's json.dumps() writes it (non-ASCII as \u escapes)
#' @keywords internal
.fw_json_string <- function(x) {
  out <- as.character(jsonlite::toJSON(enc2utf8(x), auto_unbox = TRUE))
  codes <- utf8ToInt(out)
  if (all(codes < 128)) {
    return(out)
  }
  escape <- function(code) {
    if (code < 128) return(intToUtf8(code))
    if (code < 0x10000) return(sprintf("\\u%04x", code))
    code <- code - 0x10000
    sprintf("\\u%04x\\u%04x", 0xD800 + code %/% 0x400, 0xDC00 + code %% 0x400)
  }
  paste(vapply(codes, escape, character(1)), collapse = "")
}

# The record as framework-py writes it: json.dumps() with its default
# separators, so the two languages store identical text
#' @keywords internal
.fw_depends_json <- function(dependencies) {
  items <- vapply(dependencies, function(d) {
    sprintf(
      "{\"kind\": %s, \"ref\": %s, \"hash\": %s}",
      .fw_json_string(d$kind), .fw_json_string(d$ref), .fw_json_string(d$hash)
    )
  }, character(1))
  sprintf(
    "{\"key\": %s, \"dependencies\": [%s]}",
    .fw_json_string(.fw_depends_key(dependencies)), paste(items, collapse = ", ")
  )
}

# Run fn(con) on framework.db when it has a meta table; NULL otherwise
#' @keywords internal
.fw_with_meta <- function(fn, create = FALSE) {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  db_file <- if (is.null(root)) "framework.db" else file.path(root, "framework.db")
  if (!create && !file.exists(db_file)) {
    return(NULL)
  }
  con <- .get_db_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, "meta")) {
    if (!create) return(NULL)
    DBI::dbExecute(con, paste(
      "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT,",
      "created_at DATETIME, updated_at DATETIME)"
    ))
  }
  fn(con)
}

# The key and dependencies stored for an entry, or NULL
#' @keywords internal
.fw_depends_recorded <- function(name) {
  text <- tryCatch(.fw_with_meta(function(con) {
    DBI::dbGetQuery(con, "SELECT value FROM meta WHERE key = ?", list(paste0(.fw_depends_prefix, name)))$value
  }), error = function(e) NULL)
  if (length(text) == 0 || is.na(text[1]) || !nzchar(text[1])) {
    return(NULL)
  }
  tryCatch({
    data <- jsonlite::fromJSON(text[1], simplifyVector = FALSE)
    dependencies <- lapply(data$dependencies, function(d) {
      .fw_dependency(as.character(d$kind), as.character(d$ref), as.character(d$hash))
    })
    if (!is.character(data$key) || length(data$key) != 1) stop("no key")
    list(key = data$key, dependencies = dependencies)
  }, error = function(e) NULL)
}

# Store an entry's dependencies; NULL removes them
#' @keywords internal
.fw_depends_record <- function(name, dependencies) {
  if (is.null(dependencies)) {
    .fw_depends_forget(name)
    return(invisible(NULL))
  }
  key <- paste0(.fw_depends_prefix, name)
  value <- .fw_depends_json(dependencies)
  now <- format(lubridate::now())
  .fw_with_meta(function(con) {
    exists <- DBI::dbGetQuery(con, "SELECT 1 FROM meta WHERE key = ?", list(key))
    if (nrow(exists) > 0) {
      DBI::dbExecute(con, "UPDATE meta SET value = ?, updated_at = ? WHERE key = ?", list(value, now, key))
    } else {
      DBI::dbExecute(
        con,
        "INSERT INTO meta (key, value, created_at, updated_at) VALUES (?, ?, ?, ?)",
        list(key, value, now, now)
      )
    }
  }, create = TRUE)
  invisible(NULL)
}

# Remove the stored dependencies of one entry, or of every entry
#' @keywords internal
.fw_depends_forget <- function(name = NULL) {
  tryCatch(.fw_with_meta(function(con) {
    if (is.null(name)) {
      DBI::dbExecute(con, "DELETE FROM meta WHERE key LIKE ?", list(paste0(.fw_depends_prefix, "%")))
    } else {
      DBI::dbExecute(con, "DELETE FROM meta WHERE key = ?", list(paste0(.fw_depends_prefix, name)))
    }
  }), error = function(e) {
    warning(sprintf("Failed to remove cache dependencies: %s", conditionMessage(e)), call. = FALSE)
  })
  invisible(NULL)
}

# The stored dependencies hashed again, and the references that changed.
# Values keep their stored hash; a reference that no longer resolves counts
# as changed.
#' @keywords internal
.fw_depends_recheck <- function(dependencies) {
  current <- list()
  changed <- character()
  for (dependency in dependencies) {
    if (!dependency$kind %in% c("data", "file", "folder")) {
      current <- c(current, list(dependency))
      next
    }
    fresh <- tryCatch(.fw_depends_reference(dependency$ref), error = function(e) NULL)
    if (is.null(fresh)) {
      changed <- c(changed, dependency$ref)
      next
    }
    current <- c(current, list(fresh))
    if (!identical(fresh$hash, dependency$hash)) {
      changed <- c(changed, dependency$ref)
    }
  }
  list(current = current, changed = changed)
}

# Names for what differs between two dependency lists, for messages
#' @keywords internal
.fw_depends_changed_between <- function(old, new) {
  id <- function(d) paste(d$kind, d$ref, sep = "\t")
  before <- stats::setNames(vapply(old, function(d) d$hash, character(1)), vapply(old, id, character(1)))
  after_ids <- vapply(new, id, character(1))
  names <- character()
  for (i in seq_along(new)) {
    previous <- before[after_ids[i]]
    if (is.na(previous) || !identical(unname(previous), new[[i]]$hash)) {
      names <- c(names, new[[i]]$ref)
    }
  }
  for (i in seq_along(old)) {
    if (!id(old[[i]]) %in% after_ids) names <- c(names, old[[i]]$ref)
  }
  names <- unique(names)
  if (length(names) == 0) "the dependency list" else names
}

# Whether a cache entry is current with its dependencies. With
# `dependencies`, the recorded key must match. Without them, a recorded
# entry's references are hashed again; the fresh list goes to state$carried.
#' @keywords internal
.fw_cache_dependencies_current <- function(name, dependencies = NULL, state = NULL) {
  stored <- .fw_depends_recorded(name)
  if (!is.null(dependencies)) {
    if (is.null(stored) || !identical(stored$key, .fw_depends_key(dependencies))) {
      changed <- .fw_depends_changed_between(stored$dependencies %||% list(), dependencies)
      message(sprintf("Cache '%s' is out of date: %s changed", name, paste(changed, collapse = ", ")))
      return(FALSE)
    }
    return(TRUE)
  }
  if (is.null(stored)) {
    return(TRUE)
  }
  checked <- .fw_depends_recheck(stored$dependencies)
  if (!is.null(state)) {
    state$carried <- checked$current
  }
  if (length(checked$changed) > 0) {
    warning(sprintf(paste0(
      "Cache '%s' is older than its dependencies: %s changed since it was stored, so it is ",
      "treated as a miss. Pass depends_on= to cache_remember() to recompute it without this warning."
    ), name, paste(checked$changed, collapse = ", ")), call. = FALSE)
    return(FALSE)
  }
  TRUE
}
