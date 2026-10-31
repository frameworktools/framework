#' AI Skills Management
#'
#' Framework ships agent "skills" - focused instruction files (SKILL.md) that
#' AI coding assistants load on demand. Skills are installed into a project's
#' `.claude/skills/` directory and indexed from AGENTS.md, so both Claude Code
#' (which discovers them natively) and other agents (which follow the paths
#' listed in AGENTS.md) can use them.
#'
#' @name ai_skills
NULL


#' Where each AI assistant reads skills and which stub file it gets
#'
#' Adding an assistant means adding a row here and to `ASSISTANTS` in
#' data-raw/spec_schema.R. Claude Code does not read `.agents/skills/`
#' (tested with 2.1.312), so it has its own folder. Copilot reads
#' `.agents/skills/` as well as `.github/skills/`.
#' @keywords internal
.ai_assistant_table <- function() {
  list(
    claude = list(skills_dir = ".claude/skills", stub = "CLAUDE.md"),
    codex = list(skills_dir = ".agents/skills", stub = NULL),
    copilot = list(skills_dir = ".agents/skills", stub = ".github/copilot-instructions.md")
  )
}


#' Skills that apply to a given project type
#' @keywords internal
.ai_skills_for_type <- function(project_type) {
  base_skills <- c(
    "framework-workflow",
    "framework-data",
    "framework-packages",
    "framework-outputs"
  )

  if (identical(project_type, "project_sensitive")) {
    base_skills <- c(base_skills, "framework-sensitive-data")
  }

  # Every R project type makes figures
  if (project_type %in% c("project", "project_sensitive", "course", "presentation")) {
    base_skills <- c(base_skills, "ggplot2-exploring", "ggplot2-publishing")
  }

  base_skills
}


#' Install Framework skills into a project
#'
#' Copies the SKILL.md files shipped with the package into
#' `<project>/.claude/skills/<skill-name>/SKILL.md`.
#'
#' @param project_dir Path to the project directory
#' @param project_type Project type ("project", "project_sensitive", "course", "presentation")
#' @param verbose Logical; print a message per installed skill
#' @return Invisible character vector of installed skill names
#' @keywords internal
.ai_install_skills <- function(project_dir = ".", project_type = "project", verbose = TRUE) {
  # Cloud blueprint skills (admin-managed masters) take precedence when a
  # blueprint is stashed for this creation run
  bp <- .fw_blueprint_get()
  cloud_skills <- bp$skills %||% list()
  if (length(cloud_skills) > 0) {
    installed <- character(0)
    for (skill in names(cloud_skills)) {
      target_dir <- file.path(project_dir, ".claude", "skills", skill)
      dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
      writeLines(cloud_skills[[skill]], file.path(target_dir, "SKILL.md"))
      installed <- c(installed, skill)
      if (verbose) {
        message("  Created: .claude/skills/", skill, "/SKILL.md")
      }
    }
    return(invisible(installed))
  }

  template_dir <- system.file("templates", "skills", package = "framework")
  if (!nzchar(template_dir) || !dir.exists(template_dir)) {
    warning("Skill templates not found in package installation")
    return(invisible(character(0)))
  }

  skills <- .ai_skills_for_type(project_type)
  installed <- character(0)

  for (skill in skills) {
    source_file <- file.path(template_dir, skill, "SKILL.md")
    if (!file.exists(source_file)) {
      next
    }

    target_dir <- file.path(project_dir, ".claude", "skills", skill)
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    file.copy(source_file, file.path(target_dir, "SKILL.md"), overwrite = TRUE)
    installed <- c(installed, skill)

    if (verbose) {
      message("  Created: .claude/skills/", skill, "/SKILL.md")
    }
  }

  invisible(installed)
}


#' Update Framework Skills in a Project
#'
#' Re-copies the skill files Framework ships for the project's type (the
#' `framework-*` skills and the ggplot2 skills) from the installed package
#' version into `.claude/skills/`. Run this after upgrading the framework
#' package to pick up improved skill instructions.
#'
#' Only skills Framework ships are touched; any custom skills you add
#' alongside them are left alone.
#'
#' @param project_path Path to the project directory (default: current directory)
#' @return Invisible character vector of updated skill names
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Refresh skills after upgrading the framework package
#' ai_skills_update()
#' }
#' }
ai_skills_update <- function(project_path = ".") {
  config <- tryCatch(
    settings_read(file.path(project_path, "settings.yml")),
    error = function(e) list()
  )
  project_type <- config$project_type %||% "project"

  installed <- .ai_install_skills(project_path, project_type, verbose = TRUE)

  if (length(installed) > 0) {
    message("[ok] Updated ", length(installed), " Framework skill(s)")
  } else {
    message("Note: No skills installed (package skill templates not found)")
  }

  invisible(installed)
}


# x unless it is NA (a missing name in a named vector)
`%|NA|%` <- function(x, y) if (length(x) == 0 || is.na(x)) y else unname(x)

#' Generate the skills index section for AGENTS.md
#'
#' Lists installed skills with their paths so agents that don't discover
#' `.claude/skills/` natively can still find and read them.
#'
#' @param project_type Project type
#' @return Character string with the skills section content
#' @keywords internal
.generate_skills_section <- function(project_type = "project", skills = NULL,
                                     skills_dir = ".claude/skills") {
  skills <- skills %||% .ai_skills_for_type(project_type)

  descriptions <- c(
    "framework-workflow" = "scaffold() initialization, critical rules, creating notebooks/scripts",
    "framework-data" = "reading and saving data (data_read/data_save are mandatory)",
    "framework-packages" = "adding and managing R packages (package_add, never install.packages)",
    "framework-outputs" = "results, caching, database queries, publishing",
    "framework-sensitive-data" = "PII/PHI handling and private/public directory rules",
    "ggplot2-exploring" = "quick, accurate ggplot2 figures for understanding data",
    "ggplot2-publishing" = "polished ggplot2 figures for papers, reports, and slides"
  )

  rows <- vapply(skills, function(skill) {
    sprintf("| `%s` | %s | `%s/%s/SKILL.md` |",
            skill, descriptions[skill] %|NA|% "", skills_dir, skill)
  }, character(1))

  paste(c(
    "Detailed instructions live in skill files, loaded on demand. Claude Code discovers",
    "them automatically; other agents should read the relevant SKILL.md before working",
    "on a matching task.",
    "",
    "| Skill | Covers | Path |",
    "|-------|--------|------|",
    rows
  ), collapse = "\n")
}
