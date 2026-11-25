# Project structure: a folder tree, with optional notes on its paths,
# published as a tree artifact (framework.artifact/v1, kind "tree"). The
# client builds the tree and applies the privacy rules before anything
# uploads: .git is left out, ignored paths publish only as stubs and groups
# with their rule, private folders and folders below `depth` publish as
# stubs with a file count, and `exclude` leaves paths out. The format is in
# framework-cloud docs/plans/2026-11-25-structure-artifacts.md, and Cloud's
# ArtifactTree class is the source of truth for what it accepts.

.fw_structure_cap <- 10000L
.fw_structure_max_nodes <- 5000L
.fw_structure_local_names <- 20L

# --- Ignore rules ---------------------------------------------------------

# A gitignore glob, without its leading and trailing "/", as a regular
# expression body: `*` and `?` stay within a name, `**` crosses folders, and
# a backslash escapes the next character.
#' @keywords internal
.fw_structure_glob_regex <- function(glob) {
  chars <- strsplit(glob, "", fixed = TRUE)[[1]]
  n <- length(chars)
  special <- c(".", "^", "$", "|", "(", ")", "+", "{", "}", "[", "]", "\\", "*", "?")
  escape <- function(ch) if (ch %in% special) paste0("\\", ch) else ch
  out <- character()
  i <- 1L
  while (i <= n) {
    ch <- chars[i]
    if (ch == "*" && i < n && chars[i + 1L] == "*") {
      starts <- i == 1L || chars[i - 1L] == "/"
      if (starts && i + 2L <= n && chars[i + 2L] == "/") {
        out <- c(out, "(.*/)?")
        i <- i + 3L
      } else if (starts && i + 1L == n) {
        out <- c(out, ".*")
        i <- i + 2L
      } else {
        out <- c(out, "[^/]*")
        i <- i + 2L
      }
      next
    }
    if (ch == "*") {
      out <- c(out, "[^/]*")
    } else if (ch == "?") {
      out <- c(out, "[^/]")
    } else if (ch == "\\" && i < n) {
      out <- c(out, escape(chars[i + 1L]))
      i <- i + 1L
    } else if (ch == "[" && any(chars[seq_len(n) > i + 1L] == "]")) {
      close <- which(chars == "]" & seq_len(n) > i + 1L)[1]
      set <- chars[(i + 1L):(close - 1L)]
      if (set[1] == "!") set[1] <- "^"
      set[set == "\\"] <- "\\\\"
      out <- c(out, "[", set, "]")
      i <- close
    } else {
      out <- c(out, escape(ch))
    }
    i <- i + 1L
  }
  paste(out, collapse = "")
}

# One gitignore line as a rule, or NULL for a blank line or a comment: `!`
# negates, a trailing `/` matches folders only, and a leading or middle `/`
# anchors the pattern to the folder the file is in.
#' @keywords internal
.fw_structure_ignore_rule <- function(text, line = NA_integer_) {
  text <- sub("[ \t]+$", "", text)
  if (!nzchar(text) || startsWith(text, "#")) return(NULL)
  pattern <- text
  negate <- startsWith(pattern, "!")
  if (negate) pattern <- substring(pattern, 2L)
  dir_only <- endsWith(pattern, "/")
  pattern <- sub("/+$", "", pattern)
  anchored <- grepl("/", pattern, fixed = TRUE)
  pattern <- sub("^/+", "", pattern)
  if (!nzchar(pattern)) return(NULL)
  body <- .fw_structure_glob_regex(pattern)
  list(rule = text, line = as.integer(line), negate = negate, dir_only = dir_only,
       regex = paste0(if (anchored) "^" else "^(.*/)?", body, "$"))
}

# The rules in a .gitignore file, in order
#' @keywords internal
.fw_structure_ignore_file <- function(file) {
  lines <- readLines(file, warn = FALSE, encoding = "UTF-8")
  rules <- lapply(seq_along(lines), function(i) .fw_structure_ignore_rule(lines[[i]], i))
  Filter(Negate(is.null), rules)
}

# The rule that ignores `path` (relative to the rules' folder, "/"
# separated), or NULL. The last matching rule wins, and a matching `!` rule
# un-ignores.
#' @keywords internal
.fw_structure_ignore_match <- function(rules, path, is_dir) {
  found <- NULL
  for (rule in rules) {
    if (rule$dir_only && !is_dir) next
    if (grepl(rule$regex, path, perl = TRUE)) found <- if (rule$negate) NULL else rule
  }
  found
}

# Run git in `dir`, returning its NUL-separated output as strings, or NULL
# when git fails. `input` is written to its stdin, NUL-separated.
#' @keywords internal
.fw_structure_git <- function(dir, args, input = NULL) {
  git <- Sys.which("git")
  if (!nzchar(git)) return(NULL)
  out <- tempfile("fw_git_")
  on.exit(unlink(out), add = TRUE)
  stdin <- ""
  if (!is.null(input)) {
    stdin <- tempfile("fw_git_in_")
    on.exit(unlink(stdin), add = TRUE)
    con <- file(stdin, "wb")
    for (value in input) writeBin(c(charToRaw(enc2utf8(value)), as.raw(0L)), con)
    close(con)
  }
  status <- suppressWarnings(tryCatch(
    system2(git, c("-C", shQuote(dir), args), stdout = out, stderr = FALSE, stdin = stdin),
    error = function(e) 1L
  ))
  # check-ignore exits 1 when nothing is ignored
  if (!status %in% c(0L, 1L) || !file.exists(out)) return(NULL)
  bytes <- readBin(out, "raw", n = max(file.size(out), 0))
  if (!length(bytes)) return(character())
  ends <- which(bytes == as.raw(0L))
  starts <- c(1L, utils::head(ends, -1L) + 1L)
  values <- vapply(seq_along(ends), function(i) {
    if (ends[i] == starts[i]) "" else rawToChar(bytes[starts[i]:(ends[i] - 1L)])
  }, character(1))
  Encoding(values) <- "UTF-8"
  values
}

# A git rule source as published: a .gitignore relative to `dir`, the
# published folder, or "global" or "info/exclude", never an absolute path.
# git names in-tree sources relative to the work tree's top; `prefix` is
# `dir` relative to that top.
#' @keywords internal
.fw_structure_rule_source <- function(source, prefix) {
  if (grepl("^(/|~|[A-Za-z]:[/\\\\])", source)) return("global")
  if (grepl("(^|/)\\.git/info/exclude$", source) || identical(source, "info/exclude")) return("info/exclude")
  from <- Filter(nzchar, strsplit(prefix, "/", fixed = TRUE)[[1]])
  to <- strsplit(source, "/", fixed = TRUE)[[1]]
  common <- 0L
  while (common < length(from) && common < length(to) - 1L && from[common + 1L] == to[common + 1L]) {
    common <- common + 1L
  }
  paste(c(rep("..", length(from) - common), to[seq_along(to) > common]), collapse = "/")
}

# How ignored paths under `dir` are found. With git, git decides: the
# ignored paths and each one's rule, relative to `dir`. Without git, or
# outside a work tree, the project root's .gitignore, matched here. Returns
# method, a lookup function(path, is_dir) giving a rule (rule, source,
# line) or NULL, and whether `dir` itself is ignored.
#' @keywords internal
.fw_structure_ignores <- function(dir, project_root, base) {
  if (identical(.fw_structure_git_line(dir, c("rev-parse", "--is-inside-work-tree")), "true")) {
    prefix <- .fw_structure_git_line(dir, c("rev-parse", "--show-prefix")) %||% ""
    listed <- .fw_structure_git(dir, c("ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"))
    if (!is.null(listed)) {
      rules <- list()
      if (length(listed)) {
        found <- .fw_structure_git(dir, c("check-ignore", "-v", "-z", "--stdin"), input = listed) %||% character()
        for (i in seq_len(length(found) %/% 4L)) {
          at <- (i - 1L) * 4L
          path <- sub("/+$", "", found[at + 4L])
          rules[[path]] <- list(rule = found[at + 3L],
                                source = .fw_structure_rule_source(found[at + 1L], prefix),
                                line = suppressWarnings(as.integer(found[at + 2L])))
        }
      }
      dirs <- sub("/+$", "", listed[endsWith(listed, "/")])
      root_ignored <- "." %in% dirs || "" %in% dirs
      lookup <- function(path, is_dir) {
        if (is_dir && !path %in% dirs) return(NULL)
        rules[[path]]
      }
      return(list(method = "git", lookup = lookup, root_ignored = root_ignored))
    }
  }
  file <- file.path(project_root, ".gitignore")
  if (!file.exists(file)) {
    return(list(method = "none", lookup = function(path, is_dir) NULL, root_ignored = FALSE))
  }
  rules <- .fw_structure_ignore_file(file)
  source <- .fw_structure_rule_source(".gitignore", base)
  in_project <- function(path) if (nzchar(base)) if (nzchar(path)) paste0(base, "/", path) else base else path
  lookup <- function(path, is_dir) {
    rule <- .fw_structure_ignore_match(rules, in_project(path), is_dir)
    if (is.null(rule)) NULL else list(rule = rule$rule, source = source, line = rule$line)
  }
  # The published folder is ignored when it or a folder above it is
  parts <- Filter(nzchar, strsplit(base, "/", fixed = TRUE)[[1]])
  root_ignored <- any(vapply(seq_along(parts), function(i) {
    !is.null(.fw_structure_ignore_match(rules, paste(parts[seq_len(i)], collapse = "/"), TRUE))
  }, logical(1)))
  list(method = "gitignore", lookup = lookup, root_ignored = root_ignored)
}

# git's output as one trimmed line, or NULL
#' @keywords internal
.fw_structure_git_line <- function(dir, args) {
  git <- Sys.which("git")
  if (!nzchar(git)) return(NULL)
  out <- suppressWarnings(tryCatch(system2(git, c("-C", shQuote(dir), args), stdout = TRUE, stderr = FALSE),
                                   error = function(e) NULL))
  if (!is.null(attr(out, "status")) || !length(out)) return(NULL)
  trimws(out[1])
}

# --- Walking the tree -----------------------------------------------------

# Files under `dir`, counted without following symbolic links or entering
# .git, up to the cap.
#' @keywords internal
.fw_structure_count <- function(dir, cap = .fw_structure_cap) {
  count <- 0L
  stack <- dir
  while (length(stack) && count < cap) {
    here <- stack[1]
    stack <- stack[-1]
    entries <- list.files(here, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    entries <- entries[basename(entries) != ".git"]
    if (!length(entries)) next
    folders <- !nzchar(Sys.readlink(entries)) & dir.exists(entries)
    count <- count + sum(!folders)
    stack <- c(stack, entries[folders])
  }
  as.integer(min(count, cap))
}

# Compiled `exclude` globs: a function(path, is_dir) that is TRUE for a path
# to leave out. Globs read like .gitignore lines.
#' @keywords internal
.fw_structure_excluder <- function(exclude) {
  if (is.null(exclude) || !length(exclude)) return(function(path, is_dir) FALSE)
  checkmate::assert_character(exclude, any.missing = FALSE, min.chars = 1)
  rules <- Filter(Negate(is.null), lapply(exclude, .fw_structure_ignore_rule))
  rules <- lapply(rules, function(rule) {
    rule$negate <- FALSE
    rule
  })
  function(path, is_dir) !is.null(.fw_structure_ignore_match(rules, path, is_dir))
}

# Whether a folder is private by the package's private-path rule (see
# .fw_path_is_private()): named "private" or ending in "_private", or a
# settings folder marked private or under one. Only names inside the project
# count, so a project kept under a folder named private isn't private.
#' @keywords internal
.fw_structure_private <- function(name, full, private_dirs) {
  any(.fw_is_private_folder_name(name)) ||
    (length(private_dirs) > 0 && any(.fw_path_under(.fw_full_path(full), private_dirs)))
}

#' @keywords internal
.fw_structure_join <- function(dir, name) if (nzchar(dir)) paste0(dir, "/", name) else name

# Every entry under `dir`, top down: list(path, parent, name, type ("dir"
# or "file"), level, ignored, private, depth, hidden). Folders that are
# ignored, private, or at `depth` are stubs: not entered, with a file count
# in `hidden`. Excluded paths and .git are left out. `tops` limits the
# first level to those paths (relative to `dir`), for several folders.
#' @keywords internal
.fw_structure_walk <- function(dir, ignores, excluded, private_dirs, depth = Inf, tops = NULL) {
  entries <- list()
  add <- function(entry) entries[[length(entries) + 1L]] <<- entry
  visit <- function(rel, name, parent, level) {
    full <- file.path(dir, rel)
    is_link <- nzchar(Sys.readlink(full))
    is_dir <- !is_link && dir.exists(full)
    if (excluded(rel, is_dir)) return(invisible())
    ignored <- ignores$lookup(rel, is_dir)
    if (!is_dir) {
      add(list(path = rel, parent = parent, name = name, type = "file", level = level, ignored = ignored))
      return(invisible())
    }
    # Every part of the path counts, for a top folder named by its path
    private <- .fw_structure_private(strsplit(rel, "/", fixed = TRUE)[[1]], full, private_dirs)
    at_depth <- level >= depth
    if (private || !is.null(ignored) || at_depth) {
      add(list(path = rel, parent = parent, name = name, type = "dir", level = level, ignored = ignored,
               private = private, depth = at_depth && !private && is.null(ignored),
               hidden = .fw_structure_count(full)))
      return(invisible())
    }
    add(list(path = rel, parent = parent, name = name, type = "dir", level = level))
    children(rel, level + 1L)
  }
  children <- function(rel, level) {
    names <- list.files(file.path(dir, rel), all.files = TRUE, no.. = TRUE)
    names <- sort(names[names != ".git"])
    for (name in names) visit(.fw_structure_join(rel, name), name, rel, level)
  }
  if (is.null(tops)) {
    children("", 1L)
  } else {
    for (top in tops) {
      # A folder inside an ignored folder isn't listed at all
      parts <- strsplit(top, "/", fixed = TRUE)[[1]]
      above <- vapply(seq_len(length(parts) - 1L), function(i) paste(parts[seq_len(i)], collapse = "/"), character(1))
      if (any(vapply(above, function(folder) !is.null(ignores$lookup(folder, TRUE)), logical(1)))) {
        stop(top, " is ignored by git; its structure isn't shown.", call. = FALSE)
      }
      visit(top, top, "", 1L)
    }
  }
  entries
}

# --- Nodes ----------------------------------------------------------------

# The published nodes for walked entries: folders (stubs carry ignored,
# private, depth, and hidden), files that aren't ignored, and ignored files
# as one group per folder and rule. With ignored = "hide", ignored stubs
# and groups are left out, and so is a private folder that is also ignored.
#' @keywords internal
.fw_structure_nodes <- function(entries, ignored = "rules") {
  nodes <- list()
  groups <- list()
  for (entry in entries) {
    if (entry$type == "file" && !is.null(entry$ignored)) {
      if (identical(ignored, "hide")) next
      key <- paste(entry$parent, entry$ignored$rule, entry$ignored$source, entry$ignored$line, sep = "\r")
      if (is.null(groups[[key]])) {
        groups[[key]] <- list(path = entry$parent, type = "ignored", ignored = entry$ignored, hidden = 0L)
      }
      groups[[key]]$hidden <- min(groups[[key]]$hidden + 1L, .fw_structure_cap)
      next
    }
    if (entry$type == "dir" && !is.null(entry$ignored) && identical(ignored, "hide")) next
    node <- list(path = entry$path, type = entry$type)
    if (!is.null(entry$hidden)) {
      if (!is.null(entry$ignored)) node$ignored <- entry$ignored
      if (isTRUE(entry$private)) node$private <- TRUE
      if (isTRUE(entry$depth)) node$depth <- TRUE
      node$hidden <- entry$hidden
    }
    nodes[[length(nodes) + 1L]] <- node
  }
  c(nodes, unname(groups))
}

# A path argument (notes, open, highlight) as a node path: "/" separators,
# no "./" or trailing "/".
#' @keywords internal
.fw_structure_clean_path <- function(path) {
  path <- gsub("\\\\", "/", path)
  path <- sub("^(\\./)+", "", path)
  sub("/+$", "", path)
}

# Check notes, open, and highlight against the nodes: each names a path in
# the tree, open names folders, and a note is plain text up to 500
# characters. Returns them cleaned.
#' @keywords internal
.fw_structure_marks <- function(nodes, notes = NULL, open = NULL, highlight = NULL) {
  paths <- vapply(nodes, `[[`, character(1), "path")
  types <- vapply(nodes, `[[`, character(1), "type")
  folders <- paths[types == "dir"]
  listed <- paths[types != "ignored"]
  missing <- function(what, values) {
    absent <- setdiff(values, listed)
    if (length(absent)) {
      stop(what, " names ", if (length(absent) > 1L) "paths" else "a path", " not in the tree: ",
           paste(absent, collapse = ", "), ".", call. = FALSE)
    }
  }
  if (!is.null(notes) && length(notes)) {
    if (!(is.character(notes) || is.list(notes)) || is.null(names(notes)) ||
        anyNA(names(notes)) || any(!nzchar(names(notes)))) {
      stop('notes takes text named by path, as in c("R/" = "Reusable functions").', call. = FALSE)
    }
    text <- vapply(notes, function(note) {
      if (!is.character(note) || length(note) != 1L || is.na(note)) {
        stop("Each note is one string.", call. = FALSE)
      }
      note
    }, character(1))
    long <- names(text)[nchar(text) > 500L]
    if (length(long)) stop("Notes are up to 500 characters: ", paste(long, collapse = ", "), ".", call. = FALSE)
    slash <- names(text)[endsWith(names(text), "/")]
    keys <- .fw_structure_clean_path(names(text))
    missing("notes", keys)
    not_folders <- slash[!.fw_structure_clean_path(slash) %in% folders]
    if (length(not_folders)) stop("notes names a file as a folder: ", paste(not_folders, collapse = ", "), ".", call. = FALSE)
    if (anyDuplicated(keys)) stop("notes names a path twice: ", paste(unique(keys[duplicated(keys)]), collapse = ", "), ".", call. = FALSE)
    notes <- as.list(stats::setNames(unname(text), keys))
  } else {
    notes <- NULL
  }
  check <- function(what, values) {
    if (is.null(values) || !length(values)) return(NULL)
    checkmate::assert_character(values, any.missing = FALSE, min.chars = 1, .var.name = what)
    values <- unique(.fw_structure_clean_path(values))
    missing(what, values)
    values
  }
  open <- check("open", open)
  not_folders <- setdiff(open, folders)
  if (length(not_folders)) stop("open names files, not folders: ", paste(not_folders, collapse = ", "), ".", call. = FALSE)
  highlight <- check("highlight", highlight)
  list(notes = notes, open = open, highlight = highlight)
}

# --- Building -------------------------------------------------------------

# The project root: the Framework project above the working directory, else
# the git work tree, else the working directory.
#' @keywords internal
.fw_structure_project_root <- function() {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  root <- root %||% .fw_structure_git_line(getwd(), c("rev-parse", "--show-toplevel")) %||% getwd()
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

# `path` as folders relative to the project root, checked
#' @keywords internal
.fw_structure_paths <- function(path, project_root) {
  if (is.null(path)) return("")
  checkmate::assert_character(path, any.missing = FALSE, min.len = 1)
  path <- unique(.fw_structure_clean_path(path))
  path[path == "."] <- ""
  for (one in path) {
    parts <- strsplit(one, "/", fixed = TRUE)[[1]]
    if (grepl("^(/|~|[A-Za-z]:)", one) || ".." %in% parts) {
      stop("path is a folder relative to the project root, without '..': ", one, call. = FALSE)
    }
    full <- if (nzchar(one)) file.path(project_root, one) else project_root
    if (!dir.exists(full) || nzchar(Sys.readlink(full))) stop("Not a folder in the project: ", one, call. = FALSE)
  }
  if (length(path) > 1L && "" %in% path) stop("path names the project root and other folders; name one or the other.", call. = FALSE)
  path
}

# The tree for `path`: the walked entries, the published nodes, and the
# document fields. Errors, before anything uploads, for a published folder
# that is private or ignored, and for notes, open, or highlight naming a
# path not in the tree.
#' @keywords internal
.fw_structure_build <- function(path = NULL, depth = NULL, exclude = NULL, notes = NULL, open = NULL,
                                highlight = NULL, ignored = "rules") {
  checkmate::assert_count(depth, positive = TRUE, null.ok = TRUE)
  project_root <- .fw_structure_project_root()
  paths <- .fw_structure_paths(path, project_root)
  several <- length(paths) > 1L
  base <- if (several) "" else paths
  dir <- if (nzchar(base)) file.path(project_root, base) else project_root
  root <- basename(if (several) project_root else dir)
  private_dirs <- .fw_private_directories(project_root)
  if (!several && nzchar(base)) {
    parts <- strsplit(base, "/", fixed = TRUE)[[1]]
    private <- any(.fw_is_private_folder_name(parts)) ||
      (length(private_dirs) > 0 && .fw_path_under(.fw_full_path(dir), private_dirs))
    if (private) stop(base, " is a private folder; its structure isn't shown.", call. = FALSE)
  }
  ignores <- .fw_structure_ignores(dir, project_root, base)
  if (isTRUE(ignores$root_ignored)) stop(base, " is ignored by git; its structure isn't shown.", call. = FALSE)
  entries <- .fw_structure_walk(dir, ignores, .fw_structure_excluder(exclude), private_dirs,
                                depth = depth %||% Inf, tops = if (several) paths else NULL)
  nodes <- .fw_structure_nodes(entries, ignored)
  marks <- .fw_structure_marks(nodes, notes, open, highlight)
  structure(list(root = root, base = base, method = ignores$method, ignored = ignored,
                 entries = entries, nodes = nodes, notes = marks$notes, open = marks$open,
                 highlight = marks$highlight),
            class = "framework_structure")
}

# The framework.artifact/v1 tree document for a built structure
#' @keywords internal
.fw_structure_document <- function(structure) {
  nodes <- lapply(structure$nodes, function(node) {
    note <- if (node$type != "ignored") structure$notes[[node$path]] else NULL
    if (!is.null(note)) node$note <- note
    node
  })
  document <- list(schema = "framework.artifact/v1", kind = "tree", source = list(language = "r"),
                   root = structure$root, base = structure$base, method = structure$method,
                   nodes = nodes)
  if (length(structure$open)) document$open <- I(structure$open)
  if (length(structure$highlight)) document$highlight <- I(structure$highlight)
  document
}

# --- Printing -------------------------------------------------------------

#' @keywords internal
.fw_structure_glyphs <- function() {
  if (isTRUE(l10n_info()[["UTF-8"]])) {
    list(tee = "\u251c\u2500\u2500 ", last = "\u2514\u2500\u2500 ", pipe = "\u2502   ", blank = "    ",
         dot = "\u00b7")
  } else {
    list(tee = "|-- ", last = "`-- ", pipe = "|   ", blank = "    ", dot = "-")
  }
}

#' @keywords internal
.fw_structure_files <- function(n) {
  count <- format(n, big.mark = ",", scientific = FALSE, trim = TRUE)
  if (n >= .fw_structure_cap) paste0(count, "+ files") else if (n == 1L) "1 file" else paste(count, "files")
}

# Where a rule is: ".gitignore:3", or its source alone without a line
#' @keywords internal
.fw_structure_rule_where <- function(ignored) {
  if (is.na(ignored$line %||% NA)) ignored$source else paste0(ignored$source, ":", ignored$line)
}

#' @keywords internal
.fw_structure_rule_text <- function(ignored) {
  paste0(ignored$rule, " (", .fw_structure_rule_where(ignored), ")")
}

# The tree as lines. Rows are list(parent, name, kind, sort, comment):
# folders first, then files, then ignored rows, each by name ignoring case.
#' @keywords internal
.fw_structure_lines <- function(root, rows) {
  glyphs <- .fw_structure_glyphs()
  # Keyed with a leading "/", since the top level's parent is ""
  by_parent <- split(rows, paste0("/", vapply(rows, `[[`, character(1), "parent")))
  labels <- character()
  comments <- character()
  emit <- function(parent, prefix) {
    kids <- by_parent[[paste0("/", parent)]]
    if (is.null(kids)) return(invisible())
    order <- order(vapply(kids, `[[`, integer(1), "sort"),
                   tolower(vapply(kids, `[[`, character(1), "name")), method = "radix")
    kids <- kids[order]
    for (i in seq_along(kids)) {
      kid <- kids[[i]]
      last <- i == length(kids)
      labels <<- c(labels, paste0(prefix, if (last) glyphs$last else glyphs$tee, kid$name))
      comments <<- c(comments, kid$comment %||% "")
      if (!is.null(kid$path)) emit(kid$path, paste0(prefix, if (last) glyphs$blank else glyphs$pipe))
    }
  }
  emit("", "")
  width <- min(max(c(0L, nchar(labels[nzchar(comments)], type = "width"))) + 2L, 48L)
  pad <- pmax(width - nchar(labels, type = "width"), 2L)
  body <- ifelse(nzchar(comments), paste0(labels, strrep(" ", pad), comments), labels)
  c(paste0(root, "/"), body)
}

# Rows for the local tree (`publish = FALSE`), with ignored files by name,
# up to 20 per folder and rule, or the publish form, with stubs and groups.
#' @keywords internal
.fw_structure_rows <- function(structure, publish = FALSE) {
  dot <- .fw_structure_glyphs()$dot
  join <- function(...) {
    parts <- Filter(function(part) !is.null(part) && nzchar(part), list(...))
    if (length(parts)) paste(unlist(parts), collapse = paste0(" ", dot, " ")) else ""
  }
  notes <- structure$notes %||% list()
  stub <- function(entry) {
    join(if (isTRUE(entry$private)) "private",
         if (!is.null(entry$ignored)) paste("ignored by", .fw_structure_rule_text(entry$ignored)),
         .fw_structure_files(entry$hidden))
  }
  hide <- identical(structure$ignored, "hide")
  rows <- list()
  shown <- list()
  for (entry in structure$entries) {
    if (!is.null(entry$ignored) && hide) next
    if (entry$type == "file" && !is.null(entry$ignored)) {
      if (publish) next
      key <- paste(entry$parent, .fw_structure_rule_text(entry$ignored), sep = "\r")
      shown[[key]] <- c(shown[[key]], entry$name)
      if (length(shown[[key]]) > .fw_structure_local_names) next
      rows[[length(rows) + 1L]] <- list(parent = entry$parent, name = entry$name, sort = 2L,
                                        comment = paste("ignored by", .fw_structure_rule_text(entry$ignored)))
      next
    }
    folder <- entry$type == "dir"
    comment <- join(notes[[entry$path]], if (!is.null(entry$hidden)) stub(entry))
    rows[[length(rows) + 1L]] <- list(parent = entry$parent, name = paste0(entry$name, if (folder) "/"),
                                      sort = if (folder) 0L else 1L, comment = comment,
                                      path = if (folder && is.null(entry$hidden)) entry$path)
  }
  if (publish) {
    for (node in structure$nodes) {
      if (node$type != "ignored") next
      rows[[length(rows) + 1L]] <- list(
        parent = node$path, name = sub("/+$", "", node$ignored$rule), sort = 2L,
        comment = join(paste0("ignored (", .fw_structure_rule_where(node$ignored), ")"),
                       .fw_structure_files(node$hidden))
      )
    }
  } else {
    for (key in names(shown)) {
      more <- length(shown[[key]]) - .fw_structure_local_names
      if (more <= 0L) next
      parts <- strsplit(key, "\r", fixed = TRUE)[[1]]
      rows[[length(rows) + 1L]] <- list(parent = parts[1], name = sprintf("... %d more", more), sort = 3L,
                                        comment = paste("ignored by", parts[2]))
    }
  }
  rows
}

#' @export
print.framework_structure <- function(x, ...) {
  cat(.fw_structure_lines(x$root, .fw_structure_rows(x, publish = FALSE)), sep = "\n")
  invisible(x)
}

# --- Exported -------------------------------------------------------------

#' Show a project's structure
#'
#' Lists a project's folders and files as a tree, with each ignored path's
#' `.gitignore` rule, and uploads nothing. [publish_structure()] publishes
#' the same tree to Framework Cloud, where a tutorial or course page can
#' embed it.
#'
#' Ignored paths come from git when it is installed and the project is in a
#' work tree: each shows the rule that ignores it, with the file and line
#' (`.gitignore:3`). Otherwise the project root's `.gitignore` is read on its
#' own. Ignored files are listed by name, up to 20 per folder and rule, and
#' an ignored folder shows its file count. `.git` is always left out.
#'
#' A private folder (named `private` or ending in `_private`, or a settings
#' folder marked private, as [publish()] checks) shows its file count, not
#' its contents. So does a folder below `depth`. Symbolic links show as
#' files and are never followed. File counts stop at 10,000.
#'
#' @param path Folders to show, relative to the project root: one folder, or
#'   several shown as one tree. Default: the project root.
#' @param depth Levels to list. A folder below it shows its file count.
#'   Default: no limit.
#' @param exclude Globs to leave out, written like `.gitignore` lines:
#'   `"*.log"` matches at any level, `"docs/site/"` matches that folder only.
#' @param notes Notes on paths, as text named by path:
#'   `c("R/" = "Reusable functions", "README.md" = "Start here")`. A trailing
#'   `/` on a folder is allowed. Notes are plain text, up to 500 characters.
#' @param open Folders that start open in the embed. Default: the top level
#'   is open, and deeper folders are closed.
#' @param highlight Paths drawn as highlighted in the embed.
#' @param ignored `"rules"` (the default) shows ignored paths with their
#'   rules. `"hide"` leaves them out. Private folders show either way, unless
#'   one is also ignored and `ignored = "hide"`.
#' @return A `framework_structure` object, which prints as the tree.
#'   `notes`, `open`, and `highlight` naming a path not in the published
#'   tree are an error.
#' @seealso [publish_structure()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' fw_structure(notes = c("R/" = "Reusable functions", "README.md" = "Start here"))
#' fw_structure("notebooks", depth = 1)
#' fw_structure(c("R", "notebooks"), exclude = "*.html")
#' }
#' }
fw_structure <- function(path = NULL, depth = NULL, exclude = NULL, notes = NULL, open = NULL,
                         highlight = NULL, ignored = c("rules", "hide")) {
  .fw_structure_build(path = path, depth = depth, exclude = exclude, notes = notes, open = open,
                      highlight = highlight, ignored = match.arg(ignored))
}

#' Publish a project's structure
#'
#' Publishes a project's folder tree to Framework Cloud as a tree artifact,
#' with notes on its paths, so a tutorial or course page can embed it to
#' explain how the project is laid out. [fw_structure()] shows the same tree
#' locally and uploads nothing.
#'
#' Names of ignored paths are never published. An ignored folder publishes
#' as its name, its `.gitignore` rule, and a file count. Ignored files in a
#' folder that isn't ignored publish as one group per rule, with a count. A
#' private folder (named `private` or ending in `_private`, or a settings
#' folder marked private) publishes as its name and a file count, and so
#' does a folder below `depth`. `.git` and `exclude` matches are left out.
#' A rule from the global excludes file or `.git/info/exclude` names that
#' source, never its path. File contents and sizes are never sent.
#'
#' Before uploading, `publish_structure()` prints the tree as it will
#' publish. It then uploads it as `<slug>.json` and prints the version and
#' links, as [publish()] does.
#'
#' @inheritParams fw_structure
#' @param slug Artifact slug. Default: `structure` for the project root or
#'   several folders, and `structure-<folder>` for one subfolder. See
#'   [publish()].
#' @param title Artifact title. Default: `"<folder> structure"`.
#' @param description Artifact description.
#' @param visibility `"public"`, `"unlisted"`, or `"private"`. A new artifact
#'   is unlisted unless set. See [publish()].
#' @param password Password required to view the tree on Framework Cloud.
#' @param collection Existing project collection ID or slug.
#' @param share_unlisted Consent to share an unlisted tree with collection
#'   readers.
#' @param to Publishing destination. See [publish()].
#' @param display Framework Cloud only: what the tree shows when other sites
#'   embed it, such as `list(ignored = FALSE)`. Settings: `title`,
#'   `description` (starts off), `notes`, and `ignored` (the ignored stubs
#'   and groups; private folders stay). See [publish()].
#' @return The artifact URL, invisibly, with the `embed_link` and
#'   `artifact_url` attributes. See [publish()].
#' @seealso [fw_structure()], [publish()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' publish_structure(
#'   notes = c("R/" = "Reusable functions", "README.md" = "Start here"),
#'   highlight = "README.md",
#'   exclude = "renv/"
#' )
#'
#' # One folder, two levels deep
#' publish_structure("notebooks", depth = 2, title = "Notebooks")
#' }
#' }
publish_structure <- function(path = NULL, depth = NULL, exclude = NULL, notes = NULL, open = NULL,
                              highlight = NULL, ignored = c("rules", "hide"), slug = NULL, title = NULL,
                              description = NULL, visibility = NULL, password = NULL, collection = NULL,
                              share_unlisted = FALSE, to = NULL, display = NULL) {
  display <- .fw_display_settings(display)
  checkmate::assert_string(slug, min.chars = 1, null.ok = TRUE)
  tree <- .fw_structure_build(path = path, depth = depth, exclude = exclude, notes = notes, open = open,
                              highlight = highlight, ignored = match.arg(ignored))
  document <- .fw_structure_document(tree)
  if (length(document$nodes) > .fw_structure_max_nodes) {
    stop(sprintf("The tree has %s paths; Framework Cloud takes up to %s. Lower depth or add exclude.",
                 format(length(document$nodes), big.mark = ","),
                 format(.fw_structure_max_nodes, big.mark = ",")), call. = FALSE)
  }
  slug <- slug %||% if (nzchar(tree$base)) .fw_bundle_slug(paste("structure", tree$base)) else "structure"
  slug <- .fw_bundle_slug(slug)
  title <- title %||% paste(tree$root, "structure")
  cat(.fw_structure_lines(tree$root, .fw_structure_rows(tree, publish = TRUE)), sep = "\n")
  stage <- tempfile("fw_structure_")
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  file <- file.path(stage, paste0(slug, ".json"))
  jsonlite::write_json(document, file, auto_unbox = TRUE, null = "null", digits = NA)
  publish(file, slug = slug, title = title, description = description, kind = "tree",
          visibility = visibility, password = password, collection = collection,
          share_unlisted = share_unlisted, to = to, display = display)
}
