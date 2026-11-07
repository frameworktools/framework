# Publishing to GitHub Pages: publish(to = "github") and
# publish_notebook(to = "github"). Framework Cloud's "Publish with GitHub
# Pages" commits a workflow that deploys the repository's published/ folder
# from the default branch. This side copies a document into
# published/<slug>/, commits only that folder, and pushes. Documents never
# pass through the cloud. framework-py and fw behave the same way.

# Run git in `dir`, returning output lines with the exit status attached
#' @keywords internal
.fw_git <- function(dir, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = TRUE))
  attr(out, "status") <- attr(out, "status") %||% 0L
  out
}

#' @keywords internal
.fw_git_ok <- function(out) identical(as.integer(attr(out, "status")), 0L)

# A path printed by git as a path R can use. On Windows, an MSYS or Cygwin
# git prints /d/temp/... or /cygdrive/d/temp/... for D:/temp/....
#' @keywords internal
.fw_git_native_path <- function(path, windows = .Platform$OS.type == "windows") {
  if (!windows) return(path)
  path <- sub("^/cygdrive/([A-Za-z])(/|$)", "\\U\\1:/", path, perl = TRUE)
  sub("^/([A-Za-z])(/|$)", "\\U\\1:/", path, perl = TRUE)
}

# The top folder of the work tree holding `dir`, as a path R can use, or NULL
# outside one. `git rev-parse --show-toplevel` can't be used for this: an
# MSYS or Cygwin git on Windows prints /d/temp/... for D:/temp/..., which R
# reads as a different folder. --show-cdup is relative, so it works with any
# git.
#' @keywords internal
.fw_git_toplevel <- function(dir) {
  cdup <- .fw_git(dir, "rev-parse", "--show-cdup")
  if (!.fw_git_ok(cdup)) return(NULL)
  cdup <- if (length(cdup) == 0) "" else trimws(cdup[length(cdup)])
  normalizePath(if (nzchar(cdup)) file.path(dir, cdup) else dir, winslash = "/", mustWork = FALSE)
}

# owner and repo from a GitHub remote URL (https, ssh, or scp-style), or NULL
#' @keywords internal
.fw_github_remote <- function(url) {
  m <- regmatches(url, regexec("github\\.com[:/]+([^/]+)/([^/]+?)(\\.git)?/?$", url))[[1]]
  if (length(m) == 0) {
    return(NULL)
  }
  list(owner = m[2], repo = m[3])
}

# The Pages URL GitHub gives a repository's site
#' @keywords internal
.fw_github_pages_base <- function(owner, repo) {
  host <- paste0(tolower(owner), ".github.io")
  if (identical(tolower(repo), host)) {
    return(paste0("https://", host, "/"))
  }
  paste0("https://", host, "/", repo, "/")
}

# The cloud's Pages URL for this project. One call to /api/v1/me with the
# project token. `known` is FALSE when the cloud can't be asked (no project
# token, no httr2, or the call fails); pages_url is NULL when Pages is off.
#' @keywords internal
.fw_cloud_pages_url <- function(root) {
  token <- .fw_project_token(root)
  if (is.null(token) || !requireNamespace("httr2", quietly = TRUE)) {
    return(list(known = FALSE))
  }
  url <- tryCatch(.fw_project_cloud_url(root), error = function(e) NULL)
  me <- if (is.null(url)) NULL else tryCatch(.fw_api("/api/v1/me", token = token, url = url),
                                             error = function(e) NULL)
  if (is.null(me) || !identical(me$kind, "project")) {
    return(list(known = FALSE))
  }
  pages <- me$pages_url
  list(known = TRUE, pages_url = if (is.character(pages) && nzchar(pages)) pages else NULL, server = url)
}

# Lowercase, with each run of other characters as "-": GitHub Pages URLs
# are case-sensitive. "Final Report (v2).html" becomes "final-report-v2".
#' @keywords internal
.fw_pages_slug <- function(source) {
  name <- tools::file_path_sans_ext(basename(sub("/+$", "", source)))
  gsub("^-+|-+$", "", gsub("[^a-z0-9]+", "-", tolower(name)))
}

# The remote to push to: the branch's upstream, then origin, then any
# GitHub remote. Returns name, owner, repo, and whether an upstream is set.
#' @keywords internal
.fw_pages_remote <- function(top) {
  # Quoted: an MSYS git on Windows expands {u} like a glob and loses the braces
  upstream <- .fw_git(top, "rev-parse", "--abbrev-ref", "--symbolic-full-name", shQuote("@{u}"))
  has_upstream <- .fw_git_ok(upstream)
  names <- .fw_git(top, "remote")
  names <- if (.fw_git_ok(names)) names[nzchar(names)] else character()
  candidates <- c(if (has_upstream) sub("/.*$", "", upstream[1]), "origin", names)
  for (name in unique(candidates[candidates %in% names])) {
    url <- .fw_git(top, "remote", "get-url", name)
    gh <- if (.fw_git_ok(url)) .fw_github_remote(url[1]) else NULL
    if (!is.null(gh)) {
      gh$name <- name
      gh$has_upstream <- has_upstream && identical(name, sub("/.*$", "", upstream[1]))
      return(gh)
    }
  }
  NULL
}

# Copy only the rendered page for `source` from a render folder into `stage`:
# <name>.html, and its <name>_files/ folder when there is one (a
# self-contained render has none). Other files the render left there, such
# as folders Quarto mirrors from the project, stay behind.
#' @keywords internal
.fw_stage_rendered_page <- function(rendered, source, stage) {
  main <- paste0(tools::file_path_sans_ext(basename(source)), ".html")
  found <- list.files(rendered, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  found <- found[basename(found) == main]
  if (length(found) == 0) {
    stop("No HTML output found after rendering ", basename(source), call. = FALSE)
  }
  # The shallowest match is the page (a _files folder can't hold its own name)
  page <- found[order(nchar(found))][1]
  file.copy(page, stage)
  assets <- file.path(dirname(page), paste0(tools::file_path_sans_ext(main), "_files"))
  if (dir.exists(assets)) file.copy(assets, stage, recursive = TRUE)
  invisible(file.path(stage, main))
}

# Stage `source` as a folder whose front page is index.html. Takes rendered
# HTML (with its <name>_files/ folder), a render output folder, or a .qmd or
# .Rmd to render.
#' @keywords internal
.fw_github_stage <- function(source, self_contained = TRUE) {
  stage <- tempfile("fw_pages_")
  dir.create(stage)
  ext <- tolower(tools::file_ext(source))

  if (dir.exists(source)) {
    if (!file.exists(file.path(source, "index.html"))) {
      stop("A folder published to GitHub Pages needs an index.html at its top: ", source, call. = FALSE)
    }
    file.copy(list.files(source, full.names = TRUE, all.files = TRUE, no.. = TRUE),
              stage, recursive = TRUE)
  } else if (ext %in% c("html", "htm")) {
    file.copy(source, stage)
    files_dir <- paste0(tools::file_path_sans_ext(source), "_files")
    if (dir.exists(files_dir)) file.copy(files_dir, stage, recursive = TRUE)
  } else if (ext == "qmd") {
    quarto <- Sys.which("quarto")
    if (!nzchar(quarto)) {
      stop("Rendering requires the quarto CLI on your PATH.", call. = FALSE)
    }
    # Render to a folder of its own: inside a Quarto project, Quarto mirrors
    # the project's folders there (notebooks/x.html, and resources such as
    # outputs/), and only the page and its own _files folder are published
    rendered <- tempfile("fw_render_")
    dir.create(rendered)
    on.exit(unlink(rendered, recursive = TRUE), add = TRUE)
    args <- c("render", shQuote(normalizePath(source)), "--output-dir", shQuote(rendered), "--to", "html")
    if (self_contained) args <- c(args, "--embed-resources")
    message("Rendering ", basename(source), "...")
    result <- system2(quarto, args, stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
      stop("Quarto render failed:\n", paste(result, collapse = "\n"), call. = FALSE)
    }
    .fw_stage_rendered_page(rendered, source, stage)
  } else if (ext == "rmd") {
    if (!requireNamespace("rmarkdown", quietly = TRUE)) {
      stop("Rendering .Rmd requires the rmarkdown package.", call. = FALSE)
    }
    rmarkdown::render(source, output_format = "html_document", output_dir = stage, quiet = TRUE)
  } else {
    stop(
      "GitHub Pages publishing takes rendered HTML, a render folder, ",
      "or a .qmd or .Rmd to render. Got: .", ext,
      call. = FALSE
    )
  }

  # A rendered page becomes index.html; its <name>_files/ folder keeps its
  # name, so relative links still resolve
  if (!file.exists(file.path(stage, "index.html"))) {
    main <- paste0(tools::file_path_sans_ext(basename(source)), ".html")
    if (!file.exists(file.path(stage, main))) {
      htmls <- list.files(stage, pattern = "\\.html?$")
      if (length(htmls) != 1) {
        stop("No single HTML page found to publish from ", source, call. = FALSE)
      }
      main <- htmls
    }
    file.rename(file.path(stage, main), file.path(stage, "index.html"))
  }
  stage
}

#' @keywords internal
.fw_github_publish <- function(source, slug = NULL, self_contained = TRUE, bundle = NULL, visibility = NULL) {
  if (is.null(slug)) {
    slug <- .fw_pages_slug(source)
  }
  if (!is.character(slug) || !grepl("^[a-z0-9]+(-[a-z0-9]+)*$", slug)) {
    stop(
      "`slug` must start with a lowercase letter or digit and use only lowercase ",
      "letters, digits, '.', '_', and '-' (GitHub Pages URLs are case-sensitive).",
      call. = FALSE
    )
  }

  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL) %||% getwd()
  top <- .fw_git_toplevel(root)
  if (is.null(top)) {
    stop("This project isn't a git repository. Create the project on GitHub first.", call. = FALSE)
  }
  remote <- .fw_pages_remote(top)
  if (is.null(remote)) {
    stop("This project has no GitHub remote. Create the project on GitHub first, then publish again.",
         call. = FALSE)
  }

  if (identical(visibility, "private")) {
    message("Publishing to a GitHub-confirmed private Pages site.")
  } else {
    message("GitHub Pages sites are public, even when the repository is private.")
  }
  if (!is.null(bundle)) {
    existing <- list.files(file.path(top, "published"), recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    size <- sum(file.info(existing)$size, na.rm = TRUE) + 2 * sum(vapply(bundle$manifest$files, function(x) x$bytes, numeric(1)))
    if (size > 1e9) stop("Publishing would exceed the 1 GB GitHub Pages site limit.", call. = FALSE)
    if (size > 8e8) warning("The GitHub Pages site is approaching its 1 GB limit.", call. = FALSE)
  }
  if (rlang::is_interactive() && !isTRUE(utils::askYesNo("Publish it?", default = FALSE))) {
    stop("Cancelled: nothing was published.", call. = FALSE)
  }

  stage <- if (is.null(bundle)) .fw_github_stage(source, self_contained = self_contained) else source
  if (is.null(bundle)) on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  # published/ sits at the top of the repository, where the workflow deploys
  # from. Replace published/<slug>/ completely.
  rel <- file.path("published", slug)
  target <- file.path(top, rel)
  receipt <- NULL
  if (!is.null(bundle)) {
    receipt <- .fw_folder_deliver(bundle, list(path = file.path(top, "published")))
    paths <- c(rel, "published/index.html", "published/index.json")
  } else {
    unlink(target, recursive = TRUE)
    dir.create(target, recursive = TRUE)
    file.copy(list.files(stage, full.names = TRUE, all.files = TRUE, no.. = TRUE), target, recursive = TRUE)
    paths <- rel
  }

  # Commit only this folder; anything else the user staged stays staged
  .fw_git(top, "add", "-A", "--", shQuote(paths))
  unchanged <- .fw_git(top, "diff", "--cached", "--quiet", "--", shQuote(paths))
  if (.fw_git_ok(unchanged)) {
    message("No change in ", rel, "; nothing committed or pushed.")
  } else {
    commit <- .fw_git(top, "commit", "-m", shQuote(paste("Publish", slug)), "--", shQuote(paths))
    if (!.fw_git_ok(commit)) {
      stop("git commit failed:\n", paste(commit, collapse = "\n"), call. = FALSE)
    }

    branch <- .fw_git(top, "rev-parse", "--abbrev-ref", "HEAD")[1]
    default <- .fw_git(top, "symbolic-ref", "--short", paste0("refs/remotes/", remote$name, "/HEAD"))
    if (.fw_git_ok(default)) {
      default <- sub("^[^/]+/", "", default[1])
      if (!identical(branch, default)) {
        warning(
          "You're on '", branch, "'. GitHub Pages deploys only from the default branch ('",
          default, "'), so this won't appear until it's merged there.",
          call. = FALSE, immediate. = TRUE
        )
      }
    }

    push <- if (remote$has_upstream) {
      .fw_git(top, "push")
    } else {
      .fw_git(top, "push", "-u", remote$name, "HEAD")
    }
    if (!.fw_git_ok(push)) {
      stop("Committed, but git push failed:\n", paste(push, collapse = "\n"), call. = FALSE)
    }
  }

  cloud <- .fw_cloud_pages_url(root)
  if (isTRUE(cloud$known) && is.null(cloud$pages_url)) {
    warning(
      "GitHub Pages is off for this project. Turn it on under Projects at ",
      cloud$server, ".",
      call. = FALSE, immediate. = TRUE
    )
  }
  base <- if (isTRUE(cloud$known) && !is.null(cloud$pages_url)) {
    cloud$pages_url
  } else {
    .fw_github_pages_base(remote$owner, remote$repo)
  }
  if (!grepl("/$", base)) base <- paste0(base, "/")
  url <- paste0(base, slug, "/")
  message("Published to ", url)
  if (!is.null(receipt)) {
    receipt$driver <- "github"
    receipt$url <- url
    receipt$version_url <- paste0(url, "v/", receipt$version, "/")
    receipt$commit <- .fw_git(top, "rev-parse", "HEAD")[1]
    attr(url, "receipt") <- receipt
  }
  invisible(url)
}
