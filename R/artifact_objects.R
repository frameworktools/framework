# Structured exports retain typed values for Cloud's table, model, and test readers.
# The contract lives in framework-cloud docs/notes/2026-11-02-artifact-objects-contract.md.
# Model exports deliberately omit observations, residuals, fitted values, and
# serialized internals: only coefficients and aggregate statistics leave R.
#' @keywords internal
.fw_artifact_scalar <- function(value) {
  if (length(value) != 1L) stop("Artifact table cells must contain one scalar value.", call. = FALSE)
  if (is.na(value)) return(NULL)
  if (inherits(value, "POSIXt")) return(format(value, "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC"))
  if (inherits(value, "Date")) return(as.character(value))
  if (is.factor(value) || inherits(value, "integer64") || is.complex(value)) return(as.character(value))
  if (is.numeric(value)) return(if (is.finite(value)) unname(as.vector(value)) else NULL)
  if (is.logical(value)) return(unname(as.vector(value)))
  as.character(value)
}

#' @keywords internal
.fw_artifact_column_type <- function(column) {
  if (inherits(column, "POSIXt")) return("datetime")
  if (inherits(column, "Date")) return("date")
  if (is.logical(column)) return("boolean")
  if (is.numeric(column) && !is.factor(column) && !inherits(column, "integer64")) return("number")
  "string"
}

# Up to 8 most frequent values, ties in value order, long text cut to 80 characters.
#' @keywords internal
.fw_artifact_top <- function(values, type) {
  counts <- table(as.character(values), useNA = "no")
  counts <- counts[counts > 0L]
  if (!length(counts)) return(list())
  counts <- counts[order(-as.integer(counts), names(counts))][seq_len(min(8L, length(counts)))]
  lapply(seq_along(counts), function(i) {
    value <- names(counts)[i]
    value <- if (identical(type, "boolean")) as.logical(value) else
      if (nchar(value) > 80L) substr(value, 1L, 80L) else value
    list(value = value, count = as.integer(counts[[i]]))
  })
}

#' @keywords internal
.fw_artifact_histogram <- function(values) {
  low <- min(values)
  high <- max(values)
  if (low == high) return(list(edges = as.list(c(low, high)), counts = list(length(values))))
  bins <- min(20L, length(unique(values)))
  edges <- pretty(c(low, high), n = bins)
  if (length(edges) - 1L > 20L) edges <- seq(low, high, length.out = 21L)
  bin <- findInterval(values, edges, rightmost.closed = TRUE, all.inside = TRUE)
  list(edges = as.list(edges), counts = as.list(tabulate(bin, length(edges) - 1L)))
}

# Column profile over every row of the column, whatever Cloud later previews.
#' @keywords internal
.fw_artifact_column_summary <- function(column, type) {
  missing <- is.na(column)
  present <- column[!missing]
  summary <- list(count = length(column), missing = sum(missing),
                  distinct = length(unique(if (is.factor(present)) as.character(present) else present)))
  if (identical(type, "number")) {
    values <- as.numeric(present)
    values <- values[is.finite(values)]
    if (length(values)) {
      quantiles <- stats::quantile(values, c(0.25, 0.5, 0.75), names = FALSE)
      summary$mean <- mean(values)
      if (length(values) > 1L) summary$sd <- stats::sd(values)
      summary$min <- min(values)
      summary$q1 <- quantiles[1]
      summary$median <- quantiles[2]
      summary$q3 <- quantiles[3]
      summary$max <- max(values)
      summary$histogram <- .fw_artifact_histogram(values)
    }
  } else if (type %in% c("date", "datetime")) {
    if (length(present)) {
      summary$min <- .fw_artifact_scalar(min(present))
      summary$max <- .fw_artifact_scalar(max(present))
    }
  } else {
    summary$top <- .fw_artifact_top(present, type)
  }
  summary
}

#' @keywords internal
.fw_artifact_label <- function(column) {
  label <- attr(column, "label", exact = TRUE)
  if (is.character(label) && length(label) == 1L && !is.na(label) && nzchar(label)) label else NULL
}

#' @keywords internal
.fw_artifact_table <- function(data, title = "Table", role = NULL, summaries = FALSE) {
  if (ncol(data) == 0L) stop("Artifact tables require at least one column.", call. = FALSE)
  summaries <- summaries && ncol(data) <= 200L
  columns <- lapply(seq_along(data), function(i) {
    column <- data[[i]]
    type <- .fw_artifact_column_type(column)
    entry <- list(name = names(data)[i], type = type)
    entry$label <- .fw_artifact_label(column)
    if (summaries) entry$summary <- .fw_artifact_column_summary(column, type)
    entry
  })
  rows <- lapply(seq_len(nrow(data)), function(i) {
    unname(lapply(seq_along(data), function(j) .fw_artifact_scalar(data[[j]][i])))
  })
  table <- list(title = title)
  table$role <- role
  c(table, list(columns = columns, rows = rows, row_count = nrow(data)))
}

# Non-default row names (anything but "1".."n") become a first column `row`.
#' @keywords internal
.fw_artifact_with_row_names <- function(data, names = rownames(data)) {
  data <- as.data.frame(data, stringsAsFactors = FALSE, optional = TRUE)
  if (is.null(names) || identical(as.character(names), as.character(seq_len(nrow(data))))) {
    rownames(data) <- NULL
    return(data)
  }
  rownames(data) <- NULL
  label <- if ("row" %in% names(data)) ".row" else "row"
  data <- cbind(stats::setNames(data.frame(trimws(as.character(names)), stringsAsFactors = FALSE), label),
                data)
  data
}

#' @keywords internal
.fw_artifact_contingency <- function(object) {
  counts <- unclass(object)
  dims <- dimnames(object)
  variables <- names(dims)
  if (length(dim(object)) == 1L) {
    return(data.frame(value = dims[[1]], count = as.vector(counts), stringsAsFactors = FALSE))
  }
  if (length(dim(object)) == 2L) {
    data <- as.data.frame.matrix(matrix(as.vector(counts), nrow = nrow(counts),
                                        dimnames = list(NULL, ifelse(is.na(dims[[2]]), "NA", dims[[2]]))))
    first <- if (is.null(variables) || !nzchar(variables[1])) "row" else variables[1]
    data <- cbind(stats::setNames(data.frame(dims[[1]], stringsAsFactors = FALSE), first), data)
    return(data)
  }
  # Three or more dimensions: one row per cell, the closest flat form.
  long <- as.data.frame(as.table(object), responseName = "count", stringsAsFactors = FALSE)
  long
}

#' @keywords internal
.fw_artifact_anova_title <- function(object) {
  heading <- attr(object, "heading", exact = TRUE)
  if (is.character(heading) && length(heading)) trimws(strsplit(heading[1], "\n", fixed = TRUE)[[1]][1]) else
    "Analysis of variance"
}

# ANOVA tables from anova(), summary(aov), and summary(aov with Error()).
#' @keywords internal
.fw_artifact_anova_tables <- function(object) {
  if (inherits(object, "anova")) {
    return(list(.fw_artifact_table(.fw_artifact_with_row_names(object), .fw_artifact_anova_title(object),
                                   role = "anova")))
  }
  if (inherits(object, "summary.aovlist")) {
    return(unlist(lapply(names(object), function(stratum) {
      lapply(.fw_artifact_anova_tables(object[[stratum]]), function(table) {
        table$title <- paste0(stratum, ": ", table$title)
        table
      })
    }), recursive = FALSE))
  }
  if (inherits(object, "summary.aov")) {
    titles <- if (length(object) > 1L) paste("Analysis of variance:", names(object)) else "Analysis of variance"
    return(lapply(seq_along(object), function(i) {
      .fw_artifact_table(.fw_artifact_with_row_names(object[[i]]), titles[i], role = "anova")
    }))
  }
  NULL
}

# Convert tabular objects (data frames, matrices, contingency tables) to a data frame.
#' @keywords internal
.fw_artifact_frame <- function(object) {
  if (inherits(object, "table") || inherits(object, "xtabs")) return(.fw_artifact_contingency(object))
  if (is.data.frame(object)) return(.fw_artifact_with_row_names(object))
  if (is.matrix(object) && (is.numeric(object) || is.character(object) || is.logical(object))) {
    data <- as.data.frame(object, stringsAsFactors = FALSE)
    if (is.null(colnames(object))) names(data) <- paste0("V", seq_len(ncol(object)))
    return(.fw_artifact_with_row_names(data, rownames(object)))
  }
  NULL
}

# Named numeric vectors become [{name, value}] lists; missing or infinite values are dropped.
#' @keywords internal
.fw_artifact_named_values <- function(values, fallback) {
  if (is.null(values) || !length(values)) return(NULL)
  labels <- names(values)
  if (is.null(labels)) labels <- rep("", length(values))
  labels[is.na(labels) | !nzchar(labels)] <- if (length(values) == 1L) fallback else
    paste(fallback, seq_along(values))[is.na(labels) | !nzchar(labels)]
  entries <- lapply(seq_along(values), function(i) {
    value <- .fw_artifact_scalar(unname(values[i]))
    if (is.null(value)) NULL else list(name = labels[i], value = value)
  })
  entries <- Filter(Negate(is.null), entries)
  if (length(entries)) entries else NULL
}

# htest objects become a `test` document. data.name is left out on purpose,
# because it can contain expressions that include data.
#' @keywords internal
.fw_artifact_test <- function(object) {
  test <- list(method = trimws(paste(object$method, collapse = " ")))
  if (is.character(object$alternative) && length(object$alternative) == 1L) {
    test$alternative <- object$alternative
  }
  statistic <- .fw_artifact_named_values(object$statistic, "statistic")
  if (!is.null(statistic)) test$statistic <- statistic[[1]]
  test$parameters <- .fw_artifact_named_values(object$parameter, "parameter")
  if (length(object$p.value) == 1L) test$p_value <- .fw_artifact_scalar(unname(object$p.value))
  test$estimates <- .fw_artifact_named_values(object$estimate, "estimate")
  test$null_value <- .fw_artifact_named_values(object$null.value, "null value")
  if (length(object$conf.int) == 2L) {
    interval <- list()
    level <- attr(object$conf.int, "conf.level", exact = TRUE)
    if (is.numeric(level) && length(level) == 1L) interval$level <- level
    # One-sided intervals have an infinite bound, which JSON can't carry; it is left out.
    interval$low <- .fw_artifact_scalar(object$conf.int[1])
    interval$high <- .fw_artifact_scalar(object$conf.int[2])
    if (!is.null(interval$low) || !is.null(interval$high)) test$conf_int <- interval
  }
  tables <- list()
  if (!is.null(object$expected) && is.numeric(object$expected)) {
    expected <- object$expected
    frame <- if (is.matrix(expected)) .fw_artifact_with_row_names(expected) else
      data.frame(value = if (is.null(names(expected))) as.character(seq_along(expected)) else names(expected),
                 expected = as.vector(expected), stringsAsFactors = FALSE)
    tables <- list(.fw_artifact_table(frame, "Expected counts"))
  }
  list(test = test, tables = tables)
}

# pairwise.t.test() and friends: a test whose result is a matrix of p-values.
#' @keywords internal
.fw_artifact_pairwise_test <- function(object) {
  test <- list(method = trimws(paste(object$method, collapse = " ")))
  title <- "P-values"
  if (is.character(object$p.adjust.method)) title <- paste0(title, " (", object$p.adjust.method, " adjustment)")
  list(test = test, tables = list(.fw_artifact_table(.fw_artifact_with_row_names(object$p.value), title)))
}

#' @keywords internal
.fw_artifact_family_name <- function(name) {
  if (is.null(name) || !length(name)) return(NULL)
  tolower(trimws(sub("\\(.*$", "", name[1])))
}

#' @keywords internal
.fw_artifact_exponentiate <- function(family, link) {
  if (identical(link, "logit")) return("Odds ratio")
  if (identical(link, "log") && isTRUE(family %in% c("poisson", "quasipoisson", "negative binomial"))) {
    return("Rate ratio")
  }
  NULL
}

#' @keywords internal
.fw_artifact_formula <- function(object) {
  formula <- tryCatch(stats::formula(object), error = function(e) NULL)
  if (!inherits(formula, "formula")) return(NULL)
  formula
}

#' @keywords internal
.fw_artifact_response <- function(formula) {
  if (!inherits(formula, "formula") || length(formula) != 3L) return(NULL)
  paste(deparse(formula[[2]], width.cutoff = 500L), collapse = " ")
}

#' @keywords internal
.fw_artifact_description <- function(type, family = NULL, link = NULL, response = NULL,
                                      exponentiate = .fw_artifact_exponentiate(family, link)) {
  description <- list(type = type)
  description$family <- family
  description$link <- link
  description$response <- response
  description$exponentiate <- exponentiate
  description
}

# One row per term, with Wald intervals from the estimate and its standard error.
#' @keywords internal
.fw_artifact_coefficients <- function(term, estimate, std_error = NULL, statistic = NULL, p_value = NULL,
                                      critical = stats::qnorm(0.975), component = NULL,
                                      conf_low = NULL, conf_high = NULL) {
  data <- data.frame(term = as.character(term), stringsAsFactors = FALSE)
  if (!is.null(component)) data$component <- as.character(component)
  data$estimate <- unname(as.numeric(estimate))
  if (!is.null(std_error)) data$std_error <- unname(as.numeric(std_error))
  if (!is.null(statistic)) data$statistic <- unname(as.numeric(statistic))
  if (!is.null(p_value)) data$p_value <- unname(as.numeric(p_value))
  if (is.null(conf_low) && !is.null(std_error)) {
    conf_low <- data$estimate - critical * data$std_error
    conf_high <- data$estimate + critical * data$std_error
  }
  if (!is.null(conf_low)) {
    data$conf_low <- unname(as.numeric(conf_low))
    data$conf_high <- unname(as.numeric(conf_high))
  }
  data
}

# Coefficient matrices from summary() share the layout estimate, SE, statistic, p-value.
#' @keywords internal
.fw_artifact_summary_coefficients <- function(table, critical = NULL, component = NULL) {
  p_value <- if (ncol(table) >= 4L) table[, 4] else NULL
  .fw_artifact_coefficients(rownames(table), table[, 1], table[, 2], table[, 3], p_value,
                            critical = critical %||% stats::qnorm(0.975), component = component)
}

#' @keywords internal
.fw_artifact_value <- function(expression) {
  value <- tryCatch(suppressWarnings(expression), error = function(e) NULL)
  if (is.null(value) || length(value) != 1L) return(NULL)
  value <- unname(as.vector(value))
  if (is.numeric(value) && !is.finite(value)) return(NULL)
  if (is.na(value)) return(NULL)
  value
}

#' @keywords internal
.fw_artifact_fit <- function(object) {
  list(nobs = .fw_artifact_value(stats::nobs(object)),
       aic = .fw_artifact_value(stats::AIC(object)),
       bic = .fw_artifact_value(stats::BIC(object)),
       log_likelihood = .fw_artifact_value(as.numeric(stats::logLik(object))))
}

#' @keywords internal
.fw_artifact_lm <- function(object) {
  model <- if (inherits(object, "glm")) summary(object) else stats::summary.lm(object)
  coefficients <- model$coefficients
  use_t <- identical(colnames(coefficients)[3], "t value")
  critical <- if (use_t) stats::qt(0.975, object$df.residual) else stats::qnorm(0.975)
  values <- c(list(confidence_level = 0.95, interval_method = if (use_t) "wald-t" else "wald-normal"),
              .fw_artifact_fit(object), list(df_resid = object$df.residual))
  for (field in c("r.squared", "adj.r.squared", "sigma", "dispersion")) {
    if (!is.null(model[[field]])) values[[field]] <- model[[field]]
  }
  for (field in c("deviance", "null.deviance", "converged", "theta")) {
    if (!is.null(object[[field]])) values[[field]] <- object[[field]]
  }
  if (!is.null(object$SE.theta)) values$theta_std_error <- object$SE.theta
  formula <- .fw_artifact_formula(object)
  if (inherits(object, "glm")) {
    family <- .fw_artifact_family_name(object$family$family)
    if (inherits(object, "negbin")) family <- "negative binomial"
    description <- .fw_artifact_description("glm", family, object$family$link, .fw_artifact_response(formula))
  } else {
    description <- .fw_artifact_description("linear", "gaussian", "identity", .fw_artifact_response(formula))
  }
  tables <- list(.fw_artifact_table(.fw_artifact_summary_coefficients(coefficients, critical),
                                    "Coefficients", role = "coefficients"))
  if (inherits(object, "aov")) tables <- c(tables, .fw_artifact_anova_tables(summary(object)))
  list(tables = tables, values = values, model = description, formula = formula)
}

#' @keywords internal
.fw_artifact_polr <- function(object) {
  table <- summary(object)$coefficients
  thresholds <- names(object$zeta)
  component <- ifelse(rownames(table) %in% thresholds, "threshold", "coefficient")
  p_value <- 2 * stats::pnorm(-abs(table[, 3]))
  coefficients <- .fw_artifact_coefficients(rownames(table), table[, 1], table[, 2], table[, 3], p_value,
                                            component = component)
  link <- switch(object$method, logistic = "logit", probit = "probit", cloglog = "cloglog",
                 loglog = "loglog", cauchit = "cauchit", object$method)
  values <- c(list(confidence_level = 0.95, interval_method = "wald-normal"), .fw_artifact_fit(object),
              list(deviance = object$deviance, edf = object$edf))
  formula <- .fw_artifact_formula(object)
  list(tables = list(.fw_artifact_table(coefficients, "Coefficients", role = "coefficients")), values = values,
       model = .fw_artifact_description("ordinal", NULL, link, .fw_artifact_response(formula),
                                        if (identical(link, "logit")) "Odds ratio" else NULL),
       formula = formula)
}

#' @keywords internal
.fw_artifact_multinom <- function(object) {
  estimate <- stats::coef(object)
  std_error <- summary(object)$standard.errors
  if (is.null(dim(estimate))) {
    estimate <- matrix(estimate, nrow = 1L, dimnames = list(object$lev[length(object$lev)], names(estimate)))
    std_error <- matrix(std_error, nrow = 1L, dimnames = dimnames(estimate))
  }
  term <- as.vector(outer(rownames(estimate), colnames(estimate), paste, sep = ": "))
  ordering <- order(rep(seq_len(nrow(estimate)), ncol(estimate)))
  estimate_values <- as.vector(estimate)[ordering]
  se_values <- as.vector(std_error)[ordering]
  statistic <- estimate_values / se_values
  coefficients <- .fw_artifact_coefficients(term[ordering], estimate_values, se_values, statistic,
                                            2 * stats::pnorm(-abs(statistic)))
  values <- list(confidence_level = 0.95, interval_method = "wald-normal",
                 nobs = .fw_artifact_value(NROW(object$fitted.values)),
                 aic = .fw_artifact_value(object$AIC), deviance = .fw_artifact_value(object$deviance),
                 edf = .fw_artifact_value(object$edf))
  formula <- .fw_artifact_formula(object)
  list(tables = list(.fw_artifact_table(coefficients, "Coefficients", role = "coefficients")), values = values,
       model = .fw_artifact_description("multinomial", "multinomial", "logit", .fw_artifact_response(formula)),
       formula = formula)
}

#' @keywords internal
.fw_artifact_merMod <- function(object) {
  table <- summary(object)$coefficients
  p_column <- grep("^Pr\\(", colnames(table))
  coefficients <- .fw_artifact_coefficients(rownames(table), table[, 1], table[, 2], table[, 3],
                                            if (length(p_column)) table[, p_column[1]] else NULL)
  components <- as.data.frame(lme4::VarCorr(object), stringsAsFactors = FALSE)
  correlation <- !is.na(components$var2)
  random <- data.frame(group = components$grp,
                       term = ifelse(correlation, paste(components$var1, components$var2, sep = ", "),
                                     components$var1),
                       variance = ifelse(correlation, NA_real_, components$vcov),
                       std_dev = ifelse(correlation, NA_real_, components$sdcor),
                       stringsAsFactors = FALSE)
  if (any(correlation)) random$correlation <- ifelse(correlation, components$sdcor, NA_real_)
  values <- c(list(confidence_level = 0.95, interval_method = "wald-normal"), .fw_artifact_fit(object),
              list(sigma = .fw_artifact_value(stats::sigma(object)), reml = lme4::isREML(object)))
  if (!lme4::isREML(object)) values$deviance <- .fw_artifact_value(stats::deviance(object))
  groups <- lme4::ngrps(object)
  for (name in names(groups)) values[[paste0("n_groups.", name)]] <- as.integer(groups[[name]])
  if (inherits(object, "glmerMod")) {
    family <- .fw_artifact_family_name(stats::family(object)$family)
    link <- stats::family(object)$link
  } else {
    family <- "gaussian"
    link <- "identity"
  }
  formula <- .fw_artifact_formula(object)
  list(tables = list(.fw_artifact_table(coefficients, "Fixed effects", role = "coefficients"),
                     .fw_artifact_table(random, "Random effects", role = "random_effects")),
       values = values, model = .fw_artifact_description("mixed", family, link, .fw_artifact_response(formula)),
       formula = formula)
}

#' @keywords internal
.fw_artifact_coxph <- function(object) {
  table <- summary(object)$coefficients
  values <- list(confidence_level = 0.95, interval_method = "wald-normal",
                 nobs = .fw_artifact_value(object$n), n_events = .fw_artifact_value(object$nevent),
                 concordance = .fw_artifact_value(object$concordance[["concordance"]]))
  values <- c(values, .fw_artifact_fit(object)[c("aic", "bic", "log_likelihood")])
  if (is.null(table)) {
    coefficients <- data.frame(term = character(), estimate = numeric())
  } else {
    se_column <- if ("robust se" %in% colnames(table)) "robust se" else "se(coef)"
    column <- function(pattern) {
      index <- grep(pattern, colnames(table))
      if (length(index)) table[, index[1]] else NULL
    }
    coefficients <- .fw_artifact_coefficients(rownames(table), table[, "coef"], table[, se_column],
                                              column("^z$|^Chisq$"), column("^Pr\\(|^p$"))
  }
  formula <- .fw_artifact_formula(object)
  list(tables = list(.fw_artifact_table(coefficients, "Coefficients", role = "coefficients")), values = values,
       model = .fw_artifact_description("survival", response = .fw_artifact_response(formula),
                                        exponentiate = "Hazard ratio"),
       formula = formula)
}

#' @keywords internal
.fw_artifact_survreg <- function(object) {
  table <- summary(object)$table
  scale <- grepl("^Log\\(scale\\)", rownames(table))
  coefficients <- .fw_artifact_coefficients(rownames(table), table[, 1], table[, 2], table[, 3], table[, 4],
                                            component = if (any(scale)) ifelse(scale, "scale", "coefficient"))
  distribution <- survival::survreg.distributions[[object$dist]]
  link <- if (!is.null(distribution$trans)) "log" else "identity"
  values <- c(list(confidence_level = 0.95, interval_method = "wald-normal"), .fw_artifact_fit(object))
  if (length(object$scale) == 1L) values$scale <- object$scale
  formula <- .fw_artifact_formula(object)
  list(tables = list(.fw_artifact_table(coefficients, "Coefficients", role = "coefficients")), values = values,
       model = .fw_artifact_description("survival", object$dist, link, .fw_artifact_response(formula),
                                        if (identical(link, "log")) "Time ratio" else NULL),
       formula = formula)
}

#' @keywords internal
.fw_artifact_fixest <- function(object) {
  table <- fixest::coeftable(object)
  interval <- stats::confint(object)
  coefficients <- .fw_artifact_coefficients(rownames(table), table[, 1], table[, 2], table[, 3], table[, 4],
                                            conf_low = interval[rownames(table), 1],
                                            conf_high = interval[rownames(table), 2])
  use_t <- grepl("^t", colnames(table)[3])
  values <- c(list(confidence_level = 0.95, interval_method = if (use_t) "wald-t" else "wald-normal",
                   vcov_type = .fw_artifact_value(attr(table, "vcov_type"))),
              .fw_artifact_fit(object))
  if (identical(object$method, "feols")) {
    family <- "gaussian"
    link <- "identity"
    values$r.squared <- .fw_artifact_value(fixest::r2(object, "r2"))
    values$adj.r.squared <- .fw_artifact_value(fixest::r2(object, "ar2"))
    values$within_r.squared <- .fw_artifact_value(fixest::r2(object, "wr2"))
  } else {
    family <- .fw_artifact_family_name(object$family$family)
    link <- object$family$link
    if (identical(object$method, "fenegbin")) family <- "negative binomial"
    values$pseudo_rsquared <- .fw_artifact_value(fixest::r2(object, "pr2"))
  }
  for (name in names(object$fixef_sizes)) values[[paste0("n_groups.", name)]] <- as.integer(object$fixef_sizes[[name]])
  formula <- tryCatch(stats::formula(object, type = "full"), error = function(e) .fw_artifact_formula(object))
  list(tables = list(.fw_artifact_table(coefficients, "Coefficients", role = "coefficients")), values = values,
       model = .fw_artifact_description("fixed_effects", family, link,
                                        .fw_artifact_response(.fw_artifact_formula(object))),
       formula = formula)
}

#' @keywords internal
.fw_artifact_gam <- function(object) {
  model <- summary(object)
  table <- model$p.table
  use_t <- identical(colnames(table)[3], "t value")
  critical <- if (use_t) stats::qt(0.975, object$df.residual) else stats::qnorm(0.975)
  tables <- list(.fw_artifact_table(.fw_artifact_summary_coefficients(table, critical),
                                    "Parametric coefficients", role = "coefficients"))
  smooth <- model$s.table
  if (!is.null(smooth) && nrow(smooth)) {
    smooth <- data.frame(term = rownames(smooth), edf = smooth[, 1], ref_df = smooth[, 2],
                         statistic = smooth[, 3], p_value = smooth[, 4], stringsAsFactors = FALSE)
    tables <- c(tables, list(.fw_artifact_table(smooth, "Smooth terms", role = "smooth_terms")))
  }
  values <- c(list(confidence_level = 0.95, interval_method = if (use_t) "wald-t" else "wald-normal"),
              .fw_artifact_fit(object),
              list(adj.r.squared = .fw_artifact_value(model$r.sq),
                   deviance_explained = .fw_artifact_value(model$dev.expl),
                   deviance = .fw_artifact_value(object$deviance),
                   null.deviance = .fw_artifact_value(object$null.deviance),
                   dispersion = .fw_artifact_value(model$dispersion)))
  if (length(object$gcv.ubre) == 1L) values[[tolower(object$method)]] <- unname(object$gcv.ubre)
  family <- .fw_artifact_family_name(object$family$family)
  formula <- .fw_artifact_formula(object)
  list(tables = tables, values = values,
       model = .fw_artifact_description("additive", family, object$family$link, .fw_artifact_response(formula)),
       formula = formula)
}

# Dispatch on model class. Returns NULL for objects that aren't supported models.
#' @keywords internal
.fw_artifact_model <- function(object) {
  available <- function(package) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop("Publishing a ", class(object)[1], " model requires the ", package, " package.", call. = FALSE)
    }
    TRUE
  }
  if (inherits(object, "gam") && available("mgcv")) return(.fw_artifact_gam(object))
  if (inherits(object, "mlm")) return(NULL)
  if (inherits(object, "lm")) return(.fw_artifact_lm(object))
  if (inherits(object, "polr") && available("MASS")) return(.fw_artifact_polr(object))
  if (inherits(object, "multinom") && available("nnet")) return(.fw_artifact_multinom(object))
  if (inherits(object, "merMod") && available("lme4")) return(.fw_artifact_merMod(object))
  if (inherits(object, "coxph") && available("survival")) return(.fw_artifact_coxph(object))
  if (inherits(object, "survreg") && available("survival")) return(.fw_artifact_survreg(object))
  if (inherits(object, "fixest") && available("fixest")) return(.fw_artifact_fixest(object))
  NULL
}

#' @keywords internal
.fw_artifact_metrics <- function(values) {
  values <- Filter(function(value) length(value) == 1L && !is.null(.fw_artifact_scalar(value)), values)
  unname(lapply(names(values), function(name) list(name = name, value = .fw_artifact_scalar(values[[name]]))))
}

#' @keywords internal
.fw_artifact_structured <- function(object) {
  document <- list(schema = "framework.artifact/v1",
                   source = list(language = "r", class = as.list(class(object))), metrics = list())
  anova <- .fw_artifact_anova_tables(object)
  if (!is.null(anova)) {
    document$kind <- "table"
    document$tables <- anova
    return(document)
  }
  frame <- .fw_artifact_frame(object)
  if (!is.null(frame)) {
    document$kind <- "table"
    document$tables <- list(.fw_artifact_table(frame, role = "data", summaries = TRUE))
    return(document)
  }
  if (inherits(object, "htest") || inherits(object, "pairwise.htest")) {
    result <- if (inherits(object, "htest")) .fw_artifact_test(object) else .fw_artifact_pairwise_test(object)
    document$kind <- "test"
    document$test <- result$test
    document$tables <- result$tables
    return(document)
  }
  result <- .fw_artifact_model(object)
  if (is.null(result)) return(NULL)
  document$kind <- "model"
  document$model <- result$model
  document$tables <- result$tables
  document$metrics <- .fw_artifact_metrics(result$values)
  if (!is.null(result$formula)) {
    document$formula <- paste(trimws(deparse(result$formula, width.cutoff = 500L)), collapse = " ")
  }
  document
}

# Figures ------------------------------------------------------------------

#' @keywords internal
.fw_artifact_is_figure <- function(object) {
  inherits(object, "ggplot") || inherits(object, "recordedplot") || inherits(object, "trellis") ||
    inherits(object, "htmlwidget") || inherits(object, "vegaspec")
}

#' @keywords internal
.fw_artifact_draw <- function(object) {
  if (inherits(object, "recordedplot")) grDevices::replayPlot(object) else print(object)
  invisible(NULL)
}

#' @keywords internal
.fw_artifact_render <- function(object, path, device) {
  device()
  opened <- grDevices::dev.cur()
  tryCatch(.fw_artifact_draw(object), finally = grDevices::dev.off(opened))
  path
}

#' @keywords internal
.fw_artifact_png_device <- function(path) {
  function() {
    if (requireNamespace("ragg", quietly = TRUE)) {
      ragg::agg_png(path, width = 7, height = 5, units = "in", res = 300, background = "white")
    } else {
      type <- if (capabilities("cairo")) "cairo" else getOption("bitmapType")
      grDevices::png(path, width = 7, height = 5, units = "in", res = 300, bg = "white", type = type)
    }
  }
}

#' @keywords internal
.fw_artifact_svg_limit <- function() 5 * 1024^2

# Self-contained widgets need pandoc. When none is on the PATH, use the copy
# bundled with Quarto. Returns the folder for RSTUDIO_PANDOC, or NULL.
#' @keywords internal
.fw_artifact_quarto_pandoc <- function() {
  if (nzchar(Sys.which("pandoc")) || nzchar(Sys.getenv("RSTUDIO_PANDOC"))) return(NULL)
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) return(NULL)
  tools <- file.path(dirname(normalizePath(quarto)), "tools")
  candidates <- file.path(tools, c("", "aarch64", "x86_64"), "pandoc")
  found <- candidates[file.exists(candidates)]
  if (length(found)) dirname(found[1]) else NULL
}

# Static plots: figure.svg with svglite (7 x 5 inches, white background), else
# figure.png at 300 dpi. SVG files over 5 MB fall back to PNG.
# Interactive htmlwidgets: a self-contained figure.html. Vega-Lite: figure.vl.json.
#' @keywords internal
.fw_artifact_figure <- function(object, directory, accepts) {
  failed <- function(e) {
    stop(accepts, " The plot could not be saved: ", conditionMessage(e), call. = FALSE)
  }
  if (inherits(object, "vegaspec") ||
      (inherits(object, "vegawidget") && requireNamespace("vegawidget", quietly = TRUE))) {
    spec <- if (inherits(object, "vegaspec")) object else vegawidget::as_vegaspec(object)
    path <- file.path(directory, "figure.vl.json")
    jsonlite::write_json(unclass(spec), path, auto_unbox = TRUE, null = "null", digits = NA)
    return(path)
  }
  if (inherits(object, "htmlwidget")) {
    if (!requireNamespace("htmlwidgets", quietly = TRUE)) {
      stop("Publishing an htmlwidget requires the htmlwidgets package.", call. = FALSE)
    }
    path <- file.path(directory, "figure.html")
    # htmlwidgets requires the dependency folder beside the file; it is inlined, then removed.
    libdir <- file.path(directory, "figure_files")
    on.exit(unlink(libdir, recursive = TRUE), add = TRUE)
    pandoc <- .fw_artifact_quarto_pandoc()
    if (!is.null(pandoc)) {
      previous <- Sys.getenv("RSTUDIO_PANDOC", unset = NA)
      Sys.setenv(RSTUDIO_PANDOC = pandoc)
      on.exit(if (is.na(previous)) Sys.unsetenv("RSTUDIO_PANDOC") else Sys.setenv(RSTUDIO_PANDOC = previous),
              add = TRUE)
    }
    tryCatch(htmlwidgets::saveWidget(object, path, selfcontained = TRUE, libdir = libdir),
             error = function(e) {
               stop("Publishing an htmlwidget needs a self-contained HTML file, which htmlwidgets ",
                    "could not write (", conditionMessage(e), "). Install pandoc, or save the widget ",
                    "with htmlwidgets::saveWidget() and publish the file.", call. = FALSE)
             })
    return(path)
  }
  if (inherits(object, "ggplot") && !requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Publishing a ggplot requires ggplot2.", call. = FALSE)
  }
  if (inherits(object, "trellis") && !requireNamespace("lattice", quietly = TRUE)) {
    stop("Publishing a lattice plot requires lattice.", call. = FALSE)
  }
  if (requireNamespace("svglite", quietly = TRUE)) {
    path <- file.path(directory, "figure.svg")
    tryCatch(.fw_artifact_render(object, path, function() {
      svglite::svglite(path, width = 7, height = 5, bg = "white")
    }), error = function(e) {
      unlink(path)
      failed(e)
    })
    if (file.size(path) <= .fw_artifact_svg_limit()) return(path)
    unlink(path)
  }
  path <- file.path(directory, "figure.png")
  tryCatch(.fw_artifact_render(object, path, .fw_artifact_png_device(path)), error = function(e) {
    unlink(path)
    failed(e)
  })
  path
}
