#' List all cached values
#'
#' Returns a data frame of all cache entries with their names, expiration times,
#' and status (expired or active).
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{name}{Cache key name}
#'     \item{expire_at}{Expiration timestamp (NA if no expiration)}
#'     \item{created_at}{When the cache was created}
#'     \item{updated_at}{When the cache was last updated}
#'     \item{last_read_at}{When the cache was last read}
#'     \item{status}{Either "active" or "expired"}
#'   }
#'   Returns an empty data frame if no cache entries exist.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # List all cache entries
#' cache_list()
#'
#' # Filter to see only expired caches
#' cache_list() |> dplyr::filter(status == "expired")
#' }
#' }
#'
#' @export
cache_list <- function() {

  # Reading must not create an empty framework.db
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  db_file <- if (is.null(root)) "framework.db" else file.path(root, "framework.db")

  # Get database connection

  con <- if (!file.exists(db_file)) NULL else tryCatch(
    .get_db_connection(),
    error = function(e) {
      warning(sprintf("Failed to connect to database: %s", e$message))
      return(NULL)
    }
  )


  if (is.null(con)) {
    return(data.frame(
      name = character(),
      expire_at = as.POSIXct(character()),
      created_at = as.POSIXct(character()),
      updated_at = as.POSIXct(character()),
      last_read_at = as.POSIXct(character()),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Check if cache table exists
  if (!DBI::dbExistsTable(con, "cache")) {
    return(data.frame(
      name = character(),
      expire_at = as.POSIXct(character()),
      created_at = as.POSIXct(character()),
      updated_at = as.POSIXct(character()),
      last_read_at = as.POSIXct(character()),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Query all cache entries

  result <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT name, expire_at, created_at, updated_at, last_read_at FROM cache ORDER BY name"
    ),
    error = function(e) {
      warning(sprintf("Failed to query cache table: %s", e$message))
      return(data.frame())
    }
  )

  if (nrow(result) == 0) {
    return(data.frame(
      name = character(),
      expire_at = as.POSIXct(character()),
      created_at = as.POSIXct(character()),
      updated_at = as.POSIXct(character()),
      last_read_at = as.POSIXct(character()),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Convert timestamps and determine status
  now <- Sys.time()

  safe_posix <- function(x) {
    tryCatch(
      as.POSIXct(x),
      error = function(e) {
        suppressWarnings(lubridate::ymd_hms(x, quiet = TRUE))
      }
    )
  }

  result$expire_at <- safe_posix(result$expire_at)
  result$created_at <- safe_posix(result$created_at)
  result$updated_at <- safe_posix(result$updated_at)
  result$last_read_at <- safe_posix(result$last_read_at)

  result$status <- ifelse(
    is.na(result$expire_at),
    "active",
    ifelse(now > result$expire_at, "expired", "active")
  )

  result
}

#' Validate refresh parameter
#' @param refresh Boolean or function that returns boolean
#' @return Boolean indicating if refresh is needed
#' @keywords internal
.validate_refresh <- function(refresh) {
  if (is.function(refresh)) {
    result <- tryCatch(
      refresh(),
      error = function(e) {
        warning(sprintf("Refresh function failed: %s", e$message))
        FALSE
      }
    )
    if (!is.logical(result) || length(result) != 1) {
      warning("Refresh function must return a single boolean value")
      return(FALSE)
    }
    return(result)
  }

  if (!is.logical(refresh) || length(refresh) != 1) {
    warning("Refresh parameter must be a single boolean value or a function")
    return(FALSE)
  }

  refresh
}

#' Normalize expire_after input to numeric hours
#' @param expire_after Numeric hours or character (e.g., "30 minutes",
#'   "12 hours", "1 day", "1 week", "45 seconds")
#' @param default Default value if expire_after is NULL/empty
#' @keywords internal
.normalize_expire_after <- function(expire_after, default = NULL) {
  if (is.null(expire_after) || (is.character(expire_after) && !nzchar(trimws(expire_after)))) {
    return(default)
  }

  if (is.character(expire_after)) {
    val <- trimws(tolower(expire_after))
    pattern <- paste0(
      "^([0-9]*\\.?[0-9]+)\\s*(second|seconds|sec|secs|s|minute|minutes|min|mins|",
      "hour|hours|hr|hrs|h|day|days|d|week|weeks|w)$"
    )
    m <- regexec(pattern, val)
    parts <- regmatches(val, m)[[1]]
    if (length(parts) == 3) {
      amount <- as.numeric(parts[2])
      unit <- parts[3]
      multiplier <- switch(unit,
        second = , seconds = , sec = , secs = , s = 1 / 3600,
        minute = , minutes = , min = , mins = 1 / 60,
        hour = 1, hours = 1, hr = 1, hrs = 1, h = 1,
        day = 24, days = 24, d = 24,
        week = 24 * 7, weeks = 24 * 7, w = 24 * 7,
        1
      )
      return(amount * multiplier)
    }
    stop("Could not parse expire_after value. Use numbers (hours) or strings like ",
         "'30 minutes', '2 hours', '1 day', '1 week'.")
  }

  checkmate::assert_number(expire_after, lower = 0, null.ok = TRUE)
  expire_after
}

#' Get a cache value
#' @param name The cache name
#' @param file Optional file path to store the cache (default: `cache/{name}.rds`)
#' @param expire_after Optional expiration time in hours (default: from config)
#' @param dependencies Dependencies from `.fw_depends_resolve()`, or NULL.
#'   With them, an entry recorded with a different key is out of date.
#'   Without them, the entry's recorded dependencies are hashed again, and a
#'   change is a miss with a warning.
#' @param state Optional environment; `state$carried` gets the re-hashed
#'   dependencies of an entry read without `dependencies`, so a recomputed
#'   value keeps them.
#' @return The cached result, or NULL if not found, expired, or hash mismatch
#' @keywords internal
.get_cache <- function(name, file = NULL, expire_after = NULL, dependencies = NULL, state = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)
  expire_after <- .normalize_expire_after(expire_after)

  # Determine cache file path (FW_CACHE_DIR, then the configured folder)
  cache_file <- .cache_file_path(name, file)

  if (!file.exists(cache_file)) {
    message(sprintf("Cache '%s' not found", name))
    return(NULL)
  }

  # Get metadata from database
  con <- tryCatch(
    .get_db_connection(),
    error = function(e) {
      warning(sprintf("Failed to connect to database: %s", e$message))
      return(NULL)
    }
  )

  if (is.null(con)) {
    return(NULL)
  }

  on.exit(DBI::dbDisconnect(con))

  # Get cache metadata including expire_at
  result <- tryCatch(
    DBI::dbGetQuery(con, "SELECT hash, expire_at FROM cache WHERE name = ?", list(name)),
    error = function(e) {
      warning(sprintf("Failed to query database: %s", e$message))
      return(data.frame())
    }
  )

  if (nrow(result) == 0) {
    message(sprintf("Cache '%s' not found in database", name))
    return(NULL)
  }

  # Check if cache has expired
  if (!is.na(result$expire_at)) {
    expire_at <- tryCatch(
      as.POSIXct(result$expire_at),
      error = function(e) {
        suppressWarnings(lubridate::ymd_hms(result$expire_at, quiet = TRUE))
      }
    )
    if (Sys.time() > expire_at) {
      message(sprintf("Cache '%s' has expired", name))
      .remove_cache(name, file)
      return(NULL)
    }
  }

  # Read the actual value from RDS
  # A stored NULL is a valid value, so a read error is told apart from it
  read_failed <- FALSE
  value <- tryCatch(
    readRDS(cache_file),
    error = function(e) {
      warning(sprintf("Failed to read cache file: %s", e$message))
      read_failed <<- TRUE
      NULL
    }
  )

  if (read_failed) {
    message(sprintf("Failed to read cache '%s'", name))
    return(NULL)
  }

  # Verify hash matches
  current_hash <- tryCatch(
    .calculate_file_hash(cache_file),
    error = function(e) {
      warning(sprintf("Failed to calculate file hash: %s", e$message))
      return(NULL)
    }
  )

  if (is.null(current_hash)) {
    return(NULL)
  }

  if (as.character(current_hash) != result$hash) {
    warning(sprintf("Hash mismatch for cache '%s' - cache may be corrupted", name))
    return(NULL)
  }

  if (!.fw_cache_dependencies_current(name, dependencies, state)) {
    return(NULL)
  }

  # Update last_read_at
  tryCatch(
    DBI::dbExecute(
      con,
      "UPDATE cache SET last_read_at = ? WHERE name = ?",
      list(lubridate::now(), name)
    ),
    error = function(e) {
      warning(sprintf("Failed to update last_read_at: %s", e$message))
    }
  )

  list(value = value, hash = result$hash)
}

#' Get a cached value
#' @param name The cache name
#' @param file Optional file path to store the cache (default: `cache/{name}.rds`)
#' @param expire_after Not used. Expiry is set when the value is stored, with
#'   [cache()] or [cache_remember()]. Kept so older code still runs.
#' @return The cached value, or NULL if not found, expired, or hash mismatch.
#'   A value stored with `depends_on` also counts as missing, with a warning,
#'   when a file, folder, or catalog entry it depends on has changed since.
#' @export
cache_get <- function(name, file = NULL, expire_after = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)
  expire_after <- .normalize_expire_after(expire_after)

  result <- .get_cache(name, file, expire_after)
  if (is.null(result)) {
    return(NULL)
  }
  result$value
}

#' Remember a value (get from cache or compute and store)
#'
#' Attempts to retrieve a cached value by name. If the cache doesn't exist,
#' is expired, or a refresh is requested, evaluates the expression and caches
#' the result. This is the primary caching interface for expensive computations.
#'
#' @param name The cache name (non-empty string identifier)
#' @param expr The expression to evaluate and cache if cache miss occurs.
#'   Expression is evaluated in the parent frame.
#' @param file Optional file path to store the cache
#'   (default: `cache/{name}.rds`)
#' @param expire_after Optional expiration time in hours
#'   (default: from config). Character durations like "30 minutes", "2 hours",
#'   "1 day", or "1 week" are accepted (also seconds).
#' @param expire Optional alias for `expire_after` (accepts the same formats)
#' @param refresh Optional boolean or function that returns boolean to force
#'   refresh. If TRUE or if function returns TRUE, cache is invalidated and
#'   expression is re-evaluated.
#' @param depends_on What the value is computed from. Their hashes are part of
#'   the entry's key, so the value is recomputed when any of them changes. One
#'   item or a list of items: a catalog name (`"inputs.raw.survey"`, hashed as
#'   its file), a file or folder path from the project root
#'   (`"functions/fit.R"`, `"functions"`), or any other value, such as a
#'   parameter (`list(cutoff = 0)`). A character vector is several
#'   references; a list with unnamed elements is a list of items, where a
#'   named element `cutoff = 0` is the value `list(cutoff = 0)`
#'   (`list("inputs.raw.survey", cutoff = 0)`); a fully named list is one
#'   value. A string must name a catalog entry, file, or folder; wrap a string
#'   value in a list to hash it (`list(rule = ">= 0")`). Messages name what
#'   changed: a catalog name or path, a value's name (`cutoff`), or
#'   "dependency 3 (a value)" for another value. An entry stored with
#'   dependencies and read without them ([cache_get()], or a call that leaves
#'   `depends_on` out) is checked against its files, folders, and catalog
#'   entries, and a change is a miss with a warning. Records are shared with
#'   framework-py.
#'
#' @return The cached value (if cache hit) or the result of evaluating expr
#'   (if cache miss or refresh requested)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Cache expensive computation
#' result <- cache_remember("my_analysis", {
#'   expensive_computation()
#' })
#'
#' # Force refresh when data changes
#' result <- cache_remember("analysis", {
#'   run_analysis()
#' }, refresh = file.mtime("data.csv") > cache_time)
#'
#' # Recompute when the data, the code, or a parameter changes
#' fit <- cache_remember("lpa_fit", {
#'   fit_lpa(data_read("inputs.final.cohort"), k = 4)
#' }, depends_on = list("inputs.final.cohort", "functions/lpa.R", k = 4))
#' }
#' }
#'
#' @export
cache_remember <- function(name, expr, file = NULL, expire_after = NULL, refresh = FALSE, expire = NULL,
                           depends_on = NULL) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)
  if (!is.null(expire) && !is.null(expire_after)) {
    warning("Both expire and expire_after provided; using expire_after.")
  }
  effective_expire <- .normalize_expire_after(expire_after %||% expire)
  checkmate::assert(
    checkmate::check_flag(refresh),
    checkmate::check_function(refresh)
  )

  # Hashed before evaluating, so the record describes the inputs the value
  # came from
  dependencies <- if (!is.null(depends_on)) .fw_depends_resolve(depends_on) else NULL
  state <- new.env(parent = emptyenv())

  # Check if refresh is needed
  if (.validate_refresh(refresh)) {
    message(sprintf("Cache '%s' refresh requested", name))
    .remove_cache(name, file)
  }

  # .get_cache() returns NULL on a miss and list(value = ...) on a hit, so a
  # cached NULL counts as a hit
  hit <- .get_cache(name, file, effective_expire, dependencies, state)
  if (!is.null(hit)) {
    return(hit$value)
  }
  # A value stored with dependencies keeps them when it is recomputed
  # without them
  if (is.null(dependencies) && !is.null(state$carried)) {
    dependencies <- state$carried
  }

  value <- tryCatch(
    eval(expr, envir = parent.frame()),
    error = function(e) {
      stop(sprintf("Failed to evaluate expression: %s", e$message))
    }
  )

  tryCatch(
    .fw_cache_store(name, value, file, effective_expire, dependencies),
    error = function(e) {
      warning(sprintf("Failed to cache value: %s", e$message))
    }
  )

  value
}
