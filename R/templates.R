# Template management utilities -------------------------------------------------

#' Get the Framework templates directory
#' @keywords internal
.framework_templates_dir <- function(...) {
  file.path(fw_config_dir(), "templates", ...)
}

# Mapping of logical template names to package resources. The notebook,
# script, and presentation templates are your versions of Framework's stubs:
# make_notebook(), make_script(), and make_revealjs() read them (see
# .find_stub_template()), as the Python package does. The gitignore and AI
# templates are kept for older settings; project creation does not read them.
.framework_template_sources <- list(
  notebook = list(file = "notebook-default.qmd", shipped = "stubs"),
  script = list(file = "script-default.R", shipped = "stubs"),
  presentation = list(file = "notebook-revealjs.qmd", shipped = "stubs"),
  gitignore = list(file = "gitignore-project"),
  `gitignore-project` = list(file = "gitignore-project"),
  `gitignore-project_sensitive` = list(file = "gitignore-sensitive"),
  `gitignore-course` = list(file = "gitignore-course"),
  `gitignore-presentation` = list(file = "gitignore-presentation"),
  # AI context templates - project-type specific
  ai_canonical = list(file = "ai-context.project.md"),
  ai_claude = list(file = "ai-context.project.md"),
  ai_claude_project = list(file = "ai-context.project.md"),
  ai_claude_sensitive = list(file = "ai-context.project_sensitive.md"),
  ai_claude_course = list(file = "ai-context.course.md"),
  ai_claude_presentation = list(file = "ai-context.presentation.md"),
  ai_agents = list(file = "ai-context.project.md"),
  ai_copilot = list(file = "ai-context.project.md")
)

.framework_template_path <- function(name) {
  if (!name %in% names(.framework_template_sources)) {
    stop(sprintf("Unknown template: %s", name))
  }

  tpl_dir <- .framework_templates_dir()
  if (!dir.exists(tpl_dir)) {
    dir.create(tpl_dir, recursive = TRUE, showWarnings = FALSE)
  }

  entry <- .framework_template_sources[[name]]
  if (!is.null(entry$subdir)) {
    tpl_dir <- .framework_templates_dir(entry$subdir)
    if (!dir.exists(tpl_dir)) {
      dir.create(tpl_dir, recursive = TRUE, showWarnings = FALSE)
    }
  }

  file.path(tpl_dir, entry$file)
}

.framework_template_default_path <- function(name) {
  entry <- .framework_template_sources[[name]]
  if (!is.null(entry$shipped)) {
    return(system.file(entry$shipped, entry$file, package = "framework", mustWork = TRUE))
  }
  sub_path <- if (!is.null(entry$subdir)) file.path(entry$subdir, entry$file) else entry$file
  system.file("templates", sub_path, package = "framework", mustWork = TRUE)
}

#' Ensure the requested template exists in the user config directory
#' @keywords internal
.ensure_framework_template <- function(name) {
  dest <- .framework_template_path(name)
  if (!file.exists(dest)) {
    default_path <- .framework_template_default_path(name)
    file.copy(default_path, dest, overwrite = FALSE)
  }
  dest
}

#' Read a framework template
#' @keywords internal
.read_framework_template <- function(name) {
  # Yours when you saved one, otherwise Framework's. Reading does not copy
  # the default, so later package updates still reach you.
  path <- .framework_template_path(name)
  if (!file.exists(path)) path <- .framework_template_default_path(name)
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

#' Write (overwrite) a framework template
#' @keywords internal
.write_framework_template <- function(name, contents) {
  path <- .framework_template_path(name)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(contents, con = path, sep = "\n")
  invisible(path)
}

#' Reset a template back to its packaged default
#' @keywords internal
.reset_framework_template <- function(name) {
  dest <- .framework_template_path(name)
  default_path <- .framework_template_default_path(name)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(default_path, dest, overwrite = TRUE)
  invisible(dest)
}

#' List available framework templates
#' @keywords internal
list_framework_templates <- function() {
  names(.framework_template_sources)
}

#' Get the user-editable path for a Framework template
#'
#' @param name Template identifier (e.g., "notebook", "gitignore", "ai_claude")
#' @return Absolute path to the template file, ensuring it exists.
#' @keywords internal
framework_template_path <- function(name) {
  .ensure_framework_template(name)
}

#' Read the contents of a Framework template
#'
#' Templates are your versions of Framework's starter files, kept in the
#' `templates/` folder of your Framework settings. Three are used:
#' `"notebook"` by [make_notebook()] and [make_qmd()] with the default stub,
#' `"script"` by [make_script()], and `"presentation"` by [make_revealjs()].
#' A project's own `stubs/` folder still comes first. The gitignore and AI
#' templates are kept for older settings and are not used by project creation.
#' @inheritParams framework_template_path
#' @return Character scalar containing template contents
#' @export
read_framework_template <- function(name) {
  .read_framework_template(name)
}

#' Overwrite a Framework template with new contents
#'
#' See [read_framework_template()] for which templates are used.
#' @inheritParams framework_template_path
#' @param contents Character string to write to the template file.
#' @return Invisibly returns the file path of the written template.
#' @export
write_framework_template <- function(name, contents) {
  checkmate::assert_string(contents)
  .write_framework_template(name, contents)
}

#' Reset a Framework template back to the packaged default
#' @inheritParams framework_template_path
#' @return Invisibly returns the file path of the reset template.
#' @export
reset_framework_template <- function(name) {
  .reset_framework_template(name)
}
