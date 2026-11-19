# ggplot -> phiz plot description -------------------------------------------
#
# A published ggplot gets figure.phiz.json beside its SVG: the plot written as
# a phiz plot description (format 1), which Framework Cloud compiles to a live
# Vega-Lite chart. The SVG stays as the static fallback.
#
# The description is translated from the built plot (ggplot_build()), so R's
# statistics (smooth fits and bands, bins, summaries) travel as identity layers
# with their own data. Theme chrome is dropped so the page can theme the chart,
# and ggplot's default hue palette becomes no palette at all. Anything that
# does not translate refuses the whole description: a half-translated chart is
# worse than the picture. .fw_phiz_describe() never errors.

.fw_phiz_max_bytes <- function() 5 * 1024^2

# Positions held in built data, by axis.
.fw_phiz_x <- c("x", "xmin", "xmax", "xend", "xintercept")
.fw_phiz_y <- c("y", "ymin", "ymax", "yend", "yintercept")

# Non-position aesthetics a layer may map.
.fw_phiz_mappable <- c("colour", "fill", "shape", "linetype", "label", "group", "weight")

.fw_phiz_stats <- c("StatIdentity", "StatSmooth", "StatBin", "StatCount", "StatSummary", "StatSummaryBin",
                    "StatDensity", "StatAlign", "StatUnique", "StatFunction", "StatQq", "StatQqLine", "StatEcdf")

.fw_phiz_positions <- c("PositionIdentity", "PositionStack", "PositionFill", "PositionDodge", "PositionDodge2",
                        "PositionNudge", "PositionJitter")

.fw_phiz_geoms <- c("GeomPoint", "GeomLine", "GeomPath", "GeomBar", "GeomCol", "GeomRect", "GeomSmooth",
                    "GeomErrorbar", "GeomLinerange", "GeomPointrange", "GeomHline", "GeomVline", "GeomAbline",
                    "GeomText", "GeomLabel", "GeomRibbon", "GeomArea", "GeomSegment")

.fw_phiz_refuse <- function(...) {
  stop(structure(class = c("fw_phiz_refusal", "error", "condition"),
                 list(message = paste0(...), call = NULL)))
}

# list(description = <list or NULL>, reason = <NULL or why it was refused>).
#' @keywords internal
.fw_phiz_describe <- function(plot) {
  tryCatch(
    list(description = suppressMessages(suppressWarnings(.fw_phiz_translate(plot))), reason = NULL),
    fw_phiz_refusal = function(e) list(description = NULL, reason = conditionMessage(e)),
    error = function(e) list(description = NULL, reason = paste("translation failed:", conditionMessage(e)))
  )
}

# Writes figure.phiz.json for a ggplot, or nothing. Returns the path or NULL.
#' @keywords internal
.fw_phiz_write <- function(plot, directory) {
  if (!inherits(plot, "ggplot") || !requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  described <- .fw_phiz_describe(plot)
  if (is.null(described$description)) return(NULL)
  path <- file.path(directory, "figure.phiz.json")
  written <- tryCatch({
    writeLines(.fw_phiz_json(described$description), path, useBytes = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (!written || file.size(path) > .fw_phiz_max_bytes()) {
    unlink(path)
    return(NULL)
  }
  path
}

#' @keywords internal
.fw_phiz_json <- function(description) {
  enc2utf8(as.character(jsonlite::toJSON(description, auto_unbox = TRUE, digits = NA, null = "null",
                                         na = "null", pretty = FALSE)))
}

# The translation ---------------------------------------------------------------

#' @keywords internal
.fw_phiz_translate <- function(plot) {
  if (inherits(plot, "patchwork")) .fw_phiz_refuse("patchwork compositions are not one plot")
  if (!inherits(plot, "ggplot")) .fw_phiz_refuse("not a ggplot")
  if (!length(plot$layers)) .fw_phiz_refuse("the plot has no layers")

  for (i in seq_along(plot$layers)) .fw_phiz_check_layer(plot$layers[[i]], i)
  built <- ggplot2::ggplot_build(plot)
  raw <- .fw_phiz_build_raw(plot, built)
  ctx <- list(built = built, raw = raw, layout = built$layout$layout,
              panels = nrow(built$layout$layout))
  ctx$coord <- .fw_phiz_coord(built)
  ctx$facet <- .fw_phiz_facet(built)
  ctx$axes <- list(x = .fw_phiz_axis(built, "x"), y = .fw_phiz_axis(built, "y"))
  guides <- .fw_phiz_check_guides(plot)
  theme <- .fw_phiz_theme(built)
  for (axis in c("x", "y")) {
    angle <- .fw_phiz_axis_angle(guides[[axis]]) %||% .fw_phiz_axis_angle(built$plot$scales$get_scales(axis)$guide)
    if (!is.null(angle)) theme$description[[paste0(axis, "LabelAngle")]] <- angle
  }

  layers <- list()
  mapped <- character()
  for (i in seq_along(built$data)) {
    translated <- .fw_phiz_layer(i, ctx)
    layers <- c(layers, translated$layers)
    mapped <- union(mapped, translated$mapped)
  }
  if (!length(layers)) .fw_phiz_refuse("no layer draws anything")

  scales <- list()
  for (axis in c("x", "y")) {
    scale <- ctx$axes[[axis]]$description
    if (length(scale)) scales[[axis]] <- scale
  }
  for (aesthetic in intersect(c("colour", "fill", "shape", "linetype"), mapped)) {
    scale <- .fw_phiz_legend_scale(built, raw, aesthetic)$description
    if (identical(.fw_phiz_check_guide(guides[[aesthetic]], aesthetic), "none")) scale$guide <- FALSE
    if (length(scale)) scales[[if (aesthetic == "colour") "color" else aesthetic]] <- scale
  }

  description <- list(phiz = 1L, layers = layers)
  if (length(scales)) description$scales <- scales
  labels <- .fw_phiz_labels(built, mapped, theme$hidden)
  if (length(labels)) description$labels <- labels
  if (!is.null(ctx$facet)) description$facet <- ctx$facet$description
  if (length(ctx$coord)) description$coord <- ctx$coord
  if (length(theme$description)) description$theme <- theme$description
  alt <- built$plot$labels$alt
  if (is.character(alt) && length(alt) == 1L && !is.na(alt) && nzchar(alt)) description$description <- alt
  description
}

# The plot built a second time with every non-position scale passing its values
# through unmapped, so each row's colour is its level (or number), not a hex
# code. The rows and positions must match the real build, row for row.
#' @keywords internal
.fw_phiz_build_raw <- function(plot, built) {
  scales <- built$plot$scales$clone()
  scales$scales <- lapply(scales$scales, function(scale) {
    if (any(scale$aesthetics %in% c("x", "y"))) return(scale)
    ggplot2::ggproto(NULL, scale, map = function(self, x, limits = self$get_limits()) x)
  })
  plot$scales <- scales
  raw <- ggplot2::ggplot_build(plot)
  if (length(raw$data) != length(built$data)) .fw_phiz_refuse("the layers did not build the same way twice")
  for (i in seq_along(built$data)) {
    a <- built$data[[i]]
    b <- raw$data[[i]]
    if (nrow(a) != nrow(b)) .fw_phiz_refuse("layer ", i, " did not build the same rows twice")
    for (column in intersect(c(.fw_phiz_x, .fw_phiz_y, "PANEL", "group"), names(a))) {
      if (!isTRUE(all.equal(a[[column]], b[[column]], check.attributes = FALSE))) {
        .fw_phiz_refuse("layer ", i, " did not build the same positions twice")
      }
    }
  }
  raw
}

# Coordinates ---------------------------------------------------------------------

#' @keywords internal
.fw_phiz_coord <- function(built) {
  coord <- built$plot$coordinates
  type <- class(coord)[1]
  if (!type %in% c("CoordCartesian", "CoordFlip", "CoordFixed")) {
    .fw_phiz_refuse("coordinate system ", type, " has no plot description")
  }
  out <- list()
  if (type == "CoordFixed") {
    out$type <- "fixed"
    out$ratio <- coord$ratio
  }
  if (type == "CoordFlip") out$flip <- TRUE
  for (axis in c("x", "y")) {
    limits <- coord$limits[[axis]]
    if (is.null(limits)) next
    if (length(limits) != 2L || anyNA(limits)) .fw_phiz_refuse("coord limits for ", axis, " are not two values")
    out[[paste0(axis, "lim")]] <- I(.fw_phiz_values(limits, NULL))
  }
  if (length(out) && is.null(out$type)) out <- c(list(type = "cartesian"), out)
  out
}

# Facets --------------------------------------------------------------------------

#' @keywords internal
.fw_phiz_facet <- function(built) {
  facet <- built$plot$facet
  type <- class(facet)[1]
  if (type == "FacetNull") return(NULL)
  if (!type %in% c("FacetWrap", "FacetGrid")) .fw_phiz_refuse("facet ", type, " has no plot description")
  params <- facet$params
  layout <- built$layout$layout
  free <- params$free %||% list(x = FALSE, y = FALSE)
  scales <- if (isTRUE(free$x) && isTRUE(free$y)) "free" else if (isTRUE(free$x)) "free_x" else if (isTRUE(free$y)) "free_y" else "fixed"
  labeller <- .fw_phiz_labeller(params$labeller)
  if (isFALSE(params$as.table)) .fw_phiz_refuse("facets with as.table = FALSE")

  if (type == "FacetWrap") {
    vars <- names(params$facets)
    if (!is.null(params$dir) && !params$dir %in% c("h", "lt")) .fw_phiz_refuse("facet_wrap() with dir = \"", params$dir, "\"")
    description <- list(type = "wrap", facets = I(vars))
    if (!is.null(params$ncol)) description$ncol <- as.integer(params$ncol)
    if (!is.null(params$nrow)) description$nrow <- as.integer(params$nrow)
  } else {
    rows <- names(params$rows)
    cols <- names(params$cols)
    if (length(rows) > 1L || length(cols) > 1L) .fw_phiz_refuse("facet_grid() with more than one variable on a side")
    if (!isFALSE(params$margins)) .fw_phiz_refuse("facet_grid() margins")
    vars <- c(rows, cols)
    description <- list(type = "grid")
    if (length(rows)) description$rows <- rows
    if (length(cols)) description$cols <- cols
  }
  for (var in vars) {
    if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", var)) .fw_phiz_refuse("facet variable `", var, "` is not a plain name")
    if (var %in% c(.fw_phiz_x, .fw_phiz_y, .fw_phiz_mappable, "order")) {
      .fw_phiz_refuse("facet variable `", var, "` shares a name with an aesthetic")
    }
    if (anyNA(layout[[var]])) .fw_phiz_refuse("facet variable `", var, "` has missing values")
    .fw_phiz_facet_order(layout[[var]][order(layout$PANEL)], var)
  }
  if (scales != "fixed") description$scales <- scales
  if (labeller != "value") description$labeller <- labeller
  list(description = description, vars = vars)
}

#' @keywords internal
.fw_phiz_labeller <- function(labeller) {
  if (is.null(labeller) || identical(labeller, "label_value") || identical(labeller, ggplot2::label_value)) return("value")
  if (identical(labeller, "label_both") || identical(labeller, ggplot2::label_both)) return("both")
  .fw_phiz_refuse("a facet labeller other than label_value or label_both")
}

# phiz orders panels by sorting their values, and the format has no way to give
# another order: panels must already be in sorted order.
#' @keywords internal
.fw_phiz_facet_order <- function(values, var) {
  seen <- .fw_phiz_scalar(unique(values))
  if (!identical(seen, .fw_phiz_sorted(seen))) {
    .fw_phiz_refuse("facet panels of `", var, "` are not in sorted order, which the description cannot set")
  }
}

#' @keywords internal
.fw_phiz_sorted <- function(values) {
  if (is.numeric(values)) sort(values) else sort(values, method = "radix")
}

# Facet values for each row of a layer, keyed by PANEL.
#' @keywords internal
.fw_phiz_facet_columns <- function(ctx, panel) {
  if (is.null(ctx$facet)) return(list())
  at <- match(panel, ctx$layout$PANEL)
  out <- list()
  for (var in ctx$facet$vars) out[[var]] <- .fw_phiz_scalar(ctx$layout[[var]])[at]
  out
}

# Positions -----------------------------------------------------------------------

# What the description needs to know about an axis: its kind, and its scale
# entry. Panel scales carry the trained ranges.
#' @keywords internal
.fw_phiz_axis <- function(built, axis) {
  panels <- built$layout[[paste0("panel_scales_", axis)]]
  template <- built$plot$scales$get_scales(axis)
  trained <- panels[[1]]
  if (is.null(trained)) return(list(kind = "none", description = list()))
  free <- length(panels) > 1L
  if (!inherits(trained, "ScaleContinuousPosition") && !inherits(trained, "ScaleDiscretePosition") &&
      !inherits(trained, "ScaleContinuousDate") && !inherits(trained, "ScaleContinuousDatetime")) {
    .fw_phiz_refuse("the ", axis, " scale is not a ggplot2 position scale")
  }
  scale <- template %||% trained
  if (!ggplot2::is_waiver(scale$secondary.axis) && !is.null(scale$secondary.axis) &&
      !inherits(scale$secondary.axis, "AxisSecondary") ) {
    .fw_phiz_refuse("secondary axes")
  }
  if (inherits(scale$secondary.axis, "AxisSecondary") && !scale$secondary.axis$empty()) .fw_phiz_refuse("secondary axes")
  out <- list()
  position <- scale$position
  if (!is.null(position) && position %in% c("top", "right")) out$position <- position
  .fw_phiz_check_guide(scale$guide, axis)

  if (trained$is_discrete()) {
    if (!is.null(scale$limits) && is.function(scale$limits)) .fw_phiz_refuse("limits given as a function on ", axis)
    limits <- .fw_phiz_scalar(trained$get_limits())
    if (free) {
      if (!ggplot2::is_waiver(scale$labels) || !ggplot2::is_waiver(scale$breaks)) {
        .fw_phiz_refuse("breaks or labels on a free discrete ", axis, " scale")
      }
    } else {
      out$domain <- I(limits)
      if (!ggplot2::is_waiver(scale$breaks)) {
        breaks <- .fw_phiz_scalar(trained$get_breaks())
        out$breaks <- I(breaks[!is.na(breaks)])
      }
      if (!ggplot2::is_waiver(scale$labels)) {
        breaks <- trained$get_breaks()
        breaks <- breaks[!is.na(breaks)]
        out$labels <- stats::setNames(as.list(.fw_phiz_label_text(trained$get_labels(breaks))), as.character(breaks))
      }
    }
    return(list(kind = "discrete", panels = panels, description = out))
  }

  transformation <- trained$get_transformation()
  name <- transformation$name
  kind <- "continuous"
  if (name == "log-10") {
    out$type <- "log"
  } else if (name == "sqrt") {
    out$type <- "sqrt"
  } else if (name == "reverse") {
    out$reverse <- TRUE
  } else if (name == "date") {
    out$type <- "time"
    kind <- "date"
  } else if (name == "time") {
    out$type <- "time"
    kind <- "datetime"
  } else if (name != "identity") {
    .fw_phiz_refuse("the ", name, " transformation on ", axis)
  }
  if (!is.null(scale$limits)) {
    if (is.function(scale$limits)) .fw_phiz_refuse("limits given as a function on ", axis)
    if (free) .fw_phiz_refuse("limits on a free ", axis, " scale")
    out$domain <- I(.fw_phiz_values(trained$get_limits(), transformation, kind))
  }
  custom_breaks <- !ggplot2::is_waiver(scale$breaks)
  custom_labels <- !ggplot2::is_waiver(scale$labels)
  if (custom_breaks || custom_labels) {
    if (free) .fw_phiz_refuse("breaks or labels on a free ", axis, " scale")
    if (is.null(scale$breaks)) {
      out$breaks <- I(list())
    } else {
      breaks <- trained$get_breaks()
      breaks <- breaks[!is.na(breaks)]
      out$breaks <- I(.fw_phiz_values(breaks, transformation, kind))
      if (custom_labels) out$labels <- I(.fw_phiz_label_text(trained$get_labels(breaks)))
    }
  }
  list(kind = kind, panels = panels, transformation = transformation, description = out)
}

#' @keywords internal
.fw_phiz_label_text <- function(labels) {
  if (is.expression(labels) || is.list(labels) && any(vapply(labels, is.language, logical(1)))) {
    .fw_phiz_refuse("plotmath labels")
  }
  as.character(labels)
}

# Built positions back to data values: levels on a discrete axis, inverse-
# transformed numbers on a continuous one, ISO strings on a date axis.
# Infinite values stay infinite.
#' @keywords internal
.fw_phiz_position <- function(values, axis, panel, ctx, dodge = FALSE) {
  info <- ctx$axes[[axis]]
  if (info$kind == "none") .fw_phiz_refuse("a position on an axis without a scale")
  if (info$kind == "discrete") {
    if (any(is.infinite(values))) .fw_phiz_refuse("infinite positions on a discrete axis")
    index <- round(values)
    tolerance <- if (dodge) 0.5 else 1e-8
    if (any(abs(values - index) > tolerance, na.rm = TRUE)) {
      .fw_phiz_refuse("positions between the levels of a discrete ", axis, " axis")
    }
    scales <- info$panels[ctx$layout[[paste0("SCALE_", toupper(axis))]][match(panel, ctx$layout$PANEL)]]
    out <- vapply(seq_along(index), function(i) {
      if (is.na(index[i])) return(NA_character_)
      limits <- as.character(scales[[i]]$get_limits())
      if (index[i] < 1 || index[i] > length(limits)) .fw_phiz_refuse("a position outside a discrete ", axis, " axis")
      limits[index[i]]
    }, character(1))
    return(out)
  }
  .fw_phiz_values(values, info$transformation, info$kind)
}

#' @keywords internal
.fw_phiz_values <- function(values, transformation, kind = "continuous") {
  if (is.null(transformation)) {
    if (inherits(values, "Date")) return(format(values, "%Y-%m-%dT00:00:00"))
    if (inherits(values, "POSIXct")) return(format(values, "%Y-%m-%dT%H:%M:%S"))
    return(.fw_phiz_scalar(values))
  }
  values <- as.numeric(values)
  infinite <- is.infinite(values)
  out <- transformation$inverse(values)
  if (kind == "date") {
    out <- format(as.Date(out), "%Y-%m-%dT00:00:00")
    out[infinite] <- ifelse(values[infinite] > 0, "Inf", "-Inf")
    return(out)
  }
  if (kind == "datetime") {
    out <- format(out, "%Y-%m-%dT%H:%M:%S")
    out[infinite] <- ifelse(values[infinite] > 0, "Inf", "-Inf")
    return(out)
  }
  out <- as.numeric(out)
  out[infinite] <- values[infinite]
  out
}

#' @keywords internal
.fw_phiz_scalar <- function(values) {
  if (is.factor(values)) return(as.character(values))
  if (is.numeric(values) || is.logical(values) || is.character(values)) return(as.vector(values))
  as.character(values)
}

# Guides and theme ---------------------------------------------------------------

#' @keywords internal
.fw_phiz_check_guide <- function(guide, aesthetic) {
  if (is.null(guide) || ggplot2::is_waiver(guide)) return(invisible("default"))
  if (is.character(guide)) {
    if (guide %in% c("none")) return(invisible("none"))
    if (guide %in% c("legend", "colourbar", "colorbar", "axis")) return(invisible("default"))
    .fw_phiz_refuse("guide \"", guide, "\" on ", aesthetic)
  }
  if (inherits(guide, "GuideNone")) return(invisible("none"))
  if (inherits(guide, "GuideAxis") && aesthetic %in% c("x", "y")) {
    defaults <- ggplot2::guide_axis()$params
    for (param in c("n.dodge", "minor.ticks", "cap", "check.overlap")) {
      if (!identical(guide$params[[param]], defaults[[param]])) .fw_phiz_refuse("guide_axis(", param, ") on ", aesthetic)
    }
    return(invisible("axis"))
  }
  .fw_phiz_refuse("a custom guide on ", aesthetic)
}

# The plot's guides(), keyed by aesthetic, once each is known to translate.
#' @keywords internal
.fw_phiz_check_guides <- function(plot) {
  guides <- plot$guides$guides %||% list()
  names(guides)[names(guides) == "color"] <- "colour"
  for (aesthetic in names(guides)) {
    if (!aesthetic %in% c("x", "y", "colour", "fill", "shape", "linetype")) {
      .fw_phiz_refuse("a guide on ", aesthetic)
    }
    .fw_phiz_check_guide(guides[[aesthetic]], aesthetic)
  }
  guides
}

#' @keywords internal
.fw_phiz_axis_angle <- function(guide) {
  if (!inherits(guide, "GuideAxis")) return(NULL)
  angle <- guide$params$angle
  if (is.null(angle) || ggplot2::is_waiver(angle) || !is.numeric(angle) || is.na(angle) || angle == 0) return(NULL)
  angle
}

# Theme elements that carry meaning. Everything else in the theme is chrome the
# page replaces: backgrounds, grid, fonts, colours, sizes.
#' @keywords internal
.fw_phiz_theme <- function(built) {
  theme <- built$plot$theme
  element <- function(name) ggplot2::calc_element(name, theme)
  blank <- function(name) inherits(element(name), "element_blank")
  out <- list()
  hidden <- character()

  position <- element("legend.position")
  if (is.character(position) && length(position) == 1L) {
    if (position %in% c("top", "bottom", "left", "none")) out$legendPosition <- position
    else if (position != "right") .fw_phiz_refuse("legend position \"", position, "\"")
  } else if (!is.null(position)) {
    .fw_phiz_refuse("a legend inside the panel")
  }
  direction <- theme$legend.direction
  if (is.character(direction) && length(direction) == 1L) out$legendDirection <- direction
  if (blank("legend.title")) out$legendTitle <- FALSE

  for (axis in c("x", "y")) {
    side <- if (axis == "x") "bottom" else "left"
    text <- paste0("axis.text.", axis, ".", side)
    if (blank(text)) .fw_phiz_refuse("hidden ", axis, " axis labels")
    angle <- element(text)$angle
    if (is.numeric(angle) && length(angle) == 1L && !is.na(angle) && angle != 0) {
      out[[paste0(axis, "LabelAngle")]] <- angle
    }
    if (blank(paste0("axis.title.", axis, ".", side))) hidden <- c(hidden, axis)
  }
  if (blank("strip.text.x.top") || blank("strip.text.y.right")) .fw_phiz_refuse("hidden facet labels")
  for (title in c("plot.title", "plot.subtitle", "plot.caption")) {
    if (blank(title)) hidden <- c(hidden, sub("^plot[.]", "", title))
  }
  list(description = out, hidden = hidden)
}

# Labels: titles, and one title per aesthetic. A scale's name wins over labs().
#' @keywords internal
.fw_phiz_labels <- function(built, mapped, hidden) {
  labels <- built$plot$labels
  text <- function(value, what) {
    if (is.null(value) || ggplot2::is_waiver(value)) return(NULL)
    if (is.language(value) || is.expression(value)) .fw_phiz_refuse("a plotmath ", what)
    if (is.function(value)) .fw_phiz_refuse("a ", what, " given as a function")
    if (!is.character(value) && !is.numeric(value)) .fw_phiz_refuse("a ", what, " that is not text")
    paste(as.character(value), collapse = "\n")
  }
  if (!is.null(labels$tag) && !ggplot2::is_waiver(labels$tag)) .fw_phiz_refuse("plot tags")
  out <- list()
  for (name in c("title", "subtitle", "caption")) {
    value <- text(labels[[name]], name)
    if (name %in% hidden) next
    if (!is.null(value)) out[[name]] <- value
  }
  for (aesthetic in c("x", "y", intersect(c("colour", "fill", "shape", "linetype"), mapped))) {
    key <- if (aesthetic == "colour") "color" else aesthetic
    if (aesthetic %in% hidden) {
      out[key] <- list(NULL)
      next
    }
    scale <- built$plot$scales$get_scales(aesthetic)
    name <- if (!is.null(scale) && !ggplot2::is_waiver(scale$name)) scale$name else labels[[aesthetic]]
    if (is.null(name) && !is.null(scale) && is.null(scale$name)) {
      out[key] <- list(NULL)
      next
    }
    value <- text(name, paste(aesthetic, "title"))
    if (!is.null(value)) out[[key]] <- value
  }
  out
}

# Legend scales ------------------------------------------------------------------

#' @keywords internal
.fw_phiz_hex <- function(colours) {
  rgb <- grDevices::col2rgb(colours, alpha = TRUE)
  hex <- sprintf("#%02X%02X%02X", rgb[1, ], rgb[2, ], rgb[3, ])
  translucent <- rgb[4, ] < 255
  hex[translucent] <- sprintf("%s%02X", hex[translucent], rgb[4, translucent])
  hex
}

# The scale entry for a legend, and the field type its values take.
#' @keywords internal
.fw_phiz_legend_scale <- function(built, raw, aesthetic) {
  scale <- built$plot$scales$get_scales(aesthetic)
  if (is.null(scale)) .fw_phiz_refuse("the ", aesthetic, " mapping has no scale")
  out <- list()
  if (identical(.fw_phiz_check_guide(scale$guide, aesthetic), "none")) out$guide <- FALSE
  if (inherits(scale, "ScaleDiscreteIdentity") || inherits(scale, "ScaleContinuousIdentity")) {
    if (!aesthetic %in% c("colour", "fill")) .fw_phiz_refuse("an identity ", aesthetic, " scale")
    out$identity <- TRUE
    return(list(description = out, type = "nominal", identity = TRUE))
  }
  if (inherits(scale, "ScaleDiscrete")) {
    limits <- as.character(scale$get_limits())
    if (!length(limits)) .fw_phiz_refuse("an empty ", aesthetic, " scale")
    mapped <- scale$map(scale$get_limits())
    if (anyNA(mapped)) .fw_phiz_refuse("levels of ", aesthetic, " without a value")
    if (aesthetic %in% c("colour", "fill")) {
      hex <- .fw_phiz_hex(mapped)
      default <- .fw_phiz_hex(scales::pal_hue()(length(limits)))
      if (!identical(hex, default)) out$values <- stats::setNames(as.list(hex), limits)
    } else {
      default <- switch(aesthetic,
                        shape = scales::pal_shape()(length(limits)),
                        linetype = scales::pal_linetype()(length(limits)))
      if (!identical(as.vector(mapped), as.vector(default))) {
        .fw_phiz_refuse("a ", aesthetic, " palette other than ggplot2's default")
      }
    }
    if (!identical(limits, .fw_phiz_sorted(limits))) out$domain <- I(limits)
    if (!ggplot2::is_waiver(scale$breaks) && !identical(as.character(scale$get_breaks()), limits)) {
      .fw_phiz_refuse("breaks that hide levels of ", aesthetic)
    }
    if (!ggplot2::is_waiver(scale$labels)) {
      out$labels <- stats::setNames(as.list(.fw_phiz_label_text(scale$get_labels(scale$get_limits()))), limits)
    }
    return(list(description = out, type = "nominal"))
  }
  if (!inherits(scale, "ScaleContinuous")) .fw_phiz_refuse("the ", aesthetic, " scale is not a ggplot2 scale")
  if (!aesthetic %in% c("colour", "fill")) .fw_phiz_refuse("a continuous ", aesthetic, " scale")
  transformation <- scale$get_transformation()
  if (transformation$name != "identity") .fw_phiz_refuse("the ", transformation$name, " transformation on ", aesthetic)
  palette <- .fw_phiz_continuous_palette(scale)
  out <- c(out, palette)
  if (!is.null(scale$limits)) {
    if (is.function(scale$limits)) .fw_phiz_refuse("limits given as a function on ", aesthetic)
    out$domain <- I(as.numeric(scale$get_limits()))
  }
  if (!ggplot2::is_waiver(scale$breaks) || !ggplot2::is_waiver(scale$labels)) {
    breaks <- scale$get_breaks()
    breaks <- breaks[!is.na(breaks)]
    out$breaks <- I(as.numeric(breaks))
    if (!ggplot2::is_waiver(scale$labels)) out$labels <- I(.fw_phiz_label_text(scale$get_labels(breaks)))
  }
  list(description = out, type = "quantitative")
}

# ggplot2's default gradient becomes no palette, as the default hue does.
# Viridis keeps its scheme, and two- and three-colour gradients keep their
# colours. Anything else has no faithful description.
#' @keywords internal
.fw_phiz_continuous_palette <- function(scale) {
  probe <- seq(0, 1, length.out = 11)
  palette <- scale$palette %||% scale$fallback_palette
  if (is.null(palette)) .fw_phiz_refuse("a continuous colour scale without a palette")
  got <- .fw_phiz_hex(palette(probe))
  same <- function(colours) identical(got, .fw_phiz_hex(colours))
  if (same(scales::pal_seq_gradient("#132B43", "#56B1F7")(probe))) return(list())
  schemes <- c(A = "magma", B = "inferno", C = "plasma", D = "viridis", E = "cividis")
  for (option in names(schemes)) {
    for (direction in c(1, -1)) {
      viridis <- scales::pal_gradient_n(scales::pal_viridis(option = option, direction = direction)(6))(probe)
      if (same(viridis)) {
        out <- list(scheme = unname(schemes[option]))
        if (direction == -1) out$reverse <- TRUE
        return(out)
      }
    }
  }
  ends <- .fw_phiz_hex(palette(c(0, 0.5, 1)))
  if (same(scales::pal_seq_gradient(ends[1], ends[3])(probe))) {
    return(list(range = I(ends[c(1, 3)]), interpolate = "lab"))
  }
  if (same(scales::pal_div_gradient(ends[1], ends[2], ends[3])(probe))) {
    mid <- environment(scale$rescaler)$mid
    if (!is.numeric(mid) || length(mid) != 1L) .fw_phiz_refuse("a diverging colour scale without a midpoint")
    return(list(range = I(ends), interpolate = "lab", domainMid = mid))
  }
  .fw_phiz_refuse("a continuous colour palette with no plot description")
}

# Layers -------------------------------------------------------------------------

#' @keywords internal
.fw_phiz_is_calculated <- function(quosure) {
  text <- paste(deparse(rlang::quo_get_expr(quosure)), collapse = " ")
  grepl("after_stat\\(|after_scale\\(|stage\\(|\\bstat\\(|\\.\\.[A-Za-z_.]+\\.\\.", text)
}

# Aesthetics the layer maps through a scale: its mapping and the stat's
# calculated defaults, less the constants it sets.
#' @keywords internal
.fw_phiz_mapped <- function(layer) {
  mapping <- layer$computed_mapping %||% layer$mapping
  for (name in names(mapping)) {
    text <- paste(deparse(rlang::quo_get_expr(mapping[[name]])), collapse = " ")
    if (grepl("after_scale\\(|stage\\(", text)) .fw_phiz_refuse("after_scale() or stage() in the ", name, " mapping")
  }
  defaults <- layer$stat$default_aes
  calculated <- names(defaults)[vapply(defaults, function(q) rlang::is_quosure(q) && .fw_phiz_is_calculated(q) ||
                                         is.language(q) && .fw_phiz_is_calculated(rlang::new_quosure(q)), logical(1))]
  mapped <- union(names(mapping), calculated)
  mapped[mapped == "color"] <- "colour"
  setdiff(mapped, names(layer$aes_params))
}

# What can be refused before building: the layer's geom, stat, and position.
#' @keywords internal
.fw_phiz_check_layer <- function(layer, i) {
  geom <- class(layer$geom)[1]
  stat <- class(layer$stat)[1]
  position <- class(layer$position)[1]
  if (!geom %in% .fw_phiz_geoms) .fw_phiz_refuse("layer ", i, " draws ", geom, ", which has no plot description")
  if (!stat %in% .fw_phiz_stats) .fw_phiz_refuse("layer ", i, " uses ", stat, ", which has no plot description")
  if (!position %in% .fw_phiz_positions) .fw_phiz_refuse("layer ", i, " uses ", position, ", which has no plot description")
  if (!is.null(layer$geom_params$arrow)) .fw_phiz_refuse("layer ", i, " draws arrows")
  if (isTRUE(layer$geom_params$parse)) .fw_phiz_refuse("layer ", i, " parses labels as plotmath")
  # Unseeded jitter is drawn afresh each time, so it would not match the SVG.
  if (position == "PositionJitter" && is.na(layer$position$seed %||% NA)) {
    .fw_phiz_refuse("layer ", i, " jitters without a seed")
  }
  # phiz's abline spans the x extent of plot-level data, which a description
  # built from per-layer data does not have (a format gap, reported).
  if (geom == "GeomAbline") .fw_phiz_refuse("layer ", i, " draws abline, which phiz cannot draw without plot-level data")
  invisible(NULL)
}

#' @keywords internal
.fw_phiz_layer <- function(i, ctx) {
  layer <- ctx$built$plot$layers[[i]]
  data <- ctx$built$data[[i]]
  raw <- ctx$raw$data[[i]]
  geom <- class(layer$geom)[1]
  position <- class(layer$position)[1]

  mapped <- .fw_phiz_mapped(layer)
  positional <- c(.fw_phiz_x, .fw_phiz_y, "intercept", "slope", "x", "y")
  unsupported <- setdiff(mapped, c(positional, .fw_phiz_mappable))
  if (length(unsupported)) {
    .fw_phiz_refuse("layer ", i, " maps ", paste(unsupported, collapse = ", "), ", which the description does not carry")
  }
  legends <- intersect(c("colour", "fill", "shape", "linetype"), mapped)

  if (!nrow(data)) return(list(layers = list(), mapped = character()))

  lx <- list(i = i, layer = layer, data = data, raw = raw, ctx = ctx, legends = legends, geom = geom,
             position = position, mapped = mapped)
  layers <- switch(geom,
    GeomPoint = .fw_phiz_simple(lx, "point", c("x", "y")),
    GeomLine = .fw_phiz_simple(lx, "line", c("x", "y"), line = TRUE),
    GeomPath = .fw_phiz_simple(lx, "path", c("x", "y"), line = TRUE),
    GeomText = .fw_phiz_simple(lx, "text", c("x", "y"), label = TRUE),
    GeomLabel = .fw_phiz_simple(lx, "label", c("x", "y"), label = TRUE),
    GeomSegment = .fw_phiz_simple(lx, "segment", c("x", "y", "xend", "yend")),
    GeomRect = .fw_phiz_simple(lx, "rect", c("xmin", "xmax", "ymin", "ymax")),
    GeomRibbon = .fw_phiz_ribbon(lx, area = FALSE),
    GeomArea = .fw_phiz_ribbon(lx, area = TRUE),
    GeomSmooth = .fw_phiz_smooth(lx),
    GeomBar = .fw_phiz_bars(lx),
    GeomCol = .fw_phiz_bars(lx),
    GeomErrorbar = .fw_phiz_range(lx, "errorbar"),
    GeomLinerange = .fw_phiz_range(lx, "linerange"),
    GeomPointrange = .fw_phiz_range(lx, "pointrange"),
    GeomHline = .fw_phiz_refline(lx, "y"),
    GeomVline = .fw_phiz_refline(lx, "x")
  )
  list(layers = layers, mapped = legends)
}

#' @keywords internal
.fw_phiz_flipped <- function(data) isTRUE(any(data$flipped_aes))

# Data columns and mappings for a layer's rows. positions: the position columns
# to carry. Rows with a missing required position are dropped, as ggplot2 does.
#' @keywords internal
.fw_phiz_columns <- function(lx, positions, rows = NULL, dodge = FALSE, legends = lx$legends,
                             group = FALSE, extra = list()) {
  data <- lx$data
  raw <- lx$raw
  if (!is.null(rows)) {
    data <- data[rows, , drop = FALSE]
    raw <- raw[rows, , drop = FALSE]
  }
  columns <- list()
  aes <- list()
  for (position in positions) {
    values <- data[[position]]
    if (is.null(values)) .fw_phiz_refuse("layer ", lx$i, " has no ", position, " position")
    axis <- if (position %in% .fw_phiz_x) "x" else "y"
    columns[[position]] <- .fw_phiz_position(values, axis, data$PANEL, lx$ctx, dodge = dodge)
    aes[[position]] <- list(field = position, type = .fw_phiz_field_type(lx$ctx$axes[[axis]]$kind))
  }
  for (aesthetic in legends) {
    values <- raw[[aesthetic]]
    if (is.null(values)) .fw_phiz_refuse("layer ", lx$i, " lost its ", aesthetic, " values")
    if (anyNA(values)) .fw_phiz_refuse("layer ", lx$i, " has missing ", aesthetic, " values")
    info <- .fw_phiz_legend_scale(lx$ctx$built, lx$ctx$raw, aesthetic)
    if (isTRUE(info$identity)) {
      values <- .fw_phiz_hex(as.character(values))
    } else {
      values <- .fw_phiz_scalar(values)
      if (info$type == "nominal") values <- as.character(values)
    }
    columns[[aesthetic]] <- values
    aes[[if (aesthetic == "colour") "color" else aesthetic]] <- list(field = aesthetic, type = info$type)
  }
  if (group && length(unique(data$group)) > 1L) {
    columns$group <- as.integer(data$group)
    aes$group <- list(field = "group", type = "nominal")
  }
  for (name in names(extra)) {
    columns[[name]] <- extra[[name]]$values
    aes[[extra[[name]]$aes %||% name]] <- list(field = name, type = extra[[name]]$type)
  }
  columns <- c(columns, .fw_phiz_facet_columns(lx$ctx, data$PANEL))
  list(columns = columns, aes = aes)
}

#' @keywords internal
.fw_phiz_field_type <- function(kind) {
  switch(kind, discrete = "nominal", date = "temporal", datetime = "temporal", "quantitative")
}

# A layer object from columns, mappings, and options.
#' @keywords internal
.fw_phiz_layer_object <- function(geom, built, options = list()) {
  columns <- built$columns
  infinite <- vapply(columns, function(v) is.numeric(v) && any(is.infinite(v)), logical(1))
  if (any(infinite)) .fw_phiz_refuse("infinite positions outside an annotation")
  out <- list(geom = geom, aes = built$aes, data = lapply(columns, I))
  c(out, options)
}

# Rows to keep: complete required positions. Lines and paths may not have gaps
# inside them, since ggplot2 breaks the line there.
#' @keywords internal
.fw_phiz_complete <- function(lx, positions, line = FALSE) {
  data <- lx$data
  missing <- Reduce(`|`, lapply(positions, function(p) is.na(data[[p]])), FALSE)
  if (line && any(missing)) {
    for (g in unique(data$group)) {
      m <- missing[data$group == g]
      kept <- which(!m)
      if (length(kept) && any(m[min(kept):max(kept)])) .fw_phiz_refuse("layer ", lx$i, " has a gap inside a line")
    }
  }
  which(!missing)
}

# Constant visual properties the author set on the layer. ggplot2's own
# defaults are dropped, so the page's theme colours the chart.
#' @keywords internal
.fw_phiz_style <- function(lx, kind, allow = c("colour", "fill", "alpha", "size", "linewidth", "linetype", "shape")) {
  params <- lx$layer$aes_params
  out <- list()
  for (name in names(params)) {
    value <- params[[name]]
    if (name == "color") name <- "colour"
    if (!name %in% allow) {
      # Nudges are already in the built positions; the rest is chrome.
      if (name %in% c("stroke", "family", "fontface", "lineheight", "weight", "width", "nudge_x", "nudge_y")) next
      if (name %in% c("angle", "hjust", "vjust") && kind == "text") {
        if (!is.numeric(value) || length(value) != 1L) .fw_phiz_refuse("layer ", lx$i, " sets ", name, " that is not one number")
        out[[name]] <- value
        next
      }
      if (name %in% c("colour", "fill", "alpha", "size", "linewidth", "linetype", "shape")) next
      .fw_phiz_refuse("layer ", lx$i, " sets ", name, ", which the description does not carry")
    }
    if (length(value) != 1L) .fw_phiz_refuse("layer ", lx$i, " sets ", name, " to more than one value")
    if (is.na(value)) next
    out[[if (name == "colour") "color" else name]] <- switch(name,
      colour = ,
      fill = .fw_phiz_hex(value),
      alpha = as.numeric(value),
      # Sizes in the units of the SVG fallback, where a point is a pixel.
      size = if (kind == "point") round(pi / 4 * (value * ggplot2::.pt)^2, 2) else round(value * ggplot2::.pt, 2),
      linewidth = round(value * ggplot2::.pt * 72 / 96, 2),
      linetype = .fw_phiz_linetype(value, lx$i),
      shape = .fw_phiz_shape(value, lx$i)
    )
  }
  out
}

#' @keywords internal
.fw_phiz_linetype <- function(value, i) {
  names <- c("blank", "solid", "dashed", "dotted", "dotdash", "longdash", "twodash")
  if (is.numeric(value) && value %in% 0:6) return(names[value + 1])
  if (is.character(value) && (value %in% names || grepl("^[0-9a-fA-F]{2,8}$", value))) return(value)
  .fw_phiz_refuse("layer ", i, " sets an unknown linetype")
}

#' @keywords internal
.fw_phiz_shape <- function(value, i) {
  if (is.character(value)) value <- ggplot2::translate_shape_string(value)
  if (!is.numeric(value) || !value %in% c(0:6, 8, 15:25)) .fw_phiz_refuse("layer ", i, " sets a shape the description does not carry")
  as.integer(value)
}

# Points, lines, paths, text, segments, rects.
#' @keywords internal
.fw_phiz_simple <- function(lx, geom, positions, line = FALSE, label = FALSE) {
  if (lx$position == "PositionJitter" && any(vapply(c("x", "y"), function(a) lx$ctx$axes[[a]]$kind == "discrete", logical(1)))) {
    .fw_phiz_refuse("layer ", lx$i, " jitters along a discrete axis")
  }
  if (lx$position %in% c("PositionDodge", "PositionDodge2")) .fw_phiz_refuse("layer ", lx$i, " dodges ", geom, "s")
  infinite <- vapply(positions, function(p) any(is.infinite(lx$data[[p]])), logical(1))
  if (any(infinite)) return(.fw_phiz_annotate(lx, geom, positions, label))
  rows <- .fw_phiz_complete(lx, positions, line = line)
  extra <- list()
  if (label) extra$label <- list(values = .fw_phiz_label_values(lx$data$label[rows], lx$i), type = "nominal")
  built <- .fw_phiz_columns(lx, positions, rows = rows, group = line, extra = extra)
  kind <- if (geom %in% c("text", "label")) "text" else if (geom == "point") "point" else if (geom == "rect") "filled" else "line"
  style <- .fw_phiz_style(lx, kind)
  if (geom %in% c("text", "label")) style$linewidth <- NULL
  list(.fw_phiz_layer_object(geom, built, style))
}

#' @keywords internal
.fw_phiz_label_values <- function(labels, i) {
  if (is.null(labels)) .fw_phiz_refuse("layer ", i, " has no labels")
  if (is.list(labels) || is.expression(labels)) .fw_phiz_refuse("layer ", i, " has labels that are not text")
  as.character(labels)
}

# Annotations reaching the panel's edges: a layer with -Inf or Inf positions,
# drawn with phiz's annotate, which reads "-Inf" and "Inf".
#' @keywords internal
.fw_phiz_annotate <- function(lx, geom, positions, label) {
  if (!geom %in% c("text", "label", "point", "segment", "rect")) .fw_phiz_refuse("layer ", lx$i, " has infinite positions")
  if (length(lx$legends)) .fw_phiz_refuse("layer ", lx$i, " has infinite positions and a legend")
  data <- lx$data
  if (lx$ctx$panels > 1L) .fw_phiz_refuse("layer ", lx$i, " is an annotation with infinite positions in a faceted plot")
  out <- list(geom = "annotate", annotate = geom)
  for (position in positions) {
    axis <- if (position %in% .fw_phiz_x) "x" else "y"
    values <- .fw_phiz_position(data[[position]], axis, data$PANEL, lx$ctx)
    if (is.numeric(values)) {
      written <- as.list(values)
      written[values == Inf] <- "Inf"
      written[values == -Inf] <- "-Inf"
    } else {
      written <- as.list(values)
    }
    out[[position]] <- if (length(written) == 1L) written[[1]] else written
  }
  if (label) {
    labels <- .fw_phiz_label_values(data$label, lx$i)
    out$label <- if (length(labels) == 1L) labels else I(labels)
  }
  kind <- if (geom %in% c("text", "label")) "text" else if (geom == "point") "point" else if (geom == "rect") "filled" else "line"
  list(c(out, .fw_phiz_style(lx, kind, allow = c("colour", "fill", "alpha", "size", "linewidth", "linetype"))))
}

# Ribbons, and areas (whose built ymin and ymax already hold the stack).
#' @keywords internal
.fw_phiz_ribbon <- function(lx, area) {
  flipped <- .fw_phiz_flipped(lx$data)
  positions <- if (flipped) c("y", "xmin", "xmax") else c("x", "ymin", "ymax")
  rows <- .fw_phiz_complete(lx, positions, line = TRUE)
  built <- .fw_phiz_columns(lx, positions, rows = rows, group = TRUE)
  style <- .fw_phiz_style(lx, "filled")
  if (area && is.null(style$alpha)) style$alpha <- 1
  list(.fw_phiz_layer_object("ribbon", built, style))
}

# A smooth is R's fitted line and, with se, its band: a line and a ribbon.
#' @keywords internal
.fw_phiz_smooth <- function(lx) {
  flipped <- .fw_phiz_flipped(lx$data)
  main <- if (flipped) c("x", "y") else c("x", "y")
  rows <- .fw_phiz_complete(lx, main, line = TRUE)
  style <- .fw_phiz_style(lx, "line")
  line_legends <- intersect(lx$legends, c("colour", "linetype"))
  line <- .fw_phiz_columns(lx, main, rows = rows, legends = line_legends, group = TRUE)
  layers <- list(.fw_phiz_layer_object(if (flipped) "path" else "line", line,
                                       style[intersect(names(style), c("color", "alpha", "linewidth", "linetype"))]))
  se <- lx$layer$stat_params$se %||% TRUE
  band <- if (flipped) c("y", "xmin", "xmax") else c("x", "ymin", "ymax")
  if (isTRUE(se) && all(band %in% names(lx$data)) && !all(is.na(lx$data[[band[2]]]))) {
    rows <- .fw_phiz_complete(lx, band, line = TRUE)
    ribbon <- .fw_phiz_columns(lx, band, rows = rows, legends = intersect(lx$legends, "fill"), group = TRUE)
    fill <- style[intersect(names(style), c("fill", "alpha"))]
    layers <- c(layers, list(.fw_phiz_layer_object("ribbon", ribbon, fill)))
  }
  layers
}

# Bars and columns, including histograms from their built bins.
#' @keywords internal
.fw_phiz_bars <- function(lx) {
  data <- lx$data
  flipped <- .fw_phiz_flipped(data)
  category <- if (flipped) "y" else "x"
  value <- if (flipped) "x" else "y"
  lo <- paste0(value, "min")
  hi <- paste0(value, "max")
  stacked <- lx$position %in% c("PositionStack", "PositionFill")
  dodged <- lx$position %in% c("PositionDodge", "PositionDodge2")
  if (!lx$position %in% c("PositionStack", "PositionFill", "PositionIdentity", "PositionDodge", "PositionDodge2")) {
    .fw_phiz_refuse("layer ", lx$i, " moves bars with ", lx$position)
  }
  style <- .fw_phiz_style(lx, "filled")
  if (lx$ctx$axes[[value]]$kind != "continuous" || !identical(lx$ctx$axes[[value]]$transformation$name, "identity")) {
    .fw_phiz_refuse("layer ", lx$i, " draws bars along a transformed or non-numeric axis")
  }
  # The bar's own length: R's stacked extent, signed as the bar points.
  height <- if (stacked) ifelse(data[[hi]] <= 0 & data[[lo]] < 0, data[[lo]] - data[[hi]], data[[hi]] - data[[lo]]) else data[[value]]
  rows <- which(!is.na(height) & !is.na(data[[category]]))
  position <- if (stacked) "stack" else if (dodged) "dodge" else "identity"

  if (lx$ctx$axes[[category]]$kind == "discrete") {
    extra <- list()
    extra[[value]] <- list(values = height[rows], type = "quantitative")
    if (stacked && length(unique(data$group)) > 1L) {
      reverse <- isTRUE(lx$layer$position$reverse)
      extra$order <- list(values = if (reverse) data$group[rows] else -data$group[rows], type = "quantitative")
    }
    built <- .fw_phiz_columns(lx, category, rows = rows, dodge = dodged,
                              group = dodged && !length(intersect(lx$legends, c("fill", "colour"))), extra = extra)
    options <- list(position = position)
    width <- lx$layer$geom_params$width
    if (is.numeric(width) && length(width) == 1L && !is.na(width)) options$width <- width
    return(list(.fw_phiz_layer_object("col", built, c(options, style))))
  }
  if (lx$ctx$axes[[category]]$kind != "continuous") .fw_phiz_refuse("layer ", lx$i, " draws bars along a date axis")
  if (!flipped && !dodged) {
    extra <- list(y = list(values = height[rows], type = "quantitative"))
    built <- .fw_phiz_columns(lx, c("xmin", "xmax"), rows = rows, extra = extra)
    return(list(.fw_phiz_layer_object("col", built, c(list(position = position), style))))
  }
  # Dodged or horizontal bars on a continuous axis keep R's rectangles.
  built <- .fw_phiz_columns(lx, c("xmin", "xmax", "ymin", "ymax"), rows = rows)
  list(.fw_phiz_layer_object("rect", built, style))
}

# Error bars, line ranges, and point ranges.
#' @keywords internal
.fw_phiz_range <- function(lx, geom) {
  flipped <- .fw_phiz_flipped(lx$data)
  positions <- if (flipped) c("y", "xmin", "xmax") else c("x", "ymin", "ymax")
  if (geom == "pointrange") positions <- c(positions, if (flipped) "x" else "y")
  dodged <- lx$position %in% c("PositionDodge", "PositionDodge2")
  if (!lx$position %in% c("PositionIdentity", "PositionDodge", "PositionDodge2")) {
    .fw_phiz_refuse("layer ", lx$i, " moves ranges with ", lx$position)
  }
  category <- positions[1]
  if (dodged && lx$ctx$axes[[category]]$kind != "discrete") .fw_phiz_refuse("layer ", lx$i, " dodges ranges along a numeric axis")
  rows <- .fw_phiz_complete(lx, positions)
  built <- .fw_phiz_columns(lx, positions, rows = rows, dodge = dodged,
                            group = dodged && !length(intersect(lx$legends, c("fill", "colour"))))
  options <- if (dodged) list(position = "dodge") else list()
  kind <- if (geom == "pointrange") "point" else "line"
  style <- .fw_phiz_style(lx, kind, allow = c("colour", "alpha", "linewidth", if (geom == "pointrange") c("size", "shape")))
  list(.fw_phiz_layer_object(geom, built, c(options, style)))
}

# Reference lines at mapped or fixed intercepts, one row per panel.
#' @keywords internal
.fw_phiz_refline <- function(lx, axis) {
  position <- paste0(axis, "intercept")
  rows <- .fw_phiz_complete(lx, position)
  built <- .fw_phiz_columns(lx, position, rows = rows)
  list(.fw_phiz_layer_object(if (axis == "y") "hline" else "vline", built,
                             .fw_phiz_style(lx, "line", allow = c("colour", "alpha", "linewidth", "linetype"))))
}
