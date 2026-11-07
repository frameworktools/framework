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
#'   Dot notation uses your configured directories
#'   (e.g., `inputs.raw`, `inputs.intermediate`, `outputs.private`).
#' @param type Type of data file ("csv" or "rds"). Auto-detected from extension if path includes one.
#' @param delimiter Delimiter for CSV files ("comma", "tab", "semicolon", "space")
#' @param locked Whether later reads must find the file unchanged. Default:
#'   TRUE. Saving again over locked data with different contents replaces it
#'   with a warning naming both hashes; the same contents save silently. Pass
#'   `locked = FALSE` for data a pipeline rebuilds.
#' @param force If TRUE, creates missing directories. If FALSE (default), errors if directory doesn't exist.
#' @return Invisibly returns the saved data.
#' @export
data_save <- function(data, path, type = NULL, delimiter = "comma", locked = TRUE, force = FALSE) {
  # Validate arguments
  checkmate::assert_data_frame(data, min.rows = 1)
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_choice(delimiter, c("comma", "tab", "semicolon", "space"))
  checkmate::assert_flag(locked)
  checkmate::assert_flag(force)

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

  if (has_slash) {
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

  # Check if directory exists
  if (!dir.exists(dir_path)) {
    if (force) {
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      message(sprintf("Created directory: %s", dir_path))
    } else {
      stop(sprintf(
        "Directory '%s' does not exist. Use force = TRUE to create it.",
        dir_path
      ))
    }
  }

  # Save data
  switch(type,
    csv = {
      delim <- c(comma = ",", tab = "\t", semicolon = ";", space = " ")[[delimiter]]
      readr::write_delim(data, file_path, delim = delim)
    },
    rds = saveRDS(data, file_path),
    stop(sprintf("Unsupported file type: %s", type))
  )

  message(sprintf("Data saved to: %s", .fw_project_relative_path(file_path)))

  # Database name: the catalog name, or the path as given

  # Calculate hash and update data record
  current_hash <- tryCatch(
    .calculate_file_hash(file_path),
    error = function(e) {
      stop(sprintf("Failed to calculate file hash for '%s': %s", file_path, e$message))
    }
  )

  # Saving over locked data still replaces it (data_save() is how locked
  # data is rebuilt), but says so when the contents changed, since reads
  # expect locked data unchanged. Identical contents save silently.
  previous <- tryCatch(.get_data_lock_record(data_name), error = function(e) NULL)
  if (!is.null(previous) && isTRUE(previous$locked) && !is.na(previous$hash) &&
      nzchar(previous$hash) && !identical(previous$hash, as.vector(unclass(current_hash)))) {
    warning(sprintf(
      paste0(
        "data_save() replaced locked data '%s' with different contents.\n",
        "Previous hash: %s\nCurrent hash:  %s\n",
        "Pass locked = FALSE for data a pipeline rebuilds."
      ),
      data_name, substr(previous$hash, 1, 12), substr(current_hash, 1, 12)
    ), call. = FALSE)
  }

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

  # Register saved file in settings so data_read() works without manual catalog edits
  if (is_name) {
    # Only attempt to update config for dot-notation paths
    tryCatch({
      data_add(
        file_path = file_path,
        name = data_name,
        type = type,
        delimiter = delimiter,
        locked = locked,
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
#' @param locked Whether the file should be locked (hash-verified on read)
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
                     locked = TRUE, update_config = TRUE) {
  # Validate arguments
  checkmate::assert_string(file_path, min.chars = 1)
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_choice(type, c("csv", "rds", "tsv", "excel", "stata", "spss", "spss_por", "sas", "sas_xpt", "parquet"), null.ok = TRUE)
  checkmate::assert_choice(delimiter, c("comma", "tab", "semicolon", "space"))
  checkmate::assert_flag(locked)
  checkmate::assert_flag(update_config)

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
      .data_spec_update(name, spec)
      message(sprintf("Data spec added to config: %s", name))
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

#' Get a data record's hash and lock
#' @param name The data name
#' @return A list with `hash` and `locked`, or NULL if there is no record
#' @keywords internal
.get_data_lock_record <- function(name) {
  con <- .get_db_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  result <- DBI::dbGetQuery(con, "SELECT hash, locked FROM data WHERE name = ?", list(name))
  if (nrow(result) == 0) {
    return(NULL)
  }
  list(hash = as.character(result$hash[1]), locked = isTRUE(as.logical(result$locked[1])))
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
#'
#' @return Invisibly returns NULL. Function is called for its side effect of
#'   updating the YAML configuration file.
#'
#' @keywords internal
.data_spec_update <- function(path, spec) {
  # Validate arguments
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_list(spec)

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
  keys <- .data_catalog_find(current, parts) %||% parts
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

  invisible(NULL)
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
