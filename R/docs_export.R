#' Export Package Documentation to Database
#'
#' Parses roxygen2-generated .Rd files and exports structured documentation
#' to SQLite (for GUI) or other formats. This enables searchable documentation
#' in the Framework GUI and powers the public documentation website.
#'
#' @param output_path Path to SQLite database file. Default: "docs.db"
#' @param man_dir Directory containing .Rd files. Default: "man"
#' @param package_name Package name for metadata. Default: "framework"
#' @param package_version Package version for metadata. Default: NULL (auto-detect)
#' @param include_internal Include functions that are not exported or are
#'   tagged `@keywords internal` (such as `.has_column()`). Default: FALSE
#' @param verbose Print progress messages. Default: TRUE
#' @param reference_path If set, also write the reference for the docs site
#'   (`docs/site/reference.json`) to this path, in the format of
#'   `inst/schema/docs-reference.v1.json`. Default: NULL
#'
#' @return Invisibly returns the database connection path
#'
#' @details
#' The exporter reads all .Rd files from the man/ directory and extracts:
#' - Function name, title, description, details
#' - Arguments/parameters with descriptions
#' - Usage signatures
#' - Examples (with dontrun detection)
#' - See Also references
#' - Custom sections and subsections
#' - Keywords
#'
#' The SQLite output includes FTS5 full-text search for fast querying.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Export to default location (exported functions only)
#' docs_export()
#'
#' # Export to custom location
#' docs_export("inst/gui/docs.db")
#'
#' # Include internal/private functions too
#' docs_export("all_docs.db", include_internal = TRUE)
#'
#' # Query the exported docs
#' con <- DBI::dbConnect(RSQLite::SQLite(), "docs.db")
#' DBI::dbGetQuery(con, "SELECT name, title FROM functions WHERE name LIKE 'data_%'")
#' DBI::dbDisconnect(con)
#' }
#' }
#'
#' @export
docs_export <- function(output_path = "docs.db",
                        man_dir = "man",
                        package_name = "framework",
                        package_version = NULL,
                        include_internal = FALSE,
                        verbose = TRUE,
                        reference_path = NULL) {

  if (!dir.exists(man_dir)) {
    stop("man directory not found: ", man_dir)
  }

  rd_files <- list.files(man_dir, pattern = "\\.Rd$", full.names = TRUE)
  if (length(rd_files) == 0) {
    stop("No .Rd files found in ", man_dir)
  }

  # NAMESPACE and DESCRIPTION belong to the package that holds man_dir
  pkg_root <- dirname(normalizePath(man_dir, mustWork = FALSE))
  pkg_file <- function(name) {
    path <- file.path(pkg_root, name)
    if (file.exists(path)) path else name
  }

  # Get exported functions from NAMESPACE if filtering internal
 exported_names <- NULL
  if (!include_internal && file.exists(pkg_file("NAMESPACE"))) {
    ns_lines <- readLines(pkg_file("NAMESPACE"), warn = FALSE)
    export_lines <- grep("^export\\(", ns_lines, value = TRUE)
    exported_names <- gsub("^export\\((.+)\\)$", "\\1", export_lines)
    if (verbose) message("Found ", length(exported_names), " exported functions in NAMESPACE")
  }

  if (verbose) message("Found ", length(rd_files), " .Rd files")

  # Auto-detect version from DESCRIPTION if not provided
 if (is.null(package_version)) {
    if (file.exists(pkg_file("DESCRIPTION"))) {
      desc <- read.dcf(pkg_file("DESCRIPTION"))
      package_version <- desc[1, "Version"]
    } else {
      package_version <- "unknown"
    }
  }

  # Initialize database
  if (file.exists(output_path)) {
    file.remove(output_path)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), output_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Create schema - execute inline for reliability
  # (Avoids issues with statement splitting in complex SQL)
  .create_docs_schema(con)

  # Load and insert categories
  category_map <- .load_category_map()
  category_ids <- .insert_categories(con, category_map)
  common_functions <- category_map$common_functions

  # Insert metadata
  DBI::dbExecute(con,
    "INSERT INTO metadata (key, value) VALUES (?, ?)",
    params = list("package_name", package_name)
  )
  DBI::dbExecute(con,
    "INSERT INTO metadata (key, value) VALUES (?, ?)",
    params = list("package_version", package_version)
  )
  DBI::dbExecute(con,
    "INSERT INTO metadata (key, value) VALUES (?, ?)",
    params = list("export_date", as.character(Sys.time()))
  )
  DBI::dbExecute(con,
    "INSERT INTO metadata (key, value) VALUES (?, ?)",
    params = list("rd_file_count", as.character(length(rd_files)))
  )

  # Process each .Rd file
  skipped <- 0
  for (i in seq_along(rd_files)) {
    rd_file <- rd_files[i]
    if (verbose && i %% 50 == 0) {
      message("Processing ", i, "/", length(rd_files), "...")
    }

    tryCatch({
      result <- .export_rd_file(con, rd_file, exported_names, category_ids, common_functions,
                                include_internal = include_internal)
      if (!result) skipped <- skipped + 1
    }, error = function(e) {
      warning("Error processing ", basename(rd_file), ": ", e$message)
    })
  }

  if (verbose && skipped > 0) {
    message("Skipped ", skipped, " internal/non-exported functions")
  }

  if (verbose) {
    func_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM functions")$n
    message("Exported ", func_count, " functions to ", output_path)
  }

  if (!is.null(reference_path)) {
    .docs_write_reference(output_path, reference_path, package_version)
    if (verbose) message("Wrote the docs site reference to ", reference_path)
  }

  invisible(output_path)
}


#' Parse and export a single .Rd file to the database
#' @noRd
#' @return TRUE if exported, FALSE if skipped
.export_rd_file <- function(con, rd_file, exported_names = NULL, category_ids = NULL, common_functions = NULL,
                            include_internal = FALSE) {
  rd <- tools::parse_Rd(rd_file)

  # Get function name first to check if exported
  name <- .rd_get_text(.rd_get_tag(rd, "\\name"))

 # Skip if not in exported list (when filtering is enabled)
  if (!is.null(exported_names) && !(name %in% exported_names)) {
    return(FALSE)
  }

  # Extract source file from comment
  source_file <- NULL
  for (el in rd) {
    if (!is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "COMMENT") {
      if (grepl("Please edit documentation in", el)) {
        source_file <- sub(".*documentation in ([^ ]+).*", "\\1", el)
      }
    }
  }

  # Extract main fields
  name <- .rd_get_text(.rd_get_tag(rd, "\\name"))
  title <- .rd_get_text(.rd_get_tag(rd, "\\title"))
  description <- .normalize_prose(.rd_render_content(.rd_get_tag(rd, "\\description")))
  details <- .normalize_prose(.rd_render_content(.rd_get_tag(rd, "\\details")))
  usage_raw <- .rd_get_text(.rd_get_tag(rd, "\\usage"))

  # Filter usage to only show primary function (remove alias usage lines)
  # Usage often contains multiple function calls when aliases exist
  # Multi-line function calls are separated by blank lines in usage
  usage <- if (!is.null(usage_raw) && !is.null(name)) {
    # Split by double newlines (blank lines) to separate different function usages
    usage_blocks <- strsplit(usage_raw, "\n\n+")[[1]]
    # Keep blocks that start with the main function name
    primary_blocks <- usage_blocks[grepl(paste0("^\\s*", name, "\\s*\\("), usage_blocks)]
    if (length(primary_blocks) > 0) {
      trimws(paste(primary_blocks, collapse = "\n\n"))
    } else {
      usage_raw  # Fallback to original if filtering fails
    }
  } else {
    usage_raw
  }

  value <- .normalize_prose(.rd_render_content(.rd_get_tag(rd, "\\value")))
  note <- .normalize_prose(.rd_render_content(.rd_get_tag(rd, "\\note")))

  # Extract keywords
  keywords <- c()

  for (el in rd) {
    if (!is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "\\keyword") {
      keywords <- c(keywords, .rd_get_text(el))
    }
  }
  keywords_str <- if (length(keywords) > 0) paste(keywords, collapse = ",") else NULL

  # Skip functions marked as internal (unless include_internal is TRUE)
  if ("internal" %in% keywords && !isTRUE(include_internal)) {
    return(FALSE)
  }

  # Look up category_id for this function
  category_id <- category_ids[[name]]

  # Check if this is a common function
  is_common <- if (!is.null(common_functions) && name %in% common_functions) 1L else 0L

  # Insert function (convert NULL to NA for DBI)
  .null_to_na <- function(x) if (is.null(x)) NA_character_ else x
  .null_to_na_int <- function(x) if (is.null(x)) NA_integer_ else as.integer(x)

  DBI::dbExecute(con,
    "INSERT INTO functions (name, title, description, details, usage, value, note, source_file, keywords, category_id, is_common)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      .null_to_na(name),
      .null_to_na(title),
      .null_to_na(description),
      .null_to_na(details),
      .null_to_na(usage),
      .null_to_na(value),
      .null_to_na(note),
      .null_to_na(source_file),
      .null_to_na(keywords_str),
      .null_to_na_int(category_id),
      is_common
    )
  )

  func_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id

  # Extract and insert aliases
  for (el in rd) {
    if (!is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "\\alias") {
      alias <- .rd_get_text(el)
      if (alias != name) {  # Don't duplicate the main name
        DBI::dbExecute(con,
          "INSERT OR IGNORE INTO aliases (function_id, alias) VALUES (?, ?)",
          params = list(func_id, alias)
        )
      }
    }
  }

  # Extract and insert arguments
  args_el <- .rd_get_tag(rd, "\\arguments")
  if (!is.null(args_el)) {
    position <- 0
    for (el in args_el) {
      if (is.list(el) && !is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "\\item") {
        if (length(el) >= 2) {
          param_name <- .rd_get_text(el[[1]])
          param_desc <- .rd_render_content(el[[2]])
          position <- position + 1
          DBI::dbExecute(con,
            "INSERT INTO parameters (function_id, name, description, position) VALUES (?, ?, ?, ?)",
            params = list(
              func_id,
              .null_to_na(param_name),
              .null_to_na(param_desc),
              position
            )
          )
        }
      }
    }
  }

  # Extract and insert examples
  examples_el <- .rd_get_tag(rd, "\\examples")
  if (!is.null(examples_el)) {
    .export_examples(con, func_id, examples_el)
  }

  # Extract and insert seealso
  seealso_el <- .rd_get_tag(rd, "\\seealso")
  if (!is.null(seealso_el)) {
    .export_seealso(con, func_id, seealso_el)
  }

  # Extract and insert sections
  position <- 0
  for (el in rd) {
    if (!is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "\\section") {
      position <- position + 1
      .export_section(con, func_id, el, position)
    }
  }

  # Extract subsections from details (if any)
  if (!is.null(details)) {
    details_el <- .rd_get_tag(rd, "\\details")
    if (!is.null(details_el)) {
      sub_position <- 0
      for (el in details_el) {
        if (is.list(el) && !is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "\\subsection") {
          sub_position <- sub_position + 1
          sub_title <- .rd_get_text(el[[1]])
          sub_content <- .rd_render_content(el[[2]])
          DBI::dbExecute(con,
            "INSERT INTO subsections (function_id, section_id, title, content, position)
             VALUES (?, NULL, ?, ?, ?)",
            params = list(func_id, sub_title, sub_content, sub_position)
          )
        }
      }
    }
  }

  TRUE
}


#' Get an Rd element by tag name
#' @noRd
.rd_get_tag <- function(rd, tag) {
  for (el in rd) {
    if (!is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == tag) {
      return(el)
    }
  }
  NULL
}


#' Normalize prose text by collapsing line breaks within paragraphs
#' Preserves intentional breaks (double newlines, list items)
#' @noRd
.normalize_prose <- function(text) {

  if (is.null(text) || !nzchar(text)) return(text)

  # Split into lines first
  lines <- strsplit(text, "\n")[[1]]

  # Process line by line, preserving list items and code blocks
  result_lines <- c()
  current_prose <- c()
  in_code_block <- FALSE

  for (line in lines) {
    # Check for code fence markers
    is_code_fence <- grepl("^```", trimws(line))

    if (is_code_fence) {
      # Flush any accumulated prose before code block
      if (length(current_prose) > 0) {
        result_lines <- c(result_lines, paste(current_prose, collapse = " "))
        current_prose <- c()
      }
      # Toggle code block state
      in_code_block <- !in_code_block
      # Add fence marker as-is
      result_lines <- c(result_lines, line)
      next
    }

    if (in_code_block) {
      # Inside code block - preserve lines exactly
      result_lines <- c(result_lines, line)
      next
    }

    # Check if this line is a list item (starts with - or number.)
    is_list_item <- grepl("^\\s*[-*]\\s|^\\s*\\d+\\.\\s", line)
    is_blank <- !nzchar(trimws(line))

    if (is_list_item) {
      # Flush any accumulated prose
      if (length(current_prose) > 0) {
        result_lines <- c(result_lines, paste(current_prose, collapse = " "))
        current_prose <- c()
      }
      # Add list item as-is
      result_lines <- c(result_lines, line)
    } else if (is_blank) {
      # Blank line - flush prose and add paragraph break
      if (length(current_prose) > 0) {
        result_lines <- c(result_lines, paste(current_prose, collapse = " "))
        current_prose <- c()
      }
      result_lines <- c(result_lines, "")
    } else {
      # Regular prose - accumulate
      current_prose <- c(current_prose, trimws(line))
    }
  }

  # Flush remaining prose
  if (length(current_prose) > 0) {
    result_lines <- c(result_lines, paste(current_prose, collapse = " "))
  }

  # Join and clean up multiple blank lines
  result <- paste(result_lines, collapse = "\n")
  gsub("\n{3,}", "\n\n", result)
}

#' Extract plain text from an Rd element
#' @noRd
.rd_get_text <- function(el) {
  if (is.null(el)) return(NULL)
  if (is.character(el)) return(trimws(el))

  texts <- c()
  for (child in el) {
    if (is.character(child)) {
      texts <- c(texts, child)
    } else if (is.list(child)) {
      texts <- c(texts, .rd_get_text(child))
    }
  }
  result <- paste(texts, collapse = "")
  trimws(result)
}


#' Render Rd content to markdown-ish format
#' @noRd
.rd_render_content <- function(el, in_list = FALSE) {
  if (is.null(el)) return(NULL)
  if (is.character(el)) return(el)

  tag <- attr(el, "Rd_tag")

  # Handle different tags
  if (!is.null(tag)) {
    switch(tag,
      "\\code" = {
        return(paste0("`", .rd_get_text(el), "`"))
      },
      "\\verb" = {
        return(paste0("`", .rd_get_text(el), "`"))
      },
      "\\strong" = {
        return(paste0("**", .rd_get_text(el), "**"))
      },
      "\\emph" = {
        return(paste0("*", .rd_get_text(el), "*"))
      },
      "\\link" = {
        return(paste0("`", .rd_get_text(el), "()`"))
      },
      "\\href" = {
        if (length(el) >= 2) {
          url <- .rd_get_text(el[[1]])
          text <- .rd_get_text(el[[2]])
          return(paste0("[", text, "](", url, ")"))
        }
        return(.rd_get_text(el))
      },
      "\\itemize" = {
        # Items in itemize: \item is followed by TEXT siblings until the next \item
        items <- c()
        current_item <- NULL
        for (child in el) {
          tag <- attr(child, "Rd_tag")
          if (!is.null(tag) && tag == "\\item") {
            # Save previous item if exists
            if (!is.null(current_item)) {
              items <- c(items, paste0("- ", trimws(current_item)))
            }
            # Start new item - check if \item has content inside or is empty
            if (is.list(child) && length(child) > 0) {
              current_item <- .rd_render_content(child, in_list = TRUE)
            } else {
              current_item <- ""
            }
          } else if (!is.null(current_item)) {
            # Append to current item
            current_item <- paste0(current_item, .rd_render_content(child, in_list = TRUE))
          }
        }
        # Don't forget the last item
        if (!is.null(current_item) && nzchar(trimws(current_item))) {
          items <- c(items, paste0("- ", trimws(current_item)))
        }
        return(paste(items, collapse = "\n"))
      },
      "\\enumerate" = {
        # Items in enumerate: \item is followed by TEXT siblings until the next \item
        items <- c()
        idx <- 0
        current_item <- NULL
        for (child in el) {
          tag <- attr(child, "Rd_tag")
          if (!is.null(tag) && tag == "\\item") {
            # Save previous item if exists
            if (!is.null(current_item) && nzchar(trimws(current_item))) {
              idx <- idx + 1
              items <- c(items, paste0(idx, ". ", trimws(current_item)))
            }
            # Start new item - check if \item has content inside or is empty
            if (is.list(child) && length(child) > 0) {
              current_item <- .rd_render_content(child, in_list = TRUE)
            } else {
              current_item <- ""
            }
          } else if (!is.null(current_item) || idx == 0) {
            # Append to current item (or start collecting if no \item seen yet but that's rare)
            if (is.null(current_item)) current_item <- ""
            current_item <- paste0(current_item, .rd_render_content(child, in_list = TRUE))
          }
        }
        # Don't forget the last item
        if (!is.null(current_item) && nzchar(trimws(current_item))) {
          idx <- idx + 1
          items <- c(items, paste0(idx, ". ", trimws(current_item)))
        }
        return(paste(items, collapse = "\n"))
      },
      "\\describe" = {
        items <- c()
        for (child in el) {
          if (is.list(child) && !is.null(attr(child, "Rd_tag")) && attr(child, "Rd_tag") == "\\item") {
            if (length(child) >= 2) {
              term <- .rd_get_text(child[[1]])
              desc <- .rd_render_content(child[[2]])
              items <- c(items, paste0("**", term, "**: ", trimws(desc)))
            }
          }
        }
        return(paste(items, collapse = "\n"))
      },
      "\\preformatted" = {
        # Preserve newlines in preformatted blocks
        texts <- c()
        for (child in el) {
          if (is.character(child)) {
            texts <- c(texts, child)
          }
        }
        code_content <- paste(texts, collapse = "")
        return(paste0("```\n", code_content, "\n```"))
      },
      "\\dontrun" = {
        return(.rd_render_content(el[[1]]))
      },
      "\\if" = {
        # Conditional output - skip HTML-specific content
        # Format: \if{condition}{content}
        # We're generating markdown, so skip html conditionals
        if (length(el) >= 1) {
          condition <- .rd_get_text(el[[1]])
          if (condition == "html") {
            # Skip HTML-specific content entirely
            return("")
          }
        }
        # For other conditions, try to render content
        if (length(el) >= 2) {
          return(.rd_render_content(el[[2]], in_list))
        }
        return("")
      },
      "\\out" = {
        # Raw output - skip as it's typically HTML
        return("")
      },
      "\\item" = {
        # For list items, render children
        texts <- c()
        for (child in el) {
          texts <- c(texts, .rd_render_content(child, in_list))
        }
        return(paste(texts, collapse = ""))
      }
    )
  }

  # Default: recurse through children
  texts <- c()
  for (child in el) {
    texts <- c(texts, .rd_render_content(child, in_list))
  }
  paste(texts, collapse = "")
}


#' Export examples from Rd
#' @noRd
.export_examples <- function(con, func_id, examples_el) {
  # Collect all example code
  code_parts <- c()
  in_dontrun <- FALSE
  dontrun_parts <- c()

  .collect_examples <- function(el, is_dontrun = FALSE) {
    tag <- attr(el, "Rd_tag")

    if (!is.null(tag) && tag == "\\dontrun") {
      # Process dontrun content
      for (child in el) {
        .collect_examples(child, is_dontrun = TRUE)
      }
      return()
    }

    if (is.character(el)) {
      code <- el
      if (nchar(trimws(code)) > 0) {
        if (is_dontrun) {
          dontrun_parts <<- c(dontrun_parts, code)
        } else {
          code_parts <<- c(code_parts, code)
        }
      }
      return()
    }

    if (is.list(el)) {
      for (child in el) {
        .collect_examples(child, is_dontrun)
      }
    }
  }

  .collect_examples(examples_el)

  # Insert runnable examples
  if (length(code_parts) > 0) {
    code <- trimws(paste(code_parts, collapse = ""))
    if (nchar(code) > 0) {
      DBI::dbExecute(con,
        "INSERT INTO examples (function_id, code, is_dontrun, position) VALUES (?, ?, 0, 1)",
        params = list(func_id, code)
      )
    }
  }

  # Insert dontrun examples
  if (length(dontrun_parts) > 0) {
    code <- trimws(paste(dontrun_parts, collapse = ""))
    if (nchar(code) > 0) {
      DBI::dbExecute(con,
        "INSERT INTO examples (function_id, code, is_dontrun, position) VALUES (?, ?, 1, 2)",
        params = list(func_id, code)
      )
    }
  }
}


#' Export seealso references
#' @noRd
.export_seealso <- function(con, func_id, seealso_el) {
  .extract_refs <- function(el) {
    tag <- attr(el, "Rd_tag")

    if (!is.null(tag) && tag == "\\link") {
      ref <- .rd_get_text(el)
      DBI::dbExecute(con,
        "INSERT INTO seealso (function_id, reference, link_type) VALUES (?, ?, 'function')",
        params = list(func_id, ref)
      )
      return()
    }

    if (!is.null(tag) && tag == "\\href") {
      if (length(el) >= 2) {
        url <- .rd_get_text(el[[1]])
        text <- .rd_get_text(el[[2]])
        DBI::dbExecute(con,
          "INSERT INTO seealso (function_id, reference, link_type, url) VALUES (?, ?, 'url', ?)",
          params = list(func_id, text, url)
        )
      }
      return()
    }

    if (is.list(el)) {
      for (child in el) {
        .extract_refs(child)
      }
    }
  }

  .extract_refs(seealso_el)
}


#' Export a section
#' @noRd
.export_section <- function(con, func_id, section_el, position) {
  if (length(section_el) < 2) return()

  title <- .rd_get_text(section_el[[1]])
  content <- .rd_render_content(section_el[[2]])

  DBI::dbExecute(con,
    "INSERT INTO sections (function_id, title, content, position) VALUES (?, ?, ?, ?)",
    params = list(func_id, title, content, position)
  )

  section_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id

  # Extract subsections
  sub_position <- 0
  for (el in section_el[[2]]) {
    if (is.list(el) && !is.null(attr(el, "Rd_tag")) && attr(el, "Rd_tag") == "\\subsection") {
      sub_position <- sub_position + 1
      sub_title <- .rd_get_text(el[[1]])
      sub_content <- .rd_render_content(el[[2]])
      DBI::dbExecute(con,
        "INSERT INTO subsections (function_id, section_id, title, content, position)
         VALUES (?, ?, ?, ?, ?)",
        params = list(func_id, section_id, sub_title, sub_content, sub_position)
      )
    }
  }
}


#' Create documentation database schema
#' @noRd
.create_docs_schema <- function(con) {
  # Categories table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT,
      position INTEGER
    )
  ")

  # Core function documentation
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS functions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      title TEXT,
      description TEXT,
      details TEXT,
      usage TEXT,
      value TEXT,
      note TEXT,
      source_file TEXT,
      keywords TEXT,
      category_id INTEGER,
      is_exported INTEGER DEFAULT 1,
      is_common INTEGER DEFAULT 0,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (category_id) REFERENCES categories(id)
    )
  ")

  # Function aliases
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS aliases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      function_id INTEGER NOT NULL,
      alias TEXT NOT NULL,
      FOREIGN KEY (function_id) REFERENCES functions(id) ON DELETE CASCADE,
      UNIQUE(function_id, alias)
    )
  ")

  # Function parameters
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS parameters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      function_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      position INTEGER,
      FOREIGN KEY (function_id) REFERENCES functions(id) ON DELETE CASCADE
    )
  ")

  # Examples
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS examples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      function_id INTEGER NOT NULL,
      code TEXT NOT NULL,
      is_dontrun INTEGER DEFAULT 0,
      position INTEGER,
      FOREIGN KEY (function_id) REFERENCES functions(id) ON DELETE CASCADE
    )
  ")

  # See Also references
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS seealso (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      function_id INTEGER NOT NULL,
      reference TEXT NOT NULL,
      link_type TEXT DEFAULT 'function',
      url TEXT,
      FOREIGN KEY (function_id) REFERENCES functions(id) ON DELETE CASCADE
    )
  ")

  # Custom sections
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS sections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      function_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      content TEXT,
      position INTEGER,
      FOREIGN KEY (function_id) REFERENCES functions(id) ON DELETE CASCADE
    )
  ")

  # Subsections
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS subsections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      function_id INTEGER NOT NULL,
      section_id INTEGER,
      title TEXT NOT NULL,
      content TEXT,
      position INTEGER,
      FOREIGN KEY (function_id) REFERENCES functions(id) ON DELETE CASCADE,
      FOREIGN KEY (section_id) REFERENCES sections(id) ON DELETE CASCADE
    )
  ")

  # Full-text search
  DBI::dbExecute(con, "
    CREATE VIRTUAL TABLE IF NOT EXISTS functions_fts USING fts5(
      name,
      title,
      description,
      details,
      content=functions,
      content_rowid=id
    )
  ")

  # FTS triggers
  DBI::dbExecute(con, "
    CREATE TRIGGER IF NOT EXISTS functions_ai AFTER INSERT ON functions BEGIN
      INSERT INTO functions_fts(rowid, name, title, description, details)
      VALUES (new.id, new.name, new.title, new.description, new.details);
    END
  ")

  DBI::dbExecute(con, "
    CREATE TRIGGER IF NOT EXISTS functions_ad AFTER DELETE ON functions BEGIN
      INSERT INTO functions_fts(functions_fts, rowid, name, title, description, details)
      VALUES('delete', old.id, old.name, old.title, old.description, old.details);
    END
  ")

  DBI::dbExecute(con, "
    CREATE TRIGGER IF NOT EXISTS functions_au AFTER UPDATE ON functions BEGIN
      INSERT INTO functions_fts(functions_fts, rowid, name, title, description, details)
      VALUES('delete', old.id, old.name, old.title, old.description, old.details);
      INSERT INTO functions_fts(rowid, name, title, description, details)
      VALUES (new.id, new.name, new.title, new.description, new.details);
    END
  ")

  # Indexes
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_aliases_alias ON aliases(alias)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_parameters_function ON parameters(function_id)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_examples_function ON examples(function_id)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_seealso_function ON seealso(function_id)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_functions_keywords ON functions(keywords)")

  # Metadata table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS metadata (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ")

  # Index for category lookups
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_functions_category ON functions(category_id)")
}


#' Load category map from YAML
#' @noRd
.load_category_map <- function() {
  # Try package location first
  yaml_path <- system.file("docs-export/categories.yml", package = "framework")
  if (yaml_path == "") {
    # Fallback for development
    yaml_path <- "inst/docs-export/categories.yml"
  }

  if (!file.exists(yaml_path)) {
    warning("categories.yml not found, functions will have no categories")
    return(list(categories = list(), function_to_category = list(), common_functions = character()))
  }

  cats <- yaml::read_yaml(yaml_path)

  # Build function -> category name mapping and collect common functions
  func_to_cat <- list()
  common_funcs <- character()

  for (cat_name in names(cats)) {
    cat_info <- cats[[cat_name]]
    if (!is.null(cat_info$functions)) {
      for (fn in cat_info$functions) {
        func_to_cat[[fn]] <- cat_name
      }
    }
    # Collect common functions
    if (!is.null(cat_info$common)) {
      common_funcs <- c(common_funcs, cat_info$common)
    }
  }

  list(
    categories = cats,
    function_to_category = func_to_cat,
    common_functions = unique(common_funcs)
  )
}


#' Insert categories into database and return function -> category_id map
#' @noRd
.insert_categories <- function(con, category_map) {
  cats <- category_map$categories
  func_to_cat <- category_map$function_to_category

  # Insert categories and build name -> id map
  cat_name_to_id <- list()
  position <- 0

  for (cat_name in names(cats)) {
    position <- position + 1
    cat_info <- cats[[cat_name]]
    # Use display_name if provided, otherwise use the key name
    display_name <- cat_info$display_name %||% cat_name
    description <- cat_info$description %||% ""

    DBI::dbExecute(con,
      "INSERT INTO categories (name, description, position) VALUES (?, ?, ?)",
      params = list(display_name, description, position)
    )

    cat_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id
    cat_name_to_id[[cat_name]] <- cat_id
  }

  # Build function -> category_id map
  func_to_cat_id <- list()
  for (fn in names(func_to_cat)) {
    cat_name <- func_to_cat[[fn]]
    func_to_cat_id[[fn]] <- cat_name_to_id[[cat_name]]
  }

  func_to_cat_id
}
