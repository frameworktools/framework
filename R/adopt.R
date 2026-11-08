#' Adopt an Existing Project Folder
#'
#' Turns a folder you already work in into a Framework project without moving
#' anything. `adopt()` looks at the folder names (never file names or
#' contents, and at most three levels deep), proposes which Framework
#' directory each one is, and lets you accept, change a role, or leave a
#' folder out. It then writes `settings.yml` (a single file) and
#' `.framework/spec.json` describing the folders as they are (with
#' `tools: quarto: true` when a `_quarto.yml` or `.qmd` file is at most three
#' folders deep), and adds the
#' rules of the type's `.gitignore` template that the folder's `.gitignore`
#' lacks (`.env`, `framework.db`, private folders, Quarto's lines), in one
#' block at the end. It never removes a `.gitignore` line, and leaves out a
#' rule that would ignore files git tracks. Nothing else is created, moved,
#' or overwritten, and `scaffold()` works afterwards.
#'
#' The project type follows from the folders: `course` when there are course
#' folders such as `slides/` and `modules/`, `project_sensitive` when private
#' and public folders such as `inputs/private/raw/` match the Privacy Sensitive
#' layout, `project` when any folder matches a Framework directory, and `bare`
#' otherwise. Framework's `settings/` folder and Quarto's `*_files/` render
#' folders are never proposed, and `outputs/notebooks/` becomes a render folder.
#'
#' Folders whose path contains "private" are flagged: consider the Privacy
#' Sensitive structure for that project, and keep those folders out of git.
#'
#' With `cloud = TRUE`, or when you are signed in to Framework Cloud, run
#' `adopt()` interactively, and say yes (the default is No), it then
#' registers the project with [cloud_register()]: the Cloud project gets the
#' folder's layout, the folder is linked (its project token and server go to
#' `.env`, which git is made to ignore first), and the spec is sent. If you
#' don't register, it offers to save the layout as a structure.
#'
#' @param path The project folder (default: the working directory).
#' @param yes If TRUE, accept the proposed mapping without asking. Required
#'   in a non-interactive session.
#' @param sensitive If TRUE, the project holds sensitive data
#'   (`security: sensitive: true`): Framework treats its outputs as private by
#'   default and turns on the sensitive-data guards. NULL (default) asks in
#'   an interactive review when folders look private, and is FALSE otherwise.
#' @param type The project type: "project", "project_sensitive", "course",
#'   "presentation", or "bare". NULL (default) infers it from the folders.
#'   "project_sensitive" implies `sensitive = TRUE`.
#' @param cloud If TRUE, register the adopted project on Framework Cloud and
#'   link it ([cloud_register()]); FALSE never does. NULL (default) asks in an
#'   interactive session when you are signed in.
#'
#' @return Invisibly, a list with `type`, `directories`, and
#'   `extra_directories` as written.
#'
#' @seealso [upgrade()] for a project made by an older Framework,
#'   [cloud_register()] to register and link a project later, and
#'   [structure_import()] to save the layout as a structure on Framework
#'   Cloud.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' adopt("~/projects/old-study")
#' adopt(yes = TRUE)
#' adopt("~/projects/cohort-study", yes = TRUE, sensitive = TRUE)
#' adopt("~/teaching/methods", yes = TRUE, type = "course")
#' }
#' }
#'
#' @export
adopt <- function(path = ".", yes = FALSE, sensitive = NULL, type = NULL, cloud = NULL) {
  checkmate::assert_directory_exists(path)
  checkmate::assert_flag(yes)
  checkmate::assert_flag(cloud, null.ok = TRUE)
  checkmate::assert_flag(sensitive, null.ok = TRUE)
  checkmate::assert_choice(type, .spec_types(), null.ok = TRUE)
  if (identical(type, "project_sensitive")) {
    if (isFALSE(sensitive)) {
      stop("type = \"project_sensitive\" holds sensitive data; leave sensitive out or set it to TRUE.",
           call. = FALSE)
    }
    sensitive <- TRUE
  }
  found <- c(basename(.fw_settings_files(path)),
             if (file.exists(file.path(path, ".framework", "spec.json"))) ".framework/spec.json")
  if (length(found) > 0) {
    stop("This folder is already a Framework project (found ", found[1], "). ",
         "Run framework::upgrade() to bring it to the current layout. Nothing was changed.",
         call. = FALSE)
  }

  mapping <- .adopt_review(.adopt_map(.adopt_scan(path), type = type), yes = yes,
                           allow_empty = TRUE, sensitive = sensitive)
  name <- basename(normalizePath(path))
  spec <- .adopt_spec(mapping, name, use_git = file.exists(file.path(path, ".git")),
                      quarto = .adopt_detect_quarto(path))

  args <- .spec_to_create_args(spec)
  .create_project_config(
    project_dir = path, name = spec$name, type = spec$type, author = spec$author,
    packages = args$packages, directories = spec$directories,
    extra_directories = args$extra_directories, ai = args$ai, git = spec$git,
    scaffold = spec$scaffold, settings_dir = file.path(path, "settings"),
    connections = spec$connections, render_dirs = spec$render_dirs,
    security = spec$security, tools = spec$tools, settings_layout = "flat"
  )
  # Merge the spec's .gitignore into the folder's, adding lines only, and
  # record the .gitignore the project now has
  gitignore <- .adopt_gitignore(path, spec, mapping)
  spec$git$gitignore_content <- paste(gitignore, collapse = "\n")
  .spec_write_record(path, spec)

  message("\n[ok] ", name, " is a Framework project. Run framework::scaffold() in it to start.")
  if (length(mapping$warnings) > 0 && !isTRUE(mapping$sensitive)) {
    message("Some folders look private. Keep them out of git. If the project holds sensitive data, ",
            "adopt it with sensitive = TRUE (fw adopt --sensitive), or set security: sensitive: true ",
            "in settings.yml.")
  }

  # Register on Framework Cloud: when asked to, or, signed in and
  # interactive, when the person says yes (default No)
  offer <- is.null(cloud) && !yes && rlang::is_interactive() && !is.null(.fw_cloud_token())
  host <- if (offer) .fw_cloud_host()
  if (offer) cloud <- isTRUE(.adopt_ask(paste0("Register this project on ", host, "?"), default = FALSE))
  if (isTRUE(cloud)) {
    tryCatch(cloud_register(path), error = function(e) {
      message("Not registered on Framework Cloud: ", conditionMessage(e))
    })
  } else if (offer && isTRUE(.adopt_ask(paste0("Save this folder layout as a structure on ", host, "?"),
                                        default = FALSE))) {
    .structure_upload(mapping, name)
  }
  invisible(mapping[c("type", "directories", "extra_directories")])
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
# descending into skipped or hidden folders. Symbolic links to folders are
# not followed, as in fw and framework-py.
#' @keywords internal
.adopt_scan <- function(path) {
  rules <- .adopt_rules()
  skip <- unlist(rules$skip)
  found <- character()
  walk <- function(rel, depth) {
    if (depth > rules$max_depth) return()
    full <- if (nzchar(rel)) file.path(path, rel) else path
    children <- list.dirs(full, full.names = FALSE, recursive = FALSE)
    for (child in children) {
      if (startsWith(child, ".") || .adopt_skipped(child, skip)) next
      if (.adopt_is_link(file.path(full, child))) next
      child_rel <- if (nzchar(rel)) paste(rel, child, sep = "/") else child
      found <<- c(found, child_rel)
      walk(child_rel, depth + 1)
    }
  }
  walk("", 1)
  sort(found, method = "radix")
}

# Whether a folder name is in the rules' skip list, ignoring case. A skip
# entry with * matches any characters within the name (*_files).
#' @keywords internal
.adopt_skipped <- function(name, skip) {
  name <- tolower(name)
  skip <- tolower(skip)
  literal <- !grepl("*", skip, fixed = TRUE)
  out <- name %in% skip[literal]
  for (glob in skip[!literal]) out <- out | grepl(utils::glob2rx(glob), name)
  out
}

# Whether a folder entry is a symbolic link
#' @keywords internal
.adopt_is_link <- function(path) {
  link <- Sys.readlink(path)
  !is.na(link) && nzchar(link)
}

# Map relative folder paths to Framework directory keys. The shared
# algorithm, documented in inst/conformance/README.md (adopt/):
# 1. Drop folders deeper than max_depth, or with a skipped or hidden segment.
# 2. The type: the one given, or course when enough top-level folders are
#    course signals.
# 3. For each rule that applies to the language and type, in order, and
#    whose key is still free, the first of its paths (in order) that matches
#    a folder neither assigned nor inside an assigned folder, ignoring case,
#    gets the rule's key. render_dirs rules follow, the same way.
# 4. Folders inside an assigned folder are covered by it.
# 5. Of the rest, a folder with no assigned folder inside it becomes an
#    extra directory, unless its parent is one too.
# 6. Any kept path containing "private" (any case) is a warning.
# 7. Without a given type: course, project_sensitive when a private or public
#    key matched, project when any key matched, and bare otherwise.
#' @keywords internal
.adopt_map <- function(folders, language = "r", type = NULL) {
  rules <- .adopt_rules()
  skip <- unlist(rules$skip)
  folders <- unique(sub("/+$", "", unlist(folders)))
  folders <- folders[nzchar(folders)]
  keep <- vapply(strsplit(folders, "/", fixed = TRUE), function(parts) {
    length(parts) <= rules$max_depth && !any(startsWith(parts, ".")) && !any(.adopt_skipped(parts, skip))
  }, logical(1))
  folders <- sort(folders[keep], method = "radix")

  course <- rules$types$course
  top <- tolower(folders[!grepl("/", folders, fixed = TRUE)])
  is_course <- sum(tolower(unlist(course$signals)) %in% top) >= (course$min %||% 2)
  rule_type <- type %||% if (is_course) "course" else "project"
  rules$rules <- Filter(function(r) {
    (is.null(r$languages) || language %in% unlist(r$languages)) &&
      (is.null(r$types) || rule_type %in% unlist(r$types))
  }, rules$rules)

  # A folder inside an assigned folder is covered by it and gets no key
  free <- function(assigned) {
    assigned <- as.character(unlist(assigned, use.names = FALSE))
    !folders %in% assigned &
      !vapply(folders, function(f) any(startsWith(f, paste0(assigned, "/"))), logical(1), USE.NAMES = FALSE)
  }
  directories <- list()
  for (rule in rules$rules) {
    if (!is.null(directories[[rule$key]])) next
    for (pattern in unlist(rule$patterns)) {
      hit <- folders[tolower(folders) == tolower(pattern) & free(directories)]
      if (length(hit) > 0) {
        directories[[rule$key]] <- hit[1]
        break
      }
    }
  }

  # Folders that hold rendered notebooks are render targets, not folders
  render_dirs <- list()
  for (rule in rules$render_dirs) {
    for (pattern in unlist(rule$patterns)) {
      hit <- folders[tolower(folders) == tolower(pattern) & free(c(directories, render_dirs))]
      if (length(hit) > 0) {
        render_dirs[[rule$key]] <- hit[1]
        break
      }
    }
  }

  assigned <- as.character(unlist(c(directories, render_dirs), use.names = FALSE))
  under <- function(f, roots) any(startsWith(f, paste0(roots, "/")))
  rest <- folders[!folders %in% assigned & !vapply(folders, under, logical(1), roots = assigned)]
  pure <- rest[!vapply(rest, function(f) any(startsWith(assigned, paste0(f, "/"))), logical(1))]
  parent <- function(f) if (grepl("/", f, fixed = TRUE)) sub("/[^/]+$", "", f) else ""
  extras_paths <- pure[!vapply(pure, function(f) parent(f) %in% pure, logical(1))]

  extra_directories <- list()
  taken <- c(names(directories), unlist(lapply(rules$rules, `[[`, "key")))
  for (f in extras_paths) {
    key <- .adopt_extra_key(f, c(taken, names(extra_directories)))
    extra_directories[[key]] <- list(label = basename(f), path = f)
  }

  private <- folders[grepl("private", folders, ignore.case = TRUE)]
  if (is.null(type)) {
    type <- if (is_course) {
      "course"
    } else if (any(grepl(rules$types$project_sensitive$key_pattern, names(directories)))) {
      "project_sensitive"
    } else if (length(directories) > 0) {
      "project"
    } else {
      "bare"
    }
  }
  list(
    type = type,
    directories = directories,
    extra_directories = extra_directories,
    render_dirs = render_dirs,
    warnings = lapply(private, function(f) list(code = "private_path", path = f))
  )
}

# An extra directory's key: the path lowercased, runs of other characters
# turned into "_", "dir_" in front when it doesn't start with a letter, and
# "_2", "_3", ... when the key is taken
#' @keywords internal
.adopt_extra_key <- function(path, taken) {
  key <- gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(path)))
  if (!grepl("^[a-z]", key)) key <- paste0("dir_", key)
  base <- key
  i <- 2
  while (key %in% taken) {
    key <- paste0(base, "_", i)
    i <- i + 1
  }
  key
}

# Show the mapping and let the person accept it, change a folder's role, or
# leave a folder out. With private-looking folders, an interactive review
# also asks whether the project holds sensitive data; yes = TRUE never sets it.
#' @keywords internal
.adopt_review <- function(mapping, yes = FALSE, ask_sensitive = TRUE, allow_empty = FALSE,
                          sensitive = NULL) {
  if (identical(mapping$type, "project_sensitive")) sensitive <- TRUE
  mapping$sensitive <- isTRUE(sensitive)
  if (!is.null(sensitive)) ask_sensitive <- FALSE
  if (length(mapping$directories) + length(mapping$extra_directories) == 0) {
    if (!allow_empty) stop("No folders found to map. Nothing was changed.", call. = FALSE)
    # A project of loose files (one analysis.qmd) is still a project: its
    # settings list no folders, and folders are added as they are made
    message("No folders to map: settings.yml will list none. Add folders to it as you make them.")
    return(mapping)
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
             vapply(mapping$extra_directories, `[[`, "", "path", USE.NAMES = FALSE),
             unlist(mapping$render_dirs, use.names = FALSE)),
    role = c(names(mapping$directories), rep("(other folder)", length(mapping$extra_directories)),
             sprintf("(rendered %s)", names(mapping$render_dirs))),
    stringsAsFactors = FALSE
  )
  message("Proposed mapping (type: ", mapping$type %||% "bare",
          if (isTRUE(mapping$sensitive)) ", sensitive data" else "", "):")
  for (i in seq_len(nrow(rows))) message(sprintf("  %2d. %-30s %s", i, rows$path[i], rows$role[i]))
  rows
}

#' @keywords internal
.adopt_set_role <- function(mapping, path, role) {
  mapping$directories <- mapping$directories[unlist(mapping$directories) != path]
  mapping$render_dirs <- mapping$render_dirs[unlist(mapping$render_dirs) != path]
  extra <- vapply(mapping$extra_directories, `[[`, "", "path")
  mapping$extra_directories <- mapping$extra_directories[extra != path]
  if (identical(role, "(leave out)")) return(mapping)
  if (identical(role, "(other folder)")) {
    taken <- c(names(mapping$directories), unlist(lapply(.adopt_rules()$rules, `[[`, "key")),
               names(mapping$extra_directories))
    key <- .adopt_extra_key(path, taken)
    mapping$extra_directories[[key]] <- list(label = basename(path), path = path)
  } else {
    mapping$directories[[role]] <- path
  }
  mapping
}

# The spec adopt() records: a project of the mapped type with exactly the
# mapped folders, Quarto on when the folder uses it, no other tools, no
# default packages, and no AI files. Git is on
# when the folder is a git repository (.git is a folder, or a file in a
# worktree). The type's
# own folders and render folders are not added: the spec describes the folder
# as it is.
#' @keywords internal
.adopt_spec <- function(mapping, name, use_git = FALSE, quarto = FALSE) {
  type <- mapping$type %||% "bare"
  layer <- list(
    type = type, core_files = FALSE, settings_layout = "flat",
    tools = list(quarto = isTRUE(quarto), renv = FALSE),
    directories = mapping$directories,
    extra_directories = mapping$extra_directories,
    git = list(use_git = isTRUE(use_git)),
    ai = list(enabled = FALSE),
    security = list(sensitive = isTRUE(mapping$sensitive) || identical(type, "project_sensitive"))
  )
  spec <- spec_resolve(list(list(kind = "project", key = "adopted", layer = layer)), name = name)
  spec$directories <- .adopt_named(mapping$directories)
  spec$extra_directories <- .adopt_named(mapping$extra_directories)
  spec$render_dirs <- .adopt_named(mapping$render_dirs)
  spec$packages$default_packages <- stats::setNames(list(), character())
  spec$skills <- stats::setNames(list(), character())
  spec$source <- list(origin = "r", adopted = TRUE)
  spec
}

# Whether the folder uses Quarto: a _quarto.yml (or _quarto.yaml) or a .qmd
# file in it or in a folder adopt() scans (at most the rules' max_depth
# deep, skipping the folders it skips), so a Quarto project in notebooks/
# counts. framework-py and fw: the same rule.
#' @keywords internal
.adopt_detect_quarto <- function(path) {
  folders <- c("", .adopt_scan(path))
  for (folder in folders) {
    dir <- if (nzchar(folder)) file.path(path, folder) else path
    files <- list.files(dir, all.files = FALSE, recursive = FALSE)
    if (any(tolower(files) %in% c("_quarto.yml", "_quarto.yaml")) || any(grepl("\\.qmd$", files, ignore.case = TRUE))) {
      return(TRUE)
    }
  }
  FALSE
}

# An empty list that serializes as a JSON object
#' @keywords internal
.adopt_named <- function(x) {
  if (length(x) == 0) stats::setNames(list(), character()) else x
}

# Append the rules the spec's .gitignore template has and the folder's
# .gitignore lacks, plus each folder whose path looks private. Returns the .gitignore's lines afterwards.
#' @keywords internal
.adopt_gitignore <- function(path, spec, mapping) {
  private <- vapply(mapping$warnings, `[[`, "", "path")
  wanted <- c(
    .fw_gitignore_rules(spec$git$gitignore_content),
    if (length(private) > 0) paste0("/", .fw_unignored_folders(path, private), "/")
  )
  plan <- .fw_gitignore_missing(path, wanted)
  .fw_gitignore_append(path, plan$add, "# Added by framework::adopt()")
  if (length(plan$add) > 0) {
    message("  Added to .gitignore (", length(plan$add), " rules): ", .fw_rules_summary(plan$add))
  }
  if (length(plan$negations) > 0) {
    message("  Left out of .gitignore: ", .fw_rules_summary(plan$negations), ". Added after the folder's ",
            "own rules, they could make files in ignored folders committable.")
  }
  if (length(plan$skipped) > 0) {
    message("  Left out of .gitignore because git tracks files they match: ",
            paste(sprintf("%s (%s)", names(plan$skipped), plan$skipped), collapse = ", "))
  }
  file <- file.path(path, ".gitignore")
  if (file.exists(file)) readLines(file, warn = FALSE) else character()
}

# Prompts, wrapped so tests can answer them
#' @keywords internal
.adopt_ask <- function(msg, default = FALSE) utils::askYesNo(msg, default = default)

#' @keywords internal
.adopt_readline <- function(prompt) readline(prompt)

#' @keywords internal
.adopt_menu <- function(choices, title) utils::menu(choices, title = title)
