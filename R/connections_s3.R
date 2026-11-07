#' @title S3 Connection Functions
#' @description Functions for connecting to and interacting with S3-compatible storage.
#' @name connections_s3
NULL

#' Create an S3 client from connection configuration
#'
#' Creates an S3 client object using credentials from the connection configuration.
#' Credentials are resolved from connection config, falling back to environment variables.
#' Loads .env file if present to ensure env vars are available.
#'
#' @param conn_config List. Connection configuration from config.yml
#' @return An S3 client object (from aws.s3 package)
#' @keywords internal
.s3_client <- function(conn_config) {

  if (!requireNamespace("aws.s3", quietly = TRUE)) {
    stop(
      "Package 'aws.s3' is required for S3 connections.\n",
      "Install with: install.packages('aws.s3')",
      call. = FALSE
    )
  }

  # The project's .env fills in variables the session does not set. It is
  # read here, not loaded into the session, so empty template lines never
  # blank a shell credential.
  root <- .find_project_root(getwd())
  dotenv_values <- tryCatch(
    .fw_read_dotenv(file.path(root %||% ".", ".env")),
    error = function(e) character()
  )

  # Helper to get value - env vars take precedence, then config, then default
  # This handles the case where config has placeholder defaults from env() calls
  resolve_value <- function(config_val, env_vars, default = "") {
    # First try env vars (they take precedence), then the project's .env
    for (env_var in env_vars) {
      val <- Sys.getenv(env_var, "")
      if (nchar(val) > 0) return(val)
    }
    for (env_var in env_vars) {
      val <- unname(dotenv_values[env_var])
      if (length(val) == 1 && !is.na(val) && nchar(val) > 0) return(val)
    }
    # Fall back to config value if non-empty
    if (!is.null(config_val) && nchar(config_val) > 0) {
      return(config_val)
    }
    default
  }

  # Resolve credentials with fallbacks to env vars
  access_key <- resolve_value(
    conn_config$access_key_id %||% conn_config$access_key,
    c("S3_ACCESS_KEY", "AWS_ACCESS_KEY_ID")
  )

  secret_key <- resolve_value(
    conn_config$secret_access_key %||% conn_config$secret_key,
    c("S3_SECRET_KEY", "AWS_SECRET_ACCESS_KEY")
  )

  session_token <- resolve_value(
    conn_config$session_token,
    c("S3_SESSION_TOKEN", "AWS_SESSION_TOKEN")
  )

  region <- resolve_value(
    conn_config$region,
    c("S3_REGION", "AWS_REGION", "AWS_DEFAULT_REGION"),
    default = "us-east-1"
  )

  bucket <- resolve_value(
    conn_config$bucket,
    c("S3_BUCKET")
  )

  # Custom endpoint for S3-compatible storage (MinIO, etc.)
  endpoint_raw <- resolve_value(
    conn_config$endpoint,
    c("S3_ENDPOINT")
  )

  # aws.s3 expects base_url without protocol (e.g., 'localhost:9000' not 'http://localhost:9000')
  # Also track if original was http (not https) for use_https parameter
  endpoint_is_http <- grepl("^http://", endpoint_raw)
  endpoint <- sub("^https?://", "", endpoint_raw)

  if (nchar(access_key) == 0 || nchar(secret_key) == 0) {
    stop(
      "S3 credentials not found. Provide in connection config or set:\n",
      "  S3_ACCESS_KEY and S3_SECRET_KEY environment variables\n",
      "  (or AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)",
      call. = FALSE
    )
  }

  if (nchar(bucket) == 0) {
    stop(
      "S3 bucket not specified. Provide in connection config or set:\n",
      "  S3_BUCKET environment variable",
      call. = FALSE
    )
  }

  list(
    access_key = access_key,
    secret_key = secret_key,
    session_token = if (nchar(session_token) > 0) session_token else NULL,
    region = region,
    endpoint = if (nchar(endpoint) > 0) endpoint else NULL,
    use_https = !endpoint_is_http,  # Use HTTP if endpoint was http://
    bucket = bucket,
    prefix = conn_config$prefix %||% "",
    static_hosting = isTRUE(conn_config$static_hosting)
  )
}


#' Collect all S3 connections from config
#'
#' Gathers all S3/storage bucket connections from configuration,
#' along with the default bucket name if specified.
#'
#' @param config Configuration object from settings_read().
#' @return List with connections and default_bucket fields.
#' @keywords internal
.collect_all_s3_connections <- function(config) {
  storage_buckets <- config$storage_buckets %||%
    config$connections$storage_buckets %||%
    list()

  default_bucket_name <- config$default_storage_bucket %||%
    config$connections$default_storage_bucket

  # Legacy top-level `s3:` block: named bucket entries plus default_connection
  legacy <- config$s3
  if (length(storage_buckets) == 0 && is.list(legacy)) {
    storage_buckets <- Filter(function(entry) is.list(entry) && !is.null(entry$bucket), legacy)
    default_bucket_name <- default_bucket_name %||% legacy$default_connection
  }

  list(
    connections = storage_buckets,
    default_bucket = default_bucket_name
  )
}

.resolve_s3_connection <- function(connection = NULL) {
  config <- settings_read()
  s3_sources <- .collect_all_s3_connections(config)
  all_s3 <- s3_sources$connections
  default_bucket_name <- s3_sources$default_bucket

  if (length(all_s3) == 0) {
    stop("No S3 connections configured. Add one in settings.yml:\n\n",
         "connections:\n",
         "  storage_buckets:\n",
         "    my_s3:\n",
         "      bucket: my-bucket\n",
         "      region: us-east-1\n",
         "  default_storage_bucket: my_s3",
         call. = FALSE)
  }

  # If explicit connection name provided
  if (!is.null(connection)) {
    if (is.null(all_s3[[connection]])) {
      stop(sprintf("S3 connection '%s' not found. Available: %s",
                   connection, paste(names(all_s3), collapse = ", ")),
           call. = FALSE)
    }

    conn_config <- all_s3[[connection]]
    conn_config$name <- connection
    return(.s3_client(conn_config))
  }

  # Look for default S3 connection
  # First check default_storage_bucket setting
  if (!is.null(default_bucket_name) && nchar(default_bucket_name) > 0) {
    if (!is.null(all_s3[[default_bucket_name]])) {
      conn_config <- all_s3[[default_bucket_name]]
      conn_config$name <- default_bucket_name
      return(.s3_client(conn_config))
    }
  }

  # Fall back to checking `default: true` flag on individual connections
  for (name in names(all_s3)) {
    conn <- all_s3[[name]]
    if (isTRUE(conn$default)) {
      conn$name <- name
      return(.s3_client(conn))
    }
  }

  # Final fallback: use the first defined connection
  first_name <- names(all_s3)[1]
  conn <- all_s3[[first_name]]
  conn$name <- first_name
  return(.s3_client(conn))
}


#' Upload a file to S3
#'
#' Uploads a single file to an S3 bucket.
#'
#' @param file Character. Local file path to upload.
#' @param dest Character. Destination key (path) in S3 bucket.
#' @param s3_config List. S3 configuration from .resolve_s3_connection().
#' @param content_type Character or NULL. MIME type (auto-detected if NULL).
#' @return Character. The S3 URI of the uploaded file.
#' @keywords internal
.s3_upload_file <- function(file, dest, s3_config, content_type = NULL) {
  if (!file.exists(file)) {
    stop(sprintf("File not found: %s", file), call. = FALSE)
  }

  # Build full key with prefix
  key <- if (nzchar(s3_config$prefix %||% "")) {
    paste0(s3_config$prefix, "/", dest)
  } else {
    dest
  }

  # Clean up double slashes

key <- gsub("//+", "/", key)
  key <- sub("^/", "", key)  # Remove leading slash

  # Auto-detect content type if not provided
  if (is.null(content_type)) {
    content_type <- .guess_content_type(file)
  }

  # Set credentials for this operation
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = s3_config$access_key,
    AWS_SECRET_ACCESS_KEY = s3_config$secret_key,
    AWS_DEFAULT_REGION = s3_config$region
  )

  if (!is.null(s3_config$session_token)) {
    withr::local_envvar(AWS_SESSION_TOKEN = s3_config$session_token)
  }

  # Build base_url for custom endpoints
  base_url <- s3_config$endpoint %||% "s3.amazonaws.com"
  # For custom endpoints, use empty region to avoid region prefix in URL
  region <- if (!is.null(s3_config$endpoint)) "" else s3_config$region
  use_https <- s3_config$use_https %||% TRUE

  put <- function(headers) {
    # Keep the raw response so ACL-disabled errors retain their S3 code. The
    # aws.s3 parser otherwise prints signing metadata and drops the error code.
    result <- aws.s3::put_object(
      file = file,
      object = key,
      bucket = s3_config$bucket,
      headers = headers,
      base_url = base_url,
      region = region,
      use_https = use_https,
      parse_response = FALSE
    )
    response <- attr(result, "response")
    if (is.list(response) && !is.null(response$status_code)) {
      if (response$status_code >= 300L) {
        body <- if (is.raw(response$content)) rawToChar(response$content) else ""
        matched <- regmatches(body, regexec("<Code>([A-Za-z0-9]+)</Code>", body))[[1L]]
        code <- if (length(matched) > 1L) matched[2L] else "UnknownError"
        stop(sprintf("S3 upload failed: %s (HTTP %d).", code, response$status_code), call. = FALSE)
      }
      return(invisible(TRUE))
    }
    if (identical(result, FALSE)) stop("S3 rejected the upload.", call. = FALSE)
    invisible(TRUE)
  }

  # Upload with a public-read ACL so published assets are accessible. Buckets
  # with ACLs disabled (the AWS default since 2023, "bucket owner enforced")
  # reject that header; retry without it and leave access to the bucket policy.
  result <- tryCatch(
    put(if (isTRUE(s3_config$private)) list(`Content-Type` = content_type) else list(`Content-Type` = content_type, `x-amz-acl` = "public-read")),
    error = function(e) {
      if (!grepl("AccessControlListNotSupported", conditionMessage(e), fixed = TRUE)) {
        stop(sprintf("Failed to upload to S3: %s", conditionMessage(e)), call. = FALSE)
      }
      tryCatch(
        put(list(`Content-Type` = content_type)),
        error = function(e2) stop(sprintf("Failed to upload to S3: %s", conditionMessage(e2)), call. = FALSE)
      )
    }
  )

  # Return the public URL
  .s3_public_url(key, s3_config)
}


#' Upload a directory to S3
#'
#' Recursively uploads all files in a directory to S3.
#'
#' @param dir Character. Local directory path to upload.
#' @param dest Character. Destination prefix in S3 bucket.
#' @param s3_config List. S3 configuration from .resolve_s3_connection().
#' @param pattern Character or NULL. Optional file pattern filter.
#' @return Character vector. S3 URIs of uploaded files.
#' @keywords internal
.s3_upload_dir <- function(dir, dest, s3_config, pattern = NULL) {
  if (!dir.exists(dir)) {
    stop(sprintf("Directory not found: %s", dir), call. = FALSE)
  }

  # List all files
  files <- list.files(dir, recursive = TRUE, full.names = TRUE)

  if (!is.null(pattern)) {
    files <- files[grepl(pattern, basename(files))]
  }

  if (length(files) == 0) {
    warning("No files found to upload in: ", dir)
    return(character(0))
  }

  # Upload each file
  urls <- character(length(files))
  for (i in seq_along(files)) {
    rel_path <- substring(normalizePath(files[i], winslash = "/"), nchar(normalizePath(dir, winslash = "/")) + 2L)
    file_dest <- file.path(dest, rel_path)
    urls[i] <- .s3_upload_file(files[i], file_dest, s3_config)
  }

  urls
}


#' Generate public URL for S3 object
#'
#' @param key Character. Object key in S3.
#' @param s3_config List. S3 configuration.
#' @return Character. Public URL.
#' @keywords internal
.s3_public_url <- function(key, s3_config) {
  if (!is.null(s3_config$endpoint)) {
    # Custom endpoint (MinIO, etc.)
    endpoint <- s3_config$endpoint

    # Check if endpoint already has a protocol
    if (grepl("^https?://", endpoint)) {
      # Endpoint already has protocol, use it directly
      sprintf("%s/%s/%s", endpoint, s3_config$bucket, key)
    } else {
      # No protocol, add one based on use_https setting
      protocol <- if (isTRUE(s3_config$use_https)) "https" else "http"
      sprintf("%s://%s/%s/%s", protocol, endpoint, s3_config$bucket, key)
    }
  } else {
    # Standard AWS S3 URL
    sprintf("https://%s.s3.%s.amazonaws.com/%s",
            s3_config$bucket, s3_config$region, key)
  }
}


#' Guess content type from file extension
#'
#' @param file Character. File path.
#' @return Character. MIME type.
#' @keywords internal
.guess_content_type <- function(file) {
  ext <- tolower(tools::file_ext(file))

  types <- list(
    html = "text/html",
    htm = "text/html",
    css = "text/css",
    js = "application/javascript",
    json = "application/json",
    xml = "application/xml",
    csv = "text/csv",
    txt = "text/plain",
    md = "text/markdown",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    svg = "image/svg+xml",
    pdf = "application/pdf",
    rds = "application/octet-stream",
    rda = "application/octet-stream",
    rdata = "application/octet-stream",
    zip = "application/zip",
    gz = "application/gzip",
    parquet = "application/vnd.apache.parquet"
  )

  types[[ext]] %||% "application/octet-stream"
}


#' Test storage connection
#'
#' Validates that S3/storage credentials and bucket access are working.
#'
#' @param connection Character or NULL. Connection name, or NULL for default.
#' @return Logical. TRUE if connection is valid.
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Test default storage connection
#' storage_test()
#'
#' # Test specific connection
#' storage_test("my_s3_backup")
#' }
#' }
storage_test <- function(connection = NULL) {
  s3_config <- .resolve_s3_connection(connection)

  # Set credentials
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = s3_config$access_key,
    AWS_SECRET_ACCESS_KEY = s3_config$secret_key,
    AWS_DEFAULT_REGION = s3_config$region
  )

  if (!is.null(s3_config$session_token)) {
    withr::local_envvar(AWS_SESSION_TOKEN = s3_config$session_token)
  }

  base_url <- s3_config$endpoint %||% "s3.amazonaws.com"
  # For custom endpoints, use empty region to avoid region prefix in URL
  region <- if (!is.null(s3_config$endpoint)) "" else s3_config$region
  use_https <- s3_config$use_https %||% TRUE

  result <- tryCatch({
    # Quiet: aws.s3 prints "Client error: (404) Not Found" before our message
    .fw_s3_quiet(aws.s3::bucket_exists(
      bucket = s3_config$bucket,
      base_url = base_url,
      region = region,
      use_https = use_https
    ))
  }, error = function(e) {
    message("S3 connection failed: ", e$message)
    return(FALSE)
  })

  if (isTRUE(result)) {
    message(sprintf("S3 connection OK: %s (bucket: %s)",
                    s3_config$name %||% "default", s3_config$bucket))
  } else {
    message(sprintf("S3 bucket not accessible: %s", s3_config$bucket))
  }

  invisible(isTRUE(result))
}
