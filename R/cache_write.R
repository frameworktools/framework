#' Set a cache value
#' @param name The cache name
#' @param value The value to cache
#' @param file Optional file path to store the cache (default: `cache/{name}.rds`)
#' @param expire_after Optional expiration time in hours (default: from config)
#' @keywords internal
.set_cache <- function(name, value, file = NULL, expire_after = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)

  config_obj <- settings_read()
  default_expire <- .normalize_expire_after(config_obj$options$data$cache_default_expire)

  # Determine cache file path (FW_CACHE_DIR, then the configured folder)
  cache_file <- .cache_file_path(name, file)

  # Create cache directory if it doesn't exist (lazy creation)
  cache_dir <- dirname(cache_file)
  if (!dir.exists(cache_dir)) {
    tryCatch({
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
      shown_dir <- .fw_project_relative_path(cache_dir)
      cli::cli_alert_info("Creating cache directory: {.path {shown_dir}}")
    }, error = function(e) {
      cli::cli_abort("Failed to create cache directory {.path {cache_dir}}: {e$message}")
    })
  }

  # Save value to RDS file
  tryCatch(
    saveRDS(value, cache_file),
    error = function(e) {
      stop(sprintf("Failed to save cache file: %s", e$message))
    }
  )

  # Calculate hash from file
  hash <- tryCatch(
    .calculate_file_hash(cache_file),
    error = function(e) {
      stop(sprintf("Failed to calculate file hash: %s", e$message))
    }
  )

  # The cache file, relative to the project root (the Python package reads
  # this to tell R's entries from its own)
  stored_path <- .fw_project_relative_path(cache_file)

  # Calculate expiration time
  now <- lubridate::now()
  expire_after <- .normalize_expire_after(expire_after, default_expire)
  expire_at <- if (!is.null(expire_after)) {
    now + lubridate::dseconds(expire_after * 3600)
  } else {
    NA
  }

  # Update database record with just metadata
  con <- tryCatch(
    .get_db_connection(),
    error = function(e) {
      warning(sprintf("Failed to connect to database: %s", e$message))
      return(NULL)
    }
  )

  if (is.null(con)) {
    return(FALSE)
  }

  on.exit(DBI::dbDisconnect(con))

  # A framework.db made before scaffold() has no cache table yet, so the
  # value would never be found again
  if (!DBI::dbExistsTable(con, "cache") && !is.null(.find_project_root(getwd()))) {
    suppressMessages(.ensure_framework_db())
  }

  if (DBI::dbExistsTable(con, "cache")) {
    # Databases created before file_path existed get the column added
    if (!"file_path" %in% DBI::dbListFields(con, "cache")) {
      tryCatch(
        DBI::dbExecute(con, "ALTER TABLE cache ADD COLUMN file_path TEXT"),
        error = function(e) stop(sprintf("Failed to add cache.file_path: %s", e$message))
      )
    }

    # Check if entry exists
    entry_exists <- tryCatch(
      DBI::dbGetQuery(con, "SELECT 1 FROM cache WHERE name = ?", list(name)),
      error = function(e) {
        stop(sprintf("Failed to query database: %s", e$message))
      }
    )

    if (nrow(entry_exists) > 0) {
      # Update existing entry
      tryCatch(
        DBI::dbExecute(
          con,
          "UPDATE cache SET file_path = ?, hash = ?, expire_at = ?, last_read_at = ?, updated_at = ? WHERE name = ?",
          list(stored_path, as.character(hash), expire_at, now, now, name)
        ),
        error = function(e) {
          stop(sprintf("Failed to update cache record: %s", e$message))
        }
      )
    } else {
      # Insert new entry
      tryCatch(
        DBI::dbExecute(
          con,
          "INSERT INTO cache (name, file_path, hash, expire_at, last_read_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
          list(name, stored_path, as.character(hash), expire_at, now, now, now)
        ),
        error = function(e) {
          stop(sprintf("Failed to insert cache record: %s", e$message))
        }
      )
    }
  }

  value
}

#' Cache a value
#' @param name The cache name
#' @param value The value to cache
#' @param file Optional file path to store the cache (default: `cache/{name}.rds`)
#' @param expire_after Optional expiration time in hours (default: from config)
#' @return The cached value
#' @export
cache <- function(name, value, file = NULL, expire_after = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)

  expire_after <- .normalize_expire_after(expire_after)
  .set_cache(name, value, file, expire_after)
}
