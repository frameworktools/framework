# Model variables: the data behind a published model's coefficient terms.
# The contract is the "Model variables" section of framework-embed SPEC.md.
# `variables` describes each variable the model was fit on, with a summary over
# the rows it used. `terms` maps each coefficient term to its variables and
# factor levels. Only aggregates leave R; a term whose mapping is uncertain is
# left out rather than guessed.

.fw_mv_max_variables <- 100L
.fw_mv_max_levels <- 50L
.fw_mv_max_terms <- 500L

#' @keywords internal
.fw_mv_deparse <- function(expr) paste(deparse(expr, width.cutoff = 500L), collapse = " ")

# Random-effects bars, `(x | g)` or `(x || g)`, anywhere in a formula.
#' @keywords internal
.fw_mv_bars <- function(expr) {
  if (!is.call(expr)) return(list())
  head <- expr[[1]]
  if (identical(head, as.name("|")) || identical(head, as.name("||"))) return(list(expr))
  unlist(lapply(as.list(expr)[-1], .fw_mv_bars), recursive = FALSE)
}

# The original data, when the call names it plainly (`data = penguins` or
# `data = pkg::data`). Other expressions are never evaluated.
#' @keywords internal
.fw_mv_data <- function(call, env) {
  expr <- if (is.call(call)) call$data else NULL
  if (is.null(expr) || !is.environment(env)) return(NULL)
  plain <- is.name(expr) || (is.call(expr) && as.character(expr[[1]])[1] %in% c("::", ":::"))
  if (!plain) return(NULL)
  data <- tryCatch(eval(expr, env), error = function(e) NULL)
  if (is.data.frame(data)) data else NULL
}

# Everything the builder needs from a fitted model: its frame, the terms
# behind its coefficients, contrasts, and grouping variables.
#' @keywords internal
.fw_mv_spec <- function(object) {
  if (inherits(object, "fixest")) return(.fw_mv_spec_fixest(object))
  frame <- stats::model.frame(object)
  if (!is.data.frame(frame) || !nrow(frame)) return(NULL)
  expected <- if (inherits(object, "coxph")) object$n else
    if (inherits(object, "survreg")) length(object$linear.predictors) else
      if (inherits(object, "multinom")) NROW(object$fitted.values) else NULL
  if (!is.null(expected) && !identical(as.integer(expected), nrow(frame))) return(NULL)
  full <- attr(frame, "terms")
  formula <- .fw_artifact_formula(object)
  spec <- list(frame = frame, full = full, fixed = full, contrasts = NULL, group = character(),
               prefixes = NULL, call = tryCatch(stats::getCall(object), error = function(e) NULL),
               env = if (!is.null(formula)) environment(formula) else NULL)
  if (isS4(object)) {
    spec$fixed <- stats::terms(object, fixed.only = TRUE)
    spec$contrasts <- attr(lme4::getME(object, "X"), "contrasts")
    spec$group <- unique(unlist(lapply(.fw_mv_bars(formula[[length(formula)]]),
                                       function(bar) all.vars(bar[[3]]))))
  } else {
    spec$contrasts <- object$contrasts
    if (inherits(object, "gam")) spec$fixed <- object$pterms
    if (inherits(object, "multinom")) spec$prefixes <- paste0(object$lev, ": ")
  }
  spec$data <- .fw_mv_data(spec$call, spec$env)
  spec
}

#' @keywords internal
.fw_mv_spec_fixest <- function(object) {
  data <- .fw_mv_data(object$call, object$call_env %||% environment(stats::formula(object)))
  if (is.null(data)) return(NULL)
  rows <- fixest::obs(object)
  used <- data[rows, , drop = FALSE]
  frame <- stats::model.frame(object$fml_all$linear, used)
  if (nrow(frame) != length(rows)) return(NULL)
  full <- attr(frame, "terms")
  absorbed <- if (!is.null(object$fml_all$fixef)) all.vars(object$fml_all$fixef) else character()
  list(frame = frame, full = full, fixed = full, contrasts = NULL, group = character(),
       absorbed = intersect(absorbed, names(data)), prefixes = NULL, call = object$call, data = data,
       fixest = TRUE)
}

# Row positions of the model frame in the original data, or NULL when the data
# can't be matched to the frame (renamed rows, or data changed since the fit).
#' @keywords internal
.fw_mv_rows <- function(spec, columns) {
  data <- spec$data
  if (is.null(data)) return(NULL)
  rows <- match(rownames(spec$frame), rownames(data))
  if (anyNA(rows)) return(NULL)
  for (name in intersect(columns, names(data))) {
    if (!identical(as.character(data[[name]][rows]), as.character(spec$frame[[name]]))) return(NULL)
  }
  rows
}

#' @keywords internal
.fw_mv_is_categorical <- function(column) is.factor(column) || is.character(column) || is.logical(column)

#' @keywords internal
.fw_mv_levels <- function(column) {
  if (is.factor(column)) return(levels(column))
  if (is.logical(column)) return(c("FALSE", "TRUE"))
  sort(unique(as.character(column[!is.na(column)])))
}

# The contrast matrix model.matrix() used for a factor column, by name, function, or matrix.
#' @keywords internal
.fw_mv_contrast <- function(spec, name, column) {
  levels <- .fw_mv_levels(column)
  if (length(levels) < 2L) return(NULL)
  contrast <- spec$contrasts[[name]]
  if (is.null(contrast)) {
    defaults <- getOption("contrasts", c("contr.treatment", "contr.poly"))
    contrast <- if (is.ordered(column)) defaults[[2]] else defaults[[1]]
  }
  matrix <- tryCatch({
    if (is.character(contrast)) contrast <- get(contrast, mode = "function")
    if (is.function(contrast)) contrast <- contrast(levels)
    as.matrix(contrast)
  }, error = function(e) NULL)
  if (is.null(matrix) || nrow(matrix) != length(levels)) return(NULL)
  rownames(matrix) <- levels
  if (is.null(colnames(matrix))) colnames(matrix) <- as.character(seq_len(ncol(matrix)))
  matrix
}

# A contrast column that is a 0/1 indicator of one level names that level.
#' @keywords internal
.fw_mv_indicator <- function(values, levels) {
  if (!all(values %in% c(0, 1)) || sum(values == 1) != 1L) return(NULL)
  levels[values == 1]
}

# The level the contrasts compare against: only for indicator coding with one all-zero row.
#' @keywords internal
.fw_mv_reference <- function(matrix) {
  if (is.null(matrix)) return(NULL)
  indicators <- vapply(seq_len(ncol(matrix)), function(j) {
    !is.null(.fw_mv_indicator(matrix[, j], rownames(matrix)))
  }, logical(1))
  zero <- rowSums(matrix != 0) == 0
  if (all(indicators) && sum(zero) == 1L) rownames(matrix)[zero] else NULL
}

#' @keywords internal
.fw_mv_part <- function(variable, level = NULL) {
  part <- list(variable = variable)
  part$level <- level
  part
}

# The coefficient-name pieces one model frame column can contribute, each with its part.
#' @keywords internal
.fw_mv_pieces <- function(spec, name, variable) {
  column <- spec$frame[[name]]
  piece <- function(label, level = NULL) list(name = label, part = .fw_mv_part(variable, level))
  if (isTRUE(spec$fixest) && grepl("^i\\(", name)) {
    # fixest i(): one indicator column per level, named `var::level` in the coefficients.
    levels <- colnames(column)
    if (is.null(levels) || !identical(all.vars(str2lang(name))[1], variable)) return(NULL)
    # Outside feols() the columns may read `__CLEAN__var::level` rather than `level`.
    levels <- sub("^__CLEAN__", "", levels)
    prefixed <- startsWith(levels, paste0(variable, "::"))
    levels[prefixed] <- substring(levels[prefixed], nchar(variable) + 3L)
    return(lapply(levels, function(level) piece(paste0(variable, "::", level), level)))
  }
  if (.fw_mv_is_categorical(column)) {
    levels <- .fw_mv_levels(column)
    if (length(levels) > 200L) return(NULL)
    matrix <- .fw_mv_contrast(spec, name, column)
    contrast <- if (is.null(matrix)) list() else lapply(seq_len(ncol(matrix)), function(j) {
      piece(paste0(name, colnames(matrix)[j]), .fw_mv_indicator(matrix[, j], levels))
    })
    # Full dummy coding appears without an intercept or inside some interactions.
    return(c(contrast, lapply(levels, function(level) piece(paste0(name, level), level))))
  }
  if (is.matrix(column)) {
    labels <- colnames(column) %||% as.character(seq_len(ncol(column)))
    pieces <- lapply(labels, function(label) piece(paste0(name, label)))
    return(if (ncol(column) == 1L) c(list(piece(name)), pieces) else pieces)
  }
  if (is.numeric(column)) return(list(piece(name)))
  NULL
}

# Every coefficient name the fixed terms can produce, mapped to its parts.
# A name produced twice with different parts is ambiguous and dropped.
#' @keywords internal
.fw_mv_candidates <- function(spec, variables_of) {
  factors <- attr(spec$fixed, "factors")
  if (is.null(factors) || !length(factors)) return(list())
  map <- list()
  ambiguous <- character()
  for (term in colnames(factors)) {
    names <- rownames(factors)[factors[, term] != 0]
    if (!length(names) || length(names) > 10L) next
    pieces <- lapply(names, function(name) {
      variable <- variables_of[[name]]
      if (length(variable) != 1L || !name %in% names(spec$frame)) return(NULL)
      .fw_mv_pieces(spec, name, variable)
    })
    if (any(vapply(pieces, length, integer(1)) == 0L)) next
    if (prod(vapply(pieces, length, integer(1))) > 5000) next
    combos <- list(list(name = character(), parts = list()))
    for (options in pieces) {
      combos <- unlist(lapply(options, function(option) {
        lapply(combos, function(combo) list(name = c(combo$name, option$name),
                                            parts = c(combo$parts, list(option$part))))
      }), recursive = FALSE)
    }
    for (combo in combos) {
      key <- paste(combo$name, collapse = ":")
      if (key %in% ambiguous) next
      if (!is.null(map[[key]]) && !identical(map[[key]], combo$parts)) {
        ambiguous <- c(ambiguous, key)
        map[[key]] <- NULL
      } else {
        map[[key]] <- combo$parts
      }
    }
  }
  map
}

#' @keywords internal
.fw_mv_terms <- function(spec, variables_of, coefficient_terms) {
  candidates <- .fw_mv_candidates(spec, variables_of)
  if (!length(candidates)) return(list())
  entries <- list()
  for (term in unique(coefficient_terms)) {
    key <- term
    if (is.null(candidates[[key]]) && length(spec$prefixes)) {
      prefix <- spec$prefixes[startsWith(term, spec$prefixes)]
      if (length(prefix) == 1L) key <- substring(term, nchar(prefix) + 1L)
    }
    parts <- if (nzchar(key)) candidates[[key]] else NULL
    if (is.null(parts)) next
    entries[[length(entries) + 1L]] <- list(term = term, parts = parts)
    if (length(entries) >= .fw_mv_max_terms) break
  }
  entries
}

#' @keywords internal
.fw_mv_type <- function(column) {
  if (is.factor(column) || is.character(column)) return("categorical")
  .fw_artifact_column_type(column)
}

#' @keywords internal
.fw_mv_variable <- function(name, role, values, label, numeric_fallback = FALSE) {
  entry <- list(name = name)
  entry$role <- role
  if (is.null(values)) {
    if (!numeric_fallback) return(NULL)
    entry$type <- "number"
    entry$label <- label
    return(entry)
  }
  type <- .fw_mv_type(values)
  entry$type <- type
  entry$label <- label
  if (identical(type, "categorical")) {
    entry$levels <- as.list(utils::head(.fw_mv_levels(values), .fw_mv_max_levels))
  }
  summary <- .fw_artifact_column_summary(values, if (identical(type, "categorical")) "string" else type)
  summary$histogram <- NULL
  entry$summary <- summary
  entry
}

# Variables and term mappings for a model, or NULL when the model frame can't be recovered.
#' @keywords internal
.fw_artifact_model_variables <- function(object, coefficient_terms) {
  spec <- tryCatch(.fw_mv_spec(object), error = function(e) NULL)
  if (is.null(spec)) return(NULL)
  frame <- spec$frame
  data <- spec$data
  expressions <- as.list(attr(spec$full, "variables"))[-1]
  labels <- vapply(expressions, .fw_mv_deparse, character(1))
  columns <- setdiff(names(frame), grep("^\\(.*\\)$", names(frame), value = TRUE))
  rows <- .fw_mv_rows(spec, columns)
  if (is.null(rows)) data <- NULL

  # Each frame column's underlying data variables: `log(x)` and `poly(x, 2)` are x.
  variables_of <- list()
  for (name in columns) {
    index <- match(name, labels)
    expr <- if (is.na(index)) tryCatch(str2lang(name), error = function(e) NULL) else expressions[[index]]
    if (is.null(expr)) next
    found <- if (is.name(expr)) as.character(expr) else all.vars(expr)
    if (!is.name(expr) && !is.null(data)) found <- intersect(found, names(data))
    variables_of[[name]] <- unique(found)
  }

  full <- spec$full
  response <- attr(full, "response")
  response <- if (isTRUE(response > 0)) labels[response] else character()
  offsets <- labels[attr(full, "offset") %||% integer()]
  specials <- attr(full, "specials")
  unrolled <- labels[unlist(specials[intersect(names(specials), c("strata", "cluster"))]) %||% integer()]
  frailty <- labels[unlist(specials[intersect(names(specials), c("frailty", "frailty.gamma",
                                                                  "frailty.gaussian", "frailty.t"))]) %||% integer()]
  fixed_factors <- attr(spec$fixed, "factors")
  fixed_columns <- if (length(fixed_factors)) rownames(fixed_factors)[rowSums(fixed_factors != 0) > 0] else character()
  fixed_variables <- unlist(variables_of[intersect(fixed_columns, names(variables_of))])

  role_of <- function(name, variable) {
    if (name %in% response) return("response")
    if (name %in% offsets) return("offset")
    if (name %in% frailty) return("group")
    if (name %in% unrolled) return(NULL)
    if (variable %in% spec$group && !variable %in% fixed_variables) return("group")
    "predictor"
  }
  label_of <- function(name, variable) {
    .fw_artifact_label(frame[[name]]) %||% (if (!is.null(spec$data)) .fw_artifact_label(spec$data[[variable]]))
  }
  values_of <- function(name, variable) {
    column <- frame[[name]]
    if (identical(name, variable)) return(column)
    # factor(cyl) is summarized as the model saw it; strata(x) labels its levels, so use x.
    if (.fw_mv_is_categorical(column) && length(variables_of[[name]]) == 1L && !name %in% unrolled) return(column)
    if (!is.null(data) && variable %in% names(data)) return(data[[variable]][rows])
    NULL
  }

  variables <- list()
  seen <- character()
  add <- function(entry) {
    if (is.null(entry) || entry$name %in% seen || length(variables) >= .fw_mv_max_variables) return()
    seen <<- c(seen, entry$name)
    variables[[length(variables) + 1L]] <<- entry
  }
  for (name in c(intersect(response, columns), setdiff(columns, response))) {
    found <- variables_of[[name]]
    # A predictor transformation of several variables can't be summarized as one.
    if (length(found) > 1L && !name %in% response && is.null(data)) next
    for (variable in found) {
      column <- frame[[name]]
      add(.fw_mv_variable(variable, role_of(name, variable), values_of(name, variable), label_of(name, variable),
                          numeric_fallback = is.numeric(column)))
    }
  }
  for (variable in spec$absorbed) {
    if (!is.null(data)) add(.fw_mv_variable(variable, "predictor", data[[variable]][rows],
                                            .fw_artifact_label(data[[variable]])))
  }
  for (special in c("(weights)", "(offset)")) {
    if (!special %in% names(frame) || is.null(spec$call)) next
    expr <- spec$call[[if (identical(special, "(weights)")) "weights" else "offset"]]
    found <- if (is.null(expr)) character() else all.vars(expr)
    if (!is.null(data)) found <- intersect(found, names(data))
    if (length(found) != 1L) next
    values <- if (is.name(expr)) frame[[special]] else if (!is.null(data)) data[[found]][rows]
    add(.fw_mv_variable(found, if (identical(special, "(weights)")) "weight" else "offset", values,
                        if (!is.null(spec$data)) .fw_artifact_label(spec$data[[found]])))
  }

  terms <- tryCatch(.fw_mv_terms(spec, variables_of, coefficient_terms), error = function(e) list())

  # A reference holds only when no coefficient names that level itself (as with `0 + group`).
  for (i in seq_along(variables)) {
    variable <- variables[[i]]
    if (!identical(variable$role, "predictor") || !variable$type %in% c("categorical", "boolean")) next
    name <- names(variables_of)[vapply(variables_of, function(found) identical(found, variable$name), logical(1))]
    name <- intersect(name, fixed_columns)
    if (length(name) != 1L) next
    reference <- .fw_mv_reference(.fw_mv_contrast(spec, name, frame[[name]]))
    if (is.null(reference)) next
    named <- any(vapply(terms, function(term) any(vapply(term$parts, function(part) {
      identical(part$variable, variable$name) && identical(part$level, reference)
    }, logical(1))), logical(1)))
    if (!named) variables[[i]] <- append(variable, list(reference = reference),
                                         after = match("levels", names(variable), nomatch = length(variable) - 1L))
  }
  list(variables = variables, terms = terms)
}
