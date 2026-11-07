#' Show a table in a Quarto page or Jupyter notebook
#'
#' Makes a Markdown pipe table from a data frame, which Quarto turns into a
#' real table in every output format (HTML, PDF, Word), styled like the page,
#' so it stays small in a page with `embed-resources`. In a Quarto or R
#' Markdown chunk it is shown as the table; in Jupyter (IRkernel) it is shown
#' as Markdown; at the console it prints its Markdown. framework-py's
#' `show_table()` gives the same Markdown for the same data.
#'
#' Numeric columns are right-aligned and others left-aligned. Every row is
#' shown, so summarize first. Cells follow these rules, in order: a missing
#' value shows `na`; `TRUE` and `FALSE` show as R prints them; integers get
#' `big_mark` between groups of three digits; doubles show `Inf` or `-Inf`
#' when infinite, `digits` decimals when `digits` is given (`1.50`), and
#' otherwise a whole number without decimals (`1`) and other numbers as
#' `format(x, digits = 15)` prints them, with `big_mark` grouping the whole
#' part (a number printed in exponent form, such as `1e-07`, is left as is);
#' anything else shows its text. Then `|` becomes `\|` and each run of
#' whitespace, newlines included, becomes one space.
#'
#' Row names are not shown: R tables, like tibbles, have no index. To show
#' them, make them a column first, as in
#' `show_table(cbind(name = rownames(df), df))`.
#'
#' @param data A data frame (a tibble works too) or a matrix.
#' @param caption Character or NULL. A caption below the table, written as
#'   Pandoc's `: caption` line. In Quarto, `#| tbl-cap` with
#'   `#| label: tbl-...` on the chunk does the same and adds a
#'   cross-reference; use one or the other.
#' @param digits A whole number of at least 0, or NULL. Decimal places for
#'   doubles, kept even when they are zero (`2` shows `1.50`). Default: whole
#'   numbers without decimals and other numbers as R prints them.
#' @param big_mark Character. The thousands separator for numbers, such as
#'   `","`. Default: none.
#' @param na Character. What a missing value shows. Default: an empty cell.
#'
#' @return The Markdown table, from [knitr::asis_output()], so a Quarto or R
#'   Markdown chunk shows it as a table. It also has class
#'   `framework_table`, which prints its Markdown at the console.
#'
#' @examples
#' if (requireNamespace("knitr", quietly = TRUE)) {
#'   counts <- data.frame(arm = c("a", "b"), n = c(1234L, 56L), rate = c(0.5, 0.25))
#'   show_table(counts, caption = "Counts by arm", digits = 2, big_mark = ",")
#' }
#'
#' @seealso [save_table()] to save a table as a file.
#' @export
show_table <- function(data, caption = NULL, digits = NULL, big_mark = "", na = "") {
  if (!requireNamespace("knitr", quietly = TRUE)) {
    stop("show_table() needs the knitr package. Install it with install.packages(\"knitr\").",
         call. = FALSE)
  }
  if (is.matrix(data)) data <- as.data.frame(data, stringsAsFactors = FALSE)
  if (!is.data.frame(data)) {
    stop("show_table() needs a data frame or a matrix.", call. = FALSE)
  }
  if (!is.null(digits) && !checkmate::test_count(digits)) {
    stop("digits must be a whole number of at least 0.", call. = FALSE)
  }
  checkmate::assert_string(caption, null.ok = TRUE)
  checkmate::assert_string(big_mark)
  checkmate::assert_string(na)

  header <- .fw_table_text(names(data))
  numeric <- vapply(data, function(column) is.numeric(column) && !is.logical(column), logical(1))
  cells <- lapply(data, .fw_table_column, digits = digits, big_mark = big_mark, na = na)
  rows <- if (nrow(data) > 0L) do.call(paste, c(unname(cells), sep = " | ")) else character()
  lines <- c(
    paste0("| ", paste(header, collapse = " | "), " |"),
    paste0("|", paste(ifelse(numeric, "---:", ":---"), collapse = "|"), "|"),
    if (length(rows)) paste0("| ", rows, " |")
  )
  if (!is.null(caption) && nzchar(caption)) {
    lines <- c(lines, "", paste0(": ", trimws(gsub("\\s+", " ", caption))))
  }
  out <- knitr::asis_output(paste0(paste(lines, collapse = "\n"), "\n"))
  class(out) <- c("framework_table", class(out))
  out
}

#' @export
print.framework_table <- function(x, ...) {
  cat(x)
  invisible(x)
}

# IRkernel shows a framework_table as Markdown
#' @exportS3Method repr::repr_markdown
repr_markdown.framework_table <- function(obj, ...) {
  as.character(unclass(obj))
}

# The cells of one column, as show_table() writes them
.fw_table_column <- function(column, digits = NULL, big_mark = "", na = "") {
  missing <- is.na(column)
  if (is.list(column)) {
    missing <- vapply(column, function(v) length(v) == 1L && is.atomic(v) && is.na(v), logical(1))
    text <- vapply(column, function(v) paste(format(v), collapse = ", "), character(1))
  } else if (is.logical(column)) {
    text <- ifelse(column, "TRUE", "FALSE")
  } else if (inherits(column, "integer64")) {
    text <- vapply(as.character(column), .fw_table_number, character(1), big_mark = big_mark)
  } else if (is.integer(column) && !is.factor(column)) {
    text <- vapply(column, function(v) .fw_table_number(as.character(v), big_mark), character(1))
  } else if (is.double(column) && !inherits(column, c("Date", "POSIXt", "difftime"))) {
    text <- vapply(unclass(column), .fw_table_double, character(1), digits = digits, big_mark = big_mark)
  } else {
    text <- as.character(column)
  }
  text <- .fw_table_text(text)
  text[missing] <- na
  text
}

.fw_table_double <- function(value, digits = NULL, big_mark = "") {
  if (is.na(value)) return(NA_character_)
  if (is.infinite(value)) return(if (value > 0) "Inf" else "-Inf")
  text <- if (!is.null(digits)) {
    formatC(value, format = "f", digits = digits)
  } else if (value == trunc(value)) {
    formatC(value, format = "f", digits = 0)
  } else {
    format(value, digits = 15)
  }
  .fw_table_number(text, big_mark)
}

# big_mark between groups of three digits in the whole part; an exponent
# form such as 1e-07 is left as it is
.fw_table_number <- function(text, big_mark = "") {
  if (is.na(text)) return(NA_character_)
  sign <- if (startsWith(text, "-")) "-" else ""
  body <- sub("^-", "", text)
  whole <- sub("\\..*$", "", body)
  rest <- substring(body, nchar(whole) + 1L)
  if (!grepl("^[0-9]+$", whole)) return(text)
  if (nzchar(big_mark) && nchar(whole) > 3L) {
    head <- nchar(whole) %% 3L
    if (head == 0L) head <- 3L
    starts <- seq(head + 1L, nchar(whole), by = 3L)
    whole <- paste(c(substr(whole, 1L, head), substring(whole, starts, starts + 2L)), collapse = big_mark)
  }
  paste0(sign, whole, rest)
}

# `|` becomes `\|`, and each run of whitespace one space
.fw_table_text <- function(text) {
  trimws(gsub("\\s+", " ", gsub("|", "\\|", as.character(text), fixed = TRUE)))
}
