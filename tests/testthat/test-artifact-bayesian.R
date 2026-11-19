# Bayesian models: the "Bayesian models" section of framework-embed SPEC.md.
# Fits are tiny (two chains, a few hundred iterations) and run only when a
# backend is installed.

bayes_export <- function(object) {
  path <- framework:::.fw_artifact_file(object, withr::local_tempdir(.local_envir = parent.frame()), cloud = TRUE)
  list(path = path, file = basename(path), text = paste(readLines(path, warn = FALSE), collapse = "\n"),
       document = if (grepl("\\.json$", path)) jsonlite::fromJSON(path, simplifyVector = FALSE))
}

bayes_columns <- function(table) vapply(table$columns, `[[`, character(1), "name")

bayes_table <- function(document, role) document$tables[[match(role, vapply(document$tables, function(x) x$role %||% "",
                                                                          character(1)))]]

bayes_cell <- function(table, row, name) table$rows[[row]][[match(name, bayes_columns(table))]]

bayes_terms <- function(table) vapply(table$rows, function(row) row[[1]], character(1))

has_row <- function(table, row) any(vapply(table$rows, identical, logical(1), row))

bayes_metrics <- function(document) {
  stats::setNames(lapply(document$metrics, `[[`, "value"), vapply(document$metrics, `[[`, character(1), "name"))
}

summary_columns <- c("estimate", "std_error", "conf_low", "conf_high", "rhat", "ess_bulk", "ess_tail")
ratio_columns <- c("ratio_estimate", "ratio_std_error", "ratio_conf_low", "ratio_conf_high")

# Shared checks: inference, columns, no frequentist statistics, no draws.
expect_bayesian_model <- function(result, type, ratio) {
  document <- result$document
  expect_identical(result$file, "model.json")
  expect_identical(document$kind, "model")
  expect_identical(document$model$inference, "bayesian")
  expect_identical(document$model$type, type)
  coefficients <- bayes_table(document, "coefficients")
  expected <- c("term", summary_columns, if (ratio) ratio_columns)
  expect_identical(bayes_columns(coefficients), expected)
  expect_false(any(c("statistic", "p_value") %in% bayes_columns(coefficients)))
  priors <- bayes_table(document, "priors")
  expect_identical(bayes_columns(priors)[1:2], c("parameter", "prior"))
  metrics <- bayes_metrics(document)
  expect_identical(metrics$confidence_level, 0.95)
  expect_identical(metrics$interval_method, "Equal-tailed")
  expect_identical(metrics$chains, 2L)
  expect_identical(metrics$sampler, "NUTS (Stan)")
  expect_true(all(c("nobs", "draws", "warmup", "divergent_transitions", "max_treedepth_hits") %in% names(metrics)))
  # Summaries only: far fewer numbers than one chain of draws.
  expect_lt(nchar(result$text), 20000)
  expect_false(grepl("lp__|lprior|\"draws\":\\s*\\[", result$text))
  invisible(document)
}

skip_unless_brms <- function() {
  skip_on_cran()
  skip_if_not_installed("brms")
  skip_if_not_installed("posterior")
  # cmdstanr isn't on CRAN, so it is named only as a string here.
  cmdstanr <- "cmdstanr"
  backend <- if (requireNamespace(cmdstanr, quietly = TRUE) &&
                   !is.null(tryCatch(getExportedValue(cmdstanr, "cmdstan_version")(error_on_NA = FALSE),
                                     error = function(e) NULL))) {
    "cmdstanr"
  } else if (requireNamespace("rstan", quietly = TRUE) &&
             all(vapply(c("BH", "RcppEigen", "StanHeaders"), requireNamespace, logical(1), quietly = TRUE))) {
    # rstan compiles each model against these headers. A binary install of
    # rstan leaves out BH, so the compile fails without it.
    "rstan"
  } else {
    skip("No Stan backend for brms.")
  }
  backend
}

fit_brms <- function(formula, data, ...) {
  backend <- skip_unless_brms()
  suppressWarnings(suppressMessages(brms::brm(formula, data = data, ..., backend = backend, chains = 2,
                                               iter = 400, warmup = 200, refresh = 0, seed = 1, silent = 2)))
}

test_that("posterior summaries are means, SDs, and equal-tailed intervals, and ratios come from the draws", {
  set.seed(1)
  draws <- list(`(Intercept)` = matrix(stats::rnorm(400, 1, 0.5), ncol = 2),
                x = matrix(stats::rnorm(400, 0.4, 1), ncol = 2))
  table <- framework:::.fw_bayes_table(draws, 0.9, ratio = TRUE)
  expect_identical(names(table), c("term", summary_columns, ratio_columns))
  x <- as.vector(draws$x)
  expect_equal(table$estimate[2], mean(x))
  expect_equal(table$std_error[2], stats::sd(x))
  expect_equal(c(table$conf_low[2], table$conf_high[2]), unname(stats::quantile(x, c(0.05, 0.95))))
  expect_equal(table$ratio_estimate[2], mean(exp(x)))
  expect_equal(table$ratio_conf_high[2], unname(stats::quantile(exp(x), 0.95)))
  # The mean of the ratios, not the ratio of the mean.
  expect_gt(abs(table$ratio_estimate[2] - exp(table$estimate[2])), 0.1)
  expect_true(is.na(table$ratio_estimate[1]))
  if (requireNamespace("posterior", quietly = TRUE)) {
    expect_equal(table$rhat[2], posterior::rhat(draws$x))
    expect_equal(table$ess_bulk[2], posterior::ess_bulk(draws$x))
    expect_equal(table$ess_tail[2], posterior::ess_tail(draws$x))
  }
  random <- framework:::.fw_bayes_table(draws["x"], 0.95, group = "g")
  expect_identical(names(random), c("group", "term", summary_columns))
})

test_that("brms logistic models publish posterior summaries, odds ratios, priors, and variables", {
  fit <- fit_brms(am ~ wt + gear_f, transform(mtcars, gear_f = factor(gear)), family = brms::bernoulli(),
                  prior = brms::set_prior("normal(0, 2)", class = "b"))
  fit <- brms::add_criterion(fit, "loo")
  result <- bayes_export(fit)
  document <- expect_bayesian_model(result, "glm", ratio = TRUE)
  expect_identical(document$model[c("family", "link", "response", "exponentiate")],
                   list(family = "binomial", link = "logit", response = "am", exponentiate = "Odds ratio"))
  coefficients <- bayes_table(document, "coefficients")
  expect_identical(bayes_terms(coefficients), rownames(brms::fixef(fit)))
  draws <- posterior::as_draws_array(fit, variable = "b_wt")
  expect_equal(bayes_cell(coefficients, 2, "estimate"), mean(as.vector(draws)))
  expect_equal(bayes_cell(coefficients, 2, "ratio_estimate"), mean(exp(as.vector(draws))))
  expect_equal(bayes_cell(coefficients, 2, "rhat"), posterior::rhat(posterior::extract_variable_matrix(draws, "b_wt")))
  expect_null(bayes_cell(coefficients, 1, "ratio_estimate"))
  priors <- bayes_table(document, "priors")
  expect_true(has_row(priors, list("b", "normal(0, 2)", "user")))
  metrics <- bayes_metrics(document)
  expect_identical(metrics$nobs, 32L)
  expect_identical(metrics$draws, 400L)
  expect_identical(metrics$warmup, 200L)
  expect_true(is.numeric(metrics$bayes_r2) && metrics$bayes_r2 > 0 && metrics$bayes_r2 < 1)
  expect_equal(metrics$elpd_loo, fit$criteria$loo$estimates["elpd_loo", "Estimate"])
  expect_true(all(c("elpd_loo_se", "looic", "p_loo") %in% names(metrics)))
  expect_false("waic" %in% names(metrics))
  expect_identical(document$formula, "am ~ wt + gear_f")
  expect_identical(vapply(document$variables, `[[`, character(1), "name"), c("am", "wt", "gear_f"))
  terms <- stats::setNames(lapply(document$terms, `[[`, "parts"), vapply(document$terms, `[[`, character(1), "term"))
  expect_identical(terms$gear_f4, list(list(variable = "gear_f", level = "4")))
  expect_identical(document$variables[[3]]$reference, "3")
})

test_that("brms mixed models publish group-level SDs and correlations with their group", {
  skip_if_not_installed("lme4")
  fit <- fit_brms(Reaction ~ Days + (Days | Subject), lme4::sleepstudy)
  document <- expect_bayesian_model(bayes_export(fit), "mixed", ratio = FALSE)
  expect_identical(document$model[c("family", "link", "response")],
                   list(family = "gaussian", link = "identity", response = "Reaction"))
  random <- bayes_table(document, "random_effects")
  expect_identical(bayes_columns(random), c("group", "term", summary_columns))
  expect_identical(vapply(random$rows, `[[`, character(1), 2),
                   c("sd(Intercept)", "sd(Days)", "cor(Intercept,Days)"))
  expect_identical(unique(vapply(random$rows, `[[`, character(1), 1)), "Subject")
  distributional <- bayes_table(document, "distributional")
  expect_identical(bayes_terms(distributional), "sigma")
  expect_identical(bayes_metrics(document)[["n_groups.Subject"]], 18L)
  roles <- vapply(document$variables, `[[`, character(1), "role")
  expect_identical(roles, c("response", "predictor", "group"))
})

test_that("brms binomial models with trials() keep the trials variable with the response", {
  skip_if_not_installed("lme4")
  fit <- fit_brms(incidence | trials(size) ~ period, lme4::cbpp, family = stats::binomial())
  document <- expect_bayesian_model(bayes_export(fit), "glm", ratio = TRUE)
  expect_identical(document$model$response, "incidence")
  size <- document$variables[[match("size", vapply(document$variables, `[[`, character(1), "name"))]]
  expect_identical(size$role, "response")
  expect_identical(vapply(document$terms, `[[`, character(1), "term"), c("period2", "period3", "period4"))
})

test_that("brms conditional effects publish as one figure", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  fit <- fit_brms(mpg ~ wt + hp, mtcars)
  effects <- brms::conditional_effects(fit)
  expect_length(effects, 2L)
  for (object in list(effects, brms::conditional_effects(fit, effects = "wt"), plot(effects, plot = FALSE))) {
    result <- suppressMessages(bayes_export(object))
    expect_true(result$file %in% c("figure.svg", "figure.png"))
  }
  expect_true(inherits(suppressMessages(framework:::.fw_artifact_plots(effects)), "patchwork"))
  single <- brms::conditional_effects(fit, effects = "wt")
  expect_true(inherits(suppressMessages(framework:::.fw_artifact_plots(single)), "ggplot"))
  expect_false(inherits(suppressMessages(framework:::.fw_artifact_plots(single)), "patchwork"))
})

test_that("models fit without MCMC sampling stop with a message", {
  skip_if_not_installed("brms")
  skip_if_not_installed("posterior")
  fit <- structure(list(algorithm = "meanfield"), class = "brmsfit")
  expect_error(bayes_export(fit), "algorithm = \"meanfield\" isn't supported")
})

test_that("rstanarm glm and glmer models publish posterior summaries", {
  skip_on_cran()
  skip_if_not_installed("rstanarm")
  skip_if_not_installed("lme4")
  fit_stan <- function(fun, ...) {
    suppressWarnings(fun(..., chains = 2, iter = 400, refresh = 0, seed = 1))
  }
  logit <- fit_stan(rstanarm::stan_glm, am ~ wt + factor(cyl), data = mtcars, family = stats::binomial())
  document <- expect_bayesian_model(bayes_export(logit), "glm", ratio = TRUE)
  expect_identical(document$model$exponentiate, "Odds ratio")
  coefficients <- bayes_table(document, "coefficients")
  expect_identical(bayes_terms(coefficients), c("(Intercept)", "wt", "factor(cyl)6", "factor(cyl)8"))
  draws <- as.matrix(logit, pars = "wt")
  expect_equal(bayes_cell(coefficients, 2, "estimate"), mean(draws))
  expect_equal(bayes_cell(coefficients, 2, "ratio_conf_low"), unname(stats::quantile(exp(draws), 0.025)))
  expect_identical(vapply(document$terms, `[[`, character(1), "term"), c("wt", "factor(cyl)6", "factor(cyl)8"))
  expect_true(has_row(bayes_table(document, "priors"), list("(Intercept)", "normal(0, 2.5)", "default")))

  counts <- fit_stan(rstanarm::stan_glm, count ~ spray, data = InsectSprays, family = stats::poisson())
  expect_identical(bayes_export(counts)$document$model$exponentiate, "Rate ratio")

  # stan_lmer() calls stan_glmer() unqualified, so it needs rstanarm attached; this is the same model.
  mixed <- fit_stan(rstanarm::stan_glmer, Reaction ~ Days + (Days | Subject), data = lme4::sleepstudy,
                    family = stats::gaussian())
  document <- expect_bayesian_model(bayes_export(mixed), "mixed", ratio = FALSE)
  random <- bayes_table(document, "random_effects")
  expect_identical(vapply(random$rows, `[[`, character(1), 2), c("sd(Intercept)", "sd(Days)", "cor(Intercept,Days)"))
  sigma <- as.matrix(mixed, pars = "Sigma[Subject:(Intercept),(Intercept)]")
  expect_equal(bayes_cell(random, 1, "estimate"), mean(sqrt(sigma)))
  expect_identical(bayes_terms(bayes_table(document, "distributional")), "sigma")
  expect_identical(vapply(document$variables, `[[`, character(1), "role"), c("response", "predictor", "group"))

  binomial <- fit_stan(rstanarm::stan_glmer, cbind(incidence, size - incidence) ~ period + (1 | herd),
                       data = lme4::cbpp, family = stats::binomial(), prior = rstanarm::normal(0, 1))
  document <- expect_bayesian_model(bayes_export(binomial), "mixed", ratio = TRUE)
  expect_true(has_row(bayes_table(document, "priors"), list("b", "normal(0, 1)", "user")))
  expect_identical(vapply(document$terms, `[[`, character(1), "term"), c("period2", "period3", "period4"))
})

test_that("bayesplot plots publish as figures", {
  skip_if_not_installed("bayesplot")
  skip_if_not_installed("ggplot2")
  # mcmc_pairs() needs gridExtra, which bayesplot only suggests
  skip_if_not_installed("gridExtra")
  set.seed(1)
  draws <- array(stats::rnorm(400), c(100, 2, 2), dimnames = list(NULL, NULL, c("alpha", "beta")))
  y <- stats::rnorm(20)
  yrep <- matrix(stats::rnorm(200), 10, 20)
  # mcmc_pairs() draws as it is built, so it gets a null device.
  grDevices::pdf(NULL)
  pairs <- suppressMessages(bayesplot::mcmc_pairs(draws))
  grDevices::dev.off()
  expect_s3_class(pairs, "bayesplot_grid")
  for (plot in list(bayesplot::mcmc_areas(draws), bayesplot::ppc_dens_overlay(y, yrep), pairs)) {
    result <- bayes_export(plot)
    expect_true(result$file %in% c("figure.svg", "figure.png"))
  }
})

test_that("lists of ggplots publish as one figure", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  first <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  second <- ggplot2::ggplot(mtcars, ggplot2::aes(hp, mpg)) + ggplot2::geom_point()
  expect_true(inherits(framework:::.fw_artifact_plots(list(first, second)), "patchwork"))
  expect_identical(framework:::.fw_artifact_plots(list(first)), first)
  expect_true(bayes_export(list(wt = first, hp = second))$file %in% c("figure.svg", "figure.png"))
  # Other lists are left alone.
  expect_error(bayes_export(list(1, 2)), "publish\\(\\) accepts")
})
