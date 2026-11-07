#' Read data using dot notation path or direct file path
#'
#' Supports CSV, TSV, RDS, Excel (.xlsx, .xls), Stata (.dta), SPSS (.sav, .zsav, .por),
#' and SAS (.sas7bdat, .xpt) file formats.
#'
#' @param path Dot notation path (e.g. "source.private.example") or direct file path
#' @param delim Optional delimiter for CSV files ("comma", "tab", "semicolon", "space")
#' @param keep_attributes Logical flag to preserve special attributes (e.g., haven labels). Default: FALSE (strips attributes)
#' @param ... Additional arguments passed to read functions (readr::read_delim, readxl::read_excel, haven::read_*, etc.)
#' @details
#' CSV and TSV files are read with [readr::read_delim()]. Only `""` and `"NA"`
#' are missing values (pass `na =` to change them), and leading and trailing
#' whitespace is trimmed from values and column names (`trim_ws = TRUE`), so a
#' padded number such as `"   1"` reads as a number. Pass `trim_ws = FALSE` to
#' keep the whitespace.
#' @return The loaded data, typically a data frame or tibble.
#' @export
data_read <- function(path, delim = NULL, keep_attributes = FALSE, ...) {
  # Validate arguments
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_choice(delim, c("comma", "tab", "semicolon", "space", ",", "\t", ";", " "), null.ok = TRUE)
  checkmate::assert_flag(keep_attributes)

  # Check if path is a direct file path: a relative path is looked for
  # from the project root, then from the working directory
  direct <- .fw_existing_file(path)
  if (!is.null(direct)) {
    path <- direct
    # Direct file path - create a minimal spec
    file_ext <- tolower(sub(".*\\.", "", path))
    spec <- list(
      path = path,
      type = switch(file_ext,
        csv = "csv",
        tsv = "tsv",
        txt = "tsv",  # Assume .txt files are tab-delimited
        dat = "tsv",  # Assume .dat files are tab-delimited
        rds = "rds",
        xlsx = "excel",
        xls = "excel",
        dta = "stata",
        sav = "spss",
        zsav = "spss",
        por = "spss_por",
        sas7bdat = "sas",
        sas7bcat = "sas",
        xpt = "sas_xpt",
        parquet = "parquet",
        stop(sprintf("Unsupported file extension: %s", file_ext))
      ),
      locked = FALSE,
      delimiter = NULL
    )
  } else {
    # Try to get data specification from config
    spec <- tryCatch(
      data_info(path),
      error = function(e) {
        stop(sprintf("Path '%s' is not a valid file and failed to get data specification: %s", path, e$message))
      }
    )

    if (is.null(spec)) {
      # Get suggestions for similar paths
      suggestions <- .get_data_path_suggestions(path)

      error_msg <- sprintf("No data specification found for path: %s", path)
      if (length(suggestions) > 0) {
        error_msg <- paste0(
          error_msg,
          "\n\nAvailable data paths:\n  ",
          paste(suggestions, collapse = "\n  "),
          "\n\nTip: Use settings('data') to explore the full catalog, or narrow it down with settings('data.source.private')"
        )
      }
      stop(error_msg)
    }
  }

  # Check if file exists
  if (!file.exists(spec$path)) {
    stop(sprintf("File not found: %s", spec$path))
  }

  # Only do hash checking for config-based paths (not direct file paths)
  if (is.null(direct)) {
    # Calculate current file hash
    current_hash <- tryCatch(
      .calculate_file_hash(spec$path),
      error = function(e) {
        stop(sprintf("Failed to calculate file hash: %s", e$message))
      }
    )

    # Get existing data record
    data_record <- tryCatch(
      .get_data_record(path),
      error = function(e) {
        warning(sprintf("Failed to get data record: %s", e$message))
        NULL
      }
    )

    # Handle hash checking
    if (is.null(data_record)) {
      # No record exists, create one with current hash
      tryCatch(
        .set_data(
          name = path,
          # Keep the stored path relative to the project root
          path = .fw_project_relative_path(spec$path),
          type = spec$type,
          delimiter = if (!is.null(spec$delimiter)) spec$delimiter else NA,
          locked = if (!is.null(spec$locked)) spec$locked else FALSE,
          hash = current_hash
        ),
        error = function(e) {
          warning(sprintf("Failed to set data record: %s", e$message))
        }
      )
    } else {
      # Check if file has changed
      if (data_record$hash != current_hash) {
        if (spec$locked) {
          stop(sprintf(
            "Hash mismatch for locked data '%s'\nExpected hash: %s\nCurrent hash:  %s",
            path,
            substr(data_record$hash, 1, 12),
            substr(current_hash, 1, 12)
          ))
        } else {
          warning(sprintf(
            "File hash changed for '%s'\nPrevious hash: %s\nCurrent hash:  %s",
            path,
            substr(data_record$hash, 1, 12),
            substr(current_hash, 1, 12)
          ))
        }
      }
      # Update hash and metadata
      tryCatch(
        .set_data(
          name = path,
          # Keep the stored path relative to the project root
          path = .fw_project_relative_path(spec$path),
          type = spec$type,
          delimiter = if (!is.null(spec$delimiter)) spec$delimiter else NA,
          locked = if (!is.null(spec$locked)) spec$locked else FALSE,
          hash = current_hash
        ),
        error = function(e) {
          warning(sprintf("Failed to update data record: %s", e$message))
        }
      )
    }
  }

  # Helper function to get delimiter character
  get_delimiter <- function(delimiter_name) {
    switch(delimiter_name,
      comma = ",",
      "," = ",",
      tab = "\t",
      "\t" = "\t",
      semicolon = ";",
      ";" = ";",
      space = " ",
      " " = " ",
      stop(sprintf("Unknown delimiter: %s. Must be one of: comma, tab, semicolon, space", delimiter_name))
    )
  }

  # Helper function to guess delimiter from extension
  guess_delimiter_from_ext <- function(path) {
    ext <- tolower(sub(".*\\.", "", path))
    switch(ext,
      csv = "comma",
      tsv = "tab",
      txt = "tab", # Common for tab-delimited
      dat = "tab", # Common for tab-delimited
      xlsx = NA,   # Excel files don't use delimiters
      xls = NA,    # Excel files don't use delimiters
      NULL
    )
  }

  # Determine delimiter (only for delimited file types)
  if (is.null(delim) && spec$type %in% c("csv", "tsv")) {
    # Use delimiter from spec if available, otherwise guess from extension
    if (is.null(spec$delimiter) || is.na(spec$delimiter)) {
      delim <- guess_delimiter_from_ext(spec$path)
    } else {
      delim <- spec$delimiter
    }

    if (is.null(delim)) {
      warning(sprintf("Could not determine delimiter from extension for %s, defaulting to comma", spec$path))
      delim <- "comma"
    }
  }

  # Helper to check for haven package
  require_haven <- function(file_type) {
    if (!requireNamespace("haven", quietly = TRUE)) {
      stop(
        sprintf("%s files require the haven package.\n", file_type),
        "Install with: install.packages('haven')"
      )
    }
  }

  # Helper to check for readxl package
  require_readxl <- function() {
    if (!requireNamespace("readxl", quietly = TRUE)) {
      stop(
        "Excel files require the readxl package.\n",
        "Install with: install.packages('readxl')"
      )
    }
  }

  require_arrow <- function() {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop(
        "Parquet files require the arrow package.\n",
        "Install with: install.packages('arrow')"
      )
    }
  }

  # data_add() used to record .por files as spss and .xpt files as sas
  ext <- tolower(tools::file_ext(spec$path))
  if (identical(spec$type, "spss") && ext == "por") spec$type <- "spss_por"
  if (identical(spec$type, "sas") && ext == "xpt") spec$type <- "sas_xpt"

  # readr::read_delim() keeps whitespace by default, unlike read_csv(); trim
  # it so "  1" reads as a number, as in framework-py. trim_ws in ... wins.
  read_delim_args <- list(...)
  if (!"trim_ws" %in% names(read_delim_args)) {
    read_delim_args$trim_ws <- TRUE
  }

  # Load data
  data <- tryCatch(
    switch(spec$type,
      csv = {
        do.call(readr::read_delim, c(
          list(spec$path, show_col_types = FALSE, delim = get_delimiter(delim)),
          read_delim_args
        ))
      },
      tsv = {
        do.call(readr::read_delim, c(
          list(spec$path, show_col_types = FALSE, delim = "\t"),
          read_delim_args
        ))
      },
      rds = readRDS(spec$path),
      excel = ,
      xlsx = ,
      xls = {
        require_readxl()
        readxl::read_excel(spec$path, ...)
      },
      stata = ,
      dta = {
        require_haven("Stata")
        haven::read_dta(spec$path, ...)
      },
      spss = ,
      sav = ,
      zsav = {
        require_haven("SPSS")
        haven::read_sav(spec$path, ...)
      },
      spss_por = ,
      por = {
        require_haven("SPSS portable")
        haven::read_por(spec$path, ...)
      },
      sas = ,
      sas7bdat = ,
      sas7bcat = {
        require_haven("SAS")
        haven::read_sas(spec$path, ...)
      },
      sas_xpt = ,
      xpt = {
        require_haven("SAS transport")
        haven::read_xpt(spec$path, ...)
      },
      parquet = {
        require_arrow()
        arrow::read_parquet(spec$path, as_data_frame = TRUE, ...)
      },
      stop(sprintf("Unsupported file type: %s", spec$type))
    ),
    error = function(e) {
      stop(sprintf("Failed to load data: %s", e$message))
    }
  )

  # Strip haven attributes if requested (default behavior)
  if (!keep_attributes && spec$type %in% c("stata", "dta", "spss", "sav", "zsav", "spss_por", "por", "sas", "sas7bdat", "sas7bcat", "sas_xpt", "xpt")) {
    data <- haven::zap_formats(data)
    data <- haven::zap_labels(data)
    data <- haven::zap_label(data)
    data <- as.data.frame(data)
  }

  # Output description if available
  if (!is.null(spec$description) && nzchar(spec$description)) {
    message(sprintf("Note: %s: %s", path, spec$description))
  }

  data
}

#' List all data entries from config
#'
#' Lists all data specifications defined in the configuration, showing the
#' data key, path, type, and description (if available).
#'
#' @return A data frame with columns: name, path, type, locked, description
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # List all data entries
#' data_list()
#' }
#' }
data_list <- function() {
  config <- settings_read()

  if (is.null(config$data) || length(config$data) == 0) {
    message("No data entries found in configuration")
    return(invisible(data.frame(
      name = character(),
      path = character(),
      type = character(),
      locked = logical(),
      description = character(),
      stringsAsFactors = FALSE
    )))
  }

  # Recursively extract all data entries
  extract_entries <- function(obj, prefix = "") {
    entries <- list()

    for (name in names(obj)) {
      item <- obj[[name]]
      full_name <- if (nzchar(prefix)) paste(prefix, name, sep = ".") else name

      if (is.character(item) && length(item) == 1) {
        # Shorthand entry: name: path/to/file.csv
        entries[[full_name]] <- list(
          name = full_name,
          path = item,
          type = NA_character_,
          locked = FALSE,
          description = NA_character_
        )
      } else if (is.list(item) && !is.null(item$path)) {
        # This is a data entry
        entries[[full_name]] <- list(
          name = full_name,
          path = item$path,
          type = if (!is.null(item$type)) item$type else NA_character_,
          locked = if (!is.null(item$locked)) item$locked else FALSE,
          description = if (!is.null(item$description)) item$description else NA_character_
        )
      } else if (.fw_pathless_entry(item)) {
        # broken: {type: csv} is an entry missing its path, not a group
        entries[[full_name]] <- list(
          name = full_name,
          path = NA_character_,
          type = if (is.character(item$type)) item$type else NA_character_,
          locked = isTRUE(item$locked),
          description = if (!is.null(item$description)) item$description else NA_character_
        )
      } else if (is.list(item) && is.null(item$path)) {
        # This is a nested structure, recurse
        nested <- extract_entries(item, full_name)
        entries <- c(entries, nested)
      }
    }

    entries
  }

  entries_list <- extract_entries(config$data)

  if (length(entries_list) == 0) {
    message("No data entries found in configuration")
    return(invisible(NULL))
  }

  # Print formatted output
  message(sprintf("\n%d data %s found:\n", length(entries_list), if (length(entries_list) == 1) "entry" else "entries"))

  for (entry in entries_list) {
    # Name with type badge
    # Shorthand entries (name: path) record no type
    type_badge <- if (is.na(entry$type)) "" else sprintf(" [%s]", toupper(entry$type))
    message(sprintf("- %s%s", entry$name, type_badge))

    # Path
    message(sprintf("  Path: %s", if (is.na(entry$path)) "(none)" else entry$path))

    # Flags (locked)
    if (entry$locked) {
      message("  [locked]")
    }

    # Description (if available)
    if (!is.na(entry$description) && nzchar(entry$description)) {
      message(sprintf("  %s", entry$description))
    }

    message("")  # Blank line between entries
  }

  result <- do.call(rbind, lapply(entries_list, function(e) {
    data.frame(
      name = e$name,
      path = e$path,
      type = as.character(e$type),
      locked = isTRUE(e$locked),
      description = as.character(e$description),
      stringsAsFactors = FALSE
    )
  }))
  rownames(result) <- NULL
  invisible(result)
}

# Backward compatibility alias (not exported - use data_list instead)
list_data <- function() {
  data_list()
}

#' Read data with caching (DEPRECATED)
#'
#' @description
#' `r lifecycle::badge("deprecated")`
#'
#' This function is deprecated. Use `cache_remember()` with `data_read()` instead:
#'
#' ```r
#' df <- cache_remember("my_data", data_read("source.private.example"))
#' ```
#'
#' @param path Dot notation path to load data (e.g. "source.private.example")
#' @param expire_after Optional expiration time in hours (default: from config)
#' @param refresh Optional boolean or function that returns boolean to force refresh
#' @return The loaded data, either from cache or file
#' @keywords internal
data_read_or_cache <- function(path, expire_after = NULL, refresh = FALSE) {
 .Deprecated(
    msg = paste0(
      "data_read_or_cache() is deprecated.\n",
      "Use cache_remember() with data_read() instead:\n",
      "  df <- cache_remember(\"my_data\", data_read(\"", path, "\"))"
    )
  )

  # Validate arguments
  checkmate::assert_string(path)
  checkmate::assert_number(expire_after, lower = 0, null.ok = TRUE)
  checkmate::assert(
    checkmate::check_flag(refresh),
    checkmate::check_function(refresh)
  )

  cache_key <- sprintf("data.%s", path)
  cache_remember(cache_key,
    {
      message(sprintf("Loading data from file: %s (cached as %s)", path, cache_key))
      data_read(path)
    },
    expire_after = expire_after,
    refresh = refresh
  )
}

#' Get a data value
#' @param name The data name
#' @return The data metadata (hash), or NULL if not found
#' @keywords internal
.get_data_record <- function(name) {
  con <- .get_db_connection()
  result <- DBI::dbGetQuery(
    con,
    "SELECT hash FROM data WHERE name = ?",
    list(name)
  )
  DBI::dbDisconnect(con)

  if (nrow(result) == 0) {
    return(NULL)
  }

  result
}

#' Calculate hash of a file
#' @param file_path Path to the file
#' @return The hash of the file as a character string
#' @keywords internal
.calculate_file_hash <- function(file_path) {
  # Read file content
  content <- readBin(file_path, "raw", n = file.size(file_path))
  # Calculate hash and convert to character
  as.character(openssl::sha256(content))
}

#' Get data specification from config
#'
#' Gets the data specification for a given dot notation path from settings.yml.
#' Supports dot notation (e.g., "source.private.example"), relative paths, and
#' absolute paths. Auto-detects file type from extension and applies intelligent
#' defaults for common formats.
#'
#' @param path Dot notation path (e.g. "source.private.example"), relative path,
#'   or absolute path to a data file
#'
#' @return A list with data specification including:
#'   \itemize{
#'     \item \code{path} - Full file path
#'     \item \code{type} - File type (csv, rds, stata, spss, sas, etc.)
#'     \item \code{delimiter} - Delimiter for CSV files (comma, tab, etc.)
#'     \item \code{locked} - Whether file is locked for integrity checking
#'     \item \code{private} - Whether file is in private data directory
#'     \item \code{description} - Optional description of the dataset (displayed when loading)
#'   }
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Get info from dot notation
#' info <- data_info("source.private.my_data")
#'
#' # Get info from file path
#' info <- data_info("data/public/example.csv")
#' }
#' }
#'
#' @export
data_info <- function(path) {
  # Validate arguments
  checkmate::assert_string(path, min.chars = 1)

  # Get config file path to resolve relative paths correctly
  config_file <- .get_settings_file()
  config_dir <- if (!is.null(config_file)) {
    # Normalize config_file to get absolute path, then take dirname
    dirname(normalizePath(config_file, winslash = "/", mustWork = TRUE))
  } else {
    getwd()
  }

  config <- settings_read()

  # Get file type info
  get_file_type_info <- function(path) {
    # For RDS files, we can be explicit
    if (grepl("\\.rds$", path, ignore.case = TRUE)) {
      return(list(type = "rds", delimiter = NULL))
    }

    # For TSV files
    if (grepl("\\.tsv$", path, ignore.case = TRUE)) {
      return(list(type = "tsv", delimiter = "tab"))
    }

    # For CSV files
    if (grepl("\\.csv$", path, ignore.case = TRUE)) {
      return(list(type = "csv", delimiter = "comma"))
    }

    # Excel files
    if (grepl("\\.(xlsx|xls)$", path, ignore.case = TRUE)) {
      return(list(type = "excel", delimiter = NULL))
    }

    # Parquet files
    if (grepl("\\.parquet$", path, ignore.case = TRUE)) {
      return(list(type = "parquet", delimiter = NULL))
    }

    # Stata files
    if (grepl("\\.dta$", path, ignore.case = TRUE)) {
      return(list(type = "stata", delimiter = NULL))
    }

    # SPSS files
    if (grepl("\\.(sav|zsav)$", path, ignore.case = TRUE)) {
      return(list(type = "spss", delimiter = NULL))
    }

    if (grepl("\\.por$", path, ignore.case = TRUE)) {
      return(list(type = "spss_por", delimiter = NULL))
    }

    # SAS files
    if (grepl("\\.(sas7bdat|sas7bcat)$", path, ignore.case = TRUE)) {
      return(list(type = "sas", delimiter = NULL))
    }

    if (grepl("\\.xpt$", path, ignore.case = TRUE)) {
      return(list(type = "sas_xpt", delimiter = NULL))
    }

    # For everything else, let readr figure it out
    return(list(type = "csv", delimiter = NULL))
  }

  # Create base spec with defaults
  create_base_spec <- function(path) {
    type_info <- get_file_type_info(path)
    list(
      path = path,
      type = type_info$type,
      delimiter = type_info$delimiter,
      locked = FALSE,
      private = .data_path_is_private(path, config_dir)
    )
  }

  # Create spec with optional existing spec
  create_spec <- function(path, existing_spec = NULL) {
    # Normalize relative paths against config directory
    # (paths from config are relative to config file, not current directory)
    # Check for both Unix absolute (/...) and Windows absolute (C:/... or C:\...)
    is_absolute <- grepl("^/", path) || grepl("^[A-Za-z]:[/\\\\]", path)
    if (!is_absolute) {
      # Relative path - resolve against config directory
      full_path <- file.path(config_dir, path)
      # Normalize to handle .. and . in path
      path <- normalizePath(full_path, winslash = "/", mustWork = FALSE)
    }

    spec <- create_base_spec(path)
    if (!is.null(existing_spec)) {
      for (key in names(existing_spec)) {
        # Skip 'path' key - use the normalized path we calculated
        if (key != "path" && !is.null(existing_spec[[key]])) {
          spec[[key]] <- existing_spec[[key]]
        }
      }
    }
    spec
  }

  # Handle dot notation lookup
  get_dot_notation_spec <- function(parts, config) {
    config_spec <- .data_catalog_lookup(config$data, parts)
    if (is.null(config_spec)) {
      return(NULL)
    }

    if (is.character(config_spec) && length(config_spec) == 1) {
      create_spec(config_spec)
    } else {
      create_spec(config_spec$path, config_spec)
    }
  }

  # Get spec based on path type
  get_spec_by_path_type <- function(path, config) {
    if (grepl("^/", path)) {
      # Handle absolute paths directly
      create_spec(path)
    } else if (grepl("[/\\\\]", path)) {
      # Handle relative paths by normalizing them against the working directory
      full_path <- normalizePath(file.path(getwd(), path), mustWork = FALSE)
      create_spec(full_path)
    } else {
      spec <- get_dot_notation_spec(strsplit(path, "\\.")[[1]], config)
      # A bare file name such as "iris.csv" that is not a catalog entry
      if (is.null(spec) && file.exists(path) && !dir.exists(path)) {
        spec <- create_spec(normalizePath(path, winslash = "/", mustWork = TRUE))
      }
      spec
    }
  }

  get_spec_by_path_type(path, config)
}

# Find a catalog entry by the parts of its dot-notation name. data_list()
# shows nested (inputs: raw: survey:), mixed (inputs: raw.survey:), and flat
# (inputs.raw.survey:) keys alike; nested keys are tried first. Returns the
# keys that lead to the entry, or NULL.
#' @keywords internal
.data_catalog_find <- function(node, parts) {
  is_entry <- function(x) (is.character(x) && length(x) == 1) || (is.list(x) && !is.null(x$path))
  if (length(parts) == 0) {
    return(if (is_entry(node)) character() else NULL)
  }
  if (!is.list(node)) {
    return(NULL)
  }
  for (j in seq_along(parts)) {
    key <- paste(parts[seq_len(j)], collapse = ".")
    child <- node[[key]]
    if (!is.null(child)) {
      rest <- .data_catalog_find(child, parts[-seq_len(j)])
      if (!is.null(rest)) return(c(key, rest))
    }
  }
  NULL
}

# A file is private when any folder between the project root and the file
# is named private (inputs/private/raw/x.csv included)
#' @keywords internal
.data_path_is_private <- function(path, root) {
  path <- gsub("\\\\", "/", path)
  root <- sub("/+$", "", gsub("\\\\", "/", root))
  if (!startsWith(path, paste0(root, "/"))) {
    # Outside the project, only the file's own folder counts: on macOS every
    # temporary path starts with /private
    return(basename(dirname(path)) == "private")
  }
  rel <- substring(path, nchar(root) + 2)
  "private" %in% strsplit(dirname(rel), "/", fixed = TRUE)[[1]]
}

#' @keywords internal
.data_catalog_lookup <- function(node, parts) {
  keys <- .data_catalog_find(node, parts)
  if (is.null(keys)) NULL else node[[keys]]
}

#' Get data specification (DEPRECATED)
#'
#' @description
#' `r lifecycle::badge("deprecated")`
#'
#' This function has been renamed to [data_info()]. Please use that instead.
#'
#' @param path Dot notation path or file path
#' @return A list with data specification
#' @keywords internal
data_spec_get <- function(path) {
  .Deprecated("data_info", msg = "data_spec_get() is deprecated. Use data_info() instead.")
  data_info(path)
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

#' Get suggestions for available data paths
#'
#' Helper function that extracts all available data paths from config.
#' Used to provide helpful suggestions when data_read() fails.
#'
#' @param attempted_path The path that the user tried (optional, for future fuzzy matching)
#' @return Character vector of available data paths
#' @keywords internal
.get_data_path_suggestions <- function(attempted_path = NULL) {
  config <- tryCatch(
    settings_read(),
    error = function(e) {
      return(character())
    }
  )

  if (is.null(config$data) || length(config$data) == 0) {
    return(character())
  }

  # Recursively extract all data entry paths
  extract_paths <- function(obj, prefix = "") {
    paths <- character()

    for (name in names(obj)) {
      item <- obj[[name]]
      full_name <- if (nzchar(prefix)) paste(prefix, name, sep = ".") else name

      if ((is.character(item) && length(item) == 1) || (is.list(item) && !is.null(item$path)) ||
          .fw_pathless_entry(item)) {
        # A data entry (or the name: path shorthand, or an entry missing its path)
        paths <- c(paths, full_name)
      } else if (is.list(item) && is.null(item$path)) {
        # This is a nested structure, recurse
        nested <- extract_paths(item, full_name)
        paths <- c(paths, nested)
      }
    }

    paths
  }

  all_paths <- extract_paths(config$data)

  # Limit to first 20 suggestions
  if (length(all_paths) > 20) {
    all_paths <- c(all_paths[1:20], sprintf("... and %d more", length(all_paths) - 20))
  }

  all_paths
}


# Whether a catalog item is an entry's fields without a path, rather than a
# group: every key is an entry field, and no value looks like a file path, so
# a group with an entry named `type: data/type.csv` still reads as a group.
# framework-py's catalog._pathless_entry() follows the same rule.
#' @keywords internal
.fw_pathless_entry <- function(item) {
  fields <- c("path", "type", "delimiter", "locked", "private", "description")
  if (!is.list(item) || length(item) == 0 || is.null(names(item)) ||
      !all(names(item) %in% fields)) {
    return(FALSE)
  }
  for (key in setdiff(names(item), "description")) {
    value <- item[[key]]
    if (is.list(value)) return(FALSE)
    if (is.character(value) && any(grepl("[/\\\\]", value) | nzchar(tools::file_ext(value)))) {
      return(FALSE)
    }
  }
  TRUE
}


# A file given by path. A relative path is looked for from the project root,
# then from the working directory, so a notebook in notebooks/ finds the files
# a script in the root does. NULL when there is no such file. Shared with
# framework-py.
#' @keywords internal
.fw_existing_file <- function(path) {
  if (!is.character(path) || length(path) != 1 || is.na(path) || !nzchar(path)) return(NULL)
  candidates <- unique(c(.fw_project_path(path), path))
  for (candidate in candidates) {
    if (file.exists(candidate) && !dir.exists(candidate)) return(candidate)
  }
  NULL
}
