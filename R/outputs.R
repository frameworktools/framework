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
#' The result is named by its path from the project root, such as
#' `outputs/tables/summary.csv`, as in framework-py, so files with the same
#' name in different folders stay apart. A row from an older save, named by
#' the file name alone, is renamed to the path when the file is saved again.
#'
#' @param name Ignored; kept so older callers still work. The name is the
#'   project-relative path.
#' @param path Full file path to the saved result
#' @param type Result type: "table", "figure", "model", "report", "notebook"
#' @param public Whether saved to public outputs directory
#' @param comment Optional description
#' @return NULL invisibly
#' @keywords internal
.save_result <- function(name = NULL, path, type, public = FALSE, comment = NULL) {
  # Try to get hash of file (may not exist yet in some edge cases)
  hash <- tryCatch({
    if (file.exists(path)) .calculate_file_hash(path) else NA_character_
  }, error = function(e) NA_character_)


  # Outside a project there is nothing to log to. Inside one, add the results
  # table if scaffold() has not run yet, so early saves are tracked too.
  con <- tryCatch(.fw_results_connection(create = TRUE), error = function(e) NULL)

  if (is.null(con)) {
    return(invisible(NULL))
  }

  on.exit(DBI::dbDisconnect(con), add = TRUE)

  name <- .fw_result_name(path)
  legacy <- basename(path)

  # Epoch seconds (REAL), like the data, cache, and meta tables
  now <- lubridate::now()
  # DBI parameters must have length 1: NULL comments failed every insert.
  # openssl hashes carry a class DBI won't bind.
  comment <- comment %||% NA_character_
  hash <- paste0(as.character(hash))

  tryCatch({
    # A row from before results were keyed by path takes the new name
    found <- DBI::dbGetQuery(con, "SELECT id FROM results WHERE name = ?", list(name))
    if (nrow(found) == 0 && !identical(legacy, name)) {
      DBI::dbExecute(con, "UPDATE results SET name = ? WHERE name = ?", list(name, legacy))
    }
    existing <- DBI::dbGetQuery(con, "SELECT id FROM results WHERE name = ?", list(name))
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

# The results key for a saved file: its path from the project root (with
# forward slashes), or the full path for a file outside the project.
#' @keywords internal
.fw_result_name <- function(path, root = NULL) {
  root <- root %||% tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  # Resolve the folder (it exists by now), so /var and /private/var agree
  full <- file.path(normalizePath(dirname(path), winslash = "/", mustWork = FALSE), basename(path))
  if (is.null(root)) return(full)
  base <- sub("/+$", "", normalizePath(root, winslash = "/", mustWork = FALSE))
  if (startsWith(full, paste0(base, "/"))) substring(full, nchar(base) + 2L) else full
}

# Connection to the project's framework.db with a results table, or NULL
# outside a project. With create = FALSE, a missing framework.db stays missing.
.fw_results_connection <- function(create = TRUE) {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (is.null(root)) return(NULL)
  db_path <- file.path(root, "framework.db")
  if (!create && !file.exists(db_path)) return(NULL)
  con <- .get_db_connection(root)
  if (!DBI::dbExistsTable(con, "results")) {
    if (!create) {
      DBI::dbDisconnect(con)
      return(NULL)
    }
    DBI::dbDisconnect(con)
    suppressMessages(.ensure_framework_db(root))
    con <- .get_db_connection(root)
  }
  con
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
#' Every cache function uses this, so reads, writes, and deletes agree.
#' A relative folder is relative to the project root.
#'
#' @return The cache directory path
#' @keywords internal
.get_cache_dir <- function() {
  # Check for environment variable override first
  env_cache <- Sys.getenv("FW_CACHE_DIR", "")
  if (nzchar(env_cache)) {
    return(.fw_project_path(env_cache))
  }

  # Fall back to config
  cache_dir <- tryCatch(config("cache"), error = function(e) NULL)
  if (is.null(cache_dir)) {
    cache_dir <- tryCatch(config("options.data.cache_dir"), error = function(e) NULL)
  }
  if (!is.character(cache_dir) || length(cache_dir) != 1 || !nzchar(cache_dir)) {
    # Default fallback
    cache_dir <- "outputs/cache"
  }
  .fw_project_path(cache_dir)
}

# The file behind a cache entry: `file` when given (relative to the project
# root), otherwise <cache dir>/<name>.rds
#' @keywords internal
.cache_file_path <- function(name, file = NULL) {
  if (is.null(file)) file.path(.get_cache_dir(), paste0(name, ".rds")) else .fw_project_path(file)
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
#' @param name The name for the output file (without extension). A name
#'   with `/`, such as `"meeting-2026-10-16/cohort"`, saves into subfolders
#'   of the output folder, which are created as needed.
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
  # R matches a writer argument such as `na =` to `name` by partial
  # matching, which shifts the real name into `format`. Say so plainly.
  given <- names(as.list(sys.call()))[-1L] %||% character()
  partial <- given[nzchar(given) & !given %in% c("name", "data", "format", "public", "overwrite") &
                     startsWith("name", given)]
  if (length(partial) > 0 && !"name" %in% given) {
    cli::cli_abort(c(
      "{.arg {partial[1]}} was matched to {.arg name}.",
      "i" = "Spell out {.arg name}, as in {.code save_table(df, name = \"x\", {partial[1]} = ...)}."
    ))
  }
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
  # A name with / saves into subfolders
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)

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
      path = file_path,
      type = "table",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to save table: {e$message}")
  })
  .fw_warn_public_save(file_path, public)

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
#' With `plot = NULL`, Framework saves the plot on the active graphics device,
#' base graphics or ggplot2. Some devices keep no record of what they drew,
#' such as the `Rplots.pdf` device in `Rscript`. There, a ggplot drawn last
#' is saved with [ggplot2::last_plot()], and a base plot drawn last is an
#' error. Call `dev.control("enable")` before plotting, or pass
#' `recordPlot()`.
#'
#' @param plot A ggplot2 object, a recorded plot from [grDevices::recordPlot()],
#'   or NULL to save the current plot
#' @param name The name for the output file (without extension). A name
#'   with `/`, such as `"meeting-2026-10-16/cohort"`, saves into subfolders
#'   of the output folder, which are created as needed.
#' @param format Output format: "png" (default), "pdf", "svg", "eps", "jpg",
#'   "jpeg", "tiff", or "emf", or a vector of them, such as
#'   `c("pdf", "png", "svg")`, to save one file per format. Each file gets its
#'   own row in [result_list()]. Every format, and every existing file when
#'   `overwrite = FALSE`, is checked before anything is written. emf needs the
#'   devEMF package.
#' @param width Width in inches (default: 8)
#' @param height Height in inches (default: 6)
#' @param dpi Resolution in dots per inch (default: 300)
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param ... Additional arguments passed to ggsave or the graphics device
#'
#' @return The path to the saved file (invisibly), or the paths in the order
#'   of `format` when it names several formats
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
#' # Save one figure in several formats for a journal
#' save_figure(p, "journal/figure_2", format = c("pdf", "eps", "png"))
#'
#' # Save to public directory
#' save_figure(p, "summary_plot", public = TRUE)
#'
#' # Save a base R plot
#' plot(mtcars$mpg, mtcars$hp)
#' save_figure(name = "mpg_vs_hp_base")
#' }
#' }
#'
#' @export
save_figure <- function(plot = NULL, name, format = "png", width = 8, height = 6,
                        dpi = 300, public = FALSE, overwrite = TRUE, ...) {
  checkmate::assert_string(name, min.chars = 1)
  formats <- .fw_figure_formats(format)
  checkmate::assert_number(width, lower = 0.1)
  checkmate::assert_number(height, lower = 0.1)
  checkmate::assert_number(dpi, lower = 1)
  checkmate::assert_flag(public)
  checkmate::assert_flag(overwrite)
  if (!is.null(plot) && !inherits(plot, c("ggplot", "gg", "recordedplot"))) {
    cli::cli_abort("plot must be a ggplot2 object, a recordPlot() result, or NULL (to save the current plot)")
  }
  if (is.null(plot)) plot <- .fw_current_plot()

  # Get the appropriate figures directory
  figures_dir <- .output_dir("figures", public)

  # Ensure directory exists (lazy creation)
  .ensure_output_dir(figures_dir, "figures")

  # One file per format; every one is checked before any is written
  file_paths <- file.path(figures_dir, paste0(name, ".", formats))
  if (!overwrite) {
    for (file_path in file_paths[file.exists(file_paths)]) {
      cli::cli_abort("File already exists: {.path {file_path}}. Use overwrite = TRUE to replace.")
    }
  }
  # A name with / saves into subfolders
  dir.create(dirname(file_paths[1]), recursive = TRUE, showWarnings = FALSE)

  # Save the figure
  for (i in seq_along(formats)) {
    file_path <- file_paths[i]
    tryCatch({
      if (inherits(plot, "recordedplot")) {
        .fw_save_recorded_plot(plot, file_path, formats[i], width, height, dpi, ...)
      } else {
        ggplot2::ggsave(file_path, plot = plot, device = .fw_ggsave_device(formats[i]),
                        width = width, height = height, dpi = dpi, ...)
      }
      cli::cli_alert_success("Saved figure to {.path {file_path}}")

      # Log to results database
      .save_result(
        path = file_path,
        type = "figure",
        public = public
      )
    }, error = function(e) {
      cli::cli_abort("Failed to save figure: {e$message}")
    })
    .fw_warn_public_save(file_path, public)
  }

  invisible(file_paths)
}

# The formats save_figure() writes, checked before any file is written:
# one format or several, duplicates dropped keeping the first.
.fw_figure_formats <- function(format) {
  allowed <- c("png", "pdf", "svg", "eps", "jpg", "jpeg", "tiff", "emf")
  if (is.list(format) && all(vapply(format, checkmate::test_string, logical(1)))) {
    format <- unlist(format, use.names = FALSE)
  }
  if (!is.character(format) || length(format) == 0L || anyNA(format)) {
    cli::cli_abort("format must be a format name or a vector of them")
  }
  formats <- unique(format)
  unknown <- setdiff(formats, allowed)
  if (length(unknown) > 0L) {
    cli::cli_abort("format must be one of {paste(allowed, collapse = ', ')} (got {unknown[1]})")
  }
  if ("emf" %in% formats && !.fw_emf_available()) {
    cli::cli_abort(paste(
      "emf needs the devEMF package, which isn't installed.",
      "Install it with install.packages(\"devEMF\"), or save svg or pdf and convert them",
      "(for example with Inkscape or LibreOffice)."
    ))
  }
  formats
}

.fw_emf_available <- function() requireNamespace("devEMF", quietly = TRUE)

# The ggsave() device for a format: devEMF for emf, else ggsave()'s own
# choice by file extension (eps is PostScript with onefile = FALSE).
.fw_ggsave_device <- function(format) {
  if (identical(format, "emf")) devEMF::emf else NULL
}

# The plot save_figure(plot = NULL) should save: the active device's display
# list when it has one, else the last ggplot if ggplot2 drew last.
.fw_current_plot <- function() {
  if (grDevices::dev.cur() > 1L) {
    recorded <- tryCatch(suppressWarnings(grDevices::recordPlot()), error = function(e) NULL)
    if (!is.null(recorded) && length(recorded[[1]]) > 0L) return(recorded)
  }
  last_system <- .framework_env$last_plot_system
  if (identical(last_system, "base")) {
    cli::cli_abort(c(
      "The current base R plot can't be saved: this graphics device keeps no record of it.",
      "i" = "Run {.code dev.control(\"enable\")} before plotting, or pass {.code recordPlot()} as {.arg plot}."
    ))
  }
  last <- if (requireNamespace("ggplot2", quietly = TRUE)) ggplot2::last_plot() else NULL
  if (is.null(last)) {
    cli::cli_abort("No plot to save. Draw a plot first or pass one as {.arg plot}.")
  }
  last
}

.fw_save_recorded_plot <- function(plot, file_path, format, width, height, dpi, ...) {
  previous <- grDevices::dev.cur()
  switch(format,
    png = grDevices::png(file_path, width = width, height = height, units = "in", res = dpi, ...),
    jpg = ,
    jpeg = grDevices::jpeg(file_path, width = width, height = height, units = "in", res = dpi, ...),
    tiff = grDevices::tiff(file_path, width = width, height = height, units = "in", res = dpi, ...),
    pdf = grDevices::pdf(file_path, width = width, height = height, ...),
    svg = grDevices::svg(file_path, width = width, height = height, ...),
    eps = grDevices::postscript(file_path, width = width, height = height, onefile = FALSE,
                                horizontal = FALSE, paper = "special", ...),
    emf = devEMF::emf(file = file_path, width = width, height = height, ...)
  )
  device <- grDevices::dev.cur()
  on.exit({
    grDevices::dev.off(device)
    if (previous > 1L && previous %in% grDevices::dev.list()) grDevices::dev.set(previous)
  }, add = TRUE)
  grDevices::replayPlot(plot)
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
#' @param name The name for the output file (without extension). A name
#'   with `/`, such as `"meeting-2026-10-16/cohort"`, saves into subfolders
#'   of the output folder, which are created as needed.
#' @param public If TRUE, saves to public outputs directory (for project_sensitive type)
#' @param overwrite If TRUE, overwrites existing files (default: TRUE)
#' @param ... Additional arguments passed to [saveRDS()]
#'
#' @return The path to the saved file (invisibly)
#'
#' @details Many fitted models keep the data they were fitted on: `lm()`
#'   keeps its model frame, `glm()` its data and `y`, and `lme4` its frame.
#'   With `public = TRUE`, a model that holds data rows is saved with a
#'   warning, since the rows go to the public folder with it. Refit with
#'   `model = FALSE` (and without `y = TRUE` or `x = TRUE`), or save the
#'   estimates with [save_table()]. [load_model()] reads a saved model back.
#'
#'   In a project with `security: sensitive: true`, [save_table()],
#'   [save_figure()], and `save_model()` with `public = TRUE` warn after
#'   saving when this session has read private data with [data_read()] (a
#'   catalog entry that is private, or a file in a folder named like private,
#'   confidential, or sensitive). The save still happens; check that the
#'   output holds only aggregated or de-identified results before sharing it.
#'   A model that also holds data rows gives one warning naming both.
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
  # A public model that holds data rows warns before saving
  rows_warned <- .fw_warn_model_rows(model, name, public, .fw_private_read_note())

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
  # A name with / saves into subfolders
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)

  # Save the model
  tryCatch({
    saveRDS(model, file_path, ...)
    cli::cli_alert_success("Saved model to {.path {file_path}}")

    # Log to results database
    .save_result(
      path = file_path,
      type = "model",
      public = public
    )
  }, error = function(e) {
    cli::cli_abort("Failed to save model: {e$message}")
  })
  # One warning per save: the data rows warning names the private reads
  if (!rows_warned) .fw_warn_public_save(file_path, public)

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
#' Renders a Quarto, R Markdown, or Jupyter notebook and saves the output to
#' the configured notebooks output directory. The directory is created lazily
#' on first use.
#'
#' Quarto renders a Jupyter notebook (.ipynb) from the outputs saved in it,
#' without running its cells, so run the notebook before saving it.
#'
#' @param file Path to the .qmd, .Rmd, or .ipynb file to render
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
#' # A Jupyter notebook, rendered from its saved outputs
#' save_notebook("notebooks/analysis.ipynb")
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
  checkmate::assert_file_exists(file, extension = c("qmd", "Qmd", "QMD", "rmd", "Rmd", "RMD", "ipynb", "IPYNB"))
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
      # Plain stop(): Quarto's output can hold braces cli would read as glue
      stop(paste(c("Quarto render failed:", utils::tail(cli::ansi_strip(result), 40)), collapse = "\n"), call. = FALSE)
    }

    # Find the output file
    output_pattern <- switch(format,
      html = "\\.html$",
      pdf = "\\.pdf$",
      docx = "\\.docx$"
    )
    # Inside a Quarto project the output keeps the notebook's folder
    # (notebooks/x.qmd renders to <output-dir>/notebooks/x.html)
    output_files <- list.files(temp_dir, pattern = output_pattern, full.names = TRUE, recursive = TRUE)

    if (length(output_files) == 0) {
      cli::cli_abort("No {format} output found after rendering")
    }

    # Move output to destination
    file.copy(output_files[1], dest_file, overwrite = overwrite)

    cli::cli_alert_success("Saved notebook to {.path {dest_file}}")

    # Log to results database
    .save_result(
      path = dest_file,
      type = "notebook",
      public = public
    )
  }, error = function(e) {
    # conditionMessage() keeps Quarto's error text; e$message dropped it
    # stop(), not cli: cli would fold Quarto's lines into one
    stop("Failed to render notebook: ", conditionMessage(e), call. = FALSE)
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

  # Read only: never create framework.db in the working folder.
  con <- tryCatch(.fw_results_connection(create = FALSE), error = function(e) NULL)

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
#' @param verbose Has no effect. Every section is always shown, including the
#'   project name and type that `verbose` adds in the Python package.
#'
#' @return A data frame with directory information (invisibly)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Show project structure
#' project_info()
#'
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
  cache_shown <- .fw_project_relative_path(cache_dir)
  cli::cli_text("  {.field cache}: {.path {cache_shown}} {cache_status}{cache_note}")

  cli::cli_text("")
  cli::cli_h2("Output Functions")
  # The folders the save_*() functions write to. In a sensitive project they
  # split into private (the default) and public (public = TRUE).
  for (kind in c("tables", "figures", "models", "notebooks", "reports")) {
    fn <- paste0("save_", sub("s$", "", kind))
    private_dir <- .output_dir(kind, public = FALSE)
    public_dir <- .output_dir(kind, public = TRUE)
    if (identical(private_dir, public_dir)) {
      cli::cli_text("  {.fn {fn}} \u2192 {.path {private_dir}}")
    } else {
      cli::cli_text("  {.fn {fn}} \u2192 {.path {private_dir}}, or {.path {public_dir}} with {.code public = TRUE}")
    }
  }

  invisible(dir_info)
}
