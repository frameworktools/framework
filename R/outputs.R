#' Output Save Functions
#'
#' First-class functions for saving tables, figures, models, and reports.
#' These functions implement lazy directory creation with console feedback.
#'
#' @name outputs
NULL

# -----------------------------------------------------------------------------
# Internal helper for lazy directory creation with console feedback
# -----------------------------------------------------------------------------

#' Ensure a directory exists, creating it lazily with feedback
#'
#' @param dir_path The directory path to ensure exists
#' @param dir_type Human-readable type for messaging (e.g., "tables", "figures")
#' @return The directory path (invisibly)
#' @keywords internal
.ensure_output_dir <- function(dir_path, dir_type = "output") {
  if (!dir.exists(dir_path)) {
    tryCatch({
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      cli::cli_alert_info("Creating {dir_type} directory: {.path {dir_path}}")
    }, error = function(e) {
      cli::cli_abort("Failed to create {dir_type} directory {.path {dir_path}}: {e$message}")
    })
  }
  invisible(dir_path)
}

#' Log a saved result to the framework database
#'
#' Internal function called by save_table(), save_figure(), etc. to track
#' saved outputs in the results table.
#'
#' @param name Result name/identifier (typically the filename)
#' @param path Full file path to the saved result
#' @param type Result type: "table", "figure", "model", "report", "notebook"
#' @param public Whether saved to public outputs directory
#' @param comment Optional description
#' @return NULL invisibly
#' @keywords internal
.save_result <- function(name, path, type, public = FALSE, comment = NULL) {
  # Try to get hash of file (may not exist yet in some edge cases)
  hash <- tryCatch({
    if (file.exists(path)) .calculate_file_hash(path) else NA_character_
  }, error = function(e) NA_character_)


  con <- tryCatch(
    .get_db_connection(),
    error = function(e) {
      # Silently skip if no database connection available
      return(NULL)
    }
  )

  if (is.null(con)) {
    return(invisible(NULL))
  }

  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Epoch seconds (REAL), like the data, cache, and meta tables
  now <- lubridate::now()
  # DBI parameters must have length 1: NULL comments failed every insert.
  # openssl hashes carry a class DBI won't bind.
  comment <- comment %||% NA_character_
  hash <- paste0(as.character(hash))

  # Check if entry already exists
 existing <- tryCatch(
    DBI::dbGetQuery(con, "SELECT id FROM results WHERE name = ?", list(name)),
    error = function(e) data.frame()
  )

  tryCatch({
    if (nrow(existing) > 0) {
      DBI::dbExecute(
        con,
        "UPDATE results SET type = ?, public = ?, comment = ?, hash = ?, updated_at = ? WHERE name = ?",
        list(type, as.integer(public), comment, hash, now, name)
      )
    } else {
      DBI::dbExecute(
        con,
        "INSERT INTO results (name, type, public, blind, comment, hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        list(name, type, as.integer(public), 0L, comment, hash, now, now)
      )
    }
  }, error = function(e) {
    # Silently skip database errors - don't fail the save operation
    NULL
  })

  invisible(NULL)
}

# Parse framework.db timestamps read as text: epoch seconds (the current
# format) or local "%Y-%m-%d %H:%M:%S" strings (results rows before 2.0).
#' @keywords internal
.fw_db_time <- function(x) {
  x <- as.character(x)
  out <- rep(as.POSIXct(NA), length(x))
  epoch <- !is.na(x) & grepl("^-?[0-9]+(\\.[0-9]+)?$", x)
  out[epoch] <- as.POSIXct(as.numeric(x[epoch]), origin = "1970-01-01")
  text <- !is.na(x) & !epoch
  out[text] <- as.POSIXct(x[text], format = "%Y-%m-%d %H:%M:%S")
  out
}

#' Get the cache directory, respecting FW_CACHE_DIR environment variable
#'
#' @return The cache directory path
#' @keywords internal
.get_cache_dir <- function() {
  # Check for environment variable override first

  env_cache <- Sys.getenv("FW_CACHE_DIR", "")
  if (nzchar(env_cache)) {
    return(env_cache)
  }

  # Fall back to config

  cache_dir <- config("cache")
  if (is.null(cache_dir)) {
    # Default fallback
    cache_dir <- "outputs/cache"
  }
  cache_dir
}

# -----------------------------------------------------------------------------
# Table saving
# -----------------------------------------------------------------------------

# The folder for one kind of output. A project with private and public
# output folders (sensitive data on, or outputs_private_* directories) splits
# by `public`; any other project has one folder per kind.
#' @keywords internal
.output_dir <- function(kind, public = FALSE) {
  cfg <- tryCatch(settings_read(), error = function(e) NULL)
  dirs <- cfg$directories %||% list()
  split <- isTRUE(cfg$security$sensitive) ||
    !is.null(dirs[[paste0("outputs_private_", kind)]]) ||
    !is.null(dirs[[paste0("outputs_public_", kind)]])
  if (!split) {
    return(config(paste0("outputs_", kind)) %||% file.path("outputs", kind))
  }
  side <- if (public) "public" else "private"
  config(paste0("outputs_", side, "_", kind)) %||% file.path("outputs", side, kind)
}

#' Save a table to the outputs directory
#'
#' Saves a data frame or tibble to the configured tables directory.
#' The directory is created lazily on first use.
#'
#' @param data A data frame, tibble, or other tabular data
#' @param name The name for the output file (without extension)
#' @param format Output format: "csv" (default), "rds", "xlsx", or "parquet"
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param ... Additional arguments passed to the underlying write function
#'
#' @return The path to the saved file (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Save a simple table
#' save_table(my_results, "regression_results")
#'
#' # Save as Excel
#' save_table(my_results, "regression_results", format = "xlsx")
#'
#' # Save to public directory (for sensitive projects)
#' save_table(summary_stats, "summary", public = TRUE)
#' }
#' }
#'
#' @export
save_table <- function(data, name, format = "csv", public = FALSE, overwrite = TRUE, ...) {
  checkmate::assert_data_frame(data)
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_choice(format, c("csv", "rds", "xlsx", "parquet"))
  checkmate::assert_flag(public)
  checkmate::assert_flag(overwrite)


  # Get the appropriate tables directory
  tables_dir <- .output_dir("tables", public)

  # Ensure directory exists (lazy creation)
  .ensure_output_dir(tables_dir, "tables")

  # Determine file path
  ext <- switch(format,
    csv = ".csv",
    rds = ".rds",
    xlsx = ".xlsx",
    parquet = ".parquet"
  )
  file_path <- file.path(tables_dir, paste0(name, ext))

  # Check for existing file

  if (file.exists(file_path) && !overwrite) {
    cli::cli_abort("File already exists: {.path {file_path}}. Use overwrite = TRUE to replace.")
  }

  # Save based on format
  tryCatch({
    switch(format,
      csv = readr::write_csv(data, file_path, ...),
      rds = saveRDS(data, file_path, ...),
      xlsx = {
        if (!requireNamespace("writexl", quietly = TRUE)) {
          cli::cli_abort("Package {.pkg writexl} is required for xlsx format. Install with: install.packages('writexl')")
        }
        writexl::write_xlsx(data, file_path, ...)
      },
      parquet = {
        if (!requireNamespace("arrow", quietly = TRUE)) {
          cli::cli_abort("Package {.pkg arrow} is required for parquet format. Install with: install.packages('arrow')")
        }
        arrow::write_parquet(data, file_path, ...)
      }
    )
    cli::cli_alert_success("Saved table to {.path {file_path}}")

    # Log to results database
    .save_result(
      name = basename(file_path),
      path = file_path,
      type = "table",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to save table: {e$message}")
  })

  invisible(file_path)
}

# -----------------------------------------------------------------------------
# Figure saving
# -----------------------------------------------------------------------------

#' Save a figure to the outputs directory
#'
#' Saves a ggplot2 plot or base R graphics to the configured figures directory.
#' The directory is created lazily on first use.
#'
#' @param plot A ggplot2 object, or NULL to save the current plot
#' @param name The name for the output file (without extension)
#' @param format Output format: "png" (default), "pdf", "svg", or "jpg"
#' @param width Width in inches (default: 8)
#' @param height Height in inches (default: 6)
#' @param dpi Resolution in dots per inch (default: 300)
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param ... Additional arguments passed to ggsave or the graphics device
#'
#' @return The path to the saved file (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Save a ggplot
#' p <- ggplot(mtcars, aes(mpg, hp)) + geom_point()
#' save_figure(p, "mpg_vs_hp")
#'
#' # Save as PDF for publication
#' save_figure(p, "mpg_vs_hp", format = "pdf", width = 10, height = 8)
#'
#' # Save to public directory
#' save_figure(p, "summary_plot", public = TRUE)
#' }
#' }
#'
#' @export
save_figure <- function(plot = NULL, name, format = "png", width = 8, height = 6,
                        dpi = 300, public = FALSE, overwrite = TRUE, ...) {
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_choice(format, c("png", "pdf", "svg", "jpg", "jpeg", "tiff"))
  checkmate::assert_number(width, lower = 0.1)
  checkmate::assert_number(height, lower = 0.1)
  checkmate::assert_number(dpi, lower = 1)
  checkmate::assert_flag(public)
  checkmate::assert_flag(overwrite)

  # Get the appropriate figures directory
  figures_dir <- .output_dir("figures", public)

  # Ensure directory exists (lazy creation)
  .ensure_output_dir(figures_dir, "figures")

  # Determine file path
  ext <- paste0(".", format)
  file_path <- file.path(figures_dir, paste0(name, ext))

  # Check for existing file
  if (file.exists(file_path) && !overwrite) {
    cli::cli_abort("File already exists: {.path {file_path}}. Use overwrite = TRUE to replace.")
  }

  # Save the figure
  tryCatch({
    if (inherits(plot, "ggplot") || inherits(plot, "gg")) {
      ggplot2::ggsave(file_path, plot = plot, width = width, height = height, dpi = dpi, ...)
    } else if (is.null(plot)) {
      # Save current plot
      ggplot2::ggsave(file_path, width = width, height = height, dpi = dpi, ...)
    } else {
      cli::cli_abort("plot must be a ggplot2 object or NULL (to save current plot)")
    }
    cli::cli_alert_success("Saved figure to {.path {file_path}}")

    # Log to results database
    .save_result(
      name = basename(file_path),
      path = file_path,
      type = "figure",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to save figure: {e$message}")
  })

  invisible(file_path)
}

# -----------------------------------------------------------------------------
# Model saving
# -----------------------------------------------------------------------------

#' Save a model to the outputs directory
#'
#' Saves a fitted model object to the configured models directory.
#' The directory is created lazily on first use.
#'
#' @param model A fitted model object (lm, glm, tidymodels workflow, etc.)
#' @param name The name for the output file (without extension)
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param ... Additional arguments passed to [saveRDS()]
#'
#' @return The path to the saved file (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Fit and save a model
#' model <- lm(mpg ~ hp + wt, data = mtcars)
#' save_model(model, "mpg_regression")
#' }
#' }
#'
#' @export
save_model <- function(model, name, public = FALSE, overwrite = TRUE, ...) {
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_flag(public)
  checkmate::assert_flag(overwrite)

  # Get the appropriate models directory
  models_dir <- .output_dir("models", public)

  # Ensure directory exists (lazy creation)
  .ensure_output_dir(models_dir, "models")

  # Determine file path
  file_path <- file.path(models_dir, paste0(name, ".rds"))

  # Check for existing file
  if (file.exists(file_path) && !overwrite) {
    cli::cli_abort("File already exists: {.path {file_path}}. Use overwrite = TRUE to replace.")
  }

  # Save the model
  tryCatch({
    saveRDS(model, file_path, ...)
    cli::cli_alert_success("Saved model to {.path {file_path}}")

    # Log to results database
    .save_result(
      name = basename(file_path),
      path = file_path,
      type = "model",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to save model: {e$message}")
  })

  invisible(file_path)
}

# -----------------------------------------------------------------------------
# Report saving
# -----------------------------------------------------------------------------

#' Save a report to the outputs directory
#'
#' Copies or moves a rendered report (HTML, PDF, etc.) to the configured reports directory.
#' The directory is created lazily on first use.
#'
#' @param file Path to the report file to save
#' @param name Optional new name for the file (without extension). If NULL, uses original name.
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param move If TRUE, moves the file instead of copying (default: FALSE)
#'
#' @return The path to the saved file (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Save a rendered HTML report
#' save_report("notebooks/analysis.html", "final_analysis")
#'
#' # Save to public directory
#' save_report("notebooks/summary.pdf", "public_summary", public = TRUE)
#' }
#' }
#'
#' @export
save_report <- function(file, name = NULL, public = FALSE, overwrite = TRUE, move = FALSE) {
  checkmate::assert_file_exists(file)
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(public)
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(move)

  # Get the appropriate reports directory
  reports_dir <- .output_dir("reports", public)

  # Ensure directory exists (lazy creation)
  .ensure_output_dir(reports_dir, "reports")

  # Determine destination file path
  if (is.null(name)) {
    dest_file <- file.path(reports_dir, basename(file))
  } else {
    ext <- tools::file_ext(file)
    dest_file <- file.path(reports_dir, paste0(name, if (nzchar(ext)) paste0(".", ext) else ""))
  }

  # Check for existing file
  if (file.exists(dest_file) && !overwrite) {
    cli::cli_abort("File already exists: {.path {dest_file}}. Use overwrite = TRUE to replace.")
  }

  # Copy or move the file
  tryCatch({
    if (move) {
      file.rename(file, dest_file)
      cli::cli_alert_success("Moved report to {.path {dest_file}}")
    } else {
      file.copy(file, dest_file, overwrite = overwrite)
      cli::cli_alert_success("Saved report to {.path {dest_file}}")
    }

    # Log to results database
    .save_result(
      name = basename(dest_file),
      path = dest_file,
      type = "report",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to save report: {e$message}")
  })

  invisible(dest_file)
}

# -----------------------------------------------------------------------------
# Notebook saving (render + move to output directory)
# -----------------------------------------------------------------------------

#' Save a rendered notebook to the outputs directory
#'
#' Renders a Quarto or R Markdown notebook and saves the output to the configured
#' notebooks output directory. The directory is created lazily on first use.
#'
#' @param file Path to the .qmd or .Rmd file to render
#' @param name Optional new name for the output file (without extension). If NULL,
#'   uses the original notebook name.
#' @param format Output format: "html" (default), "pdf", or "docx"
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param embed_resources If TRUE, creates a self-contained file with embedded resources
#'   (default: TRUE for html format)
#' @param ... Additional arguments passed to quarto render
#'
#' @return The path to the saved file (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Render and save a notebook
#' save_notebook("notebooks/analysis.qmd")
#'
#' # Save with a custom name
#' save_notebook("notebooks/analysis.qmd", name = "final_analysis")
#'
#' # Render to PDF
#' save_notebook("notebooks/analysis.qmd", format = "pdf")
#'
#' # Save to public directory (for sensitive projects)
#' save_notebook("notebooks/analysis.qmd", public = TRUE)
#' }
#' }
#'
#' @export
save_notebook <- function(file, name = NULL, format = "html", public = FALSE,
                          overwrite = TRUE, embed_resources = TRUE, ...) {
  checkmate::assert_file_exists(file, extension = c("qmd", "Qmd", "QMD", "rmd", "Rmd", "RMD"))
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_choice(format, c("html", "pdf", "docx"))
  checkmate::assert_flag(public)
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(embed_resources)

  # Check quarto is available
  quarto_path <- Sys.which("quarto")
  if (nchar(quarto_path) == 0) {
    cli::cli_abort("Quarto not found. Install from {.url https://quarto.org/docs/get-started/}")
  }

  # Get the appropriate notebooks output directory
  notebooks_dir <- .output_dir("notebooks", public)

  # Ensure directory exists (lazy creation)
  .ensure_output_dir(notebooks_dir, "notebooks")

  # Determine output filename
  if (is.null(name)) {
    name <- tools::file_path_sans_ext(basename(file))
  }

  ext <- switch(format,
    html = ".html",
    pdf = ".pdf",
    docx = ".docx"
  )
  dest_file <- file.path(notebooks_dir, paste0(name, ext))

  # Check for existing file
  if (file.exists(dest_file) && !overwrite) {
    cli::cli_abort("File already exists: {.path {dest_file}}. Use overwrite = TRUE to replace.")
  }

  # Create temp directory for rendering

  temp_dir <- tempfile("save_notebook_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  # Build quarto render command
  args <- c(
    "render",
    shQuote(normalizePath(file)),
    "--output-dir", shQuote(temp_dir),
    "--to", format
  )

  if (embed_resources && format == "html") {
    args <- c(args, "--embed-resources")
  }

  # Execute render
  cli::cli_alert_info("Rendering {.path {basename(file)}}...")

  tryCatch({
    result <- system2(quarto_path, args, stdout = TRUE, stderr = TRUE)

    # Check for errors
    status <- attr(result, "status")
    if (!is.null(status) && status != 0) {
      cli::cli_abort(c(
        "Quarto render failed",
        paste(result, collapse = "\n")
      ))
    }

    # Find the output file
    output_pattern <- switch(format,
      html = "\\.html$",
      pdf = "\\.pdf$",
      docx = "\\.docx$"
    )
    output_files <- list.files(temp_dir, pattern = output_pattern, full.names = TRUE)

    if (length(output_files) == 0) {
      cli::cli_abort("No {format} output found after rendering")
    }

    # Move output to destination
    file.copy(output_files[1], dest_file, overwrite = overwrite)

    cli::cli_alert_success("Saved notebook to {.path {dest_file}}")

    # Log to results database
    .save_result(
      name = basename(dest_file),
      path = dest_file,
      type = "notebook",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to render notebook: {e$message}")
  })

  invisible(dest_file)
}

# -----------------------------------------------------------------------------
# Results listing
# -----------------------------------------------------------------------------

#' List saved results from the framework database
#'
#' Retrieves a list of all saved results (tables, figures, models, reports,
#' notebooks) that have been tracked via the save_* functions.
#'
#' @param type Optional filter by type: "table", "figure", "model", "report", "notebook"
#' @param public Optional filter: TRUE for public results only, FALSE for private only
#'
#' @return A data frame with columns: name, type, public, comment, hash, created_at, updated_at.
#'   Returns an empty data frame if no results found or database unavailable.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # List all results
#' result_list()
#'
#' # List only tables
#' result_list(type = "table")
#'
#' # List only public figures
#' result_list(type = "figure", public = TRUE)
#' }
#' }
#'
#' @export
result_list <- function(type = NULL, public = NULL) {
  checkmate::assert_choice(type, c("table", "figure", "model", "report", "notebook"), null.ok = TRUE)
  checkmate::assert_flag(public, null.ok = TRUE)

  con <- tryCatch(
    .get_db_connection(),
    error = function(e) NULL
  )

  if (is.null(con)) {
    return(data.frame(
      name = character(),
      type = character(),
      public = logical(),
      comment = character(),
      hash = character(),
      created_at = character(),
      updated_at = character(),
      stringsAsFactors = FALSE
    ))
  }

  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Build query
  # Timestamps are epoch seconds; rows written before 2.0 hold local
  # "%Y-%m-%d %H:%M:%S" text. Read both as text so RSQLite doesn't coerce.
  query <- paste(
    "SELECT name, type, public, comment, hash,",
    "CAST(created_at AS TEXT) AS created_at, CAST(updated_at AS TEXT) AS updated_at",
    "FROM results WHERE deleted_at IS NULL"
  )
  params <- list()

  if (!is.null(type)) {
    query <- paste(query, "AND type = ?")
    params <- c(params, type)
  }

  if (!is.null(public)) {
    query <- paste(query, "AND public = ?")
    params <- c(params, as.integer(public))
  }

  tryCatch({
    # DBI rejects an empty parameter list for a query without placeholders
    results <- if (length(params) > 0) {
      DBI::dbGetQuery(con, query, params = params)
    } else {
      DBI::dbGetQuery(con, query)
    }
    if (nrow(results) > 0) {
      results$public <- as.logical(results$public)
      created <- .fw_db_time(results$created_at)
      updated <- .fw_db_time(results$updated_at)
      results$created_at <- format(created, "%Y-%m-%d %H:%M:%S")
      results$updated_at <- format(updated, "%Y-%m-%d %H:%M:%S")
      results <- results[order(updated, decreasing = TRUE), , drop = FALSE]
      rownames(results) <- NULL
    }
    results
  }, error = function(e) {
    data.frame(
      name = character(),
      type = character(),
      public = logical(),
      comment = character(),
      hash = character(),
      created_at = character(),
      updated_at = character(),
      stringsAsFactors = FALSE
    )
  })
}

# -----------------------------------------------------------------------------
# Project info / discovery function
# -----------------------------------------------------------------------------

#' Display project structure information
#'
#' Shows configured directories and their status (created or pending lazy creation).
#' Useful for understanding the project structure and discovering available paths.
#'
#' @param verbose If TRUE, shows additional details about each directory
#'
#' @return A data frame with directory information (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Show project structure
#' project_info()
#'
#' # Get detailed info
#' project_info(verbose = TRUE)
#' }
#' }
#'
#' @export
project_info <- function(verbose = FALSE) {

  cfg <- tryCatch(settings_read(), error = function(e) NULL)

  if (is.null(cfg)) {
    cli::cli_alert_warning("No project configuration found. Are you in a Framework project?
")
    return(invisible(NULL))
  }

  project_type <- cfg$project_type %||% "project"
  project_name <- cfg$project_name %||% basename(getwd())


  cli::cli_h1("Project: {project_name}")
  cli::cli_text("Type: {.val {project_type}}")
  cli::cli_text("")

  # Get directories from config
  dirs <- cfg$directories
  if (is.null(dirs) || length(dirs) == 0) {
    cli::cli_alert_info("No directories configured")
    return(invisible(NULL))
  }

  # Build info table
  dir_info <- data.frame(
    key = character(),
    path = character(),
    exists = logical(),
    stringsAsFactors = FALSE
  )

  cli::cli_h2("Directories")

  for (key in names(dirs)) {
    path <- dirs[[key]]
    if (is.character(path) && length(path) == 1) {
      exists <- dir.exists(path)
      status <- if (exists) {
        cli::col_green("\u2713 exists")
      } else {
        cli::col_yellow("\u2022 lazy (created on first use)")
      }

      cli::cli_text("
  {.field {key}}: {.path {path}} {status}")

      dir_info <- rbind(dir_info, data.frame(
        key = key,
        path = path,
        exists = exists,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Show cache directory info
  cli::cli_text("")
  cli::cli_h2("Special Directories")

  cache_dir <- .get_cache_dir()
  cache_exists <- dir.exists(cache_dir)
  cache_status <- if (cache_exists) cli::col_green("\u2713 exists") else cli::col_yellow("\u2022 lazy")
  cache_note <- if (nzchar(Sys.getenv("FW_CACHE_DIR", ""))) " (from FW_CACHE_DIR)" else ""
  cli::cli_text("  {.field cache}: {.path {cache_dir}} {cache_status}{cache_note}")

  cli::cli_text("")
  cli::cli_h2("Output Functions")
  cli::cli_text("  {.fn save_table} \u2192 {.path {config('outputs_tables') %||% 'outputs/tables'}}")
  cli::cli_text("  {.fn save_figure} \u2192 {.path {config('outputs_figures') %||% 'outputs/figures'}}")
  cli::cli_text("  {.fn save_model} \u2192 {.path {config('outputs_models') %||% 'outputs/models'}}")
  cli::cli_text("  {.fn save_notebook} \u2192 {.path {config('outputs_notebooks') %||% 'outputs/notebooks'}}")
  cli::cli_text("  {.fn save_report} \u2192 {.path {config('outputs_reports') %||% 'outputs/reports'}}")

  invisible(dir_info)
}
