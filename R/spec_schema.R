# Checking a spec against inst/schema/spec.v1.json before it is written.
#
# Framework Cloud validates every spec it receives against the same schema
# and refuses one with keys the schema doesn't allow (HTTP 422). R writes
# specs in project_create(), adopt(), and upgrade(); each goes through
# .spec_record_lines(), which drops keys the schema doesn't allow and stops
# on any other problem, so no spec R writes can be refused.
#
# This is a small validator for the parts of JSON Schema draft-07 that
# spec.v1.json uses: type, properties, additionalProperties, required,
# propertyNames, enum, const, pattern, minLength, maxLength, items,
# maxItems, minimum, $ref (to #/definitions), anyOf, oneOf, allOf, and
# if/then. It needs no JavaScript engine, so it runs wherever R does.
# framework-py: _spec_schema.problems() and prune().

# The parsed schema, read once per session
#' @keywords internal
.spec_schema <- function() {
  cached <- .framework_env$spec_schema
  if (!is.null(cached)) return(cached)
  path <- system.file("schema", "spec.v1.json", package = "framework")
  schema <- jsonlite::read_json(path, simplifyVector = FALSE)
  .framework_env$spec_schema <- schema
  schema
}

# A spec as JSON sees it: written the way .framework/spec.json is, and read
# back, so maps are named lists, arrays unnamed lists, and scalars length 1
#' @keywords internal
.spec_as_json_value <- function(spec) {
  attr(spec, "conflicts") <- NULL
  marked <- tryCatch(.spec_mark_maps(spec), error = function(e) spec)
  json <- jsonlite::toJSON(marked, auto_unbox = TRUE, null = "null")
  jsonlite::fromJSON(json, simplifyVector = FALSE)
}

#' @keywords internal
.spec_schema_resolve <- function(node, root) {
  while (is.list(node) && !is.null(node[["$ref"]])) {
    parts <- strsplit(sub("^#/", "", node[["$ref"]]), "/", fixed = TRUE)[[1]]
    target <- root
    for (p in parts) target <- target[[p]]
    node <- target
  }
  node
}

#' @keywords internal
.spec_json_type <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) return(if (!is.null(names(x))) "object" else "array")
  if (is.logical(x)) return("boolean")
  if (is.numeric(x)) return(if (is.integer(x) || (is.finite(x) && x == round(x))) "integer" else "number")
  if (is.character(x)) return("string")
  "unknown"
}

#' @keywords internal
.spec_where <- function(path) if (nzchar(path)) path else "(spec)"

# Problems with `value` against `schema`, as "path: what is wrong"
#' @keywords internal
.spec_schema_check <- function(value, schema, root, path = "") {
  schema <- .spec_schema_resolve(schema, root)
  if (!is.list(schema)) return(character())
  problems <- character()
  add <- function(...) problems <<- c(problems, paste0(.spec_where(path), ": ", sprintf(...)))
  type <- .spec_json_type(value)

  if (!is.null(schema$type)) {
    allowed <- unlist(schema$type)
    ok <- type %in% allowed || (identical(type, "integer") && "number" %in% allowed)
    if (!ok) {
      add("must be %s, not %s", paste(allowed, collapse = " or "), type)
      return(problems)
    }
  }
  if (!is.null(schema$const) && !identical(as.character(value), as.character(schema$const))) {
    add("must be %s", format(schema$const))
  }
  if (!is.null(schema$enum) && !(length(value) == 1 && as.character(value) %in% as.character(unlist(schema$enum)))) {
    add("must be one of %s", paste(unlist(schema$enum), collapse = ", "))
  }
  if (identical(type, "string")) {
    if (!is.null(schema$pattern) && !grepl(schema$pattern, value, perl = TRUE)) {
      add("'%s' doesn't match %s", value, schema$pattern)
    }
    if (!is.null(schema$minLength) && nchar(value) < schema$minLength) add("is shorter than %d", schema$minLength)
    if (!is.null(schema$maxLength) && nchar(value) > schema$maxLength) add("is longer than %d", schema$maxLength)
  }
  if (type %in% c("integer", "number") && !is.null(schema$minimum) && value < schema$minimum) {
    add("must be at least %s", schema$minimum)
  }
  if (identical(type, "object")) {
    props <- schema$properties %||% list()
    for (key in setdiff(unlist(schema$required), names(value))) add("missing '%s'", key)
    for (key in names(value)) {
      where <- if (nzchar(path)) paste0(path, ".", key) else key
      if (!is.null(schema$propertyNames)) {
        names_schema <- .spec_schema_resolve(schema$propertyNames, root)
        if (!is.null(names_schema$pattern) && !grepl(names_schema$pattern, key, perl = TRUE)) {
          add("key '%s' doesn't match %s", key, names_schema$pattern)
        }
        if (!is.null(names_schema$enum) && !key %in% unlist(names_schema$enum)) {
          add("key '%s' must be one of %s", key, paste(unlist(names_schema$enum), collapse = ", "))
        }
      }
      if (key %in% names(props)) {
        problems <- c(problems, .spec_schema_check(value[[key]], props[[key]], root, where))
      } else if (isFALSE(schema$additionalProperties)) {
        problems <- c(problems, sprintf("%s: '%s' is not allowed here", .spec_where(path), key))
      } else if (is.list(schema$additionalProperties)) {
        problems <- c(problems, .spec_schema_check(value[[key]], schema$additionalProperties, root, where))
      }
    }
  }
  if (identical(type, "array")) {
    if (!is.null(schema$maxItems) && length(value) > schema$maxItems) add("has more than %d items", schema$maxItems)
    if (!is.null(schema$items)) {
      for (i in seq_along(value)) {
        problems <- c(problems, .spec_schema_check(value[[i]], schema$items, root, sprintf("%s[%d]", path, i - 1L)))
      }
    }
  }
  for (part in schema$allOf) {
    part <- .spec_schema_resolve(part, root)
    if (!is.null(part[["if"]])) {
      if (length(.spec_schema_check(value, part[["if"]], root, path)) == 0 && !is.null(part[["then"]])) {
        problems <- c(problems, .spec_schema_check(value, part[["then"]], root, path))
      }
    } else {
      problems <- c(problems, .spec_schema_check(value, part, root, path))
    }
  }
  if (!is.null(schema$anyOf)) {
    passes <- vapply(schema$anyOf, function(s) length(.spec_schema_check(value, s, root, path)) == 0, logical(1))
    if (!any(passes)) add("matches none of the allowed forms")
  }
  if (!is.null(schema$oneOf)) {
    passes <- vapply(schema$oneOf, function(s) length(.spec_schema_check(value, s, root, path)) == 0, logical(1))
    if (sum(passes) != 1) add("must match exactly one of the allowed forms")
  }
  problems
}

# The spec's problems against spec.v1.json, empty when it is valid
#' @keywords internal
.spec_schema_problems <- function(spec) {
  schema <- .spec_schema()
  .spec_schema_check(.spec_as_json_value(spec), schema, schema)
}

# The spec without keys spec.v1.json doesn't allow, where the schema says
# exactly which keys an object may hold. Returns list(spec, dropped), where
# dropped are the dot paths removed. Inside anyOf and oneOf nothing is
# removed: which form applies is for the check to say.
#' @keywords internal
.spec_schema_prune <- function(spec) {
  schema <- .spec_schema()
  dropped <- character()
  prune <- function(value, node, path) {
    node <- .spec_schema_resolve(node, schema)
    if (!is.list(value) || !is.list(node)) return(value)
    if (!is.null(names(value))) {
      props <- node$properties %||% list()
      for (key in names(value)) {
        where <- if (nzchar(path)) paste0(path, ".", key) else key
        if (key %in% names(props)) {
          value[key] <- list(prune(value[[key]], props[[key]], where))
        } else if (isFALSE(node$additionalProperties)) {
          dropped <<- c(dropped, where)
          value[[key]] <- NULL
        } else if (is.list(node$additionalProperties)) {
          value[key] <- list(prune(value[[key]], node$additionalProperties, where))
        }
      }
    } else if (!is.null(node$items)) {
      for (i in seq_along(value)) value[i] <- list(prune(value[[i]], node$items, sprintf("%s[%d]", path, i - 1L)))
    }
    value
  }
  conflicts <- attr(spec, "conflicts")
  out <- prune(spec, schema, "")
  attr(out, "conflicts") <- conflicts
  list(spec = out, dropped = dropped)
}

# The spec ready to write: keys the schema doesn't allow are dropped (with a
# message naming them) and any other problem stops with all of them listed
#' @keywords internal
.spec_schema_ready <- function(spec, quiet = FALSE) {
  pruned <- .spec_schema_prune(spec)
  if (length(pruned$dropped) > 0 && !quiet) {
    message("  Left out of .framework/spec.json (not part of spec.v1, so Framework Cloud would refuse them): ",
            paste(pruned$dropped, collapse = ", "))
  }
  problems <- .spec_schema_problems(pruned$spec)
  if (length(problems) > 0) {
    stop(".framework/spec.json would not match spec.v1: ", paste(problems, collapse = "; "), call. = FALSE)
  }
  pruned
}
