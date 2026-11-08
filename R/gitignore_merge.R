# Merging rules into an existing .gitignore, for adopt() and upgrade().
# framework-py: _gitignore.missing_rules() and append_rules().
#
# The rules, shared with framework-py and fw:
# - A rule is a line that is neither blank nor a comment, trimmed. Lines are
#   compared exactly after trimming, so `/.quarto/` and `.quarto/` are
#   different rules (Quarto looks for its own exact lines).
# - Lines are only ever appended, in one block under a comment that names
#   the tool, never removed, reordered, or rewritten.
# - A rule that would ignore a file git already tracks is left out and
#   reported, so the merge never hides files the project keeps in git (a
#   tracked .Rprofile, rendered *_files/ on GitHub Pages).
# - Negations (!...) are left out and reported when the .gitignore already
#   has rules: appended after the project's own rules they would win over
#   them, and could make files in folders the project ignores committable
#   (fore's `inputs/**` with `!inputs/*/`, where the template's
#   `!/inputs/**/README.md` re-included inputs/raw/README.md). Into a new or
#   empty .gitignore the template goes whole, negations included.

# The rules in .gitignore text: lines that are neither blank nor comments,
# trimmed, in order, once each
#' @keywords internal
.fw_gitignore_rules <- function(text) {
  lines <- trimws(unlist(strsplit(paste(text, collapse = "\n"), "\r?\n")))
  unique(lines[nzchar(lines) & !startsWith(lines, "#")])
}

# The rules in `wanted` that the project's .gitignore lacks. Returns a list:
# `add`, the rules to append in order, `skipped`, a named character vector
# of rules left out because they match tracked files (rule -> one such
# file), and `negations`, the negations left out because the .gitignore
# already has rules.
#' @keywords internal
.fw_gitignore_missing <- function(root, wanted) {
  path <- file.path(root, ".gitignore")
  have <- if (file.exists(path)) .fw_gitignore_rules(readLines(path, warn = FALSE)) else character()
  add <- setdiff(.fw_gitignore_rules(wanted), have)
  negations <- if (length(have) > 0) add[startsWith(add, "!")] else character()
  add <- setdiff(add, negations)
  skipped <- character()
  if (length(add) > 0 && .fw_git_work_tree(root)) {
    for (rule in add[!startsWith(add, "!")]) {
      tracked <- .fw_git_tracked_matching(root, rule)
      if (length(tracked) > 0) skipped[[rule]] <- tracked[1]
    }
    add <- setdiff(add, names(skipped))
  }
  list(add = add, skipped = skipped, negations = negations)
}

# The text of .gitignore after appending `add` in a block under `header`
#' @keywords internal
.fw_gitignore_merged <- function(root, add, header) {
  path <- file.path(root, ".gitignore")
  lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  if (length(add) == 0) return(lines)
  if (length(lines) > 0 && nzchar(trimws(lines[length(lines)]))) lines <- c(lines, "")
  c(lines, header, add)
}

# Append `add` to the project's .gitignore under `header`. Returns the rules
# added, invisibly.
#' @keywords internal
.fw_gitignore_append <- function(root, add, header) {
  if (length(add) == 0) return(invisible(character()))
  writeLines(.fw_gitignore_merged(root, add, header), file.path(root, ".gitignore"))
  invisible(add)
}

# Whether `root` is inside a git work tree (and git is installed)
#' @keywords internal
.fw_git_work_tree <- function(root) {
  if (!nzchar(Sys.which("git"))) return(FALSE)
  out <- suppressWarnings(system2("git", c("-C", shQuote(root), "rev-parse", "--is-inside-work-tree"),
                                  stdout = TRUE, stderr = FALSE))
  identical(trimws(out[1]), "true")
}

# Files under `root` that git tracks and `rule` would ignore
#' @keywords internal
.fw_git_tracked_matching <- function(root, rule) {
  out <- suppressWarnings(system2(
    "git", c("-C", shQuote(root), "ls-files", "--cached", "--ignored", paste0("--exclude=", shQuote(rule))),
    stdout = TRUE, stderr = FALSE
  ))
  if (!is.null(attr(out, "status"))) return(character())
  out[nzchar(out)]
}

# The folders (paths from the root) that .gitignore doesn't ignore yet, and
# that the templates' **/private/** and **/*_private/** rules don't cover
#' @keywords internal
.fw_unignored_folders <- function(root, folders) {
  folders <- unique(sub("/+$", "", sub("^\\./", "", folders[nzchar(folders)])))
  if (length(folders) == 0) return(character())
  covered <- vapply(strsplit(folders, "/", fixed = TRUE), function(parts) {
    any(.fw_is_private_folder_name(parts))
  }, logical(1))
  folders <- folders[!covered]
  if (length(folders) == 0) return(character())
  ignored <- tryCatch(.fw_gitignored(paste0(folders, "/.framework-probe"), root),
                      error = function(e) rep(FALSE, length(folders)))
  folders[!ignored]
}

# A short list of rules for messages: the first few, then "and N more"
#' @keywords internal
.fw_rules_summary <- function(rules, n = 6) {
  shown <- paste(utils::head(rules, n), collapse = ", ")
  if (length(rules) > n) shown <- sprintf("%s, and %d more", shown, length(rules) - n)
  shown
}
