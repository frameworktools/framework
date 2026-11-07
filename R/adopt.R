#' Adopt an Existing Project Folder
#'
#' Turns a folder you already work in into a Framework project without moving
#' anything. `adopt()` looks at the folder names (never file names or
#' contents, and at most three levels deep), proposes which Framework
#' directory each one is, and lets you accept, change a role, or leave a
#' folder out. It then writes `settings.yml` (a single file) and
#' `.framework/spec.json` describing the folders as they are. Nothing else is
#' created, moved, or overwritten, and `scaffold()` works afterwards.
#'
#' Folders whose path contains "private" are flagged: consider the Privacy
#' Sensitive structure for that project, and keep those folders out of git.
#'
#' When you are signed in to Framework Cloud and run `adopt()` interactively,
#' it then offers to register the project (which writes its project token
#' to `.env`, making sure git ignores `.env` first) and to save the layout
#' as a structure. Both default to No.
#'
#' @param path The project folder (default: the working directory).
#' @param yes If TRUE, accept the proposed mapping without asking. Required
#'   in a non-interactive session.
#'
#' @return Invisibly, a list with `directories` and `extra_directories` as
#'   written.
#'
#' @seealso [structure_import()] to save the layout as a structure on
#'   Framework Cloud.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' adopt("~/projects/old-study")
#' adopt(yes = TRUE)
#' }
#' }
#'
#' @export
adopt <- function(path = ".", yes = FALSE) {
  checkmate::assert_directory_exists(path)
  checkmate::assert_flag(yes)
  existing <- file.path(path, c("settings.yml", "settings.yaml", "config.yml", ".framework/spec.json"))
  if (any(file.exists(existing))) {
    stop("This folder is already a Framework project (found ",
         basename(existing[file.exists(existing)][1]), "). Nothing was changed.", call. = FALSE)
  }

  mapping <- .adopt_review(.adopt_map(.adopt_scan(path)), yes = yes)
  name <- basename(normalizePath(path))
  spec <- .adopt_spec(mapping, name)

  args <- .spec_to_create_args(spec)
  .create_project_config(
    project_dir = path, name = spec$name, type = spec$type, author = spec$author,
    packages = args$packages, directories = spec$directories,
    extra_directories = args$extra_directories, ai = args$ai, git = spec$git,
    scaffold = spec$scaffold, settings_dir = file.path(path, "settings"),
    connections = spec$connections,
    security = spec$security, tools = spec$tools, settings_layout = "flat"
  )
  .spec_write_record(path, spec)

  message("\n[ok] ", name, " is a Framework project. Run framework::scaffold() in it to start.")
  if (length(mapping$warnings) > 0) {
    message("Some folders look private. Keep them out of git, and consider the Privacy Sensitive structure.")
  }

  # Signed in and interactive: offer the cloud, default No
  if (!yes && rlang::is_interactive() && !is.null(.fw_cloud_token())) {
    host <- .fw_cloud_host()
    if (isTRUE(.adopt_ask(paste0("Register this project on ", host, "?"), default = FALSE))) {
      # Check before registering, so a tracked .env never leaves a
      # registered project without its token
      ok <- tryCatch({
        .fw_refuse_tracked_env(path)
        TRUE
      }, error = function(e) {
        message(conditionMessage(e))
        FALSE
      })
      if (ok) .fw_cloud_register_project(path, name, spec$type)
    }
    if (isTRUE(.adopt_ask(paste0("Save this folder layout as a structure on ", host, "?"), default = FALSE))) {
      .structure_upload(mapping, name)
    }
  }
  invisible(mapping[c("directories", "extra_directories")])
}

#' Save a Folder's Layout as a Structure on Framework Cloud
#'
#' Maps a folder's layout the same way as [adopt()] and saves it as a
#' structure on Framework Cloud, private to you, so new projects can use it.
#' Only the folder paths and the roles you confirm are sent; file names and
#' contents never are. Changes nothing in the folder.
#'
#' @param path The folder whose layout to import (default: the working
#'   directory).
#' @param name The structure's name. Default: the folder's name.
#' @param yes If TRUE, accept the proposed mapping without asking.
#'
#' @return Invisibly, the cloud's response: `key`, `name`, and `url`.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' structure_import("~/projects/old-study", name = "Lab layout")
#' }
#' }
#'
#' @export
structure_import <- function(path = ".", name = NULL, yes = FALSE) {
  checkmate::assert_directory_exists(path)
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(yes)
  .fw_require_token()
  mapping <- .adopt_review(.adopt_map(.adopt_scan(path)), yes = yes, ask_sensitive = FALSE)
  .structure_upload(mapping, name %||% basename(normalizePath(path)))
}

# POST /api/v1/structures with the confirmed mapping
#' @keywords internal
.structure_upload <- function(mapping, name) {
  token <- .fw_require_token()
  body <- list(name = name, directories = mapping$directories)
  if (length(mapping$extra_directories) > 0) body$extra_directories <- mapping$extra_directories
  res <- .fw_api("/api/v1/structures", token = token, method = "POST", body = body)
  message("[ok] Saved structure ", res$key %||% name, if (!is.null(res$url)) paste0(": ", res$url))
  invisible(res)
}

# The shared rules in inst/adopt/rules.json
#' @keywords internal
.adopt_rules <- function() {
  jsonlite::read_json(system.file("adopt", "rules.json", package = "framework"), simplifyVector = FALSE)
}

# Relative folder paths under `path`, up to the rules' depth, without
# descending into skipped or hidden folders
#' @keywords internal
.adopt_scan <- function(path) {
  rules <- .adopt_rules()
  skip <- tolower(unlist(rules$skip))
  found <- character()
  walk <- function(rel, depth) {
    if (depth > rules$max_depth) return()
    full <- if (nzchar(rel)) file.path(path, rel) else path
    children <- list.dirs(full, full.names = FALSE, recursive = FALSE)
    for (child in children) {
      if (startsWith(child, ".") || tolower(child) %in% skip) next
      child_rel <- if (nzchar(rel)) paste(rel, child, sep = "/") else child
      found <<- c(found, child_rel)
      walk(child_rel, depth + 1)
    }
  }
  walk("", 1)
  sort(found, method = "radix")
}

# Map relative folder paths to Framework directory keys. The shared
# algorithm, documented in inst/conformance/README.md (adopt/):
# 1. Drop folders deeper than max_depth, or with a skipped or hidden segment.
# 2. For each rule in order, the first of its paths (in order) that matches
#    an unassigned folder, ignoring case, gets the rule's key.
# 3. Folders inside an assigned folder are covered by it.
# 4. Of the rest, a folder with no assigned folder inside it becomes an
#    extra directory, unless its parent is one too.
# 5. Any kept path containing "private" (any case) is a warning.
#' @keywords internal
.adopt_map <- function(folders, language = "r") {
  rules <- .adopt_rules()
  rules$rules <- Filter(function(r) is.null(r$languages) || language %in% unlist(r$languages), rules$rules)
  skip <- tolower(unlist(rules$skip))
  folders <- unique(sub("/+$", "", unlist(folders)))
  folders <- folders[nzchar(folders)]
  keep <- vapply(strsplit(folders, "/", fixed = TRUE), function(parts) {
    length(parts) <= rules$max_depth && !any(startsWith(parts, ".")) && !any(tolower(parts) %in% skip)
  }, logical(1))
  folders <- sort(folders[keep], method = "radix")

  directories <- list()
  for (rule in rules$rules) {
    for (pattern in unlist(rule$patterns)) {
      hit <- folders[tolower(folders) == tolower(pattern) & !folders %in% unlist(directories)]
      if (length(hit) > 0) {
        directories[[rule$key]] <- hit[1]
        break
      }
    }
  }

  assigned <- as.character(unlist(directories, use.names = FALSE))
  under <- function(f, roots) any(startsWith(f, paste0(roots, "/")))
  rest <- folders[!folders %in% assigned & !vapply(folders, under, logical(1), roots = assigned)]
  pure <- rest[!vapply(rest, function(f) any(startsWith(assigned, paste0(f, "/"))), logical(1))]
  parent <- function(f) if (grepl("/", f, fixed = TRUE)) sub("/[^/]+$", "", f) else ""
  extras_paths <- pure[!vapply(pure, function(f) parent(f) %in% pure, logical(1))]

  extra_directories <- list()
  taken <- c(names(directories), unlist(lapply(rules$rules, `[[`, "key")))
  for (f in extras_paths) {
    key <- gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(f)))
    if (!grepl("^[a-z]", key)) key <- paste0("dir_", key)
    base <- key
    i <- 2
    while (key %in% c(taken, names(extra_directories))) {
      key <- paste0(base, "_", i)
      i <- i + 1
    }
    extra_directories[[key]] <- list(label = basename(f), path = f)
  }

  private <- folders[grepl("private", folders, ignore.case = TRUE)]
  list(
    directories = directories,
    extra_directories = extra_directories,
    warnings = lapply(private, function(f) list(code = "private_path", path = f))
  )
}

# Show the mapping and let the person accept it, change a folder's role, or
# leave a folder out. With private-looking folders, an interactive review
# also asks whether the project holds sensitive data; yes = TRUE never sets it.
#' @keywords internal
.adopt_review <- function(mapping, yes = FALSE, ask_sensitive = TRUE) {
  mapping$sensitive <- FALSE
  if (length(mapping$directories) + length(mapping$extra_directories) == 0) {
    stop("No folders found to map. Nothing was changed.", call. = FALSE)
  }
  for (w in mapping$warnings) {
    warning("'", w$path, "' looks private. Keep it out of git and away from AI assistants.",
            call. = FALSE, immediate. = TRUE)
  }
  if (yes) {
    .adopt_print(mapping)
    return(mapping)
  }
  if (!rlang::is_interactive()) {
    stop("Review the proposed mapping in an interactive session, or pass yes = TRUE to accept it.",
         call. = FALSE)
  }
  roles <- c(unique(unlist(lapply(.adopt_rules()$rules, `[[`, "key"))), "(other folder)", "(leave out)")
  repeat {
    rows <- .adopt_print(mapping)
    answer <- tolower(trimws(.adopt_readline("Accept (a), change a folder (number), or cancel (q)? [a] ")))
    if (answer %in% c("", "a")) {
      if (ask_sensitive && length(mapping$warnings) > 0) {
        mapping$sensitive <- isTRUE(.adopt_ask(
          "Does this project hold sensitive data? Framework will treat its outputs as private by default.",
          default = FALSE
        ))
      }
      return(mapping)
    }
    if (answer %in% c("q", "c")) stop("Cancelled: nothing was changed.", call. = FALSE)
    i <- suppressWarnings(as.integer(answer))
    if (is.na(i) || i < 1 || i > nrow(rows)) next
    choice <- .adopt_menu(roles, title = paste0("Role for ", rows$path[i], ":"))
    if (choice == 0) next
    mapping <- .adopt_set_role(mapping, rows$path[i], roles[choice])
  }
}

# One row per mapped folder: number, path, and role
#' @keywords internal
.adopt_print <- function(mapping) {
  rows <- data.frame(
    path = c(unlist(mapping$directories, use.names = FALSE),
             vapply(mapping$extra_directories, `[[`, "", "path", USE.NAMES = FALSE)),
    role = c(names(mapping$directories), rep("(other folder)", length(mapping$extra_directories))),
    stringsAsFactors = FALSE
  )
  message("Proposed mapping:")
  for (i in seq_len(nrow(rows))) message(sprintf("  %2d. %-30s %s", i, rows$path[i], rows$role[i]))
  rows
}

#' @keywords internal
.adopt_set_role <- function(mapping, path, role) {
  mapping$directories <- mapping$directories[unlist(mapping$directories) != path]
  extra <- vapply(mapping$extra_directories, `[[`, "", "path")
  mapping$extra_directories <- mapping$extra_directories[extra != path]
  if (identical(role, "(leave out)")) return(mapping)
  if (identical(role, "(other folder)")) {
    key <- gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(path)))
    if (!grepl("^[a-z]", key)) key <- paste0("dir_", key)
    mapping$extra_directories[[key]] <- list(label = basename(path), path = path)
  } else {
    mapping$directories[[role]] <- path
  }
  mapping
}

# The spec adopt() records: a bare project with exactly the mapped folders,
# no tools, no default packages, and no AI files
#' @keywords internal
.adopt_spec <- function(mapping, name) {
  layer <- list(
    type = "bare", core_files = FALSE, settings_layout = "flat",
    tools = list(quarto = FALSE, renv = FALSE),
    directories = mapping$directories,
    extra_directories = mapping$extra_directories,
    git = list(use_git = FALSE),
    ai = list(enabled = FALSE),
    security = list(sensitive = isTRUE(mapping$sensitive))
  )
  spec <- spec_resolve(list(list(kind = "project", key = "adopted", layer = layer)), name = name)
  spec$packages$default_packages <- stats::setNames(list(), character())
  spec$skills <- stats::setNames(list(), character())
  spec$source <- list(origin = "r", adopted = TRUE)
  spec
}

# Prompts, wrapped so tests can answer them
#' @keywords internal
.adopt_ask <- function(msg, default = FALSE) utils::askYesNo(msg, default = default)

#' @keywords internal
.adopt_readline <- function(prompt) readline(prompt)

#' @keywords internal
.adopt_menu <- function(choices, title) utils::menu(choices, title = title)
