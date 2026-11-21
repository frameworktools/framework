# DAGs: a dagitty graph, or a ggdag tidy_dagitty, published as a dag artifact
# (framework.artifact/v1). Framework Cloud lays the graph out and draws it;
# this file only sends data: the DAGitty model text, labels, the code that
# built the graph, and what dagitty computes from it. The format is in
# framework-cloud docs/plans/2026-11-21-dag-artifacts.md, and Cloud's
# ArtifactDag class is the source of truth for what it accepts.

# Whether `object` is a graph publish() sends as a DAG.
#' @keywords internal
.fw_dag_is <- function(object) {
  inherits(object, "dagitty") || inherits(object, "tidy_dagitty")
}

# The dagitty graph inside a dagitty or tidy_dagitty object.
#' @keywords internal
.fw_dag_graph <- function(object) {
  if (!requireNamespace("dagitty", quietly = TRUE)) {
    stop('Publishing a DAG requires the dagitty package. install.packages("dagitty")', call. = FALSE)
  }
  graph <- if (inherits(object, "tidy_dagitty")) object$dag else object
  if (!inherits(graph, "dagitty")) stop("This tidy_dagitty holds no dagitty graph.", call. = FALSE)
  type <- dagitty::graphType(graph)
  if (!identical(type, "dag")) {
    stop("Only DAGs publish as a DAG; this graph is a ", type, ".", call. = FALSE)
  }
  graph
}

# Display labels by node name: ggdag's labels (the graph's `labels`
# attribute, set by dagify(labels = ) or label<-, and a tidy_dagitty's label
# column), then `labels`, which wins. Only names of nodes, and only
# non-empty labels, are kept.
#' @keywords internal
.fw_dag_labels <- function(object, graph, labels = NULL) {
  found <- attr(graph, "labels")
  if (inherits(object, "tidy_dagitty") && is.data.frame(object$data) &&
      all(c("name", "label") %in% names(object$data))) {
    data <- unique(object$data[c("name", "label")])
    found <- c(found, stats::setNames(as.character(data$label), as.character(data$name)))
  }
  if (!is.null(labels)) {
    checkmate::assert_character(labels, names = "unique", any.missing = FALSE)
    found <- c(found, labels)
  }
  if (!length(found) || is.null(names(found))) return(NULL)
  found <- found[!is.na(found) & nzchar(trimws(found)) & names(found) %in% names(graph)]
  # The last value for a name wins
  found <- found[!duplicated(names(found), fromLast = TRUE)]
  if (!length(found)) return(NULL)
  as.list(found[order(names(found))])
}

# What dagitty computes from the graph, or NULL. Adjustment sets need an
# exposure and an outcome: [[]] means no adjustment is needed and [] means
# no set of observed variables works. Implications are the testable
# conditional independencies. Whatever dagitty can't compute is left out.
#' @keywords internal
.fw_dag_analysis <- function(graph, effect = "total") {
  analysis <- list()
  if (length(dagitty::exposures(graph)) && length(dagitty::outcomes(graph))) {
    sets <- tryCatch(dagitty::adjustmentSets(graph, type = "minimal", effect = effect),
                     error = function(e) NULL)
    if (!is.null(sets)) {
      analysis$effect <- effect
      analysis$adjustment_sets <- unname(lapply(sets, function(set) I(sort(as.character(set)))))
    }
  }
  implications <- tryCatch(dagitty::impliedConditionalIndependencies(graph), error = function(e) NULL)
  if (!is.null(implications)) {
    analysis$implications <- unname(lapply(implications, function(ci) {
      list(x = as.character(ci$X), y = as.character(ci$Y), given = I(as.character(ci$Z)))
    }))
  }
  if (length(analysis)) analysis else NULL
}

# Whether ggdag is loaded. A stub point for tests.
#' @keywords internal
.fw_dag_ggdag_loaded <- function() {
  isNamespaceLoaded("ggdag")
}

# Which way y points in the graph's coordinates: "up" as ggdag draws them,
# "down" as dagitty::plot() and dagitty.net do. "auto" infers it from what
# the user could have seen: a tidy_dagitty is ggdag's, and a dagitty graph
# is too while ggdag is loaded. Otherwise only dagitty::plot() drew it.
#' @keywords internal
.fw_dag_y <- function(object, y = "auto") {
  if (!identical(y, "auto")) return(y)
  if (inherits(object, "tidy_dagitty") || .fw_dag_ggdag_loaded()) "up" else "down"
}

# DAGitty text with each pos y negated, so y points down as DAGitty and
# Framework Cloud read it. Only pos values change, each keeping dagitty's
# formatting: "1.000" becomes "-1.000", "-1.000" becomes "1.000", and a
# zero is written without a sign, never as "-0.000".
#' @keywords internal
.fw_dag_flip_y <- function(text) {
  pattern <- 'pos="([^",]+),([^",]+)"'
  matches <- gregexpr(pattern, text, perl = TRUE)
  regmatches(text, matches) <- lapply(regmatches(text, matches), function(found) {
    if (!length(found)) return(found)
    x <- sub(pattern, "\\1", found, perl = TRUE)
    y <- trimws(sub(pattern, "\\2", found, perl = TRUE))
    value <- suppressWarnings(as.numeric(y))
    flipped <- ifelse(is.na(value), y, ifelse(value == 0, sub("^[-+]", "", y),
                      ifelse(startsWith(y, "-"), substring(y, 2L), paste0("-", sub("^\\+", "", y)))))
    sprintf('pos="%s,%s"', x, flipped)
  })
  text
}

# The framework.artifact/v1 dag document for a dagitty or tidy_dagitty object.
#' @keywords internal
.fw_dag_document <- function(object, code = NULL, labels = NULL, effect = c("total", "direct"),
                             y = c("auto", "up", "down")) {
  effect <- match.arg(effect)
  y <- match.arg(y)
  checkmate::assert_character(code, any.missing = FALSE, null.ok = TRUE)
  graph <- .fw_dag_graph(object)
  # as.character() keeps roles and pos; a graph without positions gets none,
  # and Framework Cloud lays it out. Positions drawn with y up are flipped.
  text <- paste(as.character(graph), collapse = "\n")
  if (identical(.fw_dag_y(object, y), "up")) text <- .fw_dag_flip_y(text)
  document <- list(schema = "framework.artifact/v1", kind = "dag",
                   source = list(language = "r", class = as.list(class(object))),
                   dagitty = text)
  document$labels <- .fw_dag_labels(object, graph, labels)
  if (length(code)) {
    text <- sub("\n+$", "", gsub("\r\n?", "\n", paste(code, collapse = "\n")))
    if (nzchar(trimws(text))) document$code <- list(language = "r", text = text)
  }
  document$analysis <- .fw_dag_analysis(graph, effect)
  structure(document, class = "framework_dag")
}

#' Publish a DAG
#'
#' Publishes a causal diagram to Framework Cloud as a DAG artifact: a dagitty
#' graph, or a ggdag `tidy_dagitty`, with its labels, the code that built it,
#' and what dagitty computes from it. [publish()] takes the same objects with
#' the defaults; `publish_dag()` adds the code, labels, and effect.
#'
#' The DAG is sent as DAGitty model text (`as.character(dag)`), which keeps
#' exposures, outcomes, latent, adjusted, and selected nodes, and positions
#' set with `coordinates()` or `dagify(coords = )`. Framework Cloud lays out
#' a graph without positions. A reader can copy the text into dagitty.net or
#' `dagitty::dagitty()` and get the same graph back.
#'
#' Positions keep the picture drawn in R. ggdag draws y pointing up, and
#' `dagitty::plot()`, dagitty.net, and Framework Cloud draw it pointing down.
#' By default (`y = "auto"`), a `tidy_dagitty`, or a dagitty graph published
#' while ggdag is loaded, has its y positions negated in the DAGitty text; a
#' dagitty graph published without ggdag keeps them.
#'
#' When the graph has an exposure and an outcome, the minimal sufficient
#' adjustment sets from `dagitty::adjustmentSets()` are included, and the
#' testable implications from `dagitty::impliedConditionalIndependencies()`
#' always are. A computation that fails is left out.
#'
#' @param dag A `dagitty` graph, as from `dagitty::dagitty()` or
#'   `ggdag::dagify()`, or a ggdag `tidy_dagitty`. Only DAGs publish; a
#'   pdag, mag, or pag is an error.
#' @param code The R code that built the graph, as a string or lines. Shown
#'   with the DAG. Default: none.
#' @param labels Display labels by node name, as a named character vector:
#'   `c(smoking = "Smoking status")`. Labels set with ggdag
#'   (`dagify(labels = )`, `label<-`, or a `tidy_dagitty`'s `label` column)
#'   are used too; these win.
#' @param effect `"total"` (the default) or `"direct"`: the effect the
#'   adjustment sets identify.
#' @param y Which way y points in the graph's positions: `"up"`, as ggdag
#'   draws them, or `"down"`, as `dagitty::plot()` does. `"up"` negates each
#'   y in the published DAGitty text. The default, `"auto"`, is `"up"` for a
#'   `tidy_dagitty` or while ggdag is loaded, and `"down"` otherwise. A graph
#'   without positions is unaffected.
#' @param slug Artifact slug. Default: `dag`. See [publish()].
#' @param title Artifact title.
#' @param description Artifact description.
#' @param visibility `"public"`, `"unlisted"`, or `"private"`. A new artifact
#'   is unlisted unless set. See [publish()].
#' @param password Password required to view the DAG on Framework Cloud.
#' @param collection Existing project collection ID or slug.
#' @param share_unlisted Consent to share an unlisted DAG with collection
#'   readers.
#' @param to Publishing destination. See [publish()].
#' @param include_private Skip the private-data confirmation. See [publish()].
#' @return The artifact URL, invisibly.
#' @seealso [publish()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' dag <- ggdag::dagify(
#'   cancer ~ smoking + age,
#'   smoking ~ age,
#'   exposure = "smoking", outcome = "cancer",
#'   labels = c(smoking = "Smoking status", cancer = "Lung cancer", age = "Age")
#' )
#' publish_dag(dag, code = "dag <- dagify(cancer ~ smoking + age, smoking ~ age)",
#'             slug = "smoking-dag", title = "Smoking and lung cancer")
#'
#' # The defaults, through publish()
#' publish(dag, slug = "smoking-dag")
#' }
#' }
publish_dag <- function(dag, code = NULL, labels = NULL, effect = c("total", "direct"),
                        y = c("auto", "up", "down"), slug = NULL, title = NULL, description = NULL, visibility = NULL,
                        password = NULL, collection = NULL, share_unlisted = FALSE, to = NULL,
                        include_private = FALSE) {
  if (!.fw_dag_is(dag)) {
    stop("publish_dag() takes a dagitty graph or a ggdag tidy_dagitty.", call. = FALSE)
  }
  document <- .fw_dag_document(dag, code = code, labels = labels, effect = match.arg(effect),
                               y = match.arg(y))
  publish(document, slug = slug, title = title, description = description,
          visibility = visibility, password = password, collection = collection,
          share_unlisted = share_unlisted, to = to, include_private = include_private)
}
