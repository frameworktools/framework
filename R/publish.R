# The message for objects publish() can't export.
#' @keywords internal
.fw_artifact_accepts <- paste(
  "publish() accepts a file or rendered folder; a data frame, tibble, data.table, matrix,",
  "table, or xtabs; an ANOVA table; a hypothesis test (htest); an lm, glm, aov, glm.nb,",
  "polr, multinom, lme4, coxph, survreg, fixest, or mgcv gam model; a ggplot, patchwork,",
  "recorded base plot, lattice plot, or htmlwidget such as plotly; or a gt, gtsummary,",
  "or flextable table."
)

# Export supported objects locally. Models publish a summary, without observations
# or serialized model internals. Cloud receives typed JSON documents (table.json,
# model.json, test.json); buckets receive CSV tables and HTML lm/glm summaries,
# and JSON for other models and tests. Figures are the same for both.
#' @keywords internal
.fw_artifact_file <- function(object, directory, cloud = FALSE) {
  if (.fw_artifact_is_figure(object)) {
    return(.fw_artifact_figure(object, directory, .fw_artifact_accepts))
  }
  if (inherits(object, "gt_tbl") || inherits(object, "gtsummary") || inherits(object, "flextable")) {
    path <- file.path(directory, "table.html")
    if (inherits(object, "gtsummary")) {
      if (!requireNamespace("gtsummary", quietly = TRUE) || !requireNamespace("gt", quietly = TRUE)) {
        stop("Publishing a gtsummary table requires gtsummary and gt.", call. = FALSE)
      }
      object <- gtsummary::as_gt(object)
    }
    if (inherits(object, "gt_tbl")) {
      if (!requireNamespace("gt", quietly = TRUE)) stop("Publishing a gt table requires gt.", call. = FALSE)
      gt::gtsave(object, path, inline_css = TRUE)
    } else {
      if (!requireNamespace("flextable", quietly = TRUE)) stop("Publishing a flextable requires flextable.", call. = FALSE)
      flextable::save_as_html(object, path = path)
    }
    return(path)
  }
  if (!cloud) {
    frame <- .fw_artifact_frame(object)
    if (!is.null(frame)) {
      path <- file.path(directory, "table.csv")
      utils::write.csv(frame, path, row.names = FALSE)
      return(path)
    }
    if (class(object)[1] %in% c("lm", "glm")) {
      path <- file.path(directory, "model.html")
      # Coefficients and aggregate fit statistics only. summary() can include
      # residuals and formulas, so never print the entire summary or model.
      model <- summary(object)
      lines <- c("Coefficients", capture.output(print(model$coefficients)),
                 "", paste("Observations:", stats::nobs(object)))
      if (!is.null(model$r.squared)) lines <- c(lines, paste("R squared:", model$r.squared))
      if (!is.null(model$aic)) lines <- c(lines, paste("AIC:", model$aic))
      escaped <- gsub("&", "&amp;", paste(lines, collapse = "\n"), fixed = TRUE)
      escaped <- gsub("<", "&lt;", escaped, fixed = TRUE)
      escaped <- gsub(">", "&gt;", escaped, fixed = TRUE)
      writeLines(paste0('<!doctype html><html><head><meta charset="utf-8">',
                       '<title>Model results</title></head><body><pre>',
                       escaped, '</pre></body></html>'), path)
      return(path)
    }
  }
  document <- .fw_artifact_structured(object)
  if (is.null(document)) stop(.fw_artifact_accepts, call. = FALSE)
  path <- file.path(directory, paste0(document$kind, ".json"))
  jsonlite::write_json(document, path, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  path
}

#' @title Publishing Functions
#' @description Functions for publishing notebooks, data, and files to S3
#'   storage or Framework Cloud.
#' @name publish
NULL

# Uploads are the user's choice, so private paths warn rather than refuse.
# Every file that would be uploaded is checked with the private-path rule
# (see .fw_path_is_private()): a folder named private or ending in _private,
# or a settings folder marked private by its key. File names don't count. Interactive sessions ask, defaulting to No, and scripts stop unless
# include_private = TRUE. framework-py and fw apply the same rule.
#
# `reasons` are other reasons to confirm, as text (see .fw_publish_reasons()):
# each is a warning, and one question covers them and the paths. Returns
# TRUE (invisibly) when the user confirmed, so callers don't ask twice, and
# FALSE when there was nothing to confirm.
#' @keywords internal
.fw_confirm_private <- function(source, include_private = FALSE, reasons = character()) {
  if (isTRUE(include_private)) {
    return(invisible(TRUE))
  }
  paths <- source
  if (length(source) == 1L && dir.exists(source)) {
    paths <- c(source, list.files(source, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  }
  paths <- normalizePath(path.expand(paths), winslash = "/", mustWork = FALSE)
  flagged <- paths[.fw_path_is_private(paths)]
  if (length(flagged) == 0 && length(reasons) == 0) {
    return(invisible(FALSE))
  }
  if (length(flagged) > 0) {
    shown <- utils::head(flagged, 5)
    if (length(flagged) > 5) {
      shown <- c(shown, sprintf("... and %d more", length(flagged) - 5))
    }
    warning(
      sprintf("%d file(s) to upload are in private folders:\n", length(flagged)),
      paste0("  ", shown, collapse = "\n"),
      call. = FALSE, immediate. = TRUE
    )
  }
  for (reason in reasons) warning(reason, call. = FALSE, immediate. = TRUE)
  if (rlang::is_interactive()) {
    answer <- utils::askYesNo(if (length(reasons)) "Upload anyway?" else "Upload them anyway?", default = FALSE)
    if (isTRUE(answer)) {
      return(invisible(TRUE))
    }
    stop("Cancelled: nothing was published.", call. = FALSE)
  }
  stop(sprintf(paste(
    "Not uploading %s without confirmation.",
    "Review it, then pass include_private = TRUE to upload it."
  ), if (length(flagged) > 0) "files from private folders" else "this"), call. = FALSE)
}

# Why publishing `source` needs confirmation beyond its path, as text: in a
# project with `security: sensitive: true`, every notebook (.qmd, .Rmd,
# .ipynb) and every object; in any project, a notebook whose code names
# private data. framework-py's sensitive_reasons() and notebook_reasons()
# give the same reasons.
#' @keywords internal
.fw_publish_reasons <- function(source) {
  if (is.character(source) && is.null(dim(source))) {
    if (length(source) != 1L || !file.exists(source) || dir.exists(source) ||
        !tolower(tools::file_ext(source)) %in% c("qmd", "rmd", "ipynb")) {
      return(character())
    }
    name <- basename(source)
    reasons <- .fw_sensitive_reasons(paste("the rendered notebook", name))
    reads <- .fw_notebook_private_reads(source)
    if (length(reads)) {
      shown <- paste(utils::head(reads, 3), collapse = ", ")
      if (length(reads) > 3) shown <- sprintf("%s, and %d more", shown, length(reads) - 3)
      reasons <- c(reasons, sprintf("%s reads private data: %s.", name, shown))
    }
    return(reasons)
  }
  what <- if (is.data.frame(source)) "this data frame" else paste("this", class(source)[1])
  .fw_sensitive_reasons(what)
}

# The reason to confirm publishing `what` in a sensitive project, or none
#' @keywords internal
.fw_sensitive_reasons <- function(what) {
  settings <- tryCatch(settings_read(), error = function(e) NULL)
  if (!isTRUE(settings$security$sensitive)) return(character())
  sprintf(paste(
    "This project holds sensitive data (security: sensitive: true), and %s can show it.",
    "Check that it holds only results that may be shared."
  ), what)
}

# The quoted strings in a notebook's code that name private data, in order of
# appearance, once each. A string counts when it is a path (it has a / or \)
# with a private folder part, or under a settings folder marked private (see
# .fw_private_path_string()), or when it is a data catalog name whose entry
# data_info() reports as private.
# Settings keys and other strings ("private|public") don't count. A quick
# text check, like framework-py's notebook_private_reads(): data reached any
# other way is not found.
#' @keywords internal
.fw_notebook_private_reads <- function(path) {
  code <- tryCatch(.fw_notebook_code(path), error = function(e) "")
  if (!nzchar(code)) return(character())
  pattern <- "\"((?:[^\"\\\\\\n]|\\\\.)*)\"|'((?:[^'\\\\\\n]|\\\\.)*)'"
  matches <- regmatches(code, gregexpr(pattern, code, perl = TRUE))[[1]]
  strings <- unique(substring(matches, 2L, nchar(matches) - 1L))
  strings <- strings[nzchar(strings) & nchar(strings) <= 500L]
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  private_dirs <- .fw_private_directories(root)
  settings <- NULL
  found <- character()
  for (value in strings) {
    if (.fw_private_path_string(value, root, private_dirs)) {
      found <- c(found, value)
    } else if (grepl("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_-]+)+$", value)) {
      settings <- settings %||% tryCatch(settings_read(), error = function(e) list())
      parts <- strsplit(value, ".", fixed = TRUE)[[1]]
      if (is.null(settings$data) || is.null(.data_catalog_find(settings$data, parts))) next
      info <- tryCatch(data_info(value), error = function(e) NULL)
      if (isTRUE(info$private)) found <- c(found, value)
    }
  }
  found
}

# The code of a .qmd, .Rmd, or .ipynb file. Quarto and R Markdown files are
# read whole: prose rarely quotes a path, and chunk options can name data.
# For .ipynb, only code cells.
#' @keywords internal
.fw_notebook_code <- function(path) {
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (tolower(tools::file_ext(path)) != "ipynb") return(text)
  cells <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE)$cells, error = function(e) NULL)
  code <- vapply(Filter(function(cell) is.list(cell) && identical(cell$cell_type, "code"), cells %||% list()),
                 function(cell) paste(unlist(cell$source), collapse = ""), character(1))
  paste(code, collapse = "\n")
}

# Arguments that mean something only for buckets or Framework Cloud
#' @keywords internal
.fw_pages_reject <- function(dest = NULL, connection = NULL, slug = NULL) {
  given <- c(
    dest = !is.null(dest),
    connection = !is.null(connection),
    "slug = TRUE/FALSE" = is.logical(slug)
  )
  if (any(given)) {
    stop(
      "Not used with to = \"github\": ", paste(names(given)[given], collapse = ", "),
      ". Name the published folder with slug = \"...\".",
      call. = FALSE
    )
  }
}

# `slug` is a non-empty string, a flag, or NULL.
#' @keywords internal
.fw_assert_slug <- function(slug) {
  checkmate::assert(
    checkmate::check_null(slug),
    checkmate::check_flag(slug),
    checkmate::check_string(slug, min.chars = 1),
    .var.name = "slug"
  )
}

#' @keywords internal
.fw_warn_slug_ignored <- function(slug) {
  if (!is.null(slug)) {
    warning("`slug` applies to Framework Cloud only; ignored for storage buckets.", call. = FALSE)
  }
}

# The `title:` in a Quarto or R Markdown document's YAML front matter, or
# NULL. Publishing uses it as the default title instead of the file name.
.fw_doc_title <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path) || dir.exists(path)) return(NULL)
  if (!tolower(tools::file_ext(path)) %in% c("qmd", "rmd")) return(NULL)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  start <- which(trimws(lines) != "")[1]
  if (is.na(start) || trimws(lines[start]) != "---") return(NULL)
  end <- which(trimws(lines) %in% c("---", "..."))
  end <- end[end > start][1]
  if (is.na(end) || end == start + 1L) return(NULL)
  front <- tryCatch(yaml::yaml.load(paste(lines[(start + 1L):(end - 1L)], collapse = "\n")),
                    error = function(e) NULL)
  title <- if (is.list(front)) front$title else NULL
  if (is.character(title) && length(title) == 1L && !is.na(title) && nzchar(trimws(title))) trimws(title) else NULL
}

# Where publish() and publish_notebook() send output. A named connection or
# any configured storage bucket wins; otherwise a project set up from
# Framework Cloud publishes there.
#' @keywords internal
.fw_publish_target <- function(connection = NULL, to = NULL) {
  if (identical(to, "cloud")) {
    if (!is.null(connection)) stop('connection cannot be used with to = "cloud".', call. = FALSE)
    return("cloud")
  }
  if (identical(to, "bucket")) return("s3")
  if (!is.null(connection) || .fw_has_storage_buckets()) {
    return("s3")
  }
  if (!is.null(.fw_project_token())) {
    return("cloud")
  }
  stop(
    "Nowhere to publish. Add a storage bucket in settings.yml, or set up this ",
    'project from Framework Cloud with setup("<project token>").

',
    "A storage bucket looks like this:

",
    "connections:
",
    "  storage_buckets:
",
    "    my_s3:
",
    "      bucket: my-bucket
",
    "      region: us-east-1
",
    "  default_storage_bucket: my_s3",
    call. = FALSE
  )
}

#' Publish files and artifacts
#'
#' Publish files, directories, and R objects to named Cloud, GitHub, folder,
#' or S3 destinations. `publish_notebook()` renders Quarto documents.
#' `publish_data()` retains the low-level bucket export API.
#'
#' With no `connection` and no storage bucket in settings.yml, a project set
#' up from Framework Cloud publishes to its server instead (the
#' `FW_CLOUD_URL` and `FW_PROJECT_TOKEN` in the project's `.env`). Each
#' publish to Framework Cloud adds a new version of the document. Cloud
#' provides owner-only access, public and unlisted links, and password protection.
#' A new artifact is unlisted. Set `visibility = "public"` for a readable URL
#' (`/@handle/project/slug`).
#'
#' @param source A local file or rendered directory path, or an R object.
#'   `publish()` converts these objects to files:
#'   * Data frames, tibbles, data.tables, matrices, and `table` or `xtabs`
#'     contingency tables become a table with every row, a profile of each
#'     column, and variable labels from `attr(x, "label")`. Row names that
#'     aren't 1 to n become a first column named `row`.
#'   * `anova()` results and `summary(aov)` become an ANOVA table.
#'   * Hypothesis tests (`htest` objects from `t.test()`, `chisq.test()`,
#'     `wilcox.test()`, `cor.test()`, `prop.test()`, `fisher.test()`,
#'     `shapiro.test()`, and similar) become a test summary with the method,
#'     statistic, parameters, p-value, estimates, and confidence interval.
#'     The data name is left out.
#'   * `lm`, `glm`, `aov`, `MASS::glm.nb`, `MASS::polr`, `nnet::multinom`,
#'     lme4 (`lmer`, `glmer`), `survival::coxph`, `survival::survreg`,
#'     fixest, and `mgcv::gam` models become coefficients with standard
#'     errors and 95% Wald intervals, fit statistics, and a description of
#'     the model. Mixed models add random effects and gam models add smooth
#'     terms. Models never carry observations, residuals, fitted values, or
#'     the model object itself.
#'   * ggplot and patchwork plots, base graphics saved with `recordPlot()`,
#'     and lattice plots become an SVG figure (7 by 5 inches, white
#'     background) when svglite is installed, otherwise a 300 dpi PNG. An SVG
#'     larger than 5 MB is replaced by a PNG.
#'   * plotly and other htmlwidgets become a self-contained HTML file, which
#'     needs pandoc (Quarto's copy is used when pandoc isn't on the PATH).
#'   * gt, gtsummary, and flextable tables become HTML when their packages
#'     are installed.
#'
#'   Framework Cloud receives tables, tests, and models as structured JSON.
#'   Legacy storage uploads receive CSV tables, HTML summaries for `lm` and
#'   `glm`, and JSON for other models and tests. Named destinations receive
#'   typed bundles with offline readers and SHA-256 file manifests.
#' @param dest Character or NULL. Destination path in S3 bucket. If NULL,
#'   derives from source filename. On Framework Cloud, use `slug` instead;
#'   `dest` still names the document there when `slug` isn't a string, for
#'   older scripts.
#' @param connection Character or NULL. S3 connection name from config.yml.
#'   If NULL, uses the connection marked with `default: true`.
#' @param overwrite Logical. Whether to overwrite existing files. Default TRUE.
#' @param self_contained Logical. When publishing to Framework Cloud, whether
#'   to bundle an HTML file with its resources. Ignored for S3. Default TRUE.
#' @param include_private Logical. Skip the private-path check. When the
#'   path of any file to upload has a folder named `private` or ending in
#'   `_private` (in any case; file names don't count), or is under a settings
#'   folder whose key contains `private` and not `public`
#'   (`outputs_private_tables`), Framework warns
#'   and, in an interactive session, asks before publishing (default No).
#'   In a non-interactive session it stops unless `include_private = TRUE`.
#'   The same confirmation covers a notebook (`.qmd`, `.Rmd`, `.ipynb`) or an
#'   object such as a data frame in a project with `security: sensitive: true`,
#'   and, in any project, a notebook whose code quotes a path in a private
#'   folder or a data catalog name whose entry is private.
#' @param to Named destination from `publish.destinations`, or a driver name.
#'   `publish.default` selects the default destination. `"folder"` needs a named
#'   destination with a path. A folder destination with `layout: site-root`
#'   keeps only the latest publish, at the folder's root (for a GitHub Pages
#'   `docs/` folder), recorded in `.framework-site.json`; the default layout,
#'   `versioned`, keeps every version under `<slug>/v/<n>/`. `"s3"` and `"bucket"` retain legacy storage uploads.
#'   `"cloud"` selects Framework Cloud even when a
#'   bucket is configured. `"bucket"` selects storage. `"github"` publishes to the project's GitHub
#'   Pages site instead of a storage bucket or Framework Cloud: the document
#'   is bundled under `published/<slug>/`. The artifact, version archives, and
#'   site index are committed and pushed. The
#'   site deploys from the default branch once "Publish with GitHub Pages" is
#'   on for the project in Framework Cloud, and it is public even when the
#'   repository is private, so an interactive session asks first. `slug`
#'   names the folder. Runs of characters outside lowercase letters and digits
#'   become `-`. The
#'   default is the file name lowercased, with other characters as `-`
#'   ("Final Report (v2).html" becomes `final-report-v2`). A folder needs an
#'   `index.html` at its top. `dest`, `connection`, and a `TRUE`/`FALSE`
#'   `slug` are errors here.
#' @param slug Framework Cloud only. A string names the document, for
#'   example `slug = "main-results"`. It does not change visibility: a new
#'   artifact is unlisted and an existing one keeps its visibility. `TRUE`
#'   makes the artifact public under the name derived from `dest` or the file
#'   name, and `FALSE` makes it unlisted. `NULL` (the default) publishes
#'   under the derived name. Ignored, with a warning, for S3. With
#'   `to = "github"`, a string names the folder under `published/`.
#' @param title Artifact title. Default: a Quarto or R Markdown document's
#'   YAML `title`, else the file name.
#' @param description Artifact description.
#' @param kind Optional artifact kind override.
#' @param password Password required to view the artifact on Framework Cloud.
#' @param visibility Artifact visibility: `"public"`, `"unlisted"`, or `"private"`.
#'   Set `"public"` for a readable URL. An explicit visibility wins over a
#'   `TRUE` or `FALSE` `slug`. Without one, a new artifact is unlisted.
#'   Unsupported access controls fail before delivery. Private folder and S3
#'   destinations use `visibility: private` and destination access controls.
#'   `private: true` remains a compatibility alias. S3 requires API confirmation
#'   of a non-public bucket policy and Public Access Block settings.
#' @param collection Existing project collection ID or slug. Follows the latest artifact version.
#' @param share_unlisted Explicit consent to share an unlisted artifact with collection readers.
#' @return Character. Published URLs, or the local path for a folder without a URL.
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Upload a single file
#' publish("outputs/report.html")
#' # -> https://bucket.s3.region.amazonaws.com/prefix/report.html
#'
#' # Upload with custom destination
#' publish("outputs/report.html", dest = "reports/q4-2024.html")
#'
#' # Upload a directory
#' publish("outputs/charts/", dest = "reports/charts/")
#'
#' # Use specific connection
#' publish("data.csv", connection = "s3_backup")
#'
#' # Framework Cloud: a new version with a readable URL
#' publish("outputs/report.html", slug = "main-results", visibility = "public")
#'
#' # GitHub Pages: commits published/main-results/ and pushes it
#' publish("outputs/report.html", to = "github", slug = "main-results")
#' }
#' }
publish <- function(source, dest = NULL, connection = NULL, overwrite = TRUE,
                    self_contained = TRUE, slug = NULL, include_private = FALSE,
                    to = NULL, title = NULL, description = NULL, kind = NULL,
                    password = NULL, visibility = NULL, collection = NULL, share_unlisted = FALSE) {
  checkmate::assert_flag(share_unlisted)
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(self_contained)
  checkmate::assert_flag(include_private)
  .fw_assert_slug(slug)
  if (is.character(source) && is.null(dim(source))) {
    checkmate::assert_string(source, min.chars = 1)
    if (!file.exists(source)) stop("Source not found: ", source, call. = FALSE)
    # Asked once: a confirmed publish isn't asked again further down
    if (isTRUE(.fw_confirm_private(source, include_private, .fw_publish_reasons(source)))) include_private <- TRUE
    title <- title %||% .fw_doc_title(source)
  } else if (isTRUE(.fw_confirm_private(character(), include_private, .fw_publish_reasons(source)))) {
    include_private <- TRUE
  }
  if (share_unlisted && is.null(collection)) stop("share_unlisted requires a collection.", call. = FALSE)
  destination <- .fw_publish_destination(to, connection)
  visibility <- .fw_publish_visibility(destination, visibility)
  .fw_publish_capabilities(destination, visibility, password, collection)
  if (!isTRUE(destination$legacy) && destination$driver != "cloud") {
    return(.fw_publish_bundle(source, destination, dest, connection, overwrite,
                              self_contained, slug, include_private, title,
                              description, kind, password, visibility, collection))
  }
  bundle <- .fw_bundle_build(source, slug, title, description, kind, self_contained, include_private)
  on.exit(unlink(bundle$path, recursive = TRUE), add = TRUE)
  if (destination$driver == "cloud") to <- "cloud"
  if (isTRUE(destination$legacy) && identical(to, "s3")) to <- "bucket"
  if (share_unlisted && is.null(collection)) stop("share_unlisted requires a collection.", call. = FALSE)
  if (!is.character(source) || !is.null(dim(source))) {
    stage <- tempfile("fw_artifact_")
    dir.create(stage)
    on.exit(unlink(stage, recursive = TRUE), add = TRUE)
    is_cloud <- !identical(to, "github") && identical(.fw_publish_target(connection, to), "cloud")
    source <- .fw_artifact_file(source, stage, cloud = is_cloud)
    if (is_cloud && is.null(kind) && basename(source) %in% c("table.json", "model.json", "test.json", "table.html")) {
      kind <- switch(basename(source), model.json = "model", test.json = "test", "table")
    }
  }
  checkmate::assert_string(source, min.chars = 1)
  checkmate::assert_string(dest, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(connection, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(share_unlisted)
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(self_contained)
  .fw_assert_slug(slug)
  checkmate::assert_flag(include_private)

  if (!file.exists(source) && !dir.exists(source)) {
    stop(sprintf("Source not found: %s", source), call. = FALSE)
  }
  checkmate::assert_choice(to, c("cloud", "bucket", "github"), null.ok = TRUE)
  .fw_confirm_private(source, include_private)

  if (destination$driver == "cloud" && tolower(tools::file_ext(source)) %in% c("qmd", "rmd")) {
    source <- if (self_contained) file.path(bundle$path, "index.html") else bundle$path
    if (is.null(slug)) dest <- dest %||% bundle$manifest$slug
  }
  metadata <- list(title, description, kind, password, visibility, collection)
  if (identical(to, "github")) {
    if (any(!vapply(metadata, is.null, logical(1)))) {
      stop("Artifact metadata requires publishing to Framework Cloud.", call. = FALSE)
    }
    .fw_pages_reject(dest = dest, connection = connection, slug = slug)
    return(.fw_github_publish(source, slug = slug, self_contained = self_contained))
  }
  if (identical(.fw_publish_target(connection, to), "cloud")) {
    return(.fw_cloud_publish(source, dest = dest, self_contained = self_contained, slug = slug,
                             title = title, description = description, kind = kind,
                             password = password, visibility = visibility,
                             collection = collection, share_unlisted = share_unlisted))
  }
  .fw_warn_slug_ignored(slug)

  # Resolve S3 connection
  s3_config <- .resolve_s3_connection(connection)

  # Determine destination
  if (is.null(dest)) {
    dest <- basename(source)
  }

  # Upload file or directory
  if (dir.exists(source)) {
    urls <- .s3_upload_dir(source, dest, s3_config)
    message(sprintf("Published %d files to S3", length(urls)))
  } else {
    urls <- .s3_upload_file(source, dest, s3_config)
    message(sprintf("Published: %s", urls))
  }

  .fw_track_external(bundle, list(driver = "s3", url = if (length(urls)) urls[[1]] else NULL,
                                  version_url = NULL, version = 1L), visibility)
  invisible(urls)
}


#' Publish a Quarto notebook to S3 or Framework Cloud
#'
#' Renders a Quarto document and uploads it to S3. The notebook is rendered
#' to a temporary directory, uploaded, then cleaned up.
#'
#' Publishing follows [publish()]: a named `connection` or a configured
#' storage bucket comes first, then Framework Cloud when the project was set
#' up from it. Framework Cloud takes HTML output only, adds a new version on
#' each publish, and uses `slug` as [publish()] does.
#'
#' The URL format depends on the S3 connection's `static_hosting` setting:
#' - `static_hosting: true` -> uploads to `dest/index.html`, returns `dest/`
#' - `static_hosting: false` (default) -> uploads as `dest.html`, returns `dest.html`
#'
#' @param file Character. Path to .qmd file.
#' @param dest Character or NULL. Destination path in S3 (without extension).
#'   If NULL, derives from filename (e.g., "analysis.qmd" -> "analysis"). On
#'   Framework Cloud, use `slug` instead.
#' @param connection Character or NULL. S3 connection name, or NULL for default.
#' @param self_contained Logical. Whether to embed all resources. Default TRUE.
#'   Ignored if `static_hosting: false` (always renders self-contained).
#' @param format Character. Output format. Default "html".
#' @param include_private Logical. Skip the private-path check. When the
#'   path of any file to upload has a folder named `private` or ending in
#'   `_private` (in any case; file names don't count), or is under a settings
#'   folder whose key contains `private` and not `public`
#'   (`outputs_private_tables`), Framework warns
#'   and, in an interactive session, asks before publishing (default No).
#'   In a non-interactive session it stops unless `include_private = TRUE`.
#'   It also asks for every notebook in a project with
#'   `security: sensitive: true`, and for a notebook whose code names private
#'   data, as [publish()] does.
#' @param slug Framework Cloud only: name the document. It does not make
#'   the document public. See [publish()]. With `to = "github"`, names the folder
#'   under `published/`.
#' @param to Character or NULL. `"cloud"` selects Framework Cloud and `"bucket"`
#'   selects storage. `"github"` publishes the rendered HTML to the
#'   project's GitHub Pages site. See [publish()].
#' @param collection Existing project collection ID or slug. Follows the latest artifact version.
#' @param share_unlisted Explicit consent to share an unlisted artifact with collection readers.
#' @param title Character or NULL. The published title. Default: the
#'   document's YAML `title`, else its file name.
#' @param description Character or NULL. A short description of the
#'   published document.
#' @param ... Additional arguments passed to quarto render.
#' @return Character. Public URL of the published notebook.
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # With static_hosting: true -> returns /analysis/
#' # With static_hosting: false -> returns /analysis.html
#' publish_notebook("notebooks/analysis.qmd")
#'
#' # Publish to specific location
#' publish_notebook("notebooks/analysis.qmd", dest = "reports/2024/q4")
#'
#' # Publish non-self-contained (only with static_hosting: true)
#' publish_notebook("notebooks/analysis.qmd", self_contained = FALSE)
#' }
#' }
publish_notebook <- function(file,
                             dest = NULL,
                             connection = NULL,
                             self_contained = TRUE,
                             format = "html",
                             slug = NULL,
                             include_private = FALSE,
                             to = NULL,
                             collection = NULL,
                             share_unlisted = FALSE,
                             title = NULL,
                             description = NULL,
                             ...) {
  checkmate::assert_file_exists(file, extension = c("qmd", "Qmd", "QMD"))
  checkmate::assert_string(title, null.ok = TRUE)
  checkmate::assert_string(description, null.ok = TRUE)
  if (isTRUE(.fw_confirm_private(file, include_private, .fw_publish_reasons(file)))) include_private <- TRUE
  title <- title %||% .fw_doc_title(file)
  destination <- .fw_publish_destination(to, connection)
  if (!isTRUE(destination$legacy) || destination$driver == "cloud") {
    if (!identical(format, "html")) stop("Static publishing requires HTML output.", call. = FALSE)
    return(publish(file, dest = dest, connection = connection, self_contained = self_contained,
                   slug = slug, include_private = include_private, to = to,
                   collection = collection, share_unlisted = share_unlisted,
                   title = title, description = description))
  }
  if (destination$driver == "cloud") to <- "cloud"
  if (isTRUE(destination$legacy) && identical(to, "s3")) to <- "bucket"
  checkmate::assert_flag(share_unlisted)
  if (share_unlisted && is.null(collection)) stop("share_unlisted requires a collection.", call. = FALSE)
  if (!is.null(collection) && identical(to, "github")) {
    stop("Collections require publishing to Framework Cloud.", call. = FALSE)
  }
  checkmate::assert_file_exists(file, extension = c("qmd", "Qmd", "QMD"))
  checkmate::assert_string(dest, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(connection, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(self_contained)
  checkmate::assert_string(format, min.chars = 1)
  .fw_assert_slug(slug)
  checkmate::assert_flag(include_private)
  checkmate::assert_choice(to, c("cloud", "bucket", "github"), null.ok = TRUE)
  .fw_confirm_private(file, include_private)

  if (identical(to, "github")) {
    if (!identical(format, "html")) {
      stop("GitHub Pages publishes HTML only (got format = \"", format, "\").", call. = FALSE)
    }
    .fw_pages_reject(dest = dest, connection = connection, slug = slug)
    return(.fw_github_publish(file, slug = slug, self_contained = self_contained))
  }

  # Check quarto is available
  quarto_path <- Sys.which("quarto")
  if (nchar(quarto_path) == 0) {
    stop("Quarto not found. Install from https://quarto.org/docs/get-started/", call. = FALSE)
  }

  if (identical(.fw_publish_target(connection, to), "cloud")) {
    if (!identical(format, "html")) {
      stop("Framework Cloud publishes HTML only (got format = \"", format, "\").", call. = FALSE)
    }
    return(.fw_cloud_publish(file, dest = dest, self_contained = self_contained, slug = slug,
                             title = title, description = description,
                             collection = collection, share_unlisted = share_unlisted))
  }
  if (!is.null(collection)) stop("Collections require publishing to Framework Cloud.", call. = FALSE)
  .fw_warn_slug_ignored(slug)

  # Resolve S3 connection early to fail fast
  s3_config <- .resolve_s3_connection(connection)

  # Determine behavior based on static_hosting
  static_hosting <- isTRUE(s3_config$static_hosting)

  # Without static hosting, always use self-contained single file
  if (!static_hosting) {
    self_contained <- TRUE
  }

  # Create temp directory for output
  temp_dir <- tempfile("publish_notebook_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  # Build quarto render command
  args <- c(
    "render",
    shQuote(normalizePath(file)),
    "--output-dir", shQuote(temp_dir),
    "--to", format
  )

  if (self_contained) {
    args <- c(args, "--embed-resources")
  }

  # Execute render
  message(sprintf("Rendering %s...", basename(file)))
  result <- system2(quarto_path, args, stdout = TRUE, stderr = TRUE)

  # Check for errors
  status <- attr(result, "status")
  if (!is.null(status) && status != 0) {
    stop("Quarto render failed:\n", paste(result, collapse = "\n"), call. = FALSE)
  }

  # Keep only the page and its _files folder. Inside a Quarto project,
  # Quarto keeps the source folder under --output-dir (notebooks/x.qmd ->
  # <tmp>/notebooks/x.html) and mirrors resources such as outputs/ there.
  output_root <- tempfile("publish_page_")
  dir.create(output_root)
  on.exit(unlink(output_root, recursive = TRUE), add = TRUE)
  main_output <- .fw_stage_rendered_page(temp_dir, file, output_root)

  # Determine base destination (without extension)
  if (is.null(dest)) {
    base_dest <- tools::file_path_sans_ext(basename(file))
  } else {
    # Strip any trailing slash or .html extension from user-provided dest
    base_dest <- sub("/$", "", dest)
    base_dest <- sub("\\.html$", "", base_dest)
  }

  bundle <- .fw_bundle_build(main_output, slug = base_dest, title = title,
                             description = description, include_private = TRUE)
  on.exit(unlink(bundle$path, recursive = TRUE), add = TRUE)
  # Upload based on static_hosting setting
  if (static_hosting) {
    # Static hosting: upload to dest/index.html, return dest/
    upload_path <- paste0(base_dest, "/index.html")

    if (self_contained) {
      url <- .s3_upload_file(main_output, upload_path, s3_config)
    } else {
      # Upload entire directory (including _files folder)
      # Rename main file to index.html if needed
      if (basename(main_output) != "index.html") {
        new_path <- file.path(output_root, "index.html")
        file.rename(main_output, new_path)
      }
      urls <- .s3_upload_dir(output_root, base_dest, s3_config)
      url <- urls[grepl("index\\.html$", urls)][1]
      message(sprintf("Published %d files", length(urls)))
    }

    # Return clean directory URL (without index.html)
    clean_url <- .s3_public_url(paste0(base_dest, "/"), s3_config)
    message(sprintf("Published: %s", clean_url))
    invisible(clean_url)

  } else {
    # No static hosting: upload as dest.html, return dest.html
    upload_path <- paste0(base_dest, ".html")
    url <- .s3_upload_file(main_output, upload_path, s3_config)
    message(sprintf("Published: %s", url))
    invisible(url)
  }
}


#' Publish data to S3 or a named destination
#'
#' Uploads a data frame or existing data file. Like [publish()], it follows
#' `to`, then `publish.default` in settings.yml. S3 destinations, an explicit
#' `connection`, and projects without `publish.default` get a plain upload to
#' the storage bucket at `dest`. Folder, GitHub, and Cloud destinations
#' publish the file with [publish()]. The slug is `dest` without its
#' extension, with each `/` turned into `-`, then normalized like every slug
#' (lowercase, each run of other characters a `-`): `"tables/bp_by_visit.csv"`
#' publishes as `tables-bp-by-visit`. The message says which slug was used.
#'
#' @param data Data frame or character path to existing file.
#' @param dest Character. Destination path in S3 (required for data frames).
#'   For other destinations, its file name names the file, and the path
#'   without its extension, with `/` turned into `-`, is the slug.
#' @param format Character. Output format when `data` is a data frame:
#'   "csv", "rds", "parquet", or "json". Default "csv".
#' @param connection Character or NULL. S3 connection name, or NULL for default.
#' @param compress Logical. Whether to gzip compress. Default FALSE.
#' @param include_private Logical. Skip the private-path check. When the
#'   path of any file to upload has a folder named `private` or ending in
#'   `_private` (in any case; file names don't count), or is under a settings
#'   folder whose key contains `private` and not `public`
#'   (`outputs_private_tables`), Framework warns
#'   and, in an interactive session, asks before publishing (default No).
#'   In a non-interactive session it stops unless `include_private = TRUE`.
#'   A data frame in a project with `security: sensitive: true` is confirmed
#'   the same way.
#' @param to Character or NULL. Named destination from
#'   `publish.destinations`, or a driver name, as in [publish()]. Default:
#'   `publish.default`.
#' @return Character. Public URL of the published data (for a folder
#'   destination without a `url`, its location).
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Publish a data frame
#' publish_data(my_df, "datasets/customers.csv")
#'
#' # Publish as RDS
#' publish_data(my_df, "datasets/customers.rds", format = "rds")
#'
#' # Publish existing file
#' publish_data("outputs/model.rds", "models/v2/model.rds")
#' }
#' }
publish_data <- function(data,
                         dest,
                         format = "csv",
                         connection = NULL,
                         compress = FALSE,
                         include_private = FALSE,
                         to = NULL) {
  checkmate::assert_string(dest, min.chars = 1)
  checkmate::assert_choice(format, c("csv", "rds", "parquet", "json"))
  checkmate::assert_string(connection, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(compress)
  checkmate::assert_flag(include_private)
  if (is.character(data)) .fw_confirm_private(data, include_private)
  if (is.data.frame(data)) .fw_confirm_private(character(), include_private, .fw_publish_reasons(data))

  route <- .fw_publish_route(to, connection)

  # Handle data frame vs file path
  if (is.data.frame(data)) {
    # Write to temp file
    temp_file <- tempfile(fileext = paste0(".", format))
    on.exit(unlink(temp_file), add = TRUE)

    switch(format,
      csv = readr::write_csv(data, temp_file),
      rds = saveRDS(data, temp_file),
      parquet = {
        if (!requireNamespace("arrow", quietly = TRUE)) {
          stop("Package 'arrow' required for parquet format. Install with: install.packages('arrow')")
        }
        arrow::write_parquet(data, temp_file)
      },
      json = jsonlite::write_json(data, temp_file)
    )

    source_file <- temp_file
  } else if (is.character(data) && length(data) == 1) {
    if (!file.exists(data)) {
      stop(sprintf("File not found: %s", data), call. = FALSE)
    }
    source_file <- data
  } else {
    stop("'data' must be a data frame or file path", call. = FALSE)
  }

  # Compress if requested
  if (compress) {
    # Base R gzip, so R.utils (Suggests only) is not needed. A temp file, so
    # nothing is written next to the user's file.
    compressed_file <- tempfile(fileext = ".gz")
    .fw_gzip_file(source_file, compressed_file)
    source_file <- compressed_file
    on.exit(unlink(compressed_file), add = TRUE)
    if (!grepl("\\.gz$", dest)) {
      dest <- paste0(dest, ".gz")
    }
  }

  if (route$driver != "s3") {
    # Folder, GitHub, and Cloud: publish the file under dest's file name
    stage <- tempfile("fw_publish_data_")
    dir.create(stage)
    on.exit(unlink(stage, recursive = TRUE), add = TRUE)
    staged <- file.path(stage, basename(dest))
    if (!file.copy(source_file, staged)) stop("Could not stage ", basename(dest), " for publishing.", call. = FALSE)
    slug <- .fw_data_slug(dest)
    message(sprintf("Publishing %s as %s", dest, slug))
    return(publish(staged, to = route$name, slug = slug, include_private = TRUE))
  }
  s3_config <- .resolve_s3_connection(route$bucket)

  bundle <- .fw_bundle_build(if (is.data.frame(data)) data else source_file,
                             slug = .fw_data_slug(dest), include_private = TRUE)
  on.exit(unlink(bundle$path, recursive = TRUE), add = TRUE)
  # Upload
  url <- .s3_upload_file(source_file, dest, s3_config)
  message(sprintf("Published: %s", url))

  .fw_track_external(bundle, list(driver = "s3", url = url, version_url = NULL, version = 1L))
  invisible(url)
}


# The slug publish_data() uses for dest: the path without its extension
# (and .gz), with "/" turned into "-", then normalized as every slug is
# (lowercase, each other run of characters a "-"). "tables/bp_by_visit.csv"
# is "tables-bp-by-visit", so the message shows the slug the artifact gets.
#' @keywords internal
.fw_data_slug <- function(dest) {
  path <- gsub("\\\\", "/", sub("\\.gz$", "", dest))
  path <- sub("([^/])\\.[^./]*$", "\\1", path)
  parts <- strsplit(path, "/", fixed = TRUE)[[1]]
  .fw_bundle_slug(paste(parts[!parts %in% c("", ".", "..")], collapse = "-"))
}

# The slug publish_dir() uses for dest: the path with "/" turned into "-",
# normalized as every slug is. No extension is removed, since dest names a
# folder: "reports/v1.2" is "reports-v1-2".
#' @keywords internal
.fw_dir_slug <- function(dest) {
  parts <- strsplit(gsub("\\\\", "/", dest), "/", fixed = TRUE)[[1]]
  .fw_bundle_slug(paste(parts[!parts %in% c("", ".", "..")], collapse = "-"))
}

# Where publish_data(), publish_dir(), and publish_list() go. Like publish(),
# they follow `to`, then publish.default. An explicit `connection` (an S3
# bucket name), an S3 destination, or a project without publish.default keep
# the plain bucket behavior these functions always had.
.fw_publish_route <- function(to = NULL, connection = NULL) {
  checkmate::assert_string(to, min.chars = 1, null.ok = TRUE)
  bucket <- list(driver = "s3", bucket = connection, name = "s3")
  if (is.null(to)) {
    if (!is.null(connection)) return(bucket)
    settings <- tryCatch(settings_read(), error = function(e) list())
    if (is.null(settings$publish$default)) return(bucket)
  }
  destination <- .fw_publish_destination(to, connection)
  if (destination$driver == "s3") {
    destination$bucket <- destination$bucket %||% connection
  }
  destination
}

# publish_list() for a folder destination: one row per published artifact
.fw_folder_list <- function(destination, prefix = NULL, max = 1000L) {
  .fw_publish_capabilities(destination)
  root <- .fw_folder_path(destination$path)
  if (identical(destination$layout, "site-root")) {
    return(utils::head(.fw_site_root_list(root, destination$url, prefix), max))
  }
  manifests <- file.path(list.dirs(root, recursive = FALSE, full.names = TRUE), "artifact.json")
  manifests <- manifests[file.exists(manifests)]
  rows <- lapply(manifests, function(file) {
    manifest <- tryCatch(jsonlite::read_json(file, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(manifest) || !is.character(manifest$slug)) return(NULL)
    slug <- manifest$slug
    data.frame(
      key = paste0(slug, "/"),
      size = sum(vapply(manifest$files, function(x) as.numeric(x$bytes %||% 0), numeric(1))),
      last_modified = as.character(manifest$created_at %||% NA_character_),
      url = if (!is.null(destination$url)) paste0(sub("/+$", "", destination$url), "/", slug, "/")
            else file.path(root, slug, "index.html"),
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  df <- if (length(rows)) do.call(rbind, rows) else data.frame(
    key = character(0), size = numeric(0), last_modified = character(0),
    url = character(0), stringsAsFactors = FALSE
  )
  if (!is.null(prefix)) df <- df[startsWith(df$key, prefix), , drop = FALSE]
  rownames(df) <- NULL
  utils::head(df, max)
}

# publish_list() for a site-root folder: the one artifact at its root, if any
.fw_site_root_list <- function(root, url = NULL, prefix = NULL) {
  empty <- data.frame(key = character(0), size = numeric(0), last_modified = character(0),
                      url = character(0), stringsAsFactors = FALSE)
  file <- file.path(root, .fw_site_record)
  record <- if (file.exists(file)) tryCatch(jsonlite::read_json(file, simplifyVector = FALSE), error = function(e) NULL)
  slug <- if (is.list(record)) record$slug
  if (!is.character(slug) || length(slug) != 1L || (!is.null(prefix) && !startsWith(slug, prefix))) {
    return(empty)
  }
  files <- file.path(root, as.character(unlist(record$files)))
  files <- files[file.exists(files) & !dir.exists(files)]
  data.frame(
    key = paste0(slug, "/"),
    size = sum(as.numeric(file.size(files))),
    last_modified = as.character(record$created_at %||% NA_character_),
    url = if (!is.null(url)) paste0(sub("/+$", "", url), "/") else file.path(root, "index.html"),
    stringsAsFactors = FALSE
  )
}

.fw_gzip_file <- function(source, dest) {
  input <- file(source, "rb")
  on.exit(close(input), add = TRUE)
  output <- gzfile(dest, "wb")
  on.exit(close(output), add = TRUE)
  repeat {
    chunk <- readBin(input, "raw", n = 1048576L)
    if (!length(chunk)) break
    writeBin(chunk, output)
  }
  invisible(dest)
}


#' Publish a directory to S3 or a named destination
#'
#' Recursively uploads all files in a directory to S3. Like [publish()], it
#' follows `to`, then `publish.default` in settings.yml. S3 destinations, an
#' explicit `connection`, and projects without `publish.default` get a
#' file-by-file upload under `dest`. Folder, GitHub, and Cloud destinations
#' publish the directory (after `pattern` and `recursive`) with [publish()].
#' The slug is `dest` (default: the directory name) with each `/` turned into
#' `-`, then normalized like every slug, as in [publish_data()]:
#' `dest = "figures/meeting"` publishes as `figures-meeting`. The message says
#' which slug was used.
#'
#' @param dir Character. Local directory path.
#' @param dest Character or NULL. Destination prefix in S3. If NULL, uses
#'   the directory name.
#' @param connection Character or NULL. S3 connection name, or NULL for default.
#' @param pattern Character or NULL. Optional regex pattern to filter files.
#' @param recursive Logical. Whether to include subdirectories. Default TRUE.
#' @param include_private Logical. Skip the private-path check. When the
#'   path of any file to upload has a folder named `private` or ending in
#'   `_private` (in any case; file names don't count), or is under a settings
#'   folder whose key contains `private` and not `public`
#'   (`outputs_private_tables`), Framework warns
#'   and, in an interactive session, asks before publishing (default No).
#'   In a non-interactive session it stops unless `include_private = TRUE`.
#' @param to Character or NULL. Named destination from
#'   `publish.destinations`, or a driver name, as in [publish()]. Default:
#'   `publish.default`.
#' @return Character vector. Public URLs of uploaded files (for other
#'   destinations, the published artifact's URL or location).
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Upload entire directory
#' publish_dir("outputs/dashboard/")
#'
#' # Upload to specific location
#' publish_dir("outputs/dashboard/", dest = "dashboards/v2/")
#'
#' # Upload only HTML files
#' publish_dir("outputs/", pattern = "\\.html$")
#' }
#' }
publish_dir <- function(dir,
                        dest = NULL,
                        connection = NULL,
                        pattern = NULL,
                        recursive = TRUE,
                        include_private = FALSE,
                        to = NULL) {
  checkmate::assert_directory_exists(dir)
  checkmate::assert_flag(include_private)
  .fw_confirm_private(dir, include_private)
  checkmate::assert_string(dest, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(connection, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(pattern, null.ok = TRUE)
  checkmate::assert_flag(recursive)

  route <- .fw_publish_route(to, connection)

  # Determine destination
  if (is.null(dest)) {
    dest <- basename(normalizePath(dir))
  }

  # List files
  files <- list.files(dir, recursive = recursive, full.names = TRUE)

  if (!is.null(pattern)) {
    files <- files[grepl(pattern, files)]
  }

  # Filter to actual files (not directories)
  files <- files[file.info(files)$isdir == FALSE]

  if (length(files) == 0) {
    warning("No files found to upload")
    return(invisible(character(0)))
  }

  if (route$driver != "s3") {
    slug <- .fw_dir_slug(dest)
    message(sprintf("Publishing %s as %s", dest, slug))
    source <- dir
    if (!is.null(pattern) || !recursive) {
      # Publish only the selected files, keeping their relative paths
      source <- file.path(tempfile("fw_publish_dir_"), slug)
      dir.create(source, recursive = TRUE)
      on.exit(unlink(dirname(source), recursive = TRUE), add = TRUE)
      root <- normalizePath(dir, winslash = "/")
      for (file in files) {
        rel_path <- substring(normalizePath(file, winslash = "/"), nchar(root) + 2L)
        dir.create(dirname(file.path(source, rel_path)), recursive = TRUE, showWarnings = FALSE)
        file.copy(file, file.path(source, rel_path))
      }
    }
    return(publish(source, to = route$name, slug = slug, include_private = TRUE))
  }
  s3_config <- .resolve_s3_connection(route$bucket)

  bundle <- .fw_bundle_build(dir, slug = .fw_dir_slug(dest), include_private = include_private)
  on.exit(unlink(bundle$path, recursive = TRUE), add = TRUE)
  # Upload each file
  message(sprintf("Uploading %d files...", length(files)))
  urls <- character(length(files))

  for (i in seq_along(files)) {
    rel_path <- substring(normalizePath(files[i], winslash = "/"), nchar(normalizePath(dir, winslash = "/")) + 2L)
    file_dest <- file.path(dest, rel_path)
    urls[i] <- .s3_upload_file(files[i], file_dest, s3_config)
  }

  message(sprintf("Published %d files to %s", length(urls), dest))

  .fw_track_external(bundle, list(driver = "s3", url = if (length(urls)) urls[[1]] else NULL,
                                  version_url = NULL, version = 1L))
  invisible(urls)
}


#' List published files in S3 or a folder destination
#'
#' Lists files in an S3 bucket/prefix. Like [publish()], it follows `to`,
#' then `publish.default` in settings.yml. For a folder destination it lists
#' the published artifacts, one row per slug; a `layout: site-root` folder
#' has at most one, the latest publish. GitHub and Cloud destinations
#' can't be listed here.
#'
#' @param prefix Character or NULL. Prefix to filter by. If NULL, lists all
#'   files under the connection's configured prefix.
#' @param connection Character or NULL. S3 connection name, or NULL for default.
#' @param max Integer. Maximum number of files to list. Default 1000.
#' @param to Character or NULL. Named destination from
#'   `publish.destinations`, or a driver name, as in [publish()]. Default:
#'   `publish.default`.
#' @return Data frame with columns: key, size, last_modified, url.
#'
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # List all published files
#' publish_list()
#'
#' # List files under a prefix
#' publish_list("reports/")
#'
#' # List from specific connection
#' publish_list(connection = "s3_backup")
#' }
#' }
publish_list <- function(prefix = NULL, connection = NULL, max = 1000L, to = NULL) {
  checkmate::assert_string(prefix, null.ok = TRUE)
  checkmate::assert_string(connection, min.chars = 1, null.ok = TRUE)
  checkmate::assert_integerish(max, lower = 1)

  route <- .fw_publish_route(to, connection)
  if (route$driver == "folder") {
    return(.fw_folder_list(route, prefix, max))
  }
  if (route$driver != "s3") {
    stop("publish_list() lists S3 and folder destinations. '", route$name,
         "' uses the ", route$driver, " driver.", call. = FALSE)
  }

  if (!requireNamespace("aws.s3", quietly = TRUE)) {
    stop("Package 'aws.s3' required. Install with: install.packages('aws.s3')")
  }

  # Resolve S3 connection
  s3_config <- .resolve_s3_connection(route$bucket)

  # Build full prefix
  full_prefix <- if (!is.null(prefix)) {
    if (nchar(s3_config$prefix) > 0) {
      paste0(s3_config$prefix, "/", prefix)
    } else {
      prefix
    }
  } else {
    s3_config$prefix
  }

  # Set credentials
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = s3_config$access_key,
    AWS_SECRET_ACCESS_KEY = s3_config$secret_key,
    AWS_DEFAULT_REGION = s3_config$region
  )

  if (!is.null(s3_config$session_token)) {
    withr::local_envvar(AWS_SESSION_TOKEN = s3_config$session_token)
  }

  base_url <- if (!is.null(s3_config$endpoint)) s3_config$endpoint else "s3.amazonaws.com"

  # List objects
  result <- tryCatch({
    aws.s3::get_bucket(
      bucket = s3_config$bucket,
      prefix = full_prefix,
      max = max,
      base_url = base_url,
      # Custom endpoints (MinIO, R2, moto) take an empty region, as the upload
      # code does; otherwise aws.s3 builds "<region>.<endpoint>" as the host.
      region = if (!is.null(s3_config$endpoint)) "" else s3_config$region,
      use_https = s3_config$use_https %||% TRUE
    )
  }, error = function(e) {
    stop(sprintf("Failed to list S3 objects: %s", e$message), call. = FALSE)
  })

  # Convert to data frame
  if (length(result) == 0) {
    return(data.frame(
      key = character(0),
      size = numeric(0),
      last_modified = character(0),
      url = character(0),
      stringsAsFactors = FALSE
    ))
  }

  df <- data.frame(
    key = vapply(result, function(x) x$Key, character(1)),
    size = vapply(result, function(x) as.numeric(x$Size), numeric(1)),
    last_modified = vapply(result, function(x) x$LastModified, character(1)),
    stringsAsFactors = FALSE
  )

  # Add URLs
  df$url <- vapply(df$key, function(k) .s3_public_url(k, s3_config), character(1))

  df
}
