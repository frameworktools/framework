# Object families from the artifact objects contract (framework-cloud
# docs/notes/2026-11-02-artifact-objects-contract.md).

export_artifact <- function(object, cloud = TRUE) {
  path <- framework:::.fw_artifact_file(object, withr::local_tempdir(.local_envir = parent.frame()), cloud = cloud)
  list(path = path, file = basename(path),
       text = paste(readLines(path, warn = FALSE), collapse = "\n"),
       document = if (grepl("\\.json$", path)) jsonlite::fromJSON(path, simplifyVector = FALSE))
}

column_names <- function(table) vapply(table$columns, `[[`, character(1), "name")

column <- function(table, name) table$columns[[match(name, column_names(table))]]

metric_values <- function(document) {
  stats::setNames(lapply(document$metrics, `[[`, "value"),
                  vapply(document$metrics, `[[`, character(1), "name"))
}

table_roles <- function(document) vapply(document$tables, function(x) x$role %||% "", character(1))

# Models never carry observations: no observation-level fields, no data row
# names, and a coefficient table with one row per term.
expect_model_document <- function(result, type, roles = "coefficients", terms = NULL) {
  expect_identical(result$file, "model.json")
  document <- result$document
  expect_identical(document$schema, "framework.artifact/v1")
  expect_identical(document$kind, "model")
  expect_identical(document$model$type, type)
  expect_identical(table_roles(document), roles)
  coefficients <- document$tables[[1]]
  expect_true(all(c("term", "estimate") %in% column_names(coefficients)))
  if (!is.null(terms)) expect_identical(coefficients$row_count, as.integer(terms))
  expect_false(any(c("residuals", "fitted.values", "fitted", "data", "y", "x", "qr",
                     "linear.predictors", "weights") %in% names(document)))
  # `model` is the fit description, never the model frame.
  expect_true(all(names(document$model) %in% c("type", "family", "link", "response", "exponentiate")))
  expect_false(grepl("\"(residuals|fitted\\.values|linear\\.predictors)\"", result$text))
  for (car in c("Mazda RX4", "Hornet Sportabout", "Toyota Corolla")) {
    expect_false(grepl(car, result$text, fixed = TRUE))
  }
  expect_lt(nchar(result$text), 20000)
  invisible(document)
}

test_that("column summaries cover numbers, text, booleans, factors, and dates over all rows", {
  data <- data.frame(value = c(seq(1, 99), NA), flag = c(rep(TRUE, 60), rep(FALSE, 30), rep(NA, 10)),
                     group = factor(c(rep("a", 50), rep("b", 30), rep("c", 20))),
                     text = c(rep(strrep("x", 100), 3), paste0("t", 1:97)),
                     date = as.Date("2026-01-01") + c(0:98, NA))
  attr(data$value, "label") <- "Measured value"
  table <- export_artifact(data)$document$tables[[1]]
  expect_identical(column_names(table), c("value", "flag", "group", "text", "date"))
  expect_identical(column(table, "group")$type, "string")
  expect_identical(column(table, "value")$label, "Measured value")
  expect_null(column(table, "flag")$label)

  numbers <- column(table, "value")$summary
  expect_identical(c(numbers$count, numbers$missing, numbers$distinct), c(100L, 1L, 99L))
  expect_equal(numbers$mean, 50)
  expect_equal(numbers$sd, stats::sd(1:99))
  expect_equal(c(numbers$min, numbers$q1, numbers$median, numbers$q3, numbers$max), c(1, 25.5, 50, 74.5, 99))
  edges <- unlist(numbers$histogram$edges)
  counts <- unlist(numbers$histogram$counts)
  expect_length(edges, length(counts) + 1L)
  expect_lte(length(counts), 20L)
  expect_identical(sum(counts), 99L)
  expect_equal(diff(edges), rep(diff(edges)[1], length(counts)))

  flags <- column(table, "flag")$summary
  expect_identical(flags$missing, 10L)
  expect_identical(flags$top, list(list(value = TRUE, count = 60L), list(value = FALSE, count = 30L)))
  groups <- column(table, "group")$summary
  expect_identical(groups$top[[1]], list(value = "a", count = 50L))
  text <- column(table, "text")$summary
  expect_length(text$top, 8L)
  expect_identical(text$top[[1]], list(value = strrep("x", 80), count = 3L))
  dates <- column(table, "date")$summary
  expect_identical(c(dates$min, dates$max), c("2026-01-01", "2026-04-09"))
})

test_that("summaries leave out statistics that can't be computed and stop past 200 columns", {
  table <- export_artifact(data.frame(empty = c(NA_real_, NA_real_), one = c(5, NA)))$document$tables[[1]]
  expect_identical(names(column(table, "empty")$summary), c("count", "missing", "distinct"))
  one <- column(table, "one")$summary
  expect_null(one$sd)
  expect_identical(unlist(one$histogram$counts), 1L)
  wide <- as.data.frame(matrix(1, nrow = 2, ncol = 201))
  wide_table <- framework:::.fw_artifact_structured(wide)$tables[[1]]
  expect_null(wide_table$columns[[1]]$summary)
})

test_that("tibbles and data.tables export as data tables without a row column", {
  skip_if_not_installed("tibble")
  skip_if_not_installed("data.table")
  for (object in list(tibble::as_tibble(iris), data.table::as.data.table(airquality))) {
    result <- export_artifact(object)
    expect_identical(result$file, "table.json")
    table <- result$document$tables[[1]]
    expect_false("row" %in% column_names(table))
    expect_identical(table$row_count, nrow(object))
    expect_identical(table$role, "data")
  }
})

test_that("data frames with row names and matrices keep a first column named row", {
  table <- export_artifact(mtcars)$document$tables[[1]]
  expect_identical(column_names(table)[1:2], c("row", "mpg"))
  expect_identical(table$rows[[1]][[1]], "Mazda RX4")
  correlations <- export_artifact(stats::cor(mtcars[c("mpg", "wt")]))$document$tables[[1]]
  expect_identical(column_names(correlations), c("row", "mpg", "wt"))
  plain <- export_artifact(matrix(1:6, 2))$document$tables[[1]]
  expect_identical(column_names(plain), c("V1", "V2", "V3"))
  text <- export_artifact(matrix(c("a", "b"), 1))$document$tables[[1]]
  expect_identical(vapply(text$columns, `[[`, character(1), "type"), c("string", "string"))
})

test_that("contingency tables export one-way and wide two-way forms", {
  one <- export_artifact(table(mtcars$cyl))$document$tables[[1]]
  expect_identical(column_names(one), c("value", "count"))
  expect_identical(one$rows[[1]], list("4", 11L))
  two <- export_artifact(table(cyl = mtcars$cyl, gear = mtcars$gear))$document$tables[[1]]
  expect_identical(column_names(two), c("cyl", "3", "4", "5"))
  expect_identical(two$rows[[3]], list("8", 12L, 0L, 2L))
  crossed <- export_artifact(stats::xtabs(~ wool + tension, warpbreaks))
  expect_identical(crossed$document$source$class, list("xtabs", "table"))
  expect_identical(column_names(crossed$document$tables[[1]]), c("wool", "L", "M", "H"))
})

test_that("ANOVA tables keep their row names", {
  result <- export_artifact(stats::anova(stats::lm(mpg ~ wt + hp, mtcars)))
  expect_identical(result$file, "table.json")
  table <- result$document$tables[[1]]
  expect_identical(table$role, "anova")
  expect_identical(column_names(table)[1:2], c("row", "Df"))
  expect_identical(vapply(table$rows, `[[`, character(1), 1), c("wt", "hp", "Residuals"))
  summary_table <- export_artifact(summary(stats::aov(breaks ~ wool * tension, warpbreaks)))$document$tables[[1]]
  expect_identical(vapply(summary_table$rows, `[[`, character(1), 1),
                   c("wool", "tension", "wool:tension", "Residuals"))
  strata <- export_artifact(summary(stats::aov(yield ~ N * P + Error(block), npk)))$document
  expect_length(strata$tables, 2L)
  expect_true(all(table_roles(strata) == "anova"))
})

test_that("hypothesis tests export test documents without data names", {
  secret_measurements <- c(5.1, 4.9, 6.2, 5.8, 6.0, 5.5, 5.3, 4.8)
  secret_group <- rep(c("a", "b"), each = 4)
  welch <- export_artifact(stats::t.test(secret_measurements ~ secret_group))
  expect_identical(welch$file, "test.json")
  document <- welch$document
  expect_identical(document$kind, "test")
  expect_identical(document$source$class, list("htest"))
  test <- document$test
  expect_identical(test$method, "Welch Two Sample t-test")
  expect_identical(test$alternative, "two.sided")
  expect_identical(test$statistic$name, "t")
  expect_identical(test$parameters[[1]]$name, "df")
  expect_true(is.numeric(test$p_value))
  expect_length(test$estimates, 2L)
  expect_identical(test$null_value[[1]]$value, 0L)
  expect_identical(names(test$conf_int), c("level", "low", "high"))
  expect_equal(test$conf_int$level, 0.95)
  expect_false(grepl("secret", welch$text, fixed = TRUE))
  expect_false(grepl("data.name|data_name", welch$text))

  paired <- export_artifact(stats::t.test(sleep$extra[1:10], sleep$extra[11:20], paired = TRUE))$document$test
  expect_identical(paired$method, "Paired t-test")
  one_sided <- export_artifact(stats::t.test(sleep$extra, alternative = "greater"))$document$test
  expect_identical(one_sided$alternative, "greater")
  expect_null(one_sided$conf_int$high)
  expect_true(is.numeric(one_sided$conf_int$low))

  chi <- export_artifact(suppressWarnings(stats::chisq.test(table(mtcars$cyl, mtcars$am))))$document
  expect_identical(chi$test$statistic$name, "X-squared")
  expect_identical(chi$tables[[1]]$title, "Expected counts")
  correlation <- export_artifact(stats::cor.test(~ mpg + wt, mtcars))$document$test
  expect_identical(correlation$estimates[[1]]$name, "cor")
  proportions <- export_artifact(stats::prop.test(c(15, 25), c(50, 50)))$document$test
  expect_identical(vapply(proportions$estimates, `[[`, character(1), "name"), c("prop 1", "prop 2"))
  fisher <- export_artifact(stats::fisher.test(table(mtcars$am, mtcars$vs)))$document$test
  expect_identical(fisher$estimates[[1]]$name, "odds ratio")
  shapiro <- export_artifact(stats::shapiro.test(mtcars$mpg))$document$test
  expect_identical(shapiro$method, "Shapiro-Wilk normality test")
  expect_null(shapiro$conf_int)
  expect_null(shapiro$parameters)
  wilcox <- export_artifact(suppressWarnings(stats::wilcox.test(mpg ~ am, mtcars)))$document$test
  expect_identical(wilcox$statistic$name, "W")
  pairwise <- export_artifact(stats::pairwise.t.test(airquality$Ozone, airquality$Month))$document
  expect_identical(pairwise$kind, "test")
  expect_identical(column_names(pairwise$tables[[1]])[1], "row")
})

test_that("lm, glm, and aov export model descriptions", {
  linear <- expect_model_document(export_artifact(stats::lm(mpg ~ wt + hp, mtcars)), "linear", terms = 3)
  expect_identical(linear$model, list(type = "linear", family = "gaussian", link = "identity", response = "mpg"))
  logit <- expect_model_document(export_artifact(stats::glm(am ~ wt, stats::binomial(), mtcars)), "glm")
  expect_identical(logit$model[c("family", "link", "exponentiate")],
                   list(family = "binomial", link = "logit", exponentiate = "Odds ratio"))
  poisson <- expect_model_document(export_artifact(stats::glm(count ~ spray, stats::poisson(), InsectSprays)), "glm")
  expect_identical(poisson$model$exponentiate, "Rate ratio")
  quasi <- expect_model_document(export_artifact(stats::glm(count ~ spray, stats::quasipoisson(), InsectSprays)), "glm")
  expect_identical(quasi$model$exponentiate, "Rate ratio")
  gaussian <- expect_model_document(export_artifact(stats::glm(mpg ~ wt, stats::gaussian(), mtcars)), "glm")
  expect_null(gaussian$model$exponentiate)
  gamma <- expect_model_document(export_artifact(stats::glm(mpg ~ wt, stats::Gamma("log"), mtcars)), "glm")
  expect_identical(gamma$model[c("family", "link")], list(family = "gamma", link = "log"))
  expect_null(gamma$model$exponentiate)
  variance <- expect_model_document(export_artifact(stats::aov(breaks ~ wool + tension, warpbreaks)), "linear",
                                    roles = c("coefficients", "anova"))
  expect_identical(variance$model$response, "breaks")
})

test_that("MASS glm.nb and polr export rate and odds ratio models", {
  skip_if_not_installed("MASS")
  nb <- expect_model_document(export_artifact(MASS::glm.nb(Days ~ Sex + Age, MASS::quine)), "glm")
  expect_identical(nb$model[c("family", "link", "exponentiate")],
                   list(family = "negative binomial", link = "log", exponentiate = "Rate ratio"))
  expect_true(is.numeric(metric_values(nb)$theta))
  ordinal <- MASS::polr(Sat ~ Infl + Type, MASS::housing, weights = Freq, Hess = TRUE)
  polr <- expect_model_document(export_artifact(ordinal), "ordinal", terms = 7)
  expect_identical(polr$model[c("link", "exponentiate")], list(link = "logit", exponentiate = "Odds ratio"))
  coefficients <- polr$tables[[1]]
  expect_identical(column_names(coefficients)[1:3], c("term", "component", "estimate"))
  components <- vapply(coefficients$rows, `[[`, character(1), 2)
  expect_identical(components, c(rep("coefficient", 5), rep("threshold", 2)))
  expect_true(all(c("p_value", "conf_low", "conf_high") %in% column_names(coefficients)))
})

test_that("nnet multinom exports one row per level and term", {
  skip_if_not_installed("nnet")
  fit <- nnet::multinom(Species ~ Sepal.Width, iris, trace = FALSE)
  document <- expect_model_document(export_artifact(fit), "multinomial", terms = 4)
  expect_identical(vapply(document$tables[[1]]$rows, `[[`, character(1), 1),
                   c("versicolor: (Intercept)", "versicolor: Sepal.Width",
                     "virginica: (Intercept)", "virginica: Sepal.Width"))
  expect_equal(document$tables[[1]]$rows[[2]][[3]], unname(summary(fit)$standard.errors[1, 2]))
  expect_identical(document$model$response, "Species")
})

test_that("lme4 models export fixed effects, random effects, and group counts", {
  skip_if_not_installed("lme4")
  fit <- lme4::lmer(Reaction ~ Days + (Days | Subject), lme4::sleepstudy)
  document <- expect_model_document(export_artifact(fit), "mixed", roles = c("coefficients", "random_effects"),
                                    terms = 2)
  expect_identical(document$model[c("family", "link", "response")],
                   list(family = "gaussian", link = "identity", response = "Reaction"))
  random <- document$tables[[2]]
  expect_identical(column_names(random), c("group", "term", "variance", "std_dev", "correlation"))
  expect_identical(random$row_count, 4L)
  expect_identical(metric_values(document)[["n_groups.Subject"]], 18L)
  expect_true(all(c("conf_low", "conf_high") %in% column_names(document$tables[[1]])))
  binomial <- lme4::glmer(cbind(incidence, size - incidence) ~ period + (1 | herd), lme4::cbpp,
                          family = stats::binomial())
  glmer <- expect_model_document(export_artifact(binomial), "mixed", roles = c("coefficients", "random_effects"))
  expect_identical(glmer$model$exponentiate, "Odds ratio")
  expect_true("p_value" %in% column_names(glmer$tables[[1]]))
  expect_identical(metric_values(glmer)[["n_groups.herd"]], 15L)
})

test_that("survival models export hazard and time ratios", {
  skip_if_not_installed("survival")
  lung <- survival::lung
  cox <- survival::coxph(survival::Surv(time, status) ~ age + sex, lung)
  document <- expect_model_document(export_artifact(cox), "survival", terms = 2)
  expect_identical(document$model$exponentiate, "Hazard ratio")
  expect_true(is.numeric(metric_values(document)$concordance))
  expect_equal(document$tables[[1]]$rows[[1]][[2]], unname(stats::coef(cox)[1]))
  aft <- survival::survreg(survival::Surv(time, status) ~ age + sex, lung)
  survreg <- expect_model_document(export_artifact(aft), "survival", terms = 4)
  expect_identical(survreg$model[c("family", "link", "exponentiate")],
                   list(family = "weibull", link = "log", exponentiate = "Time ratio"))
  expect_identical(vapply(survreg$tables[[1]]$rows, `[[`, character(1), 2),
                   c("coefficient", "coefficient", "coefficient", "scale"))
})

test_that("fixest models export coefficients with fixest intervals", {
  skip_if_not_installed("fixest")
  fit <- fixest::feols(mpg ~ wt | cyl, mtcars)
  document <- expect_model_document(export_artifact(fit), "fixed_effects", terms = 1)
  expect_identical(document$model$family, "gaussian")
  row <- document$tables[[1]]$rows[[1]]
  expect_equal(c(row[[6]], row[[7]]), unname(unlist(stats::confint(fit)[1, ])))
  expect_identical(metric_values(document)[["n_groups.cyl"]], 3L)
  poisson <- expect_model_document(export_artifact(fixest::fepois(count ~ spray, InsectSprays)), "fixed_effects")
  expect_identical(poisson$model$exponentiate, "Rate ratio")
})

test_that("mgcv gam exports parametric and smooth terms", {
  skip_if_not_installed("mgcv")
  fit <- mgcv::gam(mpg ~ s(wt) + am, data = mtcars)
  document <- expect_model_document(export_artifact(fit), "additive", roles = c("coefficients", "smooth_terms"),
                                    terms = 2)
  expect_identical(column_names(document$tables[[2]]), c("term", "edf", "ref_df", "statistic", "p_value"))
  expect_identical(document$tables[[2]]$rows[[1]][[1]], "s(wt)")
  logistic <- mgcv::gam(am ~ s(wt, k = 4), family = stats::binomial(), data = mtcars)
  expect_identical(expect_model_document(export_artifact(logistic), "additive",
                                         roles = c("coefficients", "smooth_terms"))$model$exponentiate,
                   "Odds ratio")
})

test_that("bucket exports write CSV for tables and JSON for other structured objects", {
  table <- export_artifact(table(cyl = mtcars$cyl, gear = mtcars$gear), cloud = FALSE)
  expect_identical(table$file, "table.csv")
  expect_match(table$text, "^\"cyl\",\"3\",\"4\",\"5\"")
  expect_identical(export_artifact(stats::lm(mpg ~ wt, mtcars), cloud = FALSE)$file, "model.html")
  expect_identical(export_artifact(stats::t.test(mpg ~ am, mtcars), cloud = FALSE)$file, "test.json")
})

test_that("base and lattice plots export SVG figures, with a PNG fallback for large files", {
  skip_if_not_installed("svglite")
  grDevices::pdf(NULL)
  grDevices::dev.control("enable")
  graphics::hist(mtcars$mpg)
  recorded <- grDevices::recordPlot()
  grDevices::dev.off()
  base <- export_artifact(recorded)
  expect_identical(base$file, "figure.svg")
  expect_match(base$text, "fill: #FFFFFF", fixed = TRUE)
  skip_if_not_installed("lattice")
  expect_identical(export_artifact(lattice::xyplot(mpg ~ wt, mtcars))$file, "figure.svg")
  testthat::local_mocked_bindings(.fw_artifact_svg_limit = function() 10)
  path <- framework:::.fw_artifact_file(recorded, withr::local_tempdir(), cloud = TRUE)
  expect_identical(basename(path), "figure.png")
  expect_identical(readBin(path, "raw", n = 4L), as.raw(c(137, 80, 78, 71)))
  expect_identical(list.files(dirname(path)), "figure.png")
})

test_that("patchwork compositions export as figures", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  skip_if_not_installed("svglite")
  plot <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  expect_identical(export_artifact(patchwork::wrap_plots(plot, plot))$file, "figure.svg")
})

test_that("a ggplot that can't be drawn stops with the accepts message", {
  skip_if_not_installed("ggplot2")
  plot <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, missing_column)) + ggplot2::geom_point()
  expect_error(framework:::.fw_artifact_file(plot, withr::local_tempdir(), cloud = TRUE),
               "publish\\(\\) accepts.*could not be saved")
})

test_that("htmlwidgets export self-contained HTML", {
  skip_if_not_installed("plotly")
  skip_if_not_installed("htmlwidgets")
  skip_if(!nzchar(Sys.which("pandoc")) && !nzchar(Sys.getenv("RSTUDIO_PANDOC")) &&
            is.null(framework:::.fw_artifact_quarto_pandoc()), "pandoc is not available")
  stage <- withr::local_tempdir()
  widget <- plotly::plot_ly(x = 1:3, y = c(2, 1, 3), type = "scatter", mode = "markers")
  path <- framework:::.fw_artifact_file(widget, stage, cloud = TRUE)
  expect_identical(basename(path), "figure.html")
  expect_identical(list.files(stage), "figure.html")
  expect_false(grepl("<script src=\"(?!data:)", paste(readLines(path, warn = FALSE), collapse = "\n"), perl = TRUE))
})

test_that("unsupported objects stop with the accepts message", {
  expect_error(framework:::.fw_artifact_file(list(a = 1), withr::local_tempdir(), cloud = TRUE),
               "publish() accepts a file or rendered folder", fixed = TRUE)
  expect_error(framework:::.fw_artifact_file(1:3, withr::local_tempdir(), cloud = TRUE),
               "htest", fixed = TRUE)
})

variable <- function(document, name) {
  document$variables[[match(name, vapply(document$variables, `[[`, character(1), "name"))]]
}

term_parts <- function(document) {
  stats::setNames(lapply(document$terms, `[[`, "parts"), vapply(document$terms, `[[`, character(1), "term"))
}

test_that("models describe their variables over the model frame and map interaction terms", {
  data <- iris
  attr(data$Sepal.Length, "label") <- "Sepal length (cm)"
  data$Sepal.Length[1:3] <- NA
  fit <- stats::lm(Sepal.Length ~ Petal.Length * Species, data)
  document <- expect_model_document(export_artifact(fit), "linear", terms = 6)
  expect_identical(vapply(document$variables, `[[`, character(1), "name"),
                   c("Sepal.Length", "Petal.Length", "Species"))
  expect_identical(vapply(document$variables, `[[`, character(1), "role"), c("response", "predictor", "predictor"))
  response <- variable(document, "Sepal.Length")
  expect_identical(response$type, "number")
  expect_identical(response$label, "Sepal length (cm)")
  expect_identical(c(response$summary$count, response$summary$missing), c(147L, 0L))
  expect_equal(response$summary$mean, mean(data$Sepal.Length, na.rm = TRUE))
  expect_null(response$summary$histogram)
  species <- variable(document, "Species")
  expect_identical(species$type, "categorical")
  expect_identical(species$levels, list("setosa", "versicolor", "virginica"))
  expect_identical(species$reference, "setosa")
  expect_identical(species$summary$top[[1]], list(value = "versicolor", count = 50L))

  parts <- term_parts(document)
  expect_identical(names(parts), c("Petal.Length", "Speciesversicolor", "Speciesvirginica",
                                   "Petal.Length:Speciesversicolor", "Petal.Length:Speciesvirginica"))
  expect_identical(parts[["Speciesversicolor"]], list(list(variable = "Species", level = "versicolor")))
  expect_identical(parts[["Petal.Length:Speciesvirginica"]],
                   list(list(variable = "Petal.Length"), list(variable = "Species", level = "virginica")))
})

test_that("glm models map factor() terms to the variable and level", {
  fit <- stats::glm(am ~ wt + factor(cyl), stats::binomial(), mtcars)
  document <- expect_model_document(export_artifact(fit), "glm")
  cyl <- variable(document, "cyl")
  expect_identical(cyl[c("role", "type", "reference")], list(role = "predictor", type = "categorical", reference = "4"))
  expect_identical(cyl$levels, list("4", "6", "8"))
  expect_identical(variable(document, "am")$role, "response")
  parts <- term_parts(document)
  expect_identical(names(parts), c("wt", "factor(cyl)6", "factor(cyl)8"))
  expect_identical(parts[["factor(cyl)8"]], list(list(variable = "cyl", level = "8")))
})

test_that("transformed terms map to the variable they transform, summarized untransformed", {
  fit <- stats::lm(log(mpg) ~ log(hp) + poly(wt, 2) + I(disp / 100), mtcars)
  document <- expect_model_document(export_artifact(fit), "linear", terms = 5)
  expect_identical(vapply(document$variables, `[[`, character(1), "name"), c("mpg", "hp", "wt", "disp"))
  expect_equal(variable(document, "mpg")$summary$mean, mean(mtcars$mpg))
  expect_equal(variable(document, "disp")$summary$max, max(mtcars$disp))
  parts <- term_parts(document)
  expect_identical(names(parts), c("log(hp)", "poly(wt, 2)1", "poly(wt, 2)2", "I(disp/100)"))
  expect_identical(unname(unlist(parts)), c("hp", "wt", "wt", "disp"))
})

test_that("ordered, logical, character, and uncoded factors get levels only where they're certain", {
  data <- data.frame(y = c(1.2, 3.4, 2.2, 5.1, 4.4, 3.9, 2.8, 6.0, 5.5, 4.1, 3.3, 2.0),
                     dose = factor(rep(c("low", "mid", "high"), 4), levels = c("low", "mid", "high"),
                                   ordered = TRUE),
                     treated = rep(c(TRUE, FALSE), each = 6),
                     site = rep(c("north", "south"), 6), stringsAsFactors = FALSE)
  document <- export_artifact(stats::lm(y ~ dose + treated + site, data))$document
  dose <- variable(document, "dose")
  expect_identical(dose$levels, list("low", "mid", "high"))
  expect_null(dose$reference)
  expect_identical(variable(document, "treated")[c("type", "reference")], list(type = "boolean", reference = "FALSE"))
  expect_identical(variable(document, "site")[c("type", "reference")], list(type = "categorical", reference = "north"))
  parts <- term_parts(document)
  expect_identical(parts[["dose.L"]], list(list(variable = "dose")))
  expect_identical(parts[["treatedTRUE"]], list(list(variable = "treated", level = "TRUE")))
  expect_identical(parts[["sitesouth"]], list(list(variable = "site", level = "south")))
  expect_false("(Intercept)" %in% names(parts))

  uncoded <- export_artifact(stats::lm(y ~ 0 + site, data))$document
  expect_null(variable(uncoded, "site")$reference)
  expect_identical(names(term_parts(uncoded)), c("sitenorth", "sitesouth"))
})

test_that("weights and offsets are variables with their own roles", {
  skip_if_not_installed("MASS")
  ordinal <- MASS::polr(Sat ~ Infl + Type, MASS::housing, weights = Freq, Hess = TRUE)
  document <- export_artifact(ordinal)$document
  expect_identical(variable(document, "Freq")$role, "weight")
  expect_identical(variable(document, "Sat")[c("role", "type")], list(role = "response", type = "categorical"))
  expect_false(any(c("Low|Medium", "Medium|High") %in% names(term_parts(document))))

  counts <- data.frame(events = c(2, 5, 3, 8, 4, 9), exposure = c(10, 20, 12, 30, 15, 28),
                       arm = rep(c("a", "b"), 3))
  rate <- export_artifact(stats::glm(events ~ arm + offset(log(exposure)), stats::poisson(), counts))$document
  expect_identical(variable(rate, "exposure")$role, "offset")
  expect_identical(names(term_parts(rate)), "armb")
})

test_that("variables cap factor levels at 50", {
  data <- data.frame(y = seq_len(120), group = factor(sprintf("g%03d", rep(1:60, 2))))
  group <- variable(framework:::.fw_artifact_structured(stats::lm(y ~ group, data)), "group")
  expect_length(group$levels, 50L)
  expect_identical(group$summary$distinct, 60L)
})

test_that("mixed models mark random-effects grouping factors", {
  skip_if_not_installed("lme4")
  fit <- lme4::lmer(Reaction ~ Days + (Days | Subject), lme4::sleepstudy)
  document <- export_artifact(fit)$document
  expect_identical(vapply(document$variables, `[[`, character(1), "role"), c("response", "predictor", "group"))
  expect_identical(variable(document, "Subject")$type, "categorical")
  expect_identical(variable(document, "Subject")$summary$count, 180L)
  expect_identical(names(term_parts(document)), "Days")
  binomial <- lme4::glmer(cbind(incidence, size - incidence) ~ period + (1 | herd), lme4::cbpp,
                          family = stats::binomial())
  glmer <- export_artifact(binomial)$document
  expect_identical(vapply(glmer$variables, `[[`, character(1), "name"), c("incidence", "size", "period", "herd"))
  expect_identical(variable(glmer, "herd")$role, "group")
  expect_identical(term_parts(glmer)[["period2"]], list(list(variable = "period", level = "2")))
})

test_that("survival, multinomial, additive, and fixest models describe their variables", {
  skip_if_not_installed("survival")
  skip_if_not_installed("nnet")
  skip_if_not_installed("mgcv")
  skip_if_not_installed("fixest")
  cox <- export_artifact(survival::coxph(survival::Surv(time, status) ~ age + factor(sex) +
                                           survival::strata(ph.ecog), survival::lung))$document
  expect_identical(vapply(cox$variables, `[[`, character(1), "name"), c("time", "status", "age", "sex", "ph.ecog"))
  expect_identical(variable(cox, "time")$role, "response")
  expect_null(variable(cox, "ph.ecog")$role)
  expect_identical(variable(cox, "ph.ecog")$type, "number")
  expect_identical(term_parts(cox)[["factor(sex)2"]], list(list(variable = "sex", level = "2")))

  multinomial <- export_artifact(nnet::multinom(Species ~ Sepal.Width, iris, trace = FALSE))$document
  expect_identical(names(term_parts(multinomial)), c("versicolor: Sepal.Width", "virginica: Sepal.Width"))

  additive <- export_artifact(mgcv::gam(mpg ~ s(wt) + factor(am), data = mtcars))$document
  expect_identical(vapply(additive$variables, `[[`, character(1), "name"), c("mpg", "am", "wt"))
  expect_identical(names(term_parts(additive)), "factor(am)1")

  absorbed <- export_artifact(fixest::feols(mpg ~ wt + i(gear, ref = 3) | cyl, mtcars))$document
  expect_identical(vapply(absorbed$variables, `[[`, character(1), "name"), c("mpg", "wt", "gear", "cyl"))
  expect_identical(term_parts(absorbed)[["gear::5"]], list(list(variable = "gear", level = "5")))
})
