# Bayesian models: brms (brmsfit) and rstanarm (stanreg) fits.
# The contract is the "Bayesian models" section of framework-embed SPEC.md.
# Every table cell summarizes the posterior draws: posterior mean and SD, an
# equal-tailed credible interval, R-hat, and bulk and tail ESS. Ratio columns
# summarize the exponentiated draws. The draws themselves never leave R.

.fw_bayes_level <- 0.95

# Draw matrices (iterations by chains) for the named variables of a 3-D draws array.
#' @keywords internal
.fw_bayes_matrices <- function(draws, variables) {
  values <- unclass(draws)
  chains <- dim(values)[2]
  stats::setNames(lapply(variables, function(variable) {
    matrix(values[, , variable], ncol = chains)
  }), variables)
}

# R-hat, bulk ESS, or tail ESS of one draw matrix, from posterior or else rstan.
#' @keywords internal
.fw_bayes_convergence <- function(draws, measure) {
  fun <- if (requireNamespace("posterior", quietly = TRUE)) {
    getExportedValue("posterior", measure)
  } else if (requireNamespace("rstan", quietly = TRUE)) {
    getExportedValue("rstan", c(rhat = "Rhat", ess_bulk = "ess_bulk", ess_tail = "ess_tail")[[measure]])
  }
  if (is.null(fun)) return(NA_real_)
  .fw_artifact_value(fun(draws)) %||% NA_real_
}

# One row per parameter. `draws` is a named list of draw matrices; `group` adds a
# first column. Ratio columns summarize exp() of each draw.
#' @keywords internal
.fw_bayes_table <- function(draws, level, ratio = FALSE, group = NULL) {
  probs <- c((1 - level) / 2, 1 - (1 - level) / 2)
  summarise <- function(values) {
    values <- as.vector(values)
    c(mean(values), stats::sd(values), stats::quantile(values, probs, names = FALSE))
  }
  data <- data.frame(term = names(draws), stringsAsFactors = FALSE)
  if (!is.null(group)) data <- cbind(data.frame(group = group, stringsAsFactors = FALSE), data)
  if (!length(draws)) {
    data$estimate <- numeric()
    return(data)
  }
  summaries <- do.call(rbind, lapply(draws, summarise))
  data$estimate <- summaries[, 1]
  data$std_error <- summaries[, 2]
  data$conf_low <- summaries[, 3]
  data$conf_high <- summaries[, 4]
  for (measure in c("rhat", "ess_bulk", "ess_tail")) {
    data[[measure]] <- vapply(draws, .fw_bayes_convergence, numeric(1), measure = measure)
  }
  if (ratio) {
    # An intercept or threshold is a baseline, not a ratio, so its ratio cells stay empty.
    baseline <- grepl("^\\(?intercept\\)?(\\[[0-9]+\\])?$", tolower(names(draws)))
    ratios <- do.call(rbind, lapply(draws, function(values) summarise(exp(values))))
    ratios[baseline, ] <- NA_real_
    data$ratio_estimate <- ratios[, 1]
    data$ratio_std_error <- ratios[, 2]
    data$ratio_conf_low <- ratios[, 3]
    data$ratio_conf_high <- ratios[, 4]
  }
  rownames(data) <- NULL
  data
}

#' @keywords internal
.fw_bayes_require_sampling <- function(algorithm, package) {
  if (is.null(algorithm) || identical(algorithm, "sampling")) return(invisible(TRUE))
  stop("Publishing a ", package, " model fit with algorithm = \"", algorithm, "\" isn't supported. ",
       "Only models fit by MCMC sampling publish.", call. = FALSE)
}

# Family names as the glm adapter writes them, so the model name reads the same.
#' @keywords internal
.fw_bayes_family <- function(family) {
  family <- .fw_artifact_family_name(family)
  if (is.null(family)) return(NULL)
  switch(family, bernoulli = "binomial", negbinomial = , negbinomial2 = , neg_binomial_2 = "negative binomial",
         family)
}

#' @keywords internal
.fw_bayes_type <- function(family, link, mixed) {
  if (isTRUE(family %in% c("cumulative", "sratio", "cratio", "acat"))) return(if (mixed) "mixed" else "ordinal")
  if (isTRUE(family %in% c("categorical", "multinomial"))) return("multinomial")
  if (mixed) return("mixed")
  if (identical(family, "gaussian") && identical(link, "identity")) return("linear")
  "glm"
}

# Sampler settings and diagnostics from a stanfit.
#' @keywords internal
.fw_bayes_sampler <- function(stanfit) {
  values <- list()
  if (!inherits(stanfit, "stanfit") || !length(stanfit@sim)) return(values)
  values$warmup <- .fw_artifact_value(as.integer(stanfit@sim$warmup))
  args <- if (length(stanfit@stan_args)) stanfit@stan_args[[1]] else list()
  algorithm <- toupper(as.character(args$algorithm %||% "NUTS")[1])
  engine <- tolower(as.character(args$engine %||% "")[1])
  values$sampler <- if (identical(algorithm, "NUTS") || identical(engine, "nuts")) "NUTS (Stan)" else
    if (algorithm %in% c("HMC", "STATIC")) "HMC (Stan)" else paste0(algorithm, " (Stan)")
  if (identical(values$sampler, "NUTS (Stan)") && requireNamespace("rstan", quietly = TRUE)) {
    values$divergent_transitions <- .fw_artifact_value(as.integer(rstan::get_num_divergent(stanfit)))
    values$max_treedepth_hits <- .fw_artifact_value(as.integer(rstan::get_num_max_treedepth(stanfit)))
  }
  values
}

# LOO and WAIC only when the fit already stores them: they are not computed here.
#' @keywords internal
.fw_bayes_criteria <- function(loo, waic) {
  values <- list()
  estimate <- function(criterion, row, column = "Estimate") {
    table <- criterion$estimates
    if (!is.matrix(table) || !row %in% rownames(table) || !column %in% colnames(table)) return(NULL)
    .fw_artifact_value(table[row, column])
  }
  if (inherits(loo, "loo")) {
    values$elpd_loo <- estimate(loo, "elpd_loo")
    values$elpd_loo_se <- estimate(loo, "elpd_loo", "SE")
    values$looic <- estimate(loo, "looic")
    values$p_loo <- estimate(loo, "p_loo")
  }
  if (inherits(waic, "loo")) values$waic <- estimate(waic, "waic")
  values
}

# Bayes R² as its posterior mean, skipped when draws times observations is large.
#' @keywords internal
.fw_bayes_r2 <- function(compute, draws, nobs) {
  if (is.null(nobs) || as.numeric(draws) * as.numeric(nobs) > 5e6) return(NULL)
  values <- tryCatch(suppressWarnings(compute()), error = function(e) NULL)
  if (!is.numeric(values) || !length(values)) return(NULL)
  .fw_artifact_value(mean(as.vector(values)))
}

#' @keywords internal
.fw_bayes_formula <- function(formula) {
  if (!inherits(formula, "formula")) return(NULL)
  environment <- environment(formula)
  attributes(formula) <- NULL
  formula <- stats::as.formula(formula, env = environment %||% globalenv())
  formula
}

# brms ---------------------------------------------------------------------

#' @keywords internal
.fw_bayes_brms_response <- function(formula) {
  if (!inherits(formula, "formula") || length(formula) != 3L) return(NULL)
  lhs <- formula[[2]]
  if (is.call(lhs) && identical(lhs[[1]], as.name("|"))) lhs <- lhs[[2]]
  .fw_mv_deparse(lhs)
}

# Population-level draws are b_<term>, or bsp_, bcs_, or bs_ for special terms.
#' @keywords internal
.fw_bayes_brms_fixed <- function(object, variables) {
  terms <- rownames(brms::fixef(object))
  names <- vapply(terms, function(term) {
    found <- intersect(paste0(c("b_", "bsp_", "bcs_", "bs_"), term), variables)
    if (length(found)) found[1] else NA_character_
  }, character(1))
  stats::setNames(names[!is.na(names)], terms[!is.na(names)])
}

# sd_<group>__<coef> and cor_<group>__<coef>__<coef>, as brms prints them.
#' @keywords internal
.fw_bayes_brms_random <- function(variables) {
  sds <- grep("^sd_.+__.+$", variables, value = TRUE)
  cors <- grep("^cor_.+__.+__.+$", variables, value = TRUE)
  parts <- strsplit(c(sds, cors), "__", fixed = TRUE)
  group <- sub("^(sd|cor)_", "", vapply(parts, `[`, character(1), 1L))
  term <- vapply(parts, function(part) {
    if (startsWith(part[1], "sd_")) paste0("sd(", paste(part[-1], collapse = "__"), ")") else
      paste0("cor(", paste(part[-1], collapse = ","), ")")
  }, character(1))
  # brms prints each group's SDs, then its correlations.
  order <- order(match(group, unique(group)), !startsWith(c(sds, cors), "sd_"))
  list(variables = c(sds, cors)[order], group = group[order], term = term[order])
}

#' @keywords internal
.fw_bayes_brms_priors <- function(object) {
  priors <- tryCatch(as.data.frame(brms::prior_summary(object)), error = function(e) NULL)
  if (is.null(priors) || !nrow(priors)) return(NULL)
  field <- function(name) {
    values <- if (name %in% names(priors)) as.character(priors[[name]]) else rep("", nrow(priors))
    values[is.na(values)] <- ""
    values
  }
  # An empty prior below its class inherits the class prior, so only the class row stays.
  keep <- nzchar(field("prior")) | (!nzchar(field("coef")) & !nzchar(field("group")))
  priors <- priors[keep, , drop = FALSE]
  if (!nrow(priors)) return(NULL)
  class <- field("class")
  parameter <- vapply(seq_len(nrow(priors)), function(i) {
    pieces <- c(class[i], field("resp")[i], field("dpar")[i], field("nlpar")[i])
    name <- paste(pieces[nzchar(pieces)], collapse = "_")
    group <- field("group")[i]
    coef <- field("coef")[i]
    if (nzchar(group)) name <- paste0(name, "_", group)
    if (nzchar(coef)) name <- paste0(name, if (nzchar(group)) "__" else "_", coef)
    name
  }, character(1))
  prior <- field("prior")
  prior[!nzchar(prior)] <- "(flat)"
  source <- field("source")
  data <- data.frame(parameter = parameter, prior = prior, stringsAsFactors = FALSE)
  if (any(nzchar(source))) data$source <- ifelse(nzchar(source), source, NA_character_)
  data
}

#' @keywords internal
.fw_artifact_brmsfit <- function(object, level = .fw_bayes_level) {
  .fw_bayes_require_sampling(object$algorithm, "brms")
  if (inherits(object$formula, "mvbrmsformula")) {
    stop("Publishing a multivariate brms model isn't supported.", call. = FALSE)
  }
  if (!length(object$fit@sim)) stop("The brms model has no posterior draws.", call. = FALSE)
  variables <- posterior::variables(object)
  fixed <- .fw_bayes_brms_fixed(object, variables)
  random <- .fw_bayes_brms_random(variables)
  dpars <- setdiff(intersect(as.character(object$family$dpars), variables), "mu")
  smooths <- grep("^sds_", variables, value = TRUE)
  draws <- posterior::as_draws_array(object, variable = unique(c(fixed, random$variables, dpars, smooths)))
  matrices <- .fw_bayes_matrices(draws, posterior::variables(draws))

  family <- .fw_bayes_family(object$family$family)
  link <- object$family$link
  mixed <- length(random$variables) > 0L
  main <- .fw_bayes_formula(object$formula$formula)
  description <- .fw_artifact_description(.fw_bayes_type(family, link, mixed), family, link,
                                          .fw_bayes_brms_response(main))
  description$inference <- "bayesian"
  ratio <- !is.null(description$exponentiate)

  tables <- list(.fw_artifact_table(.fw_bayes_table(stats::setNames(matrices[fixed], names(fixed)), level, ratio),
                                    if (mixed) "Population-level effects" else "Coefficients",
                                    role = "coefficients"))
  if (mixed) {
    tables <- c(tables, list(.fw_artifact_table(
      .fw_bayes_table(stats::setNames(matrices[random$variables], random$term), level, group = random$group),
      "Group-level effects", role = "random_effects")))
  }
  if (length(smooths)) {
    terms <- paste0("sds(", sub("^sds_", "", smooths), ")")
    tables <- c(tables, list(.fw_artifact_table(.fw_bayes_table(stats::setNames(matrices[smooths], terms), level),
                                                "Smooth terms", role = "smooth_terms")))
  }
  if (length(dpars)) {
    tables <- c(tables, list(.fw_artifact_table(.fw_bayes_table(matrices[dpars], level),
                                                "Distributional parameters", role = "distributional")))
  }
  priors <- .fw_bayes_brms_priors(object)
  if (!is.null(priors)) tables <- c(tables, list(.fw_artifact_table(priors, "Priors", role = "priors")))

  nobs <- .fw_artifact_value(stats::nobs(object))
  values <- list(nobs = nobs, confidence_level = level, interval_method = "Equal-tailed",
                 chains = posterior::nchains(draws), draws = posterior::ndraws(draws))
  values <- c(values, .fw_bayes_sampler(object$fit))
  if (!isTRUE(family %in% c("categorical", "multinomial", "cumulative", "sratio", "cratio", "acat"))) {
    values$bayes_r2 <- .fw_bayes_r2(function() brms::bayes_R2(object, summary = FALSE),
                                    values$draws, nobs)
  }
  values <- c(values, .fw_bayes_criteria(object$criteria$loo, object$criteria$waic))
  if (mixed) {
    groups <- tryCatch(brms::ngrps(object), error = function(e) NULL)
    for (name in names(groups)) values[[paste0("n_groups.", name)]] <- as.integer(groups[[name]][1])
  }

  formula <- main
  extra <- Filter(function(f) inherits(f, "formula"), object$formula$pforms %||% list())
  if (length(extra)) {
    formula <- paste(vapply(c(list(main), extra), function(f) {
      paste(trimws(deparse(.fw_bayes_formula(f), width.cutoff = 500L)), collapse = " ")
    }, character(1)), collapse = "; ")
  }
  list(tables = tables, values = values, model = description, formula = formula)
}

# rstanarm -----------------------------------------------------------------

#' @keywords internal
.fw_bayes_rstanarm_supported <- c("stan_glm", "stan_glm.nb", "stan_lm", "stan_aov", "stan_glmer",
                                  "stan_lmer", "stan_glmer.nb")

# Group-level SDs and correlations from the Sigma[group:coef,coef] covariance draws.
#' @keywords internal
.fw_bayes_rstanarm_random <- function(object, draws) {
  coefs <- object$glmod$reTrms$cnms
  available <- dimnames(draws)[[3]]
  out <- list(draws = list(), group = character())
  strip <- function(name) if (identical(name, "(Intercept)")) "Intercept" else name
  for (group in names(coefs)) {
    names <- coefs[[group]]
    variance <- function(a, b) {
      key <- c(sprintf("Sigma[%s:%s,%s]", group, a, b), sprintf("Sigma[%s:%s,%s]", group, b, a))
      key <- intersect(key, available)
      if (length(key)) .fw_bayes_matrices(draws, key[1])[[1]] else NULL
    }
    sds <- lapply(names, function(name) {
      value <- variance(name, name)
      if (is.null(value)) NULL else sqrt(value)
    })
    for (i in seq_along(names)) {
      if (is.null(sds[[i]])) next
      out$draws[[length(out$draws) + 1L]] <- sds[[i]]
      names(out$draws)[length(out$draws)] <- paste0("sd(", strip(names[i]), ")")
      out$group <- c(out$group, group)
    }
    for (i in seq_along(names)) for (j in seq_along(names)) {
      if (j <= i || is.null(sds[[i]]) || is.null(sds[[j]])) next
      covariance <- variance(names[j], names[i])
      if (is.null(covariance)) next
      out$draws[[length(out$draws) + 1L]] <- covariance / (sds[[i]] * sds[[j]])
      names(out$draws)[length(out$draws)] <- paste0("cor(", strip(names[i]), ",", strip(names[j]), ")")
      out$group <- c(out$group, group)
    }
  }
  out
}

# A prior from rstanarm's prior_summary() as text, such as normal(0, 2.5).
#' @keywords internal
.fw_bayes_rstanarm_prior_text <- function(prior, index = 1L) {
  dist <- prior$dist
  if (is.null(dist) || !length(dist)) return(NULL)
  pick <- function(value) {
    if (is.null(value) || !length(value)) return(NULL)
    value <- value[min(index, length(value))]
    if (is.na(value)) NULL else format(signif(value, 3))
  }
  scale <- pick(prior$adjusted_scale) %||% pick(prior$scale)
  arguments <- switch(dist,
    normal = , cauchy = , logistic = , laplace = , lasso = c(pick(prior$location), scale),
    student_t = , hs = , hs_plus = c(pick(prior$df), pick(prior$location), scale),
    exponential = paste0("rate = ", if (!is.null(pick(prior$adjusted_scale))) {
      format(signif(1 / prior$adjusted_scale[min(index, length(prior$adjusted_scale))], 3))
    } else {
      pick(prior$rate) %||% format(signif(1 / as.numeric(scale), 3))
    }),
    decov = c(paste0("reg = ", pick(prior$regularization)), paste0("conc = ", pick(prior$concentration)),
              paste0("shape = ", pick(prior$shape)), paste0("scale = ", pick(prior$scale))),
    lkj = c(paste0("reg = ", pick(prior$regularization)), paste0("df = ", pick(prior$df)),
            paste0("scale = ", pick(prior$scale))),
    c(pick(prior$location), scale))
  paste0(dist, "(", paste(arguments, collapse = ", "), ")")
}

#' @keywords internal
.fw_bayes_rstanarm_priors <- function(object) {
  summary <- tryCatch(rstanarm::prior_summary(object), error = function(e) NULL)
  if (is.null(summary)) return(NULL)
  call <- object$call
  source <- function(argument) if (!is.null(call) && !is.null(call[[argument]])) "user" else "default"
  rows <- list()
  add <- function(parameter, prior, argument) {
    if (is.null(prior)) return()
    rows[[length(rows) + 1L]] <<- data.frame(parameter = parameter, prior = prior, source = source(argument),
                                             stringsAsFactors = FALSE)
  }
  if (!is.null(summary$prior_intercept)) {
    add("(Intercept)", .fw_bayes_rstanarm_prior_text(summary$prior_intercept), "prior_intercept")
  }
  coefficients <- summary$prior
  if (!is.null(coefficients$dist)) {
    terms <- setdiff(names(rstanarm::fixef(object)), "(Intercept)")
    texts <- vapply(seq_along(terms), function(i) .fw_bayes_rstanarm_prior_text(coefficients, i) %||% NA_character_,
                    character(1))
    if (length(unique(texts)) == 1L) {
      add("b", texts[1], "prior")
    } else {
      for (i in seq_along(terms)) add(terms[i], texts[i], "prior")
    }
  }
  aux <- summary$prior_aux
  if (!is.null(aux)) add(aux$aux_name %||% "aux", .fw_bayes_rstanarm_prior_text(aux), "prior_aux")
  covariance <- summary$prior_covariance
  if (!is.null(covariance)) add("Covariance", .fw_bayes_rstanarm_prior_text(covariance), "prior_covariance")
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

#' @keywords internal
.fw_artifact_stanreg <- function(object, level = .fw_bayes_level) {
  .fw_bayes_require_sampling(object$algorithm, "rstanarm")
  if (!isTRUE(object$stan_function %in% .fw_bayes_rstanarm_supported)) {
    stop("Publishing a ", object$stan_function %||% "rstanarm", " model isn't supported. rstanarm models from ",
         paste(.fw_bayes_rstanarm_supported, collapse = ", "), " publish.", call. = FALSE)
  }
  draws <- as.array(object)
  available <- dimnames(draws)[[3]]
  terms <- intersect(names(rstanarm::fixef(object)), available)
  mixed <- !is.null(object$glmod)
  aux <- intersect(c("sigma", "reciprocal_dispersion", "shape", "phi"), available)
  matrices <- .fw_bayes_matrices(draws, c(terms, aux))

  family <- .fw_bayes_family(object$family$family)
  link <- object$family$link
  formula <- .fw_artifact_formula(object)
  description <- .fw_artifact_description(.fw_bayes_type(family, link, mixed), family, link,
                                          .fw_artifact_response(formula))
  description$inference <- "bayesian"
  ratio <- !is.null(description$exponentiate)

  tables <- list(.fw_artifact_table(.fw_bayes_table(matrices[terms], level, ratio),
                                    if (mixed) "Fixed effects" else "Coefficients", role = "coefficients"))
  if (mixed) {
    random <- .fw_bayes_rstanarm_random(object, draws)
    tables <- c(tables, list(.fw_artifact_table(.fw_bayes_table(random$draws, level, group = random$group),
                                                "Random effects", role = "random_effects")))
  }
  if (length(aux)) {
    tables <- c(tables, list(.fw_artifact_table(.fw_bayes_table(matrices[aux], level),
                                                "Distributional parameters", role = "distributional")))
  }
  priors <- .fw_bayes_rstanarm_priors(object)
  if (!is.null(priors)) tables <- c(tables, list(.fw_artifact_table(priors, "Priors", role = "priors")))

  nobs <- .fw_artifact_value(stats::nobs(object))
  values <- list(nobs = nobs, confidence_level = level, interval_method = "Equal-tailed",
                 chains = dim(draws)[2], draws = dim(draws)[1] * dim(draws)[2])
  values <- c(values, .fw_bayes_sampler(object$stanfit))
  values$bayes_r2 <- .fw_bayes_r2(function() rstanarm::bayes_R2(object), values$draws, nobs)
  values <- c(values, .fw_bayes_criteria(object$loo %||% object$criteria$loo,
                                         object$waic %||% object$criteria$waic))
  if (mixed) {
    groups <- tryCatch(rstanarm::ngrps(object), error = function(e) NULL)
    for (name in names(groups)) values[[paste0("n_groups.", name)]] <- as.integer(groups[[name]])
  }
  list(tables = tables, values = values, model = description, formula = formula)
}
