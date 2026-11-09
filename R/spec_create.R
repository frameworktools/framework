#' Create a Project from a Layers File
#'
#' Reads a `.framework/layers.json` file (the format framework.pub sends),
#' resolves it with [spec_resolve()], and creates the project in `path`. This
#' is the entry point the framework.pub GitHub Action runs, and it can also be
#' used locally.
#'
#' With `interactive = FALSE` it runs headless, for automation: it never
#' prompts, does not initialize git or make a commit (the caller owns the
#' repository), does not add the project to the local registry, and refuses
#' to write under `.github/workflows/`. In that mode `path` may be an existing
#' git checkout that contains only `.git/`, `.github/`, `.framework/`,
#' `README.md`, and `LICENSE`. Anything else in it is an error, so a
#' misconfigured run cannot overwrite real work.
#'
#' @param layers_file Path to a layers file (see `inst/schema/layers.v1.json`).
#' @param path Directory to create the project in (default: current directory).
#' @param interactive If `FALSE`, run headless as described above.
#'
#' @return Invisibly, a list with `success`, `path`, and the resolved `spec`.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # In the framework.pub GitHub Action
#' project_create_from_layers(".framework/layers.json", path = ".", interactive = FALSE)
#' }
#' }
#'
#' @seealso [spec_resolve()], [project_create()]
#' @export
project_create_from_layers <- function(layers_file, path = ".", interactive = FALSE) {
  checkmate::assert_file_exists(layers_file)
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_flag(interactive)

  envelope <- tryCatch(
    jsonlite::read_json(layers_file, simplifyVector = FALSE),
    error = function(e) {
      stop(sprintf("Failed to read layers file '%s': %s", layers_file, conditionMessage(e)), call. = FALSE)
    }
  )
  if (!identical(as.integer(envelope$spec_version), 1L)) {
    stop(sprintf("Unsupported spec_version in '%s': %s (this framework reads 1)",
                 layers_file, format(envelope$spec_version)), call. = FALSE)
  }
  if (is.null(envelope$name) || !nzchar(envelope$name)) {
    stop(sprintf("Layers file '%s' has no project name", layers_file), call. = FALSE)
  }

  spec <- spec_resolve(envelope$layers %||% list(), name = envelope$name, author = envelope$author)
  if (!is.null(envelope$source)) spec$source <- envelope$source

  result <- .project_create_from_spec(spec, path, headless = !interactive)
  invisible(c(result, list(spec = spec)))
}


# Files and folders allowed in a checkout that headless creation writes into.
.spec_checkout_allowlist <- c(".git", ".github", ".framework", "README.md", "LICENSE")

#' Create a project from a resolved spec
#' @keywords internal
.project_create_from_spec <- function(spec, location, headless = FALSE) {
  problems <- spec_check(spec)
  if (length(problems) > 0) {
    stop("The project spec is invalid:\n", paste0("  - ", problems, collapse = "\n"), call. = FALSE)
  }

  project_dir <- path.expand(location)
  if (headless) {
    .spec_assert_checkout(project_dir)
    workflow_files <- grep("^\\.github/workflows/", names(spec$files), value = TRUE)
    if (length(workflow_files) > 0) {
      stop(sprintf(
        "Headless creation cannot write workflow files (GitHub rejects them from GITHUB_TOKEN pushes): %s",
        paste(workflow_files, collapse = ", ")
      ), call. = FALSE)
    }
  } else if (dir.exists(project_dir)) {
    stop(sprintf("Project directory already exists: %s", project_dir), call. = FALSE)
  }
  dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)
  message("Creating project in: ", project_dir)

  type <- spec$type
  # The bare structure gets no agent files, workspace, or Quarto config;
  # core_files false leaves out only Framework's runtime files, .env and
  # scaffold.R, so a project need not use the framework package
  is_bare <- identical(type, "bare")
  core <- .spec_core_files(spec)
  use_split_files <- identical(.spec_settings_layout(spec), "split")
  tools <- spec$tools %||% list()
  tools$renv <- .spec_tool_on(spec, "renv")
  args <- .spec_to_create_args(spec)

  .create_project_directories(project_dir, spec$directories, args$extra_directories, spec$render_dirs)

  settings_dir <- file.path(project_dir, "settings")
  connections_rel_path <- if (use_split_files) "settings/connections.yml" else NULL
  .create_project_config(
    project_dir = project_dir,
    name = spec$name,
    type = type,
    author = spec$author,
    packages = args$packages,
    directories = spec$directories,
    extra_directories = args$extra_directories,
    ai = args$ai,
    git = spec$git,
    scaffold = spec$scaffold,
    settings_dir = settings_dir,
    connections = spec$connections,
    connections_file = connections_rel_path,
    render_dirs = spec$render_dirs,
    quarto = spec$quarto,
    security = spec$security,
    data_hooks = spec$data_hooks,
    tools = tools,
    settings_layout = .spec_settings_layout(spec),
    publish = spec$publish
  )
  if (use_split_files) {
    .create_connections_file(project_dir, spec$connections, connections_rel_path)
  }

  if (core) {
    .create_env_file(project_dir, list(variables = spec$env))
  }
  .create_gitignore(project_dir, spec$git$gitignore_content)
  .ignore_publish_folders(project_dir, spec$publish, spec$security)

  if (!is_bare && isTRUE(spec$ai$enabled)) {
    .spec_write_ai(project_dir, spec)
  }

  if (core) {
    .create_scaffold_file(project_dir, spec$scaffold)
  }
  editors <- .ide_files(spec$scaffold$ide)
  if (editors$rproj) {
    .create_rproj_file(project_dir, spec$name)
  }
  if (!is_bare && editors$workspace) {
    .create_code_workspace(project_dir, spec$name)
  }
  .create_stub_files(project_dir, type, spec$name, spec$author)

  # Blueprint files last, so they replace generated stubs of the same name
  .spec_write_files(project_dir, spec)

  if (isTRUE(tools$renv)) {
    .init_renv(project_dir)
  }

  if (!is_bare && .spec_tool_on(spec, "quarto")) {
    quarto_result <- quarto_generate_all(
      project_path = project_dir,
      project_type = type,
      render_dirs = spec$render_dirs,
      quarto_settings = spec$quarto,
      directories = spec$directories,
      root_output_dir = spec$quarto$render_dir
    )
    if (isTRUE(quarto_result$success)) {
      message("[ok] Generated ", quarto_result$count, " Quarto configuration file(s)")
    }
  }

  .spec_keep_folders(project_dir)
  .spec_write_record(project_dir, spec)

  project_id <- NULL
  if (!headless) {
    if (isTRUE(spec$git$use_git)) {
      .init_git_repo(project_dir, spec$git$hooks)
    }
    if (!.fw_temp_path(project_dir)) {
      project_id <- add_project_to_config(project_dir)
    }
  }

  if (!headless && .spec_tool_on(spec, "jupyter")) {
    .offer_jupyter_kernel()
  }

  message("[ok] Project created: ", project_dir)
  list(success = TRUE, path = project_dir, id = project_id)
}

# An empty folder holds a .gitkeep, so the folders creation made survive
# git, GitHub, and its Download ZIP. (Outputs and render folders are still
# made when first used, as in Python.)
.spec_keep_folders <- function(project_dir) {
  skip <- "(^|/)(\\.git|renv|\\.quarto|_freeze|node_modules|\\.venv)(/|$)"
  dirs <- list.dirs(project_dir, full.names = FALSE, recursive = TRUE)
  dirs <- dirs[nzchar(dirs) & !grepl(skip, dirs)]
  for (dir_name in dirs) {
    path <- file.path(project_dir, dir_name)
    if (length(list.files(path, all.files = TRUE, no.. = TRUE)) == 0) {
      file.create(file.path(path, ".gitkeep"))
    }
  }
  invisible(TRUE)
}

.spec_assert_checkout <- function(project_dir) {
  if (!dir.exists(project_dir)) return(invisible(TRUE))
  present <- list.files(project_dir, all.files = TRUE, no.. = TRUE)
  unexpected <- setdiff(present, .spec_checkout_allowlist)
  if (length(unexpected) > 0) {
    stop(sprintf(
      "Refusing to create a project in '%s': it already contains %s. Headless creation only runs in a fresh checkout (allowed: %s).",
      project_dir, paste(unexpected, collapse = ", "), paste(.spec_checkout_allowlist, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

# Convert keyed spec sections to the list shapes the settings writers use.
.spec_to_create_args <- function(spec) {
  extra <- lapply(names(spec$extra_directories), function(key) {
    entry <- spec$extra_directories[[key]]
    list(key = key, label = entry$label %||% key, path = entry$path)
  })
  packages <- lapply(names(spec$packages$default_packages), function(name) {
    c(list(name = name), Filter(Negate(is.null), spec$packages$default_packages[[name]]))
  })
  list(
    extra_directories = extra,
    packages = list(use_renv = isTRUE(spec$packages$use_renv), default_packages = packages),
    ai = list(
      enabled = isTRUE(spec$ai$enabled),
      canonical_file = "AGENTS.md",
      assistants = as.list(names(spec$ai$assistants))
    )
  )
}

.spec_template_vars <- function(spec) {
  list(
    project_name = spec$name,
    author = spec$author$name %||% "",
    author_email = spec$author$email %||% "",
    affiliation = spec$author[["affiliation"]] %||% "",
    date = format(Sys.Date())
  )
}

# Replace {{ var }} for the fixed set of variables only, leaving other
# double-brace text (such as Quarto shortcodes) untouched.
.spec_fill_template <- function(content, vars) {
  for (var in names(vars)) {
    content <- gsub(sprintf("\\{\\{\\s*%s\\s*\\}\\}", var), vars[[var]], content, perl = TRUE)
  }
  content
}

.spec_write_text <- function(project_dir, rel_path, content) {
  target <- file.path(project_dir, rel_path)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  tryCatch(
    writeLines(content, target, useBytes = TRUE),
    error = function(e) stop(sprintf("Failed to write '%s': %s", rel_path, conditionMessage(e)), call. = FALSE)
  )
}

.spec_write_files <- function(project_dir, spec) {
  vars <- .spec_template_vars(spec)
  for (rel_path in names(spec$files)) {
    entry <- spec$files[[rel_path]]
    content <- entry$content
    if (isTRUE(entry$template)) content <- .spec_fill_template(content, vars)
    .spec_write_text(project_dir, rel_path, content)
    message("  Created: ", rel_path)
  }
}

# Skills folders and stub files for the selected assistants. With no
# assistants selected, skills go to .agents/skills only.
.spec_assistant_targets <- function(spec) {
  table <- .ai_assistant_table()
  selected <- intersect(names(spec$ai$assistants), names(table))
  if (length(selected) == 0) {
    return(list(skills_dirs = ".agents/skills", stubs = character()))
  }
  rows <- table[selected]
  list(
    skills_dirs = unique(vapply(rows, `[[`, "", "skills_dir")),
    stubs = unlist(lapply(rows, `[[`, "stub"), use.names = FALSE)
  )
}

.spec_write_ai <- function(project_dir, spec) {
  targets <- .spec_assistant_targets(spec)

  for (stub in targets$stubs) {
    content <- if (identical(stub, "CLAUDE.md")) "@AGENTS.md" else .ai_pointer_stub(spec$name)
    .spec_write_text(project_dir, stub, content)
    message("  Created: ", stub)
  }

  for (skill in names(spec$skills)) {
    entry <- spec$skills[[skill]]
    for (skills_dir in targets$skills_dirs) {
      target <- file.path(skills_dir, skill)
      if (isTRUE(entry$package)) {
        source_dir <- system.file("templates", "skills", skill, package = "framework")
        .skill_package_install(source_dir, project_dir, target, skill)
      } else if (!is.null(entry$sync) && !is.null(entry$bundle)) {
        .skill_cloud_install(project_dir, target, entry)
      } else {
        .spec_write_text(project_dir, file.path(target, "SKILL.md"), entry$content)
        for (f in names(entry$files)) {
          .spec_write_text(project_dir, file.path(target, f), entry$files[[f]])
        }
      }
    }
  }
  if (length(spec$skills) > 0) {
    message("  Installed ", length(spec$skills), " skill(s) in ", paste(targets$skills_dirs, collapse = ", "))
  }

  # After the skills, so the skills table can read their descriptions
  if (identical(spec$ai$agents_md, "stub") && !"AGENTS.md" %in% names(spec$files)) {
    .spec_write_text(project_dir, "AGENTS.md", .spec_agents_md(project_dir, spec, targets$skills_dirs[1]))
    message("  Created: AGENTS.md")
  }

  if (isTRUE(spec$security$sensitive)) {
    .spec_write_agent_guards(project_dir, spec)
  }
}

# The full guide, generated from the settings just written; the short stub
# if that fails
.spec_agents_md <- function(project_dir, spec, skills_dir) {
  config <- tryCatch(settings_read(file.path(project_dir, "settings.yml")), error = function(e) NULL)
  content <- if (!is.null(config)) {
    tryCatch(
      ai_generate_context(project_dir, project_name = spec$name, project_type = spec$type,
                          config = config, skills = names(spec$skills), skills_dir = skills_dir,
                          core = .spec_core_files(spec)),
      error = function(e) NULL
    )
  }
  if (is.null(content)) {
    return(.spec_agents_md_stub(spec))
  }
  # Name the folders agents must stay out of, right after the header
  if (isTRUE(spec$security$sensitive)) {
    content <- sub("\n## Skills", paste0("\n", .spec_restricted_notice(spec), "\n\n## Skills"), content, fixed = FALSE)
  }
  content
}

.spec_restricted_notice <- function(spec) {
  sprintf(
    "This project holds restricted data. Do not read or print files in %s. Work from the data dictionary and simulated data instead.",
    paste0("`", .spec_restricted_paths(spec), "`", collapse = ", ")
  )
}

.spec_agents_md_stub <- function(spec) {
  lines <- c(
    sprintf("# %s", spec$name),
    "",
    "This is a Framework project (R). Framework skills for this project are installed for your AI assistant.",
    "",
    "Start every notebook and script with `framework::scaffold()`. It loads the project's settings, packages, and functions."
  )
  if (isTRUE(spec$security$sensitive)) {
    lines <- c(lines, "", .spec_restricted_notice(spec))
  }
  c(lines, "", "## Project Notes", "")
}

# Directories AI agents must not read in a sensitive project: every
# configured folder (directories, extra_directories, render_dirs) with a
# segment named "private" or ending in "_private", collapsed to that
# segment, and every directories entry whose key marks it private
# (inputs_private_raw: inputs/raw), as configured. Folders inside another
# restricted folder are left out. .env (secrets) is added by the callers.
# framework-py: _spec.restricted_paths().
.spec_restricted_paths <- function(spec) {
  clean <- function(x) {
    x <- as.character(unlist(x, use.names = FALSE))
    x <- sub("/+$", "", sub("^\\./", "", x[!is.na(x) & nzchar(x)]))
    x[vapply(x, .spec_is_safe_path, logical(1))]
  }
  paths <- clean(c(spec$directories, lapply(spec$extra_directories, `[[`, "path"), spec$render_dirs))
  restricted <- character()
  for (p in paths) {
    parts <- strsplit(p, "/", fixed = TRUE)[[1]]
    i <- which(.fw_is_private_folder_name(parts))
    if (length(i) > 0) restricted <- c(restricted, paste(parts[seq_len(i[1])], collapse = "/"))
  }
  keys <- tolower(names(spec$directories) %||% character())
  private_keys <- spec$directories[grepl("private", keys, fixed = TRUE) & !grepl("public", keys, fixed = TRUE)]
  restricted <- unique(c(restricted, clean(private_keys)))
  restricted <- restricted[restricted != "."]
  inside <- vapply(restricted, function(p) any(startsWith(p, paste0(setdiff(restricted, p), "/"))), logical(1))
  paste0(sort(restricted[!inside]), "/")
}

# Record how the project was made. The generating package version goes in
# source.framework_version. Keys spec.v1 doesn't allow are left out, and a
# spec that doesn't match it otherwise is never written.
.spec_write_record <- function(project_dir, spec) {
  .spec_write_text(project_dir, ".framework/spec.json", .spec_record_lines(spec))
  message("  Created: .framework/spec.json")
}

# The lines of .framework/spec.json for a spec
.spec_record_lines <- function(spec) {
  record <- spec
  attr(record, "conflicts") <- NULL
  record$source <- record$source %||% list(origin = "r")
  record$source$framework_version <- as.character(utils::packageVersion("framework"))
  record <- .spec_mark_maps(record)
  # Only what spec.v1 allows, so Framework Cloud accepts the spec as written
  record <- .spec_schema_ready(record)$spec
  json <- jsonlite::toJSON(record, auto_unbox = TRUE, pretty = 2, null = "null")
  strsplit(as.character(json), "\n", fixed = TRUE)[[1]]
}

# Keep AI agents out of restricted directories (sensitive projects only).
# Claude Code: Read/Edit deny rules block its file tools and recognized shell
# file commands; the OS sandbox's denyRead also blocks subprocesses such as
# Rscript. failIfUnavailable makes the sandbox fail closed. Other assistants
# get the AGENTS.md rule and the sensitive-data skill only, for now.
.spec_write_agent_guards <- function(project_dir, spec) {
  if (!"claude" %in% names(spec$ai$assistants)) return(invisible(NULL))

  restricted <- sub("/$", "", .spec_restricted_paths(spec))
  deny <- c(
    unlist(lapply(restricted, function(p) c(sprintf("Read(/%s/**)", p), sprintf("Edit(/%s/**)", p)))),
    "Read(/.env)"
  )
  sandbox_deny <- c(paste0("./", restricted), "./.env")

  path <- file.path(project_dir, ".claude", "settings.json")
  settings <- if (file.exists(path)) {
    tryCatch(jsonlite::read_json(path, simplifyVector = FALSE),
             error = function(e) stop(sprintf("Failed to read '%s': %s", path, conditionMessage(e)), call. = FALSE))
  } else {
    list()
  }
  settings$permissions$deny <- as.list(unique(c(unlist(settings$permissions$deny), deny)))
  settings$sandbox$enabled <- TRUE
  settings$sandbox$failIfUnavailable <- TRUE
  settings$sandbox$filesystem$denyRead <- as.list(unique(c(unlist(settings$sandbox$filesystem$denyRead), sandbox_deny)))

  json <- jsonlite::toJSON(settings, auto_unbox = TRUE, pretty = 2)
  .spec_write_text(project_dir, ".claude/settings.json", json)
  message("  Created: .claude/settings.json (keeps Claude Code out of ", paste(restricted, collapse = ", "), ")")
}

# Jupyter needs the R kernel registered once per machine. That writes to the
# user's Jupyter folder, outside R's own, so it only happens when the user
# says yes in an interactive session. Otherwise this prints the command.
#' @keywords internal
.offer_jupyter_kernel <- function() {
  command <- "IRkernel::installspec()"
  if (rlang::is_interactive() && requireNamespace("IRkernel", quietly = TRUE) &&
      isTRUE(utils::askYesNo("Register the R kernel with Jupyter now?", default = FALSE))) {
    IRkernel::installspec()
    return(invisible(TRUE))
  }
  message("To run R notebooks in Jupyter, register the R kernel once on this machine: ",
          if (requireNamespace("IRkernel", quietly = TRUE)) command
          else paste0('install.packages("IRkernel"); ', command))
  invisible(FALSE)
}
