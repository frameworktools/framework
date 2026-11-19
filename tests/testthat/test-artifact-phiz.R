# ggplot -> phiz plot descriptions (R/artifact_phiz.R). Every written
# description is checked against phiz's JSON Schema, copied into
# fixtures/phiz-plot-description.schema.json from phiz's
# schema/plot-description.schema.json (format 1).

phiz_penguins <- function() {
  if (exists("penguins", envir = asNamespace("datasets"))) return(get("penguins", envir = asNamespace("datasets")))
  if (requireNamespace("palmerpenguins", quietly = TRUE)) {
    data <- palmerpenguins::penguins
    names(data)[names(data) == "flipper_length_mm"] <- "flipper_len"
    names(data)[names(data) == "body_mass_g"] <- "body_mass"
    names(data)[names(data) == "bill_length_mm"] <- "bill_len"
    names(data)[names(data) == "bill_depth_mm"] <- "bill_dep"
    return(as.data.frame(data))
  }
  testthat::skip("No penguins data (R >= 4.5 or palmerpenguins)")
}

phiz_describe <- function(plot) {
  described <- framework:::.fw_phiz_describe(plot)
  if (is.null(described$description)) fail(paste("refused:", described$reason))
  expect_phiz_valid(described$description)
  # Round-trip through JSON, as Cloud reads it.
  jsonlite::fromJSON(framework:::.fw_phiz_json(described$description), simplifyVector = FALSE)
}

phiz_refused <- function(plot) {
  described <- framework:::.fw_phiz_describe(plot)
  expect_null(described$description)
  described$reason
}

expect_phiz_valid <- function(description) {
  json <- framework:::.fw_phiz_json(description)
  # The schema is a test fixture, which the built package leaves out
  schema <- testthat::test_path("fixtures", "phiz-plot-description.schema.json")
  if (requireNamespace("jsonvalidate", quietly = TRUE) && file.exists(schema)) {
    # The schema file, verbatim from phiz, has no final newline.
    validator <- suppressWarnings(jsonvalidate::json_schema$new(schema, engine = "ajv"))
    valid <- validator$validate(json, verbose = TRUE)
    expect_true(valid, info = paste(utils::capture.output(print(attr(valid, "errors"))), collapse = "\n"))
  } else {
    # The schema's top-level shape, without jsonvalidate.
    parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
    expect_identical(parsed$phiz, 1L)
    expect_true(all(names(parsed) %in% c("phiz", "data", "aes", "layers", "scales", "labels", "facet", "coord",
                                         "theme", "width", "height", "description", "tooltip")))
    for (layer in parsed$layers) expect_true(is.character(layer$geom))
  }
}

column <- function(layer, name) unlist(layer$data[[name]])

test_that("the penguins scatter keeps species in the legend and drops the default palette", {
  skip_if_not_installed("ggplot2")
  penguins <- phiz_penguins()
  plot <- ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass, colour = species)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(x = "Flipper length (mm)", y = "Body mass (g)", colour = "Species", title = "Penguins")
  d <- phiz_describe(plot)

  expect_identical(d$phiz, 1L)
  expect_length(d$layers, 1L)
  layer <- d$layers[[1]]
  expect_identical(layer$geom, "point")
  expect_identical(layer$alpha, 0.7)
  expect_identical(layer$aes$color, list(field = "colour", type = "nominal"))
  expect_setequal(unique(column(layer, "colour")), c("Adelie", "Chinstrap", "Gentoo"))
  complete <- penguins[!is.na(penguins$flipper_len) & !is.na(penguins$body_mass), ]
  expect_equal(column(layer, "x"), complete$flipper_len)
  expect_equal(column(layer, "y"), complete$body_mass)
  expect_identical(column(layer, "colour"), as.character(complete$species))
  # The default hue palette is no scale, so the page supplies its own colours.
  expect_null(d$scales$color)
  expect_null(d$theme)
  expect_identical(d$labels, list(title = "Penguins", x = "Flipper length (mm)", y = "Body mass (g)", color = "Species"))
})

test_that("smooths carry R's fitted line and band as line and ribbon layers", {
  skip_if_not_installed("ggplot2")
  penguins <- phiz_penguins()
  plot <- ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass, colour = species)) +
    ggplot2::geom_point() + ggplot2::geom_smooth(method = "lm")
  d <- phiz_describe(plot)
  expect_identical(vapply(d$layers, `[[`, character(1), "geom"), c("point", "line", "ribbon"))
  fit <- suppressMessages(suppressWarnings(ggplot2::layer_data(plot, 2)))
  expect_equal(column(d$layers[[2]], "y"), fit$y)
  expect_equal(column(d$layers[[3]], "ymin"), fit$ymin)
  expect_equal(column(d$layers[[3]], "ymax"), fit$ymax)
  expect_setequal(unique(column(d$layers[[2]], "colour")), c("Adelie", "Chinstrap", "Gentoo"))
  expect_false(any(vapply(d$layers, function(l) identical(l$geom, "smooth"), logical(1))))

  loess <- phiz_describe(ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point() +
                           ggplot2::geom_smooth(method = "loess", se = FALSE))
  expect_identical(vapply(loess$layers, `[[`, character(1), "geom"), c("point", "line"))
})

test_that("histograms carry R's bins", {
  skip_if_not_installed("ggplot2")
  penguins <- phiz_penguins()
  plot <- ggplot2::ggplot(penguins, ggplot2::aes(body_mass, fill = species)) + ggplot2::geom_histogram(bins = 20)
  d <- phiz_describe(plot)
  layer <- d$layers[[1]]
  expect_identical(layer$geom, "col")
  expect_identical(layer$position, "stack")
  expect_null(layer$bins)
  bins <- suppressWarnings(ggplot2::layer_data(plot, 1))
  expect_equal(column(layer, "xmin"), bins$xmin)
  expect_equal(column(layer, "xmax"), bins$xmax)
  expect_equal(column(layer, "y"), bins$count)
  expect_equal(sum(column(layer, "y")), sum(!is.na(penguins$body_mass)))
  expect_setequal(unique(column(layer, "fill")), c("Adelie", "Chinstrap", "Gentoo"))
  expect_identical(d$labels$y, "count")
})

test_that("facet_wrap and facet_grid carry their panels", {
  skip_if_not_installed("ggplot2")
  penguins <- phiz_penguins()
  d <- phiz_describe(ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass)) + ggplot2::geom_point() +
                       ggplot2::facet_wrap(~island, ncol = 2, scales = "free_y") + ggplot2::theme_minimal())
  expect_identical(d$facet, list(type = "wrap", facets = list("island"), ncol = 2L, scales = "free_y"))
  complete <- penguins[!is.na(penguins$flipper_len) & !is.na(penguins$body_mass), ]
  expect_setequal(unique(column(d$layers[[1]], "island")), levels(penguins$island))
  expect_identical(sort(column(d$layers[[1]], "island")), sort(as.character(complete$island)))
  expect_null(d$theme)

  complete <- penguins[!is.na(penguins$sex), ]
  grid <- phiz_describe(ggplot2::ggplot(complete, ggplot2::aes(flipper_len, body_mass)) + ggplot2::geom_point() +
                          ggplot2::facet_grid(sex ~ species, labeller = ggplot2::label_both))
  expect_identical(grid$facet, list(type = "grid", rows = "sex", cols = "species", labeller = "both"))
  expect_true(all(c("sex", "species") %in% names(grid$layers[[1]]$data)))
})

test_that("author decisions about scales, coordinates, legends, and axes carry over", {
  skip_if_not_installed("ggplot2")
  penguins <- phiz_penguins()
  plot <- ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass, colour = species)) + ggplot2::geom_point() +
    ggplot2::scale_y_log10() +
    ggplot2::scale_x_continuous(breaks = c(180, 200, 220), labels = c("short", "mid", "long")) +
    ggplot2::scale_colour_manual(values = c(Adelie = "darkorange", Chinstrap = "purple", Gentoo = "cyan4")) +
    ggplot2::coord_cartesian(xlim = c(170, 235)) +
    ggplot2::theme(legend.position = "bottom", axis.text.x = ggplot2::element_text(angle = 45),
                   panel.background = ggplot2::element_rect(fill = "grey20"))
  d <- phiz_describe(plot)
  expect_identical(d$scales$y, list(type = "log"))
  expect_identical(d$scales$x, list(breaks = list(180L, 200L, 220L), labels = list("short", "mid", "long")))
  expect_identical(d$scales$color$values, list(Adelie = "#FF8C00", Chinstrap = "#A020F0", Gentoo = "#008B8B"))
  expect_identical(d$coord, list(type = "cartesian", xlim = list(170L, 235L)))
  expect_identical(d$theme, list(legendPosition = "bottom", xLabelAngle = 45L))
  # Positions are back on the data scale, not log10.
  complete <- penguins[!is.na(penguins$flipper_len) & !is.na(penguins$body_mass), ]
  expect_equal(column(d$layers[[1]], "y"), complete$body_mass)

  flipped <- phiz_describe(ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point() +
                             ggplot2::scale_y_reverse() + ggplot2::coord_flip())
  expect_identical(flipped$scales$y, list(reverse = TRUE))
  expect_identical(flipped$coord, list(type = "cartesian", flip = TRUE))
  expect_equal(column(flipped$layers[[1]], "y"), mtcars$mpg)

  viridis <- phiz_describe(ggplot2::ggplot(penguins, ggplot2::aes(bill_len, bill_dep, colour = body_mass)) +
                             ggplot2::geom_point() + ggplot2::scale_colour_viridis_c(option = "C"))
  expect_identical(viridis$scales$color, list(scheme = "plasma"))
  expect_identical(viridis$layers[[1]]$aes$color$type, "quantitative")
  default <- phiz_describe(ggplot2::ggplot(penguins, ggplot2::aes(bill_len, bill_dep, colour = body_mass)) +
                             ggplot2::geom_point())
  expect_null(default$scales$color)

  levels <- data.frame(g = factor(c("b", "a", "c"), levels = c("c", "b", "a")), v = 1:3)
  ordered <- phiz_describe(ggplot2::ggplot(levels, ggplot2::aes(g, v, colour = g)) + ggplot2::geom_point() +
                             ggplot2::guides(colour = "none"))
  expect_identical(ordered$scales$x$domain, list("c", "b", "a"))
  expect_identical(ordered$scales$color, list(domain = list("c", "b", "a"), guide = FALSE))
  angled <- phiz_describe(ggplot2::ggplot(levels, ggplot2::aes(g, v)) + ggplot2::geom_point() +
                            ggplot2::guides(x = ggplot2::guide_axis(angle = 90)))
  expect_identical(angled$theme, list(xLabelAngle = 90L))
})

test_that("stacked and dodged columns carry each bar's own value", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(g = c("b", "a", "c", "a", "b", "c"), h = c("u", "u", "u", "v", "v", "v"), v = c(3, 5, 2, -1, 4, 6))
  stacked <- phiz_describe(ggplot2::ggplot(df, ggplot2::aes(h, v, fill = g)) + ggplot2::geom_col())
  layer <- stacked$layers[[1]]
  expect_identical(layer$geom, "col")
  expect_identical(layer$position, "stack")
  values <- stats::setNames(column(layer, "y"), paste(column(layer, "x"), column(layer, "fill")))
  expect_equal(values[paste(df$h, df$g)], stats::setNames(df$v, paste(df$h, df$g)))

  dodged <- phiz_describe(ggplot2::ggplot(df, ggplot2::aes(h, v, fill = g)) + ggplot2::geom_col(position = "dodge"))
  expect_identical(dodged$layers[[1]]$position, "dodge")
  expect_setequal(column(dodged$layers[[1]], "x"), c("u", "v"))

  counts <- phiz_describe(ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl))) + ggplot2::geom_bar())
  expect_equal(column(counts$layers[[1]], "y"), as.numeric(table(mtcars$cyl)))
})

test_that("ranges, reference lines, text, ribbons, and annotations translate", {
  skip_if_not_installed("ggplot2")
  estimates <- data.frame(term = c("a", "b"), m = c(1, 2), lo = c(0.5, 1.2), hi = c(1.4, 2.9))
  d <- phiz_describe(ggplot2::ggplot(estimates, ggplot2::aes(term, m, ymin = lo, ymax = hi)) +
                       ggplot2::geom_pointrange() + ggplot2::geom_errorbar(width = 0.2) +
                       ggplot2::geom_linerange() + ggplot2::geom_hline(yintercept = 1, linetype = "dashed"))
  expect_identical(vapply(d$layers, `[[`, character(1), "geom"), c("pointrange", "errorbar", "linerange", "hline"))
  expect_equal(column(d$layers[[1]], "ymax"), estimates$hi)
  expect_identical(d$layers[[4]]$linetype, "dashed")
  expect_equal(column(d$layers[[4]], "yintercept"), 1)

  text <- phiz_describe(ggplot2::ggplot(mtcars[1:3, ], ggplot2::aes(wt, mpg, label = rownames(mtcars)[1:3])) +
                          ggplot2::geom_text(nudge_y = 0.5))
  expect_identical(column(text$layers[[1]], "label"), rownames(mtcars)[1:3])
  expect_equal(column(text$layers[[1]], "y"), mtcars$mpg[1:3] + 0.5)

  area <- phiz_describe(ggplot2::ggplot(data.frame(x = rep(1:3, 2), y = c(1, 2, 3, 3, 2, 1), g = rep(c("a", "b"), each = 3)),
                                        ggplot2::aes(x, y, fill = g)) + ggplot2::geom_area())
  expect_identical(area$layers[[1]]$geom, "ribbon")
  expect_identical(area$layers[[1]]$alpha, 1L)

  annotated <- phiz_describe(ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point() +
                               ggplot2::annotate("rect", xmin = 3, xmax = 4, ymin = -Inf, ymax = Inf, alpha = 0.2))
  expect_identical(annotated$layers[[2]], list(geom = "annotate", annotate = "rect", xmin = 3L, xmax = 4L,
                                              ymin = "-Inf", ymax = "Inf", alpha = 0.2))

  dates <- phiz_describe(ggplot2::ggplot(data.frame(d = as.Date(c("2024-01-01", "2024-02-01")), y = 1:2),
                                         ggplot2::aes(d, y)) + ggplot2::geom_line())
  expect_identical(dates$scales$x, list(type = "time"))
  expect_identical(dates$layers[[1]]$aes$x$type, "temporal")
  expect_identical(column(dates$layers[[1]], "x"), c("2024-01-01T00:00:00", "2024-02-01T00:00:00"))
})

test_that("anything that does not translate refuses the whole description", {
  skip_if_not_installed("ggplot2")
  penguins <- phiz_penguins()
  base <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  if (requireNamespace("ggrepel", quietly = TRUE)) {
    expect_match(phiz_refused(base + ggrepel::geom_text_repel(ggplot2::aes(label = rownames(mtcars)))),
                 "GeomTextRepel")
  }
  if (requireNamespace("patchwork", quietly = TRUE)) {
    expect_match(phiz_refused(patchwork::wrap_plots(base, base)), "patchwork")
  }
  expect_match(phiz_refused(base + ggplot2::coord_polar()), "CoordPolar")
  expect_match(phiz_refused(ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), mpg)) + ggplot2::geom_boxplot()), "GeomBoxplot")
  expect_match(phiz_refused(ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg, size = hp)) + ggplot2::geom_point()), "maps size")
  expect_match(phiz_refused(base + ggplot2::geom_abline(intercept = 37, slope = -5)), "abline")
  expect_match(phiz_refused(ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass, colour = sex)) +
                              ggplot2::geom_point()), "missing colour")
  expect_match(phiz_refused(ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), mpg)) + ggplot2::geom_jitter()), "seed")
  expect_match(phiz_refused(base + ggplot2::theme(legend.position = "inside")), "legend position")
  expect_match(phiz_refused(base + ggplot2::scale_x_continuous(sec.axis = ggplot2::sec_axis(~ . * 2))), "secondary")
  expect_match(phiz_refused(base + ggplot2::labs(tag = "A")), "tags")
  expect_match(phiz_refused(base + ggplot2::theme(axis.text.x = ggplot2::element_blank())), "axis labels")
})

test_that("published ggplots write figure.phiz.json beside the image only when they translate", {
  skip_if_not_installed("ggplot2")
  directory <- withr::local_tempdir()
  plot <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg, colour = factor(cyl))) + ggplot2::geom_point()
  path <- framework:::.fw_artifact_file(plot, directory, cloud = TRUE)
  expect_true(basename(path) %in% c("figure.svg", "figure.png"))
  description <- file.path(directory, "figure.phiz.json")
  expect_true(file.exists(description))
  expect_phiz_valid(jsonlite::fromJSON(description, simplifyVector = FALSE))

  refused <- withr::local_tempdir()
  path <- framework:::.fw_artifact_file(ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), mpg)) +
                                          ggplot2::geom_boxplot(), refused, cloud = TRUE)
  expect_true(file.exists(path))
  expect_false(file.exists(file.path(refused, "figure.phiz.json")))

  # A failed translation never fails the publish.
  testthat::local_mocked_bindings(.fw_phiz_translate = function(plot) stop("boom"))
  broken <- withr::local_tempdir()
  expect_true(file.exists(framework:::.fw_artifact_file(plot, broken, cloud = TRUE)))
  expect_false(file.exists(file.path(broken, "figure.phiz.json")))
})

test_that("publishing a ggplot to Framework Cloud sends its plot description", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("httr2")
  withr::local_dir(withr::local_tempdir())
  withr::local_envvar(FW_PROJECT_TOKEN = NA, FW_CLOUD_URL = NA)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  sent <- list()
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      fields <- rlang::list2(...)
      sent[[length(sent) + 1L]] <<- list(fields = names(fields), description = if (!is.null(fields$plot_description)) {
        jsonlite::fromJSON(fields$plot_description$path, simplifyVector = FALSE)
      })
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(id = 1L, version = 1L, url = "http://localhost:8080/d/x"),
    .package = "httr2"
  )
  suppressMessages(publish(ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point(), slug = "fig"))
  expect_true(all(c("file", "plot_description") %in% sent[[1]]$fields))
  expect_identical(sent[[1]]$description$layers[[1]]$geom, "point")

  suppressMessages(publish(ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), mpg)) + ggplot2::geom_boxplot(), slug = "box"))
  expect_false("plot_description" %in% sent[[2]]$fields)
})

# Compiles each description with phiz when a checkout is named, so the format
# and the translation stay in step: FW_PHIZ_PATH=/path/to/phiz.
test_that("written descriptions compile with phiz", {
  skip_if_not_installed("ggplot2")
  phiz <- Sys.getenv("FW_PHIZ_PATH")
  skip_if(!nzchar(phiz) || !file.exists(file.path(phiz, "vendor", "autoload.php")), "FW_PHIZ_PATH is not a phiz checkout")
  skip_if(!nzchar(Sys.which("php")), "php is not installed")
  penguins <- phiz_penguins()
  plots <- list(
    ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass, colour = species)) + ggplot2::geom_point() +
      ggplot2::geom_smooth(method = "lm"),
    ggplot2::ggplot(penguins, ggplot2::aes(body_mass, fill = species)) + ggplot2::geom_histogram(bins = 20),
    ggplot2::ggplot(penguins, ggplot2::aes(flipper_len, body_mass)) + ggplot2::geom_point() + ggplot2::facet_wrap(~island),
    ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), fill = factor(gear))) + ggplot2::geom_bar(position = "dodge"),
    ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point() +
      ggplot2::annotate("rect", xmin = 3, xmax = 4, ymin = -Inf, ymax = Inf, alpha = 0.2)
  )
  script <- withr::local_tempfile(fileext = ".php")
  writeLines(c("<?php", sprintf("require %s;", deparse(file.path(phiz, "vendor", "autoload.php"))),
               "Phiz\\Plot::fromJson(file_get_contents($argv[1]))->toArray();", "echo 'ok';"), script)
  for (plot in plots) {
    json <- withr::local_tempfile(fileext = ".json")
    writeLines(framework:::.fw_phiz_json(framework:::.fw_phiz_describe(plot)$description), json)
    out <- suppressWarnings(system2("php", c(script, json), stdout = TRUE, stderr = TRUE))
    expect_identical(tail(out, 1), "ok", info = paste(out, collapse = "\n"))
  }
})
