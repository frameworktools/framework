#' Save data using dot notation or file path
#'
#' @param data Data frame to save
#' @param path Either:
#'
#'   - Dot notation: `inputs.raw.filename` resolves to inputs/raw/filename.rds.
#'     A name may end in the extension: `inputs.raw.filename.csv` is the name
#'     `inputs.raw.filename` saved as CSV.
#'   - Direct path with a `/`: "inputs/raw/filename.csv". A relative path
#'     starts at the project root, not the working directory. framework.db
#'     records it relative to the project root with forward slashes, so
#'     "./inputs/raw/filename.csv" and "inputs/raw/filename.csv" are the
#'     same record.
#'
#'   A bare file name such as "filename.csv" is an error.
#'
#'   A name already in the data catalog is saved to its entry's file, in its
#'   entry's type and delimiter, and the entry is left as it is (its
#'   description and other fields are kept). A `type` or `delimiter` that
#'   differs from the entry's is an error.
#'
#'   Dot notation uses your configured directories
#'   (e.g., `inputs.raw`, `inputs.intermediate`, `outputs.private`).
#' @param type Type of data file ("csv" or "rds"). Auto-detected from extension if path includes one.
#' @param delimiter Delimiter for CSV files ("comma", "tab", "semicolon", "space")
#' @param locked Whether later reads must find the file unchanged. Default:
#'   FALSE, so a pipeline can save the data again. Pass `locked = TRUE` to
#'   lock data you mean to keep as it is. Left out, a save keeps a lock the
#'   data already has, unless `unlock = TRUE`. `locked = FALSE` on locked
#'   data is an error unless `unlock = TRUE`.
#' @param unlock If TRUE, replaces locked data and saves it unlocked, unless
#'   `locked = TRUE`. Without it, `data_save()` stops before writing when the
#'   save would change locked data: a data catalog entry with `locked: true`,
#'   or a file saved earlier with `locked = TRUE`. Saving the same contents
#'   again needs no `unlock`.
#' @param force If TRUE, creates any missing folder. If FALSE (default), a
#'   missing folder is created only when it is a folder named in the settings
#'   (`directories`, `extra_directories`, `render_dirs`) or inside one, such
#'   as `inputs/private/intermediate` in a fresh checkout; any other missing
#'   folder is an error.
#' @return Invisibly returns the saved data.
#' @details
#' After writing, `data_save()` warns when the file's folder (from the
#' project root) has no segment named like private, confidential, or
#' sensitive and the data has columns whose names look like direct
#' identifiers: dates of birth, ZIP codes, SSNs, medical record numbers, and
#' names alongside a date of birth. Only column names are checked, never
#' values. The save still happens.
#'
#' Data is saved unlocked unless you lock it. Locked data protects inputs:
#' [data_read()] stops when a locked file changed. So `data_save()` never
#' changes a locked file unless asked. Save under another name, or pass
#' `unlock = TRUE` to replace it; the new file is then unlocked, and later
#' saves replace it. Pass `unlock = TRUE, locked = TRUE` to replace it and
#' keep it locked.
#' @export
data_save <- function(data, path, type = NULL, delimiter = "comma", locked = FALSE, force = FALSE,
                      unlock = FALSE) {
  # Left out, `locked` keeps the lock the data already has (see below)
  lock_given <- !missing(locked)
  delimiter_given <- !missing(delimiter)
  # Validate arguments
  checkmate::assert_data_frame(data, min.rows = 1)
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_choice(delimiter, c("comma", "tab", "semicolon", "space"))
  checkmate::assert_flag(locked)
  checkmate::assert_flag(force)
  checkmate::assert_flag(unlock)

  # Detect path format. A path with a slash is a file path from the project
  # root. A dot name ending in an extension, such as inputs.final.x.csv, is
  # the catalog name inputs.final.x saved as that type.
  has_slash <- grepl("[/\\\\]", path)
  has_extension <- grepl("\\.(csv|rds)$", path, ignore.case = TRUE)
  data_name <- path
  is_name <- !has_slash

  if (!has_slash && has_extension) {
    given <- tolower(sub("^.*\\.", "", path))
    if (!is.null(type) && !identical(tolower(type), given)) {
      stop(sprintf("'%s' ends in .%s, but type is '%s'.", path, given, type), call. = FALSE)
    }
    type <- given
    path <- sub("\\.[^.]+$", "", path)
    data_name <- path
  }

  # A name already in the data catalog is saved to its entry's file, in its
  # entry's type and delimiter, and the entry is left as it is, as Stata's
  # fw_save and framework-py do
  entry <- if (is_name) .fw_save_catalog_entry(path) else NULL

  if (!is.null(entry)) {
    entry_type <- if (identical(entry$type, "tsv")) "csv" else entry$type
    if (!is.null(type) && !identical(tolower(type), entry_type)) {
      stop(sprintf(
        "'%s' is a %s file in the data catalog (%s), but type is '%s'.\nLeave type out to save it as its entry says, or save it under another name.",
        path, entry$type, .fw_project_relative_path(entry$path), type
      ), call. = FALSE)
    }
    type <- entry_type
    if (identical(type, "csv") && !is.null(entry$delimiter)) {
      if (delimiter_given && !identical(delimiter, entry$delimiter)) {
        stop(sprintf(
          "'%s' is %s-delimited in the data catalog, but delimiter is '%s'. Leave delimiter out to save it as its entry says, or save it under another name.",
          path, entry$delimiter, delimiter
        ), call. = FALSE)
      }
      delimiter <- entry$delimiter
    }
    if (!type %in% c("csv", "rds")) {
      stop(sprintf(
        "data_save() writes csv or rds files. '%s' is a %s file in the data catalog.",
        path, entry$type
      ), call. = FALSE)
    }
    file_path <- entry$path
    dir_path <- dirname(file_path)
    file_name <- basename(file_path)

  } else if (has_slash) {
    # Direct file path mode, relative to the project root (as catalog paths
    # are), so a notebook in notebooks/ writes where a script in the root would
    file_path <- path
    # framework.db records the path in one form, so "./x/y.csv" and
    # "x/y.csv" are the same record
    data_name <- .fw_clean_data_path(path)

    # Auto-detect type from extension if not specified
    if (is.null(type)) {
      if (grepl("\\.csv$", path, ignore.case = TRUE)) {
        type <- "csv"
      } else if (grepl("\\.rds$", path, ignore.case = TRUE)) {
        type <- "rds"
      } else {
        stop("Cannot auto-detect file type from path. Please specify 'type' parameter.")
      }
    }

    # Ensure extension matches type
    expected_ext <- paste0(".", type)
    if (!grepl(paste0(expected_ext, "$"), path, ignore.case = TRUE)) {
      file_path <- paste0(path, expected_ext)
      message(sprintf("Note: Added .%s extension to path", type))
    }

    file_path <- .fw_project_path(file_path)
    dir_path <- dirname(file_path)
    file_name <- basename(file_path)

  } else if (grepl("\\.", path) && all(nzchar(strsplit(path, ".", fixed = TRUE)[[1]]))) {
    # Dot notation mode - directory key required
    # Example: "inputs.raw.filename" → inputs/raw/filename.rds
    # Example: "outputs.private.results" → outputs/private/results.rds
    parts <- strsplit(path, ".", fixed = TRUE)[[1]]

    # The directory key is the longest leading run of parts that names a
    # configured directory: inputs.private.raw.x -> inputs_private_raw
    all_dirs <- tryCatch(config("directories"), error = function(e) list())
    available_keys <- if (is.list(all_dirs)) names(all_dirs) else character(0)
    n_dir <- 0
    for (k in rev(seq_len(length(parts) - 1))) {
      key <- paste(parts[seq_len(k)], collapse = "_")
      if (key %in% available_keys && is.character(all_dirs[[key]]) && length(all_dirs[[key]]) == 1) {
        n_dir <- k
        break
      }
    }

    if (n_dir == 0) {
      stop(sprintf(
        "Unknown directory in '%s'. Start the name with a configured directory.\n\nAvailable directories:\n  %s\n\nExamples:\n  data_save(df, 'inputs.raw.mydata')\n  data_save(df, 'outputs.private.results')",
        path,
        paste(gsub("_", ".", available_keys), collapse = ", ")
      ))
    }

    # Configured directories are relative to the project root, so this
    # works the same from notebooks/ as from the root
    dir_path <- .fw_project_path(all_dirs[[paste(parts[seq_len(n_dir)], collapse = "_")]])
    file_base <- paste(parts[-seq_len(n_dir)], collapse = "_")

    # Default type to rds if not specified
    if (is.null(type)) type <- "rds"

    file_name <- paste0(file_base, ".", type)
    file_path <- file.path(dir_path, file_name)

  } else {
    # Simple filename with no directory
    stop(sprintf(
      "'%s' has no directory. Either:\n  - Use dot notation: 'inputs.raw.%s' or 'inputs.intermediate.%s'\n  - Provide a path from the project root: 'inputs/raw/%s.%s'",
      path, path, path, path, type %||% "rds"
    ), call. = FALSE)
  }

  # Validate type after resolution
  checkmate::assert_choice(type, c("csv", "rds"))

  # A missing folder is created when it is a settings folder or inside one
  # (git doesn't keep empty or ignored folders, so a fresh checkout of a
  # sensitive project has no inputs/private/...), or with force = TRUE.
  # Anywhere else a missing folder is more likely a typo.
  if (!dir.exists(dir_path)) {
    if (force || .fw_in_settings_folder(dir_path)) {
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      message(sprintf("Created directory: %s", dir_path))
    } else {
      stop(sprintf(
        "Directory '%s' does not exist and isn't a settings folder. Use force = TRUE to create it.",
        dir_path
      ))
    }
  }

  write_data <- function(dest) {
    switch(type,
      csv = {
        delim <- c(comma = ",", tab = "\t", semicolon = ";", space = " ")[[delimiter]]
        readr::write_delim(data, dest, delim = delim)
      },
      rds = saveRDS(data, dest),
      stop(sprintf("Unsupported file type: %s", type))
    )
  }

  # Locked data stays unchanged unless unlock = TRUE: reads stop when a
  # locked file changed. The new contents go to a temporary file first, so a
  # refused save leaves the locked file as it was. The same contents pass.
  held <- .fw_locked_data_at(file_path, name = if (is_name) data_name else NULL)
  if (!is.null(held) && lock_given && !locked && !unlock) {
    stop(.fw_locked_message(
      "data_save()", held,
      "Pass unlock = TRUE to save it unlocked.",
      headline = "%s does not remove a lock with locked = FALSE."
    ), call. = FALSE)
  }
  if (!is.null(held)) {
    same <- FALSE
    if (.fw_same_file(held$file, file_path)) {
      tmp <- tempfile("fw-save-", tmpdir = dir_path, fileext = paste0(".", type))
      on.exit(unlink(tmp), add = TRUE)
      write_data(tmp)
      same <- identical(.calculate_file_hash(tmp), .calculate_file_hash(file_path))
    }
    if (!same && !unlock) {
      stop(.fw_locked_message(
        "data_save()", held,
        c("Save the data under another name, or pass unlock = TRUE to replace it.",
          "The new file is then unlocked. Add locked = TRUE to keep it locked.")
      ), call. = FALSE)
    }
    if (!same) message(sprintf("Replacing locked data '%s' (unlock = TRUE).", held$name))
  }
  # Without `locked`, locked data saved with the same contents stays locked,
  # and unlock = TRUE saves it unlocked. Everything else is saved unlocked.
  if (!lock_given) locked <- !is.null(held) && !unlock
  # A save by path to the file of a locked catalog entry updates that entry
  # and its record, as a save by name does, so data_read() by name finds the
  # new contents and lock
  if (!is_name && !is.null(held) && identical(held$source, "catalog")) {
    data_name <- held$name
    is_name <- TRUE
    entry <- .fw_save_catalog_entry(data_name)
  }
  write_data(file_path)

  message(sprintf("Data saved to: %s", .fw_project_relative_path(file_path)))

  # Identifier-like column names outside a private folder: warn, the save
  # still happens. Names only, never values.
  .fw_warn_identifiers(
    names(data), .fw_project_relative_path(file_path),
    sensitive = isTRUE(tryCatch(.fw_settings_sensitive(settings_read()), error = function(e) FALSE))
  )

  # Database name: the catalog name, or the path as given

  # Calculate hash and update data record
  current_hash <- tryCatch(
    .calculate_file_hash(file_path),
    error = function(e) {
      stop(sprintf("Failed to calculate file hash for '%s': %s", file_path, e$message))
    }
  )

  tryCatch(
    .set_data(
      name = data_name,
      path = .fw_project_relative_path(file_path),
      type = type,
      delimiter = if (type == "csv") delimiter else NA,
      locked = locked,
      hash = current_hash
    ),
    error = function(e) {
      stop(sprintf("Failed to update database record for '%s': %s", data_name, e$message))
    }
  )
  message(sprintf("\u2713 Database updated: %s", data_name))

  # Mirror the digest to the project's cloud ledger (opt-in via project
  # token; quiet no-op otherwise -- framework.db stays canonical)
  .fw_ledger_push_quietly(data_name, current_hash, file_path = file_path)

  # An existing entry already names this file. Only its lock can change, so
  # the catalog's flag agrees with framework.db; everything else is left as it is.
  if (is_name && !is.null(entry)) {
    if (!identical(isTRUE(entry$locked), isTRUE(locked))) {
      tryCatch({
        .data_spec_update(data_name, if (locked) list(locked = TRUE) else list(), drop = "locked")
        message(sprintf("Data catalog entry %s: %s", if (locked) "locked" else "unlocked", data_name))
      }, error = function(e) {
        warning(sprintf(
          "File saved but could not update the lock in the data catalog for '%s': %s",
          data_name, e$message
        ))
      })
    }
  } else if (is_name) {
    # Register saved file in settings so data_read() works without manual catalog edits
    # Only attempt to update config for dot-notation paths
    tryCatch({
      data_add(
        file_path = file_path,
        name = data_name,
        type = type,
        delimiter = delimiter,
        locked = locked,
        unlock = unlock,
        update_config = TRUE
      )
    }, error = function(e) {
      warning(sprintf(
        "File saved but could not update data catalog for '%s': %s",
        data_name,
        e$message
      ))
    })
  }

  invisible(data)
}

#' Add an existing file to the data catalog
#'
#' Registers an existing data file with the Framework data catalog. This allows
#' you to track files that were created outside of Framework (e.g., downloaded
#' from external sources, copied from other projects) and use them with
#' `data_read()` using dot notation.
#'
#' @param file_path Path to the existing file (must exist)
#' @param name Optional dot notation name for the data catalog (e.g., `inputs.raw.survey_data`).
#'   If NULL, a file in a configured inputs directory is named after the
#'   directory's key and the file name: `inputs/private/raw/participants.csv`
#'   in `inputs_private_raw` becomes `inputs.private.raw.participants`. Files
#'   elsewhere use the file name alone.
#' @param type Optional type override. Auto-detected from file extension if NULL.
#' @param delimiter Delimiter for CSV files ("comma", "tab", "semicolon", "space")
#' @param locked Whether the file should be locked (hash-verified on read).
#'   Default: FALSE. Left out, a file already locked in the data catalog or
#'   framework.db stays locked. `locked = FALSE` on locked data is an error
#'   unless `unlock = TRUE`.
#' @param unlock If TRUE, removes an existing lock unless `locked = TRUE`.
#'   The data catalog changes only when `update_config = TRUE`. Default:
#'   FALSE, so a lock stays.
#' @param update_config If TRUE (default), also updates the YAML config with the data spec
#'
#' @return Invisibly returns the data spec that was created
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Add a downloaded CSV file to the catalog
#' data_add("inputs/raw/survey_results.csv", name = "inputs.raw.survey_results")
#'
#' # Now you can read it with dot notation
#' data_read("inputs.raw.survey_results")
#'
#' # Add with auto-generated name
#' data_add("inputs/intermediate/cleaned_data.rds")
#' # Name will be derived as "inputs.intermediate.cleaned_data"
#' }
#' }
#'
#' @export
data_add <- function(file_path, name = NULL, type = NULL, delimiter = "comma",
                     locked = FALSE, update_config = TRUE, unlock = FALSE) {
  lock_given <- !missing(locked)
  # Validate arguments
  checkmate::assert_string(file_path, min.chars = 1)
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_choice(type, c("csv", "rds", "tsv", "excel", "stata", "spss", "spss_por", "sas", "sas_xpt", "parquet"), null.ok = TRUE)
  checkmate::assert_choice(delimiter, c("comma", "tab", "semicolon", "space"))
  checkmate::assert_flag(locked)
  checkmate::assert_flag(update_config)
  checkmate::assert_flag(unlock)

  # Check file exists: a relative path from the project root, then from the
  # working directory
  found <- .fw_existing_file(file_path)
  if (is.null(found)) {
    stop(sprintf("File not found: %s", file_path))
  }
  file_path <- found

  # Normalize the path
  file_path <- normalizePath(file_path, winslash = "/", mustWork = TRUE)

  # Auto-detect type from extension if not specified
  if (is.null(type)) {
    file_ext <- tolower(sub(".*\\.", "", file_path))
    type <- switch(file_ext,
      csv = "csv",
      tsv = "tsv",
      txt = "tsv",
      dat = "tsv",
      rds = "rds",
      xlsx = "excel",
      xls = "excel",
      dta = "stata",
      sav = "spss",
      zsav = "spss",
      por = "spss_por",
      sas7bdat = "sas",
      xpt = "sas_xpt",
      parquet = "parquet",
      stop(sprintf("Cannot auto-detect type for extension: %s. Please specify 'type' parameter.", file_ext))
    )
  }

  # Generate name from file path if not provided
  if (is.null(name)) {
    # Try to make a sensible dot-notation name from the path
    # e.g., "inputs/raw/survey.csv" -> "inputs.raw.survey"
    # e.g., "inputs/intermediate/cleaned.rds" -> "inputs.intermediate.cleaned"
    rel_path <- file_path
    prefix <- NULL

    # Match the deepest configured inputs directory (inputs_raw,
    # inputs_private_raw, inputs_public_final, ...) and use its key as the
    # prefix (inputs_private_raw -> inputs.private.raw)
    directories <- tryCatch(settings_read()$directories, error = function(e) NULL)
    input_keys <- grep("^inputs(_|$)", names(directories), value = TRUE)
    best_length <- 0L
    for (dir_key in input_keys) {
      dir_path <- directories[[dir_key]]
      if (!is.character(dir_path) || length(dir_path) != 1 || !nzchar(dir_path)) next
      dir_path <- normalizePath(.fw_project_path(dir_path), winslash = "/", mustWork = FALSE)
      if (startsWith(file_path, paste0(dir_path, "/")) && nchar(dir_path) > best_length) {
        best_length <- nchar(dir_path)
        rel_path <- substring(file_path, nchar(dir_path) + 2)
        prefix <- gsub("_", ".", dir_key)
      }
    }

    # Remove extension and convert path separators to dots
    name_base <- sub("\\.[^.]+$", "", basename(rel_path))
    if (!is.null(prefix)) {
      name <- paste(prefix, name_base, sep = ".")
    } else {
      # Use filename without directory structure
      name <- name_base
      message(sprintf("Note: Using '%s' as data name. Consider specifying a more descriptive name.", name))
    }
  }

  # Left out, `locked` keeps a lock the file already has, so registering
  # locked data again doesn't unlock it. Removing a lock takes unlock = TRUE.
  held <- tryCatch(.fw_locked_data_at(file_path, name = name), error = function(e) NULL)
  if (!is.null(held) && !unlock) {
    if (lock_given && !locked) {
      stop(.fw_locked_message(
        "data_add()", held,
        "Pass unlock = TRUE to register it unlocked.",
        headline = "%s does not remove a lock with locked = FALSE."
      ), call. = FALSE)
    }
    locked <- TRUE
  } else if (!lock_given) {
    locked <- FALSE
  }

  # Calculate hash
  current_hash <- tryCatch(
    .calculate_file_hash(file_path),
    error = function(e) {
      stop(sprintf("Failed to calculate file hash for '%s': %s", file_path, e$message))
    }
  )

  # Determine delimiter value for storage
  delimiter_value <- if (type == "csv") delimiter else NA

  # Record the path relative to the project root, so the catalog keeps
  # working when the project is moved or cloned to another machine
  stored_path <- .fw_project_relative_path(file_path)

  # Register in the database
  tryCatch(
    .set_data(
      name = name,
      path = stored_path,
      type = type,
      delimiter = delimiter_value,
      locked = locked,
      hash = current_hash
    ),
    error = function(e) {
      stop(sprintf("Failed to register data in database: %s", e$message))
    }
  )

  message(sprintf("Data registered in database: %s", name))

  # Build spec for config
  spec <- list(
    path = stored_path,
    type = type
  )
  if (!is.na(delimiter_value)) {
    spec$delimiter <- delimiter
  }
  if (locked) {
    spec$locked <- TRUE
  }

  # Update YAML config if requested

  if (update_config) {
    tryCatch({
      # An existing entry keeps its other fields (description, notes); the
      # delimiter and lock follow this file
      existed <- .data_spec_update(name, spec, drop = c("delimiter", "locked"))
      message(sprintf("Data spec %s config: %s", if (existed) "updated in" else "added to", name))
    }, error = function(e) {
      warning(sprintf("Could not update config (database record was still created): %s", e$message))
    })
  }

  message(sprintf("\nYou can now read this data with: data_read(\"%s\")", name))

  invisible(spec)
}


# A data path as framework.db records it: relative to the project root, with
# forward slashes and no ./ or ../ segments. A path outside the project stays
# absolute.
#' @keywords internal
.fw_clean_data_path <- function(path) {
  path <- gsub("\\\\", "/", path.expand(path))
  .fw_project_relative_path(.fw_lexical_path(.fw_project_path(path)))
}

# Resolve . and .. segments and repeated slashes without touching the disk
#' @keywords internal
.fw_lexical_path <- function(path) {
  path <- gsub("\\\\", "/", path)
  prefix <- regmatches(path, regexpr("^([A-Za-z]:)?/+", path))
  if (length(prefix) == 0) prefix <- ""
  parts <- strsplit(substring(path, nchar(prefix) + 1L), "/+")[[1]]
  out <- character()
  for (part in parts) {
    if (part %in% c("", ".")) next
    if (identical(part, "..")) {
      if (length(out) > 0 && !identical(out[length(out)], "..")) {
        out <- out[-length(out)]
        next
      }
      if (nzchar(prefix)) next
    }
    out <- c(out, part)
  }
  rest <- paste(out, collapse = "/")
  if (!nzchar(prefix) && !nzchar(rest)) "." else paste0(prefix, rest)
}

# An absolute path inside the project, made relative to the project root.
# Paths outside the project stay absolute.
#' @keywords internal
.fw_project_relative_path <- function(path) {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (is.null(root)) {
    return(path)
  }
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  prefix <- paste0(sub("/+$", "", root), "/")
  if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1) else path
}

#' Set a data value
#' @param name The data name
#' @param path The file path
#' @param type The data type (csv, rds, etc.)
#' @param delimiter The delimiter for CSV files
#' @param locked Whether the data is locked
#' @param hash The hash of the data
#' @keywords internal
.set_data <- function(name, path = NULL, type = NULL, delimiter = NULL, locked = FALSE, hash = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(path, null.ok = TRUE, na.ok = TRUE)
  checkmate::assert_string(type, null.ok = TRUE, na.ok = TRUE)
  checkmate::assert_string(delimiter, null.ok = TRUE, na.ok = TRUE)
  checkmate::assert_flag(locked)
  checkmate::assert_string(hash, null.ok = TRUE, na.ok = TRUE)

  # Get database connection
  con <- tryCatch(
    .get_db_connection(),
    error = function(e) {
      stop(sprintf("Failed to connect to database: %s", e$message))
    }
  )
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  now <- lubridate::now()

  # Convert booleans to integers for SQLite
  locked_int <- as.integer(locked)

  # Convert NULL values to NA for SQLite
  path_value <- if (is.null(path)) NA else path
  type_value <- if (is.null(type)) NA else type
  delimiter_value <- if (is.null(delimiter)) NA else delimiter
  hash_value <- if (is.null(hash)) NA else hash

  # Check if entry exists
  entry_exists <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT 1 FROM data WHERE name = ?",
      list(name)
    ),
    error = function(e) {
      stop(sprintf("Failed to check for existing data record: %s", e$message))
    }
  )

  if (nrow(entry_exists) > 0) {
    # Update existing entry
    tryCatch(
      DBI::dbExecute(
        con,
        "UPDATE data SET path = ?, type = ?, delimiter = ?, locked = ?, hash = ?, last_read_at = ?, updated_at = ? WHERE name = ?",
        list(path_value, type_value, delimiter_value, locked_int, hash_value, now, now, name)
      ),
      error = function(e) {
        stop(sprintf("Failed to update data record: %s", e$message))
      }
    )
  } else {
    # Insert new entry
    tryCatch(
      DBI::dbExecute(
        con,
        "INSERT INTO data (name, path, type, delimiter, locked, hash, last_read_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        list(name, path_value, type_value, delimiter_value, locked_int, hash_value, now, now, now)
      ),
      error = function(e) {
        stop(sprintf("Failed to insert data record: %s", e$message))
      }
    )
  }

  invisible(NULL)
}

# The locked data a write to `file_path` would change, or NULL. Locked data
# is a data catalog entry with locked: true, or a framework.db record saved
# locked (data_save() to a path has no catalog entry). An entry counts when
# its file exists and is `file_path`, or when its name is `name`, since a
# save by name repoints the entry. A catalog entry's flag wins over its
# record, so locked: false in the settings unlocks it.
# Returns list(name, file, source), source "catalog" or "record".
#' @keywords internal
.fw_locked_data_at <- function(file_path, name = NULL) {
  hit <- function(entry_name, entry_path) {
    if (is.na(entry_path) || !nzchar(entry_path)) return(FALSE)
    file <- .fw_project_path(entry_path)
    file.exists(file) && (identical(entry_name, name) || .fw_same_file(file, file_path))
  }
  catalog <- tryCatch(suppressMessages(data_list()), error = function(e) NULL)
  cataloged <- character()
  if (is.data.frame(catalog)) {
    cataloged <- catalog$name
    for (i in seq_len(nrow(catalog))) {
      if (isTRUE(catalog$locked[i]) && hit(catalog$name[i], catalog$path[i])) {
        return(list(name = catalog$name[i], file = .fw_project_path(catalog$path[i]), source = "catalog"))
      }
    }
  }
  records <- tryCatch(.fw_locked_records(), error = function(e) NULL)
  if (is.data.frame(records)) {
    for (i in seq_len(nrow(records))) {
      if (records$name[i] %in% cataloged) next
      if (hit(records$name[i], records$path[i])) {
        return(list(name = records$name[i], file = .fw_project_path(records$path[i]), source = "record"))
      }
    }
  }
  NULL
}

# framework.db data records marked locked: name and path
#' @keywords internal
.fw_locked_records <- function() {
  con <- .get_db_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(con, "SELECT name, path, locked FROM data")
  rows[vapply(rows$locked, function(x) isTRUE(as.logical(x)), logical(1)), c("name", "path"), drop = FALSE]
}

# Whether two paths name the same file. Case is ignored where the file
# system usually ignores it (macOS, Windows).
#' @keywords internal
.fw_same_file <- function(a, b) {
  key <- function(p) {
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
    if (.Platform$OS.type == "windows" || identical(Sys.info()[["sysname"]], "Darwin")) tolower(p) else p
  }
  identical(key(a), key(b))
}

# The error for a write that would change locked data
#' @keywords internal
.fw_locked_message <- function(caller, held, advice, headline = "%s does not overwrite locked data.") {
  where <- if (identical(held$source, "catalog")) {
    "locked: true in the data catalog"
  } else {
    "saved with locked = TRUE"
  }
  paste(c(
    sprintf(headline, caller),
    sprintf("  dataset: %s (%s)", held$name, where),
    sprintf("  file:    %s", .fw_project_relative_path(held$file)),
    advice
  ), collapse = "\n")
}

#' Remove a data value
#' @param name The data name to remove
#' @keywords internal
.remove_data <- function(name) {
  con <- .get_db_connection()
  DBI::dbExecute(
    con,
    "DELETE FROM data WHERE name = ?",
    params = list(name)
  )
  DBI::dbDisconnect(con)
}


#' Update data spec in the correct YAML file
#'
#' Traverses a dot-notated key like "final.public.test" and updates or inserts
#' the given spec in the corresponding YAML file (either embedded in settings.yml
#' or in an external settings/data.yml file). Automatically handles nested paths
#' and creates intermediate structures as needed.
#'
#' @param path Dot notation key (e.g., "final.public.test") indicating where
#'   to place the spec in the configuration hierarchy
#' @param spec A named list containing the data spec fields (path, type,
#'   delimiter, locked, encrypted, etc.)
#' @param drop Fields to remove from an existing entry when `spec` leaves
#'   them out. An existing entry's other fields, such as `description`, are
#'   kept.
#'
#' @return Invisibly returns whether the entry already existed. Called for
#'   its side effect of updating the YAML configuration file.
#'
#' @keywords internal
.data_spec_update <- function(path, spec, drop = character()) {
  # Validate arguments
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_list(spec)
  checkmate::assert_character(drop)

  parts <- strsplit(path, "\\.")[[1]]

  # Discover settings file
  config_path <- .get_settings_file()
  if (is.null(config_path)) {
    stop("Configuration file 'settings.yml' (or legacy config.yml) not found")
  }

  # Load raw config to determine where `data` is defined
  raw_config <- tryCatch(
    .fw_read_yaml(config_path),
    error = function(e) {
      stop(sprintf("Failed to read %s: %s", config_path, e$message))
    }
  )

  # Support both environment-scoped and flat configs
  has_envs <- !is.null(raw_config$default) && is.list(raw_config$default)
  env_key <- if (has_envs) "default" else NULL
  env_config <- if (has_envs) raw_config$default else raw_config

  data_source <- env_config$data

  # Determine if `data` is a path or inline
  is_external <- is.character(data_source) && length(data_source) == 1
  if (is_external) {
    data_path <- data_source
    current <- if (file.exists(data_path)) {
      tryCatch({
        external_content <- .fw_read_yaml(data_path)
        # External data files have a 'data' wrapper, extract it
        if (!is.null(external_content$data)) {
          external_content$data
        } else {
          external_content
        }
      },
      error = function(e) {
        stop(sprintf("Failed to read data file '%s': %s", data_path, e$message))
      })
    } else {
      list()
    }
  } else {
    data_path <- config_path
    current <- if (is.null(data_source)) list() else data_source
  }

  # Update an existing entry where it is (nested, mixed, or flat keys);
  # otherwise nest a new one
  found <- .data_catalog_find(current, parts)
  existed <- !is.null(found)
  keys <- found %||% parts
  if (existed) {
    # Update the entry, not replace it: set the fields in spec, remove the
    # fields in drop that spec leaves out, and keep every other field
    old <- current[[keys]]
    if (is.character(old)) old <- list(path = old)
    for (field in setdiff(drop, names(spec))) old[[field]] <- NULL
    for (field in names(spec)) old[[field]] <- spec[[field]]
    spec <- old
  }
  set_in <- function(node, keys, value) {
    if (!is.list(node)) node <- list()
    node[[keys[1]]] <- if (length(keys) == 1) value else set_in(node[[keys[1]]], keys[-1], value)
    node
  }
  current <- set_in(current, keys, spec)

  # Write back to the correct location, rewriting only the data: block so
  # the rest of the file (comments included) stays as it was
  tryCatch({
    if (is_external) {
      dir.create(dirname(data_path), recursive = TRUE, showWarnings = FALSE)
      wrapped <- file.exists(data_path) &&
        "data" %in% names(tryCatch(.fw_read_yaml(data_path), error = function(e) NULL))
      if (wrapped) {
        .fw_yaml_set(data_path, "data", current)
      } else {
        # Wrap in 'data' key when writing to external file
        .fw_write_yaml(list(data = current), data_path)
      }
    } else {
      .fw_yaml_set(config_path, c(env_key, "data"), current)
    }
  }, error = function(e) {
    stop(sprintf("Failed to write configuration: %s", e$message))
  })

  invisible(existed)
}

# The data_info() spec of a name already in the data catalog, or NULL. An
# entry without a path is saved like a new name.
#' @keywords internal
.fw_save_catalog_entry <- function(name) {
  data <- tryCatch(settings_read()$data, error = function(e) NULL)
  if (!is.list(data) || is.null(.data_catalog_find(data, strsplit(name, ".", fixed = TRUE)[[1]]))) {
    return(NULL)
  }
  spec <- tryCatch(data_info(name), error = function(e) NULL)
  if (is.null(spec) || !is.character(spec$path) || !nzchar(spec$path)) NULL else spec
}

#' Update data with hash in the data table
#' @param name The data name
#' @param hash The hash to store
#' @keywords internal
.update_data_with_hash <- function(name, hash) {
  con <- .get_db_connection()
  now <- lubridate::now()

  # Check if entry exists
  entry_exists <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM data WHERE name = ?",
    list(name)
  )

  if (nrow(entry_exists) > 0) {
    # Update existing entry
    DBI::dbExecute(
      con,
      "UPDATE data SET hash = ?, last_read_at = ?, updated_at = ? WHERE name = ?",
      list(hash, now, now, name)
    )
  } else {
    # Insert new entry
    DBI::dbExecute(
      con,
      "INSERT INTO data (name, hash, last_read_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
      list(name, hash, now, now, now)
    )
  }

  DBI::dbDisconnect(con)
}

# Whether a folder (absolute, or relative to the project root) is a folder
# the settings name, or inside one
#' @keywords internal
.fw_in_settings_folder <- function(path) {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (is.null(root)) return(FALSE)
  cfg <- tryCatch(suppressWarnings(settings_read()), error = function(e) NULL)
  if (!is.list(cfg)) return(FALSE)
  folders <- .fw_all_project_folders(cfg, root)
  folders <- folders[nzchar(folders) & folders != "."]
  if (length(folders) == 0) return(FALSE)
  full <- .fw_full_path(.fw_folder_abs(root, path))
  any(.fw_path_under(full, .fw_full_path(file.path(root, folders))))
}
