# Reading and writing settings files without losing what the person wrote.
#
# yaml::write_yaml() on its own writes TRUE as `yes`, turns a one-item
# sequence such as `assistants: [claude]` into a scalar, and drops every
# comment. These helpers:
#
# - .fw_read_yaml() reads a file for editing: it marks sequences so a
#   one-item list stays a list, and keeps `!expr` tags.
# - .fw_as_yaml() / .fw_write_yaml() write true/false and keep marked
#   sequences as sequences.
# - .fw_yaml_set() changes one section of a file and rewrites only that
#   section's lines, leaving every other line byte for byte.

#' @keywords internal
.fw_yaml_read_handlers <- function() {
  list(
    seq = function(x) {
      scalars <- length(x) > 0 && all(vapply(x, function(e) {
        is.atomic(e) && length(e) == 1 && is.null(attr(e, "tag"))
      }, logical(1)))
      if (scalars && length(unique(vapply(x, function(e) class(e)[1], character(1)))) == 1) {
        x <- unlist(x, use.names = FALSE)
      }
      attr(x, "fw_seq") <- TRUE
      x
    },
    expr = function(x) structure(x, tag = "!expr")
  )
}

#' Read a YAML settings file for editing
#' @param file Path to the file.
#' @return The parsed content, with sequences marked so they write back as
#'   sequences.
#' @keywords internal
.fw_read_yaml <- function(file) {
  text <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  yaml::yaml.load(text, handlers = .fw_yaml_read_handlers())
}

# Turn marked one-item (or empty) vectors into lists, which yaml writes as
# sequences, and drop the marker.
.fw_yaml_prepare <- function(x) {
  # A data frame (from JSON) is a sequence of rows, not a map of columns
  if (is.data.frame(x)) {
    x <- lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
  }
  seq <- isTRUE(attr(x, "fw_seq"))
  if (!is.null(attr(x, "fw_seq"))) attr(x, "fw_seq") <- NULL
  if (is.list(x)) {
    if (length(x) > 0) {
      nms <- names(x)
      x[] <- lapply(x, function(e) if (is.null(e)) e else .fw_yaml_prepare(e))
      names(x) <- nms
    }
    return(x)
  }
  if (seq && is.atomic(x) && length(x) <= 1 && is.null(attr(x, "tag"))) {
    return(as.list(x))
  }
  x
}

#' Serialize settings to YAML text
#'
#' Like yaml::as.yaml(), but writes logicals as true/false and keeps
#' sequences that were read with .fw_read_yaml() as sequences.
#' @param x The value to write.
#' @return A YAML string.
#' @keywords internal
.fw_as_yaml <- function(x) {
  yaml::as.yaml(
    .fw_yaml_prepare(x),
    handlers = list(logical = function(v) {
      out <- ifelse(is.na(v), "~", ifelse(v, "true", "false"))
      class(out) <- "verbatim"
      out
    })
  )
}

#' Write settings to a YAML file
#' @param x The value to write.
#' @param file Path to the file.
#' @return Invisibly returns `file`.
#' @keywords internal
.fw_write_yaml <- function(x, file) {
  .fw_write_text(.fw_as_yaml(x), file)
  invisible(file)
}

.fw_write_text <- function(text, file) {
  con <- file(file, open = "wb")
  on.exit(close(con))
  writeChar(enc2utf8(text), con, eos = NULL, useBytes = TRUE)
}

#' Set one section of a YAML settings file
#'
#' Replaces the value at `keys` (one or two levels, such as `"data"` or
#' `c("default", "data")`) and rewrites only that block of lines; comments
#' and formatting elsewhere in the file stay as they were. When the block
#' can't be found safely (flow style, unusual layout), the whole file is
#' rewritten instead.
#'
#' @param file Path to the YAML file.
#' @param keys Character vector of one or two keys.
#' @param value The new value (NULL removes the key).
#' @return Invisibly returns `file`.
#' @keywords internal
.fw_yaml_set <- function(file, keys, value) {
  original <- if (file.exists(file)) readChar(file, file.info(file)$size, useBytes = TRUE) else NULL
  .fw_write_text(.fw_yaml_set_text(original, keys, value), file)
  invisible(file)
}

# .fw_yaml_set() on text: the YAML `text` (NULL for a new file) with the
# value at `keys` replaced, changing only that block when it can, or
# rewritten whole otherwise
#' @keywords internal
.fw_yaml_set_text <- function(text, keys, value) {
  stopifnot(is.character(keys), length(keys) %in% c(1, 2))

  full <- if (!is.null(text)) yaml::yaml.load(text, handlers = .fw_yaml_read_handlers()) else NULL
  if (!is.list(full)) full <- list()
  if (length(keys) == 2) {
    parent <- full[[keys[1]]]
    if (!is.list(parent)) parent <- list()
    parent[keys[2]] <- list(value)
    if (is.null(value)) parent[[keys[2]]] <- NULL
    full[[keys[1]]] <- parent
  } else {
    full[keys] <- list(value)
    if (is.null(value)) full[[keys]] <- NULL
  }

  rewritten <- .fw_as_yaml(full)
  if (!is.null(text)) {
    original <- text
    candidate <- tryCatch(.fw_yaml_replace_block(original, keys, value), error = function(e) NULL)
    if (!is.null(candidate)) {
      # The edit is right when the file reads as before with only that key
      # changed. Comparing with the original, not a re-serialized copy,
      # keeps formatting elsewhere (long numbers, quoting) from forcing a
      # whole-file rewrite.
      same <- tryCatch({
        expected <- yaml::yaml.load(original)
        if (!is.list(expected)) expected <- list()
        new_value <- yaml::yaml.load(.fw_as_yaml(list(v = value)))$v
        if (length(keys) == 2) {
          parent <- expected[[keys[1]]]
          if (!is.list(parent)) parent <- list()
          parent[keys[2]] <- list(new_value)
          if (is.null(value)) parent[[keys[2]]] <- NULL
          expected[[keys[1]]] <- parent
        } else {
          expected[keys] <- list(new_value)
          if (is.null(value)) expected[[keys]] <- NULL
        }
        identical(yaml::yaml.load(candidate), expected)
      }, error = function(e) FALSE)
      if (same) return(candidate)
    }
  }
  rewritten
}

# Replace the block for `keys` in YAML `text`, returning the new text, or
# NULL when the layout isn't one this can edit safely.
.fw_yaml_replace_block <- function(text, keys, value) {
  eol <- if (grepl("\r\n", text, fixed = TRUE)) "\r\n" else "\n"
  lines <- strsplit(text, eol, fixed = TRUE)[[1]]
  ends_with_eol <- endsWith(text, eol)
  if (length(lines) == 0) return(NULL)

  indent_of <- function(line) nchar(line) - nchar(sub("^ +", "", line))
  is_content <- function(line) grepl("\\S", line) && !grepl("^\\s*#", line)
  key_pattern <- function(key, indent) {
    sprintf("^%s(%s|\"%s\"|'%s'):(\\s|$)", strrep(" ", indent), .fw_regex_escape(key),
            .fw_regex_escape(key), .fw_regex_escape(key))
  }

  # The end (exclusive) of the block opened at line i: the next content line
  # at or below its indentation. Trailing blank lines and comments at or
  # below that indentation belong to what follows.
  block_end <- function(i, indent) {
    j <- i + 1
    while (j <= length(lines) && (!is_content(lines[j]) || indent_of(lines[j]) > indent)) j <- j + 1
    while (j - 1 > i && (!grepl("\\S", lines[j - 1]) ||
                         (grepl("^\\s*#", lines[j - 1]) && indent_of(lines[j - 1]) <= indent))) {
      j <- j - 1
    }
    j
  }

  find_key <- function(key, indent, from, to) {
    if (from > to) return(NA_integer_)
    hits <- which(grepl(key_pattern(key, indent), lines[from:to]))
    if (length(hits) == 0) NA_integer_ else from + hits[1] - 1L
  }

  render <- function(key, value, indent) {
    block <- .fw_as_yaml(stats::setNames(list(value), key))
    block_lines <- strsplit(sub("\n$", "", block), "\n", fixed = TRUE)[[1]]
    paste0(strrep(" ", indent), block_lines)
  }

  region_start <- 1L
  region_end <- length(lines)
  indent <- 0L
  if (length(keys) == 2) {
    p <- find_key(keys[1], 0L, 1L, length(lines))
    if (is.na(p)) return(NULL)
    # The parent must be a block mapping (nothing after the colon)
    if (!grepl(":\\s*(#.*)?$", lines[p])) return(NULL)
    p_end <- block_end(p, 0L)
    children <- if (p + 1 <= p_end - 1) (p + 1):(p_end - 1) else integer(0)
    children <- children[vapply(lines[children], is_content, logical(1))]
    if (length(children) == 0) return(NULL)
    indent <- indent_of(lines[children[1]])
    if (indent == 0) return(NULL)
    region_start <- p + 1L
    region_end <- p_end - 1L
  }
  key <- keys[length(keys)]

  k <- find_key(key, indent, region_start, region_end)
  new_block <- if (is.null(value)) character(0) else render(key, value, indent)
  if (is.na(k)) {
    if (is.null(value)) return(text)
    # Add the key after the last content line of the region
    content <- which(vapply(lines[region_start:region_end], is_content, logical(1)))
    at <- if (length(content) > 0) region_start + max(content) - 1L else region_start - 1L
    lines <- append(lines, new_block, after = at)
  } else {
    k_end <- block_end(k, indent)
    lines <- c(lines[seq_len(k - 1)], new_block,
               if (k_end <= length(lines)) lines[k_end:length(lines)] else character(0))
  }

  out <- paste(lines, collapse = eol)
  if (ends_with_eol || length(lines) == 0) out <- paste0(out, eol)
  out
}

.fw_regex_escape <- function(x) gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
