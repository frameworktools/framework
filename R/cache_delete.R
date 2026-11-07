#' Remove a cache value
#' @param name The cache name to remove
#' @param file Optional file path of the cache (default: `cache/{name}.rds`)
#' @keywords internal
.remove_cache <- function(name, file = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)

  # Determine cache file path (FW_CACHE_DIR, then the configured folder)
  cache_file <- .cache_file_path(name, file)

  if (file.exists(cache_file)) {
    tryCatch(
      unlink(cache_file),
      error = function(e) {
        warning(sprintf("Failed to remove cache file: %s", e$message))
      }
    )
  }

  # Remove database record
  con <- tryCatch(
    .get_db_connection(),
    error = function(e) {
      warning(sprintf("Failed to connect to database: %s", e$message))
      return(NULL)
    }
  )

  if (!is.null(con)) {
    on.exit(DBI::dbDisconnect(con))
    tryCatch(
      DBI::dbExecute(con, "DELETE FROM cache WHERE name = ?", list(name)),
      error = function(e) {
        warning(sprintf("Failed to remove cache record: %s", e$message))
      }
    )
  }
  .fw_depends_forget(name)
}

#' Remove a cached value
#' @param name The cache name to remove
#' @param file Optional file path of the cache (default: `cache/{name}.rds`)
#' @return Invisibly returns NULL.
#' @export
cache_forget <- function(name, file = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)

  .remove_cache(name, file)
  invisible(NULL)
}

#' Clear all cached values
#' @return Invisibly returns NULL.
#' @export
cache_flush <- function() {
  # FW_CACHE_DIR, then the configured folder
  cache_dir <- .get_cache_dir()

  # Remove all RDS files
  if (dir.exists(cache_dir)) {
    tryCatch(
      unlink(list.files(cache_dir, pattern = "\\.rds$", full.names = TRUE)),
      error = function(e) {
        warning(sprintf("Failed to remove cache files: %s", e$message))
      }
    )
  }

  # Clear database records
  con <- tryCatch(
    .get_db_connection(),
    error = function(e) {
      warning(sprintf("Failed to connect to database: %s", e$message))
      return(NULL)
    }
  )

  if (!is.null(con)) {
    on.exit(DBI::dbDisconnect(con))
    # Entries saved with a custom `file =` live outside the cache folder
    custom <- tryCatch(
      if ("file_path" %in% DBI::dbListFields(con, "cache")) {
        DBI::dbGetQuery(con, "SELECT file_path FROM cache WHERE file_path IS NOT NULL")$file_path
      },
      error = function(e) NULL
    )
    for (path in custom) {
      path <- .fw_project_path(path)
      if (grepl("\\.rds$", path, ignore.case = TRUE) && file.exists(path)) unlink(path)
    }
    tryCatch(
      DBI::dbExecute(con, "DELETE FROM cache"),
      error = function(e) {
        warning(sprintf("Failed to clear cache records: %s", e$message))
      }
    )
  }
  .fw_depends_forget()

  invisible(NULL)
}
