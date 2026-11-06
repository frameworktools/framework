#' Capture and Save Data to File
#'
#' @description
#' Saves data to a file in various formats based on the object type and specified format.
#' If no name is provided, uses the name of the object passed in.
#' If no location is provided, uses the scratch directory from the configuration.
#'
#' @param x The object to save
#' @param name Optional character string specifying the name of the file (without extension).
#'   If not provided, will use the name of the object passed in.
#' @param to Optional character string indicating the output format. One of: "text", "rds", "csv", "tsv".
#'   If not provided, will choose based on object type.
#' @param location Optional character string specifying the directory where the file should be saved.
#'   If NULL, uses the scratch directory from the configuration.
#' @param n Optional number of rows to capture for data frames (default: all rows)
#'
#' @return The input object `x` invisibly.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Save a character vector as text
#' scratch_capture(c("hello", "world"))
#'
#' # Save a data frame as TSV
#' scratch_capture(mtcars)
#'
#' # Save an R object as RDS
#' scratch_capture(list(a = 1, b = 2), to = "rds")
#' }
#' }
#'
#' @export
scratch_capture <- function(x, name = NULL, to = NULL, location = NULL, n = Inf) {
  # Validate arguments
  checkmate::assert_string(name, null.ok = TRUE)
  checkmate::assert_choice(to, c("text", "rds", "csv", "tsv"), null.ok = TRUE)
  checkmate::assert_string(location, null.ok = TRUE)
  checkmate::assert_number(n, lower = 0)

  # Get default location from config if not provided
  if (is.null(location)) {
    config <- settings_read()
    location <- config$directories$scratch %||%
      config$options$data$scratch_dir %||%
      "outputs/private/scratch"
  }

  # Create directory if it doesn't exist
  if (!dir.exists(location)) {
    tryCatch(
      dir.create(location, recursive = TRUE, showWarnings = FALSE),
      error = function(e) {
        stop(sprintf("Failed to create scratch directory '%s': %s", location, e$message))
      }
    )
  }

  # Get object name if not provided
  if (is.null(name)) {
    # Try to get the name of the object passed in
    name <- deparse(substitute(x))

    # If it's a pipe expression, try to get the name from the pipe chain
    if (grepl("\\|>", name)) {
      # Get all expressions in the pipe chain
      pipe_expr <- strsplit(name, "\\|>")[[1]]
      pipe_expr <- trimws(pipe_expr)

      # Look through the chain from right to left for a valid variable name
      for (expr in rev(pipe_expr)) {
        # Skip the capture() call itself
        if (grepl("^capture\\(\\)$", expr)) next

        # If we find a valid variable name, use it
        if (grepl("^[a-zA-Z][a-zA-Z0-9_.]*$", expr)) {
          name <- expr
          break
        }
      }

      # If we didn't find a valid name, use timestamp
      if (grepl("^capture_", name)) {
        name <- paste0("capture_", format(Sys.time(), "%Y%m%d_%H%M%S"))
      }
    } else if (grepl("\\(", name) || grepl("\\{", name)) {
      # For other complex expressions, use timestamp
      name <- paste0("capture_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    } else {
      # Clean up the name by removing any quotes and whitespace
      name <- gsub("[\"']", "", name)
      name <- trimws(name)
    }
  }

  # Determine output format if not specified
  if (is.null(to)) {
    if (is.data.frame(x) || inherits(x, "tbl")) {
      to <- "tsv"
    } else {
      # Default to text for everything else
      to <- "text"
    }
  }

  # Validate 'to' parameter
  if (!to %in% c("text", "rds", "csv", "tsv")) {
    stop("'to' must be one of: 'text', 'rds', 'csv', 'tsv'")
  }

  # Check if name already has an extension
  has_extension <- grepl("\\.(txt|tsv|csv|rds)$", name)
  if (has_extension) {
    # Extract base name and extension
    name_parts <- strsplit(name, "\\.")[[1]]
    base_name <- paste(name_parts[-length(name_parts)], collapse = ".")
    ext <- name_parts[length(name_parts)]

    # Override 'to' parameter with the extension from the filename
    to <- switch(ext,
      "txt" = "text",
      "tsv" = "tsv",
      "csv" = "csv",
      "rds" = "rds"
    )
    name <- base_name
  }

  # Handle data frames
  if (is.data.frame(x) || inherits(x, "tbl")) {
    # Limit rows if n is finite
    if (is.finite(n)) {
      x <- head(x, n)
    }

    if (to == "rds") {
      file_path <- file.path(location, paste0(name, ".rds"))
      saveRDS(x, file_path)
    } else if (to == "csv") {
      file_path <- file.path(location, paste0(name, ".csv"))
      # Quote fields that need it, so "Springfield, IL" stays one field.
      readr::write_csv(x, file_path, na = "NA")
    } else if (to == "tsv") {
      file_path <- file.path(location, paste0(name, ".tsv"))
      readr::write_tsv(x, file_path, na = "NA", quote = "needed")
    } else {
      stop("Data frames can only be saved as 'rds', 'csv', or 'tsv'")
    }
  } else if (is.vector(x) && !is.list(x)) {
    # Handle vectors
    if (to == "text") {
      file_path <- file.path(location, paste0(name, ".txt"))
      writeLines(as.character(x), file_path)
    } else if (to == "rds") {
      file_path <- file.path(location, paste0(name, ".rds"))
      saveRDS(x, file_path)
    } else {
      stop("Vectors can only be saved as 'text' or 'rds'")
    }
  } else {
    # Handle lists and other objects
    if (to == "text") {
      file_path <- file.path(location, paste0(name, ".txt"))
      # Plain lists read best as YAML. Classed lists such as lm fits and
      # their summaries print with their own methods, as does anything YAML
      # can't represent.
      yaml_text <- if (is.list(x) && !is.object(x)) {
        tryCatch(yaml::as.yaml(x, indent = 2), error = function(e) NULL)
      }
      if (!is.null(yaml_text)) {
        writeLines(
          c(
            sprintf("List of %d items:", length(x)),
            "",
            yaml_text
          ),
          file_path
        )
      } else {
        writeLines(capture.output(print(x)), file_path)
      }
    } else if (to == "rds") {
      file_path <- file.path(location, paste0(name, ".rds"))
      saveRDS(x, file_path)
    } else {
      stop("Complex objects can only be saved as 'text' or 'rds'")
    }
  }

  # Return the saved object invisibly
  invisible(x)
}

#' Clean up the scratch directory
#'
#' Deletes the files at the top of the scratch directory, dotfiles included.
#' Subfolders and their contents stay.
#' @return Invisibly returns NULL. Called for side effect of removing scratch files.
#' @export
scratch_clean <- function() {
  config <- settings_read()
  scratch_dir <- config$directories$scratch %||%
    config$options$data$scratch_dir %||%
    "outputs/private/scratch"

  if (dir.exists(scratch_dir)) {
    files <- list.files(scratch_dir, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    files <- files[!dir.exists(files)]
    file.remove(files)
    message("Scratch directory cleaned: ", scratch_dir)
  } else {
    message("Scratch directory does not exist: ", scratch_dir)
  }

  invisible(NULL)
}
