# Columns that look like direct identifiers, found from column names alone.
#
# A cheap check for real data about people where it doesn't belong:
# data_save() warns when it writes such columns outside a private folder, and
# git_security_audit() flags tracked data files whose header has them. Only
# names are read, never values, so a file is opened for its header only.
#
# A column name is split into lowercase tokens at non-alphanumeric characters
# and camelCase boundaries (patientDOB -> patient, dob), and `joined` is the
# tokens run together. The first matching kind wins:
#
# - dob: a token dob; or a token birth with date, dt, or day; or joined
#   containing dateofbirth, birthdate, or birthday.
# - zip: a token zip, zipcode, zip5, zip9, postal, postcode, or postalcode; or
#   joined containing zipcode or postalcode. Three-digit zip3 is not flagged.
# - ssn: a token ssn, or joined containing socialsecurity.
# - mrn: a token mrn, or joined containing medicalrecordnumber,
#   medicalrecordno, or medrec.
# - name: a token name with first, last, given, family, full, middle, maiden,
#   patient, or person; or joined equal to firstname, lastname, surname,
#   fullname, fname, or lname. Names alone are common in data that isn't about
#   people (a site's name), so they count only alongside a dob column.

# The file types whose header the audit reads
.fw_identifier_header_types <- c("csv", "tsv", "txt", "parquet", "dta", "sav")

#' @keywords internal
.fw_identifier_tokens <- function(column) {
  spaced <- gsub("([a-z0-9])([A-Z])", "\\1 \\2", column, perl = TRUE)
  spaced <- gsub("([A-Z]+)([A-Z][a-z])", "\\1 \\2", spaced, perl = TRUE)
  tokens <- strsplit(tolower(spaced), "[^a-z0-9]+", perl = TRUE)[[1]]
  tokens[nzchar(tokens)]
}

#' @keywords internal
.fw_identifier_kind <- function(column) {
  words <- .fw_identifier_tokens(column)
  joined <- paste(words, collapse = "")
  has <- function(parts) any(vapply(parts, grepl, logical(1), x = joined, fixed = TRUE))
  if ("dob" %in% words ||
      ("birth" %in% words && any(c("date", "dt", "day") %in% words)) ||
      has(c("dateofbirth", "birthdate", "birthday"))) {
    return("dob")
  }
  if (any(c("zip", "zipcode", "zip5", "zip9", "postal", "postcode", "postalcode") %in% words) ||
      has(c("zipcode", "postalcode"))) {
    return("zip")
  }
  if ("ssn" %in% words || has("socialsecurity")) {
    return("ssn")
  }
  if ("mrn" %in% words || has(c("medicalrecordnumber", "medicalrecordno", "medrec"))) {
    return("mrn")
  }
  if (("name" %in% words &&
       any(c("first", "last", "given", "family", "full", "middle", "maiden", "patient", "person") %in% words)) ||
      joined %in% c("firstname", "lastname", "surname", "fullname", "fname", "lname")) {
    return("name")
  }
  NA_character_
}

#' Columns that look like direct identifiers
#'
#' Name columns count only when a dob column is there too.
#'
#' @param columns Column names.
#' @return A data frame with `column` and `kind` (dob, zip, ssn, mrn, or name),
#'   in column order.
#' @keywords internal
.fw_identifier_columns <- function(columns) {
  columns <- as.character(columns)
  kinds <- vapply(columns, .fw_identifier_kind, character(1), USE.NAMES = FALSE)
  keep <- !is.na(kinds) & (kinds != "name" | any(kinds == "dob", na.rm = TRUE))
  data.frame(column = columns[keep], kind = kinds[keep], stringsAsFactors = FALSE)
}

#' A data file's column names, reading only its header
#'
#' CSV, TSV, and text files: the first line, split on a tab when the file is
#' `.tsv` or the line has one, else on `;` when it has more of them than `,`,
#' else on `,`. Parquet: the schema from the file's metadata (needs arrow). Stata and SPSS: the
#' metadata (needs haven).
#'
#' @param path The file.
#' @return Column names, or NULL when the type isn't supported, its reader
#'   isn't installed, or the file can't be read.
#' @keywords internal
.fw_header_columns <- function(path) {
  ext <- tolower(tools::file_ext(path))
  tryCatch({
    if (ext %in% c("csv", "tsv", "txt")) {
      con <- file(path, open = "r", encoding = "UTF-8-BOM")
      on.exit(close(con), add = TRUE)
      line <- suppressWarnings(readLines(con, n = 1, warn = FALSE))
      if (length(line) == 0) return(NULL)
      line <- sub("^\ufeff", "", line)
      if (!nzchar(trimws(line))) return(NULL)
      count <- function(ch) lengths(regmatches(line, gregexpr(ch, line, fixed = TRUE)))
      delimiter <- if (ext == "tsv" || grepl("\t", line, fixed = TRUE)) {
        "\t"
      } else if (count(";") > count(",")) {
        ";"
      } else {
        ","
      }
      return(scan(text = line, what = "", sep = delimiter, quote = "\"", quiet = TRUE,
                  na.strings = character(), strip.white = FALSE, blank.lines.skip = FALSE,
                  comment.char = ""))
    }
    if (ext == "parquet") {
      if (!requireNamespace("arrow", quietly = TRUE)) return(NULL)
      # The file's schema only (arrow::read_schema() takes a stream, not a path)
      return(arrow::ParquetFileReader$create(path)$GetSchema()$names)
    }
    if (ext %in% c("dta", "sav")) {
      if (!requireNamespace("haven", quietly = TRUE)) return(NULL)
      data <- if (ext == "dta") haven::read_dta(path, n_max = 0) else haven::read_sav(path, n_max = 0)
      return(names(data))
    }
    NULL
  }, error = function(e) NULL)
}

#' Warn when data saved outside a private folder has identifier-like columns
#'
#' @param columns The saved data's column names.
#' @param relative The file's path from the project root.
#' @param sensitive Whether the project is `security: sensitive: true`.
#' @return Invisibly, the matching columns (a data frame).
#' @keywords internal
.fw_warn_identifiers <- function(columns, relative, sensitive = FALSE) {
  folder <- dirname(relative)
  if (.fw_private_segment(folder)) return(invisible(NULL))
  found <- .fw_identifier_columns(columns)
  if (nrow(found) == 0) return(invisible(found))
  shown <- paste(utils::head(found$column, 5), collapse = ", ")
  if (nrow(found) > 5) shown <- sprintf("%s, and %d more", shown, nrow(found) - 5)
  advice <- if (isTRUE(sensitive)) {
    "If this is real data about people, save it in a private folder instead."
  } else {
    paste0("If this is real data about people, save it in a private folder, which git ",
           "ignores, and consider a privacy-sensitive project (type project_sensitive).")
  }
  warning(sprintf(
    "%s has columns that look like direct identifiers (%s), and it isn't in a private folder. %s",
    relative, shown, advice
  ), call. = FALSE)
  invisible(found)
}
