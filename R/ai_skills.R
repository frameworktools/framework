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
      if (dir.exists(target_dir)) {
        if (verbose) message("  Preserved local skill: ", skill)
        next
      }
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
  statuses <- character(0)

  for (skill in skills) {
    source_file <- file.path(template_dir, skill, "SKILL.md")
    if (!file.exists(source_file)) {
      next
    }

    target_dir <- file.path(project_dir, ".claude", "skills", skill)
    skill_hash <- function() {
      if (dir.exists(target_dir)) tryCatch(.skill_hash(.skill_scan(target_dir)), error = function(e) NA) else NULL
    }
    before <- skill_hash()
    if (!.skill_package_install(dirname(source_file), project_dir,
        file.path(".claude", "skills", skill), skill)) {
      if (verbose) message("  Preserved local skill: ", skill)
      statuses[[skill]] <- "Preserved"
      next
    }
    installed <- c(installed, skill)

    status <- if (is.null(before)) "Created" else if (identical(before, skill_hash())) "Up to date" else "Updated"
    statuses[[skill]] <- status
    if (verbose) {
      message("  ", status, ": .claude/skills/", skill, "/SKILL.md")
    }
  }

  # What happened to each skill: Created, Updated, Up to date, or Preserved
  attr(installed, "status") <- statuses
  invisible(installed)
}


#' Update Framework Skills in a Project
#'
#' Re-copies the skill files Framework ships for the project's type (the
#' `framework-*` skills and the ggplot2 skills) from the installed package
#' version into `.claude/skills/`. Run this after upgrading the framework
#' package to pick up improved skill instructions.
#'
#' Locally edited skills and account-owned forks are preserved. Unchanged
#' package skills receive the new package version, including skills installed
#' before `.framework/skills.lock.json` existed whose `SKILL.md` matches any
#' version the package has shipped. Replaced skills are backed up to
#' `.framework/skills-backups/`. Custom skills are left alone.
#'
#' @param project_path Path to the project directory (default: current directory)
#' @return Invisible character vector of the package skills now in the
#'   project (created, updated, or already up to date). Its `status`
#'   attribute names what happened to each skill, including preserved ones.
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
  checkmate::assert_string(project_path, min.chars = 1)
  # A mistyped path must not create a new folder full of skills
  if (!dir.exists(project_path) || !.has_settings_file(project_path)) {
    stop("Not a Framework project (no settings.yml): ", project_path, call. = FALSE)
  }
  config <- tryCatch(
    settings_read(file.path(project_path, "settings.yml")),
    error = function(e) list()
  )
  project_type <- config$project_type %||% "project"

  installed <- .ai_install_skills(project_path, project_type, verbose = TRUE)
  statuses <- attr(installed, "status") %||% character(0)

  if (length(statuses) == 0) {
    message("Note: No skills installed (package skill templates not found)")
  } else {
    counts <- table(factor(statuses, levels = c("Updated", "Created", "Up to date", "Preserved")))
    parts <- c(
      if (counts[["Updated"]] > 0) paste(counts[["Updated"]], "updated"),
      if (counts[["Created"]] > 0) paste(counts[["Created"]], "created"),
      if (counts[["Up to date"]] > 0) paste(counts[["Up to date"]], "already up to date"),
      if (counts[["Preserved"]] > 0) paste(counts[["Preserved"]], "locally edited, kept")
    )
    message("[ok] Framework skills: ", paste(parts, collapse = ", "))
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
