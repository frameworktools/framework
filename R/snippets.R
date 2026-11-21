# Code snippets: a chunk's code and the text it printed, published as a
# code_snippet artifact (framework.artifact/v1). Framework Cloud validates,
# highlights, styles, and truncates them; this file only captures. The format
# is in framework-cloud docs/plans/2026-11-18-code-snippets.md, and Cloud's
# ArtifactSnippet class is the source of truth for what it accepts.
#
# Two ways in:
#   * publish_snippet() publishes a chunk of a Quarto or R Markdown render.
#     Under knitr, library(framework) wraps knitr's source, output, message,
#     warning, and error hooks. Each wrapper records its piece for the chunk
#     label and passes it through unchanged, so the record holds what the
#     rendered notebook shows. The plot hook is left alone.
#   * fw_snippet() runs a braced block in a script through evaluate and
#     publishes its code and printed text.

.fw_snippet_hook_types <- c("source", "output", "message", "warning", "error")

.fw_snippet_hook_attr <- "framework_snippet_hook"

# Whether a knitr render is running in this session.
#' @keywords internal
.fw_snippet_in_render <- function() {
  isTRUE(getOption("knitr.in.progress")) && isNamespaceLoaded("knitr")
}

# Whether this render's knitr hooks carry the recording wrappers.
#' @keywords internal
.fw_snippet_hooks_active <- function() {
  if (!.fw_snippet_in_render()) return(FALSE)
  isTRUE(attr(knitr::knit_hooks$get("source"), .fw_snippet_hook_attr))
}

# Wrap knitr's output hooks for this render. knitr restores its hooks after
# every render, so wrappers present now were installed in this render, and
# installing fresh ones starts a new record. Called when the package loads or
# attaches and from scaffold(), so a second render in the same session still
# records once the notebook calls library(framework) or scaffold().
#' @keywords internal
.fw_snippet_hooks_install <- function() {
  if (!.fw_snippet_in_render()) return(invisible(FALSE))
  if (.fw_snippet_hooks_active()) return(invisible(TRUE))
  .framework_env$snippets <- list()
  hooks <- list()
  for (type in .fw_snippet_hook_types) {
    hooks[[type]] <- .fw_snippet_hook(type, knitr::knit_hooks$get(type))
  }
  knitr::knit_hooks$set(hooks)
  invisible(TRUE)
}

#' @keywords internal
.fw_snippet_hook <- function(type, previous) {
  force(type)
  force(previous)
  hook <- function(x, options, ...) {
    # Recording must never break the render
    tryCatch(.fw_snippet_record(type, x, options), error = function(e) NULL)
    if (is.function(previous)) previous(x, options, ...) else paste(x, collapse = "\n")
  }
  attr(hook, .fw_snippet_hook_attr) <- TRUE
  hook
}

# Add one piece of a chunk's rendered output to that chunk's record.
#' @keywords internal
.fw_snippet_record <- function(type, x, options) {
  label <- options$label
  if (!is.character(label) || length(label) != 1L || !nzchar(label)) return(invisible(NULL))
  text <- paste(as.character(x), collapse = "\n")
  # knitr adds the comment prefix before it calls an output hook (see
  # knitr:::comment_out()). Output shown as-is never had one.
  if (type != "source" && !identical(options$results, "asis")) {
    text <- .fw_snippet_uncomment(text, options$comment)
  }
  block <- .fw_snippet_block(if (type == "source") "code" else type, text)
  if (is.null(block)) return(invisible(NULL))
  record <- .framework_env$snippets[[label]]
  if (is.null(record)) {
    record <- list(blocks = list(), width = .fw_snippet_width(),
                   input = .fw_snippet_knitr_input(), chunk_lines = .fw_snippet_knitr_lines())
  }
  record$blocks <- c(record$blocks, list(block))
  .framework_env$snippets[[label]] <- record
  invisible(NULL)
}

# Remove knitr's comment prefix ("## " by default) from each line.
#' @keywords internal
.fw_snippet_uncomment <- function(text, comment) {
  if (!is.character(comment) || length(comment) != 1L || is.na(comment) || !nzchar(comment)) {
    return(text)
  }
  prefix <- paste(comment, "")
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  if (!length(lines)) return(text)
  lines <- ifelse(startsWith(lines, prefix), substring(lines, nchar(prefix) + 1L),
                  ifelse(lines == comment, "", lines))
  paste(lines, collapse = "\n")
}

# A block, or NULL when it has no text. Line endings become \n and trailing
# newlines go. Text is never cut: Cloud applies the limits.
#' @keywords internal
.fw_snippet_block <- function(type, text) {
  text <- gsub("\r\n?", "\n", paste(text, collapse = "\n"))
  text <- sub("\n+$", "", text)
  if (!nzchar(trimws(text))) return(NULL)
  list(type = type, text = text)
}

#' @keywords internal
.fw_snippet_width <- function() {
  width <- getOption("width")
  if (is.numeric(width) && length(width) == 1L && !is.na(width) && width >= 20 && width <= 1000) {
    as.integer(width)
  } else {
    NULL
  }
}

# The file knitr is rendering. Quarto renders an intermediate .rmarkdown file
# beside the .qmd; the .qmd is the source.
#' @keywords internal
.fw_snippet_knitr_input <- function() {
  input <- tryCatch(knitr::current_input(dir = TRUE), error = function(e) NULL)
  if (!is.character(input) || length(input) != 1L || is.na(input)) return(NULL)
  if (grepl("\\.rmarkdown$", input)) {
    qmd <- sub("\\.rmarkdown$", ".qmd", input)
    if (file.exists(qmd)) input <- qmd
  }
  input
}

# The current chunk's lines in the input file, fences included, as c(first,
# last). knitr exposes them only through an internal function, so a knitr
# without it gives NULL.
#' @keywords internal
.fw_snippet_knitr_lines <- function() {
  current <- tryCatch(utils::getFromNamespace("current_lines", "knitr")(), error = function(e) NULL)
  if (!is.character(current) || length(current) != 1L) return(NULL)
  bounds <- suppressWarnings(as.integer(strsplit(current, "-", fixed = TRUE)[[1]]))
  if (length(bounds) != 2L || anyNA(bounds) || bounds[1] < 1L || bounds[2] < bounds[1]) return(NULL)
  bounds
}

# The lines of a chunk's code in its file: the chunk without its fences and
# its leading #| options. NULL unless the first of those lines matches the
# first line of the recorded code, so a file that changed since the render, or
# a Quarto include that moved lines, gives no wrong range.
#' @keywords internal
.fw_snippet_code_lines <- function(path, chunk_lines, blocks) {
  if (is.null(path) || is.null(chunk_lines) || !file.exists(path)) return(NULL)
  text <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
  if (is.null(text) || chunk_lines[2] > length(text)) return(NULL)
  first <- chunk_lines[1]
  last <- chunk_lines[2]
  if (grepl("^\\s*(`{3,}|~{3,})", text[first])) first <- first + 1L
  if (last > first && grepl("^\\s*(`{3,}|~{3,})\\s*$", text[last])) last <- last - 1L
  while (first <= last && grepl("^\\s*#\\|", text[first])) first <- first + 1L
  while (last >= first && !nzchar(trimws(text[last]))) last <- last - 1L
  if (first > last) return(NULL)
  codes <- Filter(function(block) identical(block$type, "code"), blocks)
  if (!length(codes)) return(NULL)
  expected <- trimws(strsplit(codes[[1]]$text, "\n", fixed = TRUE)[[1]][1])
  if (!identical(trimws(text[first]), expected)) return(NULL)
  c(first, last)
}

# Where the source file sits: its path from the git repository's top (the
# path a GitHub permalink needs), else from the Framework project root, and
# the commit checked out. NULLs when unknown.
#' @keywords internal
.fw_snippet_location <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(list(file = NULL, commit = NULL))
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  directory <- dirname(path)
  top <- .fw_git(directory, "rev-parse", "--show-toplevel")
  root <- if (.fw_git_ok(top) && length(top) == 1L) normalizePath(.fw_git_native_path(top), winslash = "/", mustWork = FALSE) else NULL
  commit <- NULL
  if (!is.null(root)) {
    head <- .fw_git(directory, "rev-parse", "HEAD")
    if (.fw_git_ok(head) && length(head) == 1L && grepl("^[0-9a-f]{40}$", head)) commit <- head
  } else {
    root <- tryCatch(.find_project_root(directory), error = function(e) NULL)
    if (!is.null(root)) root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  }
  file <- if (!is.null(root) && startsWith(path, paste0(root, "/"))) {
    substring(path, nchar(root) + 2L)
  } else {
    basename(path)
  }
  list(file = file, commit = commit)
}

# The repository URL to name in the snippet: the argument, else
# publish.repository in settings.yml. Sent only when given, so publishing
# never reveals a repository by default.
#' @keywords internal
.fw_snippet_repository <- function(repository = NULL) {
  if (is.null(repository)) {
    repository <- tryCatch(settings_read()$publish$repository, error = function(e) NULL)
  }
  if (is.null(repository)) return(NULL)
  if (!is.character(repository) || length(repository) != 1L || is.na(repository) ||
      !grepl("^https://", repository)) {
    stop("repository must be an https URL, such as https://github.com/owner/repo.", call. = FALSE)
  }
  repository
}

#' @keywords internal
.fw_snippet_source <- function(path, label, lines = NULL, repository = NULL, deparsed = FALSE) {
  location <- .fw_snippet_location(path)
  source <- list(language = "r", file = location$file, label = label,
                 lines = if (!is.null(lines)) as.list(as.integer(lines)),
                 commit = location$commit, repository = .fw_snippet_repository(repository))
  if (isTRUE(deparsed)) source$deparsed <- TRUE
  Filter(Negate(is.null), source)
}

# display.links from list(notebook = "https://...", model = "slug" or URL).
#' @keywords internal
.fw_snippet_links <- function(links) {
  if (is.null(links) || !length(links)) return(NULL)
  rels <- names(links)
  if (is.null(rels) || any(!nzchar(rels)) || !all(rels %in% c("notebook", "model"))) {
    stop('links must be named "notebook" or "model", as in list(notebook = "https://...", model = "model-slug").',
         call. = FALSE)
  }
  out <- list()
  for (i in seq_along(links)) {
    rel <- rels[i]
    value <- links[[i]]
    if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
      stop("Each link must be one string.", call. = FALSE)
    }
    if (grepl("^https://[^[:space:]]+$", value)) {
      out <- c(out, list(list(rel = rel, url = value)))
    } else if (rel == "model" && grepl("^[A-Za-z0-9_-]{1,120}$", value)) {
      out <- c(out, list(list(rel = rel, artifact = value)))
    } else if (rel == "model") {
      stop("A model link takes an artifact slug in this project or an https URL.", call. = FALSE)
    } else {
      stop("A notebook link takes an https URL.", call. = FALSE)
    }
  }
  out
}

# The framework.artifact/v1 code_snippet document. Adjacent code blocks join,
# as do adjacent output blocks, which is how a notebook shows them.
#' @keywords internal
.fw_snippet_document <- function(blocks, source, width = NULL, output = TRUE, folded = NULL, links = NULL) {
  checkmate::assert_flag(output)
  checkmate::assert_flag(folded, null.ok = TRUE)
  blocks <- Filter(Negate(is.null), blocks)
  if (!output) blocks <- Filter(function(block) identical(block$type, "code"), blocks)
  merged <- list()
  for (block in blocks) {
    n <- length(merged)
    if (n && identical(merged[[n]]$type, block$type) && block$type %in% c("code", "output")) {
      merged[[n]]$text <- paste(merged[[n]]$text, block$text, sep = "\n")
    } else {
      merged[[n + 1L]] <- block
    }
  }
  if (!any(vapply(merged, function(block) identical(block$type, "code"), logical(1)))) {
    return(NULL)
  }
  if (!is.null(folded)) {
    merged <- lapply(merged, function(block) {
      if (identical(block$type, "output")) block$folded <- folded
      block
    })
  }
  snippet <- Filter(Negate(is.null), list(width = width, blocks = merged))
  document <- list(schema = "framework.artifact/v1", kind = "code_snippet",
                   source = source, snippet = snippet)
  links <- .fw_snippet_links(links)
  if (length(links)) document$display <- list(links = links)
  structure(document, class = "framework_code_snippet")
}

# Publish a snippet document through publish(), which writes it as
# code_snippet.json and picks the destination.
#' @keywords internal
.fw_snippet_publish <- function(document, label, slug = NULL, title = NULL, description = NULL,
                                visibility = NULL, password = NULL, collection = NULL,
                                share_unlisted = FALSE, to = NULL, include_private = FALSE,
                                display = NULL) {
  if (is.null(slug)) slug <- .fw_bundle_slug(label)
  publish(document, slug = slug, title = title %||% label, description = description,
          visibility = visibility, password = password, collection = collection,
          share_unlisted = share_unlisted, to = to, include_private = include_private,
          display = display)
}

#' Publish a notebook chunk as a code snippet
#'
#' Publishes a chunk of a Quarto or R Markdown notebook to Framework Cloud as
#' a code snippet: its code and the text it printed, as the rendered notebook
#' shows them. A blog post or report can embed the snippet beside the results
#' it produced.
#'
#' Under `quarto render` or `rmarkdown::render()`, `library(framework)`
#' records each chunk's code, printed output, messages, warnings, and errors
#' as knitr renders them. Chunk options therefore apply: `echo = FALSE` leaves
#' out the code, and `results = "hide"`, `message = FALSE`, and
#' `warning = FALSE` leave out those outputs. Plots are not recorded. Output
#' shown with `results = "asis"` is not recorded either, because knitr passes
#' it straight to the document. knitr's comment prefix (`## `) is removed.
#'
#' Call `publish_snippet()` in any chunk after the labelled one, usually a
#' chunk with `include: false`. The labelled chunk must run after
#' `library(framework)` (or `scaffold()`), and not from the knitr cache.
#'
#' Outside a render, as when a chunk runs in the editor, nothing has been
#' recorded. `publish_snippet()` then publishes nothing and says why. It never
#' runs the chunk again.
#'
#' The snippet names its source: the language, the file's path from the git
#' repository's top (or the project root), the chunk label, the chunk's code
#' lines, and the commit checked out. The repository URL is sent only when
#' `repository` is given or `publish.repository` is set in `settings.yml`.
#' Framework Cloud builds a GitHub permalink from a GitHub repository, the
#' commit, the file, and the lines.
#'
#' Framework Cloud highlights the code, converts ANSI colors in output, and
#' shortens long output. When the snippet matches its newest version, Cloud
#' adds no version and the message says it is unchanged.
#'
#' @param label The chunk label, as in `#| label: fit-model`.
#' @param folded `TRUE` folds the output blocks and `FALSE` opens them. The
#'   default, `NULL`, lets Framework Cloud fold output longer than 12 lines.
#'   Messages, warnings, and errors follow Cloud's rule.
#' @param output `FALSE` publishes the code without its output.
#' @param links Links shown with the snippet:
#'   `list(notebook = "https://...", model = "model-slug")`. `notebook` takes
#'   an https URL. `model` takes the slug of a model artifact in the same
#'   project, or an https URL.
#' @param slug Artifact slug. Default: the label, lowercased, with other
#'   characters as `-`.
#' @param title Artifact title. Default: the label.
#' @param description Artifact description.
#' @param visibility `"public"`, `"unlisted"`, or `"private"`. A new artifact
#'   is unlisted unless set. See [publish()].
#' @param password Password required to view the snippet on Framework Cloud.
#' @param collection Existing project collection ID or slug.
#' @param share_unlisted Consent to share an unlisted snippet with collection
#'   readers.
#' @param to Publishing destination. See [publish()].
#' @param repository Repository URL to name in the snippet, such as
#'   `"https://github.com/owner/repo"`. Default: `publish.repository` in
#'   `settings.yml`, else none.
#' @param include_private Skip the private-data confirmation. See [publish()].
#' @param display Framework Cloud only: what the snippet shows when other
#'   sites embed it, such as `list(links = FALSE)`. `output = FALSE` there
#'   starts the output hidden, with Show output; the `output` argument
#'   leaves it out entirely. See [publish()].
#' @return The artifact URL, invisibly, with the embed link in its
#'   `embed_link` attribute (see [publish()]), or `NULL` when nothing was
#'   published.
#' @seealso [fw_snippet()] for scripts, [publish()].
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # In a Quarto notebook, after a chunk labelled fit-model:
#' publish_snippet("fit-model", links = list(notebook = "https://example.org/analysis"))
#'
#' # The code alone
#' publish_snippet("fit-model", output = FALSE, slug = "fit-model-code")
#' }
#' }
publish_snippet <- function(label, folded = NULL, output = TRUE, links = NULL, slug = NULL,
                            title = NULL, description = NULL, visibility = NULL, password = NULL,
                            collection = NULL, share_unlisted = FALSE, to = NULL,
                            repository = NULL, include_private = FALSE, display = NULL) {
  checkmate::assert_string(label, min.chars = 1)
  display <- .fw_display_settings(display)
  checkmate::assert_flag(output)
  checkmate::assert_flag(folded, null.ok = TRUE)
  if (!.fw_snippet_in_render()) {
    message("No snippet published. publish_snippet() publishes a chunk as a notebook render ",
            "showed it, and outside quarto render or rmarkdown::render() no chunk output is recorded.")
    return(invisible(NULL))
  }
  if (!.fw_snippet_hooks_active()) {
    .fw_snippet_hooks_install()
    .fw_snippet_warn("No snippet published for chunk \"", label, "\". Chunk output is recorded once ",
                     "library(framework) runs in the render. In a session that had already attached ",
                     "framework, call scaffold() before that chunk.")
    return(invisible(NULL))
  }
  current <- knitr::opts_current$get("label")
  if (identical(current, label)) {
    .fw_snippet_warn("No snippet published. Call publish_snippet(\"", label, "\") from a later chunk, ",
                     "after the chunk has finished.")
    return(invisible(NULL))
  }
  record <- .framework_env$snippets[[label]]
  if (is.null(record)) {
    .fw_snippet_warn("No snippet published. No chunk labelled \"", label, "\" has shown code or output ",
                     "in this render so far. Check the label, and that the chunk runs before this one ",
                     "and isn't cached.")
    return(invisible(NULL))
  }
  lines <- .fw_snippet_code_lines(record$input, record$chunk_lines, record$blocks)
  source <- .fw_snippet_source(record$input, label, lines, repository)
  document <- .fw_snippet_document(record$blocks, source, record$width, output, folded, links)
  if (is.null(document)) {
    .fw_snippet_warn("No snippet published. Chunk \"", label, "\" shows no code (echo is off).")
    return(invisible(NULL))
  }
  # knitr would put the publish messages in the chunk's output, often hidden.
  # The render's log shows them instead.
  withCallingHandlers(
    .fw_snippet_publish(document, label, slug = slug, title = title, description = description,
                        visibility = visibility, password = password, collection = collection,
                        share_unlisted = share_unlisted, to = to, include_private = include_private,
                        display = display),
    message = function(m) {
      cat(conditionMessage(m), file = stderr())
      invokeRestart("muffleMessage")
    }
  )
}

# A warning that also reaches the render's log: knitr keeps warnings in the
# chunk's output, which a publishing chunk usually hides.
#' @keywords internal
.fw_snippet_warn <- function(...) {
  text <- paste0(...)
  cat("Warning: ", text, "\n", sep = "", file = stderr())
  warning(text, call. = FALSE)
}

#' Run code in a script and publish it as a code snippet
#'
#' Runs a braced block of code, prints its output as usual, and publishes the
#' code and its printed text to Framework Cloud as a code snippet. Use it in R
#' scripts. In Quarto and R Markdown notebooks, use [publish_snippet()].
#'
#' The block runs in the calling environment, so its assignments stay
#' available afterward. It runs through `evaluate::evaluate()`, which splits
#' it into expressions and keeps each one's output, messages, warnings, and
#' errors in order. After the block finishes, its output is printed, its
#' messages and warnings are signaled again, and its plots are drawn on the
#' current device. Plots are left out of the snippet. When the block stops
#' with an error, nothing is published and the error is signaled again.
#'
#' The code text comes from the block's source references, so comments and
#' layout are kept. `Rscript` keeps source references only with
#' `options(keep.source = TRUE)` set before the code is parsed, as in
#' `Rscript -e 'options(keep.source = TRUE); source("script.R")'`. Without
#' them, the code is deparsed, which drops comments and reformats it, and the
#' snippet's source records that. Source lines and the file come from the
#' source references. The commit and repository follow [publish_snippet()].
#'
#' @param label A name for the snippet, used as its label and default slug.
#' @param code A braced block of code: `{ ... }`.
#' @param output `FALSE` publishes the code without its output. The output
#'   is still printed.
#' @param folded `TRUE` folds the output blocks and `FALSE` opens them. The
#'   default, `NULL`, lets Framework Cloud fold output longer than 12 lines.
#' @param links Links shown with the snippet. See [publish_snippet()].
#' @param ... Passed to [publish_snippet()]'s publishing arguments: `slug`,
#'   `title`, `description`, `visibility`, `password`, `collection`,
#'   `share_unlisted`, `to`, `repository`, `include_private`, and `display`.
#' @return The artifact URL, invisibly, with the embed link in its
#'   `embed_link` attribute. See [publish()].
#' @seealso [publish_snippet()], [publish()].
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' fw_snippet("fit-model", {
#'   fit <- lm(mpg ~ wt + hp, data = mtcars)
#'   summary(fit)
#' })
#' coef(fit)
#' }
#' }
fw_snippet <- function(label, code, output = TRUE, folded = NULL, links = NULL, ...) {
  checkmate::assert_string(label, min.chars = 1)
  checkmate::assert_flag(output)
  checkmate::assert_flag(folded, null.ok = TRUE)
  if (!requireNamespace("evaluate", quietly = TRUE)) {
    stop('fw_snippet() requires the evaluate package. install.packages("evaluate")', call. = FALSE)
  }
  options <- list(...)
  allowed <- c("slug", "title", "description", "visibility", "password", "collection",
               "share_unlisted", "to", "repository", "include_private", "display")
  given <- names(options) %||% rep("", length(options))
  if (any(!given %in% allowed)) {
    stop("fw_snippet() takes these publishing arguments by name: ", paste(allowed, collapse = ", "), ".",
         call. = FALSE)
  }
  # Checked before the block runs
  options$display <- .fw_display_settings(options$display)
  expression <- substitute(code)
  if (!is.call(expression) || !identical(expression[[1]], as.name("{"))) {
    stop("fw_snippet() takes a braced block of code: fw_snippet(\"", label, "\", { ... }).", call. = FALSE)
  }
  envir <- parent.frame()
  found <- .fw_snippet_code_text(expression)
  if (!nzchar(trimws(found$text))) stop("The code block is empty.", call. = FALSE)
  if (isTRUE(found$deparsed)) {
    message("fw_snippet(): no source references, so the code is deparsed without comments. ",
            "Set options(keep.source = TRUE) before the script is parsed to keep its text.")
  }
  results <- evaluate::evaluate(found$text, envir = envir, stop_on_error = 1L, new_device = TRUE)
  blocks <- .fw_snippet_evaluate_blocks(results)
  failure <- .fw_snippet_replay(results)
  if (!is.null(failure)) stop(failure)
  path <- found$file %||% .fw_snippet_script_path()
  lines <- if (!is.null(found$file)) found$lines
  source <- .fw_snippet_source(path, label, lines, options$repository, deparsed = found$deparsed)
  document <- .fw_snippet_document(blocks, source, .fw_snippet_width(), output, folded, links)
  options$repository <- NULL
  do.call(.fw_snippet_publish, c(list(document, label), options))
}

# The block's code as text, with its file and lines when source references
# exist, else deparsed. With references, the text runs from the line after
# the opening brace to the line before the closing one, so comments inside
# the block stay.
#' @keywords internal
.fw_snippet_code_text <- function(expression) {
  statements <- as.list(expression)[-1]
  refs <- attr(expression, "srcref")
  whole <- attr(expression, "wholeSrcref")
  if (length(statements) && length(refs) == length(statements) + 1L && !is.null(whole)) {
    brace <- refs[[1]]
    first <- refs[[2]]
    last <- refs[[length(refs)]]
    srcfile <- attr(first, "srcfile")
    # A statement on the brace's line starts at its own column
    from <- if (first[1] > brace[1]) brace[1] + 1L else first[1]
    to <- if (whole[3] > last[3]) whole[3] - 1L else last[3]
    lines <- tryCatch(as.character(getSrcLines(srcfile, from, to)), error = function(e) NULL)
    if (length(lines) == to - from + 1L) {
      # srcref columns 5 and 6 count characters
      if (to == last[3] && whole[3] == last[3]) lines[length(lines)] <- substr(lines[length(lines)], 1L, last[6])
      # Blank out the brace before a statement on its line, keeping the
      # statement's column for the dedent below
      if (from == first[1]) lines[1] <- paste0(strrep(" ", first[5] - 1L), substring(lines[1], first[5]))
      while (length(lines) && !nzchar(trimws(lines[1]))) {
        lines <- lines[-1]
        from <- from + 1L
      }
      while (length(lines) && !nzchar(trimws(lines[length(lines)]))) {
        lines <- lines[-length(lines)]
        to <- to - 1L
      }
      indent <- .fw_snippet_indent(lines)
      if (indent > 0L) lines <- substring(lines, indent + 1L)
      return(list(text = paste(lines, collapse = "\n"), file = .fw_snippet_srcfile_path(srcfile),
                  lines = c(from, to), deparsed = FALSE))
    }
  }
  text <- vapply(statements, function(statement) {
    paste(deparse(statement, width.cutoff = 80L), collapse = "\n")
  }, character(1))
  list(text = paste(text, collapse = "\n"), file = NULL, lines = NULL, deparsed = TRUE)
}

# The absolute path of a parsed file, or NULL for code typed at the console
# or passed to Rscript -e.
#' @keywords internal
.fw_snippet_srcfile_path <- function(srcfile) {
  file <- if (is.environment(srcfile)) srcfile$filename
  if (!is.character(file) || length(file) != 1L || !nzchar(file)) return(NULL)
  if (!grepl("^(/|~|[A-Za-z]:)", file) && is.character(srcfile$wd)) file <- file.path(srcfile$wd, file)
  if (!file.exists(file)) return(NULL)
  normalizePath(file, winslash = "/", mustWork = TRUE)
}

# The smallest leading whitespace among nonblank lines.
#' @keywords internal
.fw_snippet_indent <- function(lines) {
  lines <- lines[nzchar(trimws(lines))]
  if (!length(lines)) return(0L)
  min(nchar(sub("^(\\s*).*$", "\\1", lines)))
}

# The script Rscript is running, from --file=.
#' @keywords internal
.fw_snippet_script_path <- function() {
  file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  if (length(file) == 1L && file.exists(file)) normalizePath(file, winslash = "/", mustWork = TRUE)
}

# Snippet blocks from evaluate()'s results. Plots are dropped.
#' @keywords internal
.fw_snippet_evaluate_blocks <- function(results) {
  lapply(results, function(item) {
    if (inherits(item, "source")) return(.fw_snippet_block("code", item$src))
    if (is.character(item)) return(.fw_snippet_block("output", item))
    if (inherits(item, "error")) return(.fw_snippet_block("error", .fw_snippet_condition_text(item, "Error")))
    if (inherits(item, "warning")) return(.fw_snippet_block("warning", .fw_snippet_condition_text(item, "Warning")))
    if (inherits(item, "message")) return(.fw_snippet_block("message", conditionMessage(item)))
    NULL
  })
}

# A warning or error as R prints it: "Warning in f(): text" or "Error: text".
#' @keywords internal
.fw_snippet_condition_text <- function(condition, prefix) {
  call <- conditionCall(condition)
  where <- if (!is.null(call)) paste0(" in ", paste(deparse(call, nlines = 1L), collapse = "")) else ""
  paste0(prefix, where, ": ", conditionMessage(condition))
}

# Print what the block printed, signal its messages and warnings again, and
# draw its plots. Returns the block's error, if any, for the caller to raise.
#' @keywords internal
.fw_snippet_replay <- function(results) {
  for (item in results) {
    if (inherits(item, "source")) next
    if (is.character(item)) {
      cat(item, sep = "")
    } else if (inherits(item, "error")) {
      return(item)
    } else if (inherits(item, "warning")) {
      warning(item)
    } else if (inherits(item, "message")) {
      message(item)
    } else if (inherits(item, "recordedplot")) {
      tryCatch(grDevices::replayPlot(item), error = function(e) NULL)
    }
  }
  NULL
}
