#' Save data using dot notation or file path
#'
#' @param data Data frame to save
#' @param path Either:
#'
#'   - Dot notation: `inputs.raw.filename` resolves to inputs/raw/filename.rds
#'   - Direct path: "inputs/raw/filename.csv" uses path as-is
#'
#'   Dot notation uses your configured directories
#'   (e.g., `inputs.raw`, `inputs.intermediate`, `outputs.private`).
#' @param type Type of data file ("csv" or "rds"). Auto-detected from extension if path includes one.
#' @param delimiter Delimiter for CSV files ("comma", "tab", "semicolon", "space")
#' @param locked Whether the file should be locked after saving
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

  # Detect path format
  has_slash <- grepl("/", path, fixed = TRUE)
  has_extension <- grepl("\\.(csv|rds)$", path, ignore.case = TRUE)

  if (has_slash || has_extension) {
    # Direct file path mode
    file_path <- path

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

    dir_path <- dirname(file_path)
    file_name <- basename(file_path)

  } else if (grepl("\\.", path)) {
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
      "Path '%s' has no directory. Either:\n  - Use dot notation: 'inputs.raw.%s' or 'inputs.intermediate.%s'\n  - Provide full path: 'inputs/raw/%s.%s'",
      path, path, path, path, type %||% "rds"
    ))
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

  # Create normalized name for database tracking
  # Use the original path input as the identifier
  data_name <- path

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

  # Register saved file in settings so data_read() works without manual catalog edits
  if (!has_slash && !has_extension && grepl("\\.", path)) {
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
#'   If NULL, derives name from file path relative to project root.
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

  # Check file exists

  if (!file.exists(file_path)) {
    stop(sprintf("File not found: %s", file_path))
  }

  # Normalize the path
  file_path <- normalizePath(file_path, mustWork = TRUE)

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

    # Try to make path relative to common directories
    for (dir_key in c("inputs_raw", "inputs_intermediate", "inputs_final", "inputs_reference")) {
      dir_path <- tryCatch(config(sprintf("directories.%s", dir_key)), error = function(e) NULL)
      if (is.character(dir_path) && length(dir_path) == 1) {
        dir_path <- normalizePath(.fw_project_path(dir_path), mustWork = FALSE)
      } else {
        dir_path <- NULL
      }
      if (!is.null(dir_path) && startsWith(file_path, paste0(dir_path, "/"))) {
        rel_path <- substring(file_path, nchar(dir_path) + 2)
        # Convert directory key to dot notation (inputs_raw -> inputs.raw)
        prefix <- gsub("_", ".", dir_key)
        break
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
    yaml::read_yaml(config_path, eval.expr = FALSE),
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
        external_content <- yaml::read_yaml(data_path, eval.expr = FALSE)
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

  # Write back to the correct location
  tryCatch({
    if (is_external) {
      dir.create(dirname(data_path), recursive = TRUE, showWarnings = FALSE)
      # Wrap in 'data' key when writing to external file
      yaml::write_yaml(list(data = current), data_path)
    } else {
      env_config$data <- current
      if (!is.null(env_key)) {
        raw_config[[env_key]] <- env_config
      } else {
        raw_config <- env_config
      }
      yaml::write_yaml(raw_config, config_path)
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
