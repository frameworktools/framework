#' Create a new Framework project (internal)
#'
#' Low-level function that creates a complete Framework project. This is called
#' by the GUI and by user-facing functions like [new()] and [new_project()].
#' Users should typically use [new()] instead.
#'
#' @param name Project name (used for project title)
#' @param location Full path to the project directory (will be created)
#' @param type Project type: "project", "project_sensitive", "course", "presentation"
#' @param author List with name, email, affiliation
#' @param packages List with use_renv (logical) and default_packages (list of package configs)
#' @param directories Named list of directory paths (notebooks, scripts, functions, etc.)
#' @param extra_directories List of additional custom directories
#' @param ai List with enabled, assistants, canonical_content
#' @param git List with use_git, hooks, gitignore_content
#' @param scaffold List with seed_on_scaffold, seed, set_theme_on_scaffold, ggplot_theme, ide, positron
#' @param quarto List with html and revealjs format configurations for Quarto
#' @param render_dirs Named list of render directory paths for Quarto outputs
#'
#' @return List with success status, project path, and project ID
#' @keywords internal
#' @export
project_create <- function(
  name,
  location,
  type = "project",
  author = list(name = "", email = "", affiliation = ""),
  packages = list(use_renv = FALSE, default_packages = list()),
  directories = list(),
  extra_directories = list(),
  ai = list(enabled = FALSE, assistants = c(), canonical_content = ""),
  git = list(use_git = TRUE, hooks = list(), gitignore_content = ""),
  scaffold = list(
    seed_on_scaffold = FALSE,
    seed = "",
    set_theme_on_scaffold = TRUE,
    ggplot_theme = "theme_minimal"
  ),
  connections = NULL,
  env = NULL,
  quarto = NULL,
  render_dirs = NULL
) {
  # A resolved spec (from spec_resolve()) as the first argument
  if (is.list(name) && !is.null(name$spec_version)) {
    checkmate::assert_string(location, min.chars = 1)
    return(invisible(.project_create_from_spec(name, location)))
  }

  # Validate inputs
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(location, min.chars = 1)
  checkmate::assert_choice(type, c("project", "project_sensitive", "course", "presentation", "bare"))
  checkmate::assert_list(author)
  checkmate::assert_list(packages)
  checkmate::assert_list(directories)
  checkmate::assert_list(ai)
  checkmate::assert_list(git)
  checkmate::assert_list(scaffold)
  if (!is.null(connections)) {
    checkmate::assert_list(connections)
  }
  if (!is.null(env)) {
    checkmate::assert(
      checkmate::check_character(env, len = 1),
      checkmate::check_list(env)
    )
  }

  # "bare" projects get settings.yml, an .Rproj, and (optionally) git -- nothing else
  is_bare <- identical(type, "bare")

  # Backfill render directory defaults when not provided
  if (is.null(render_dirs) || length(render_dirs) == 0) {
    render_dirs <- .default_render_dirs_for_type(type)
  }

  # Ensure quarto list exists and has a root render_dir if catalog defines one
  if (is.null(quarto)) {
    quarto <- list()
  }
  if (is.null(quarto$render_dir)) {
    default_root_dir <- .default_root_render_dir_for_type(type)
    if (!is.null(default_root_dir)) {
      quarto$render_dir <- default_root_dir
    }
  }

  # Use location as the full project directory path
  project_dir <- path.expand(location)

  # Check if directory already exists
  if (dir.exists(project_dir)) {
    stop("Project directory already exists: ", project_dir)
  }

  # Create project directory
  dir.create(project_dir, recursive = TRUE)
  message("Created project directory: ", project_dir)

  # Create subdirectories from directories config
  .create_project_directories(project_dir, directories, extra_directories, render_dirs)

  # For project/project_sensitive: use split files in settings/
  # For course/presentation: everything inline in settings.yml
  use_split_files <- type %in% c("project", "project_sensitive")

  settings_dir <- file.path(project_dir, "settings")
  if (use_split_files) {
    dir.create(settings_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Connections: split file for project/project_sensitive, inline for course/presentation
  connections_rel_path <- if (use_split_files) "settings/connections.yml" else NULL

  .create_project_config(
    project_dir = project_dir,
    name = name,
    type = type,
    author = author,
    packages = packages,
    directories = directories,
    extra_directories = extra_directories,
    ai = ai,
    git = git,
    scaffold = scaffold,
    settings_dir = settings_dir,
    connections = connections,
    connections_file = connections_rel_path,
    render_dirs = render_dirs,
    quarto = quarto
  )

  # Only create separate connections file for split-file projects
  if (use_split_files) {
    .create_connections_file(
      project_dir = project_dir,
      connections = connections,
      relative_path = connections_rel_path
    )
  }

  if (!is_bare) {
    .create_env_file(
      project_dir = project_dir,
      env_config = env
    )
  }

  # Create .gitignore: the given content, else the template for the project
  # type. Every project gets one, because .env holds secrets.
  gitignore <- git$gitignore_content %||% ""
  if (!nzchar(paste(gitignore, collapse = ""))) {
    gitignore <- .spec_gitignore(type, identical(type, "project_sensitive"), list())
  }
  .create_gitignore(project_dir, gitignore)

  # Create AI context files
  if (ai$enabled && !is_bare) {
    .create_ai_files(project_dir, ai$assistants, ai$canonical_content, type, name)
  }

  # Create scaffold.R with seed and theme setup
  if (!is_bare) {
    .create_scaffold_file(project_dir, scaffold)
  }

  # Create .Rproj file (always)
  .create_rproj_file(project_dir, name)

  # Create .code-workspace file for VSCode/Positron users
  ide <- scaffold$ide %||% ""
  positron <- scaffold$positron %||% FALSE
  if (!is_bare && (grepl("vscode|positron", ide, ignore.case = TRUE) || isTRUE(positron))) {
    .create_code_workspace(project_dir, name)
  }

  # Create stub files for specific project types
  .create_stub_files(project_dir, type, name, author)

  # Initialize renv if requested (before git so renv files are committed)
  if (packages$use_renv) {
    .init_renv(project_dir)
  }

  # Generate Quarto configuration files (before git so configs are committed)
  if (!is_bare && (!is.null(quarto) || !is.null(render_dirs))) {
    root_output_dir <- NULL
    if (!is.null(quarto) && !is.null(quarto$render_dir)) {
      root_output_dir <- quarto$render_dir
    }
    quarto_result <- quarto_generate_all(
      project_path = project_dir,
      project_type = type,
      render_dirs = render_dirs,
      quarto_settings = quarto,
      directories = directories,
      root_output_dir = root_output_dir
    )
    if (quarto_result$success) {
      message("[ok] Generated ", quarto_result$count, " Quarto configuration file(s)")
    }
  }

  # Initialize git repository LAST so all files are included in initial commit
  if (git$initialize %||% git$use_git %||% TRUE) {
    .init_git_repo(project_dir, git$hooks)
  }

  # Add to project registry (skip for temp directories used in tests)
  project_id <- NULL
  if (!grepl("^/tmp/|^/var/folders/", project_dir)) {
    project_id <- add_project_to_config(project_dir)
  }

  message("[ok] Project created successfully: ", project_dir)

  list(
    success = TRUE,
    path = project_dir,
    id = project_id
  )
}

# Directory entries that name a file (presentation: presentation.qmd), which
# project creation and bootstrap() must not make into folders
#' @keywords internal
.fw_is_file_entry <- function(path) {
  grepl("\\.(qmd|Rmd|R|md)$", path)
}

#' Create project subdirectories
#' @keywords internal
.create_project_directories <- function(project_dir, directories, extra_directories, render_dirs = NULL) {

  # Create standard directories
  for (dir_name in directories) {
    if (!is.null(dir_name) && nzchar(dir_name)) {
      # Skip output directories to avoid clutter; they'll be created on demand by renders
      if (grepl("^outputs/", dir_name)) {
        next
      }
      # Skip if this looks like a file (has a file extension)
      if (.fw_is_file_entry(dir_name)) {
        next
      }

      dir_path <- file.path(project_dir, dir_name)
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      message("  Created: ", dir_name)
    }
  }

  # Create extra directories
  if (length(extra_directories) > 0) {
    for (extra_dir in extra_directories) {
      if (!is.null(extra_dir$path) && nzchar(extra_dir$path)) {
        dir_path <- file.path(project_dir, extra_dir$path)
        dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
        message("  Created: ", extra_dir$path)
      }
    }
  }

  # Create render output directories (only for notebooks; others lazy-created on demand)
  if (!is.null(render_dirs) && length(render_dirs) > 0) {
    for (dir_name_idx in seq_along(render_dirs)) {
      dir_name <- render_dirs[[dir_name_idx]]
      dir_key <- names(render_dirs)[dir_name_idx]
      if (is.null(dir_name) || !nzchar(dir_name)) next

      # Only pre-create notebook render outputs to reduce clutter
      if (!is.null(dir_key) && !grepl("notebook", dir_key, ignore.case = TRUE)) next

      if (.fw_is_file_entry(dir_name)) next
      dir_path <- file.path(project_dir, dir_name)
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      message("  Created render output: ", dir_name)
    }
  }
}

#' Convert data frame to list of lists for YAML serialization
#' JSON arrays of objects become data frames in R, but YAML needs list of lists
#' @keywords internal
.df_to_list_of_lists <- function(df) {

  if (is.null(df) || length(df) == 0) {
    return(list())
  }
  if (is.data.frame(df)) {
    return(lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE])))
  }
  # Already a list, return as-is
  if (is.list(df)) {
    return(df)
  }
  list()
}

#' Resolve default render directory mappings for a project type from the catalog
#' @keywords internal
.default_render_dirs_for_type <- function(type) {
  catalog_path <- system.file("settings/settings-catalog.yml", package = "framework")
  if (!file.exists(catalog_path)) {
    return(list())
  }
  catalog <- yaml::read_yaml(catalog_path)
  render_dirs <- catalog$project_types[[type]]$render_dirs
  if (is.null(render_dirs)) return(list())

  lapply(render_dirs, function(entry) {
    if (is.list(entry) && !is.null(entry$default)) {
      entry$default
    } else {
      entry
    }
  })
}

#' Resolve default root render_dir (if defined) for a project type
#' @keywords internal
.default_root_render_dir_for_type <- function(type) {
  catalog_path <- system.file("settings/settings-catalog.yml", package = "framework")
  if (!file.exists(catalog_path)) {
    return(NULL)
  }
  catalog <- yaml::read_yaml(catalog_path)
  rd <- catalog$project_types[[type]]$quarto$render_dir
  if (is.null(rd)) return(NULL)
  if (is.list(rd) && !is.null(rd$default)) {
    return(rd$default)
  }
  rd
}

#' Create project config.yml
#' @keywords internal
.create_project_config <- function(
  project_dir,
  name,
  type,
  author,
  packages,
  directories,
  extra_directories,
  ai,
  git,
  scaffold,
  settings_dir,
  connections = NULL,
  connections_file = NULL,
  render_dirs = NULL,
  quarto = NULL,
  security = NULL,
  data_hooks = NULL,
  tools = NULL,
  settings_layout = NULL
) {
  # Split settings files for project and project_sensitive by default, a
  # single settings.yml for the rest; a spec's settings_layout decides
  use_split_files <- identical(settings_layout %||% .spec_default_settings_layout(type), "split")
  if (!is.null(packages) && !is.null(tools$renv)) packages$use_renv <- isTRUE(tools$renv)

  if (use_split_files) {
    # Ensure settings directory exists
    dir.create(settings_dir, recursive = TRUE, showWarnings = FALSE)

    # Main settings.yml with ONLY top-level metadata and directory structure
    # Everything else goes in split files
    main_config <- list(
      default = list(
        project_name = name,
        project_type = type,
        tools = if (length(tools) > 0) tools else NULL,

        # Directory configuration (inline for discoverability)
        directories = directories,
        extra_directories = if (length(extra_directories) > 0) extra_directories else NULL,
        render_dirs = render_dirs,

        # References to split files for ALL domain-specific settings
        author = "settings/author.yml",
        packages = "settings/packages.yml",
        git = "settings/git.yml",
        ai = "settings/ai.yml",
        scaffold = "settings/scaffold.yml",
        connections = connections_file,
        quarto = "settings/quarto.yml",
        data = "settings/data.yml",
        security = security,
        data_hooks = if (length(data_hooks) > 0) data_hooks else NULL
      )
    )

    # Write main settings.yml
    yaml::write_yaml(main_config, file.path(project_dir, "settings.yml"))
    message("  Created: settings.yml")

    # Write split files
    yaml::write_yaml(list(author = .author_normalize(author)), file.path(settings_dir, "author.yml"))

    yaml::write_yaml(list(packages = list(
      use_renv = packages$use_renv %||% FALSE,
      default_packages = .df_to_list_of_lists(packages$default_packages)
    )), file.path(settings_dir, "packages.yml"))

    yaml::write_yaml(list(git = list(
      enabled = git$initialize %||% git$use_git %||% TRUE,
      user_name = git$user_name %||% "",
      user_email = git$user_email %||% "",
      hooks = git$hooks
    )), file.path(settings_dir, "git.yml"))

    yaml::write_yaml(list(ai = list(
      enabled = ai$enabled %||% FALSE,
      canonical_file = ai$canonical_file %||% "AGENTS.md",
      assistants = ai$assistants
    )), file.path(settings_dir, "ai.yml"))

    yaml::write_yaml(list(scaffold = list(
      seed_on_scaffold = scaffold$seed_on_scaffold %||% FALSE,
      seed = scaffold$seed %||% "",
      set_theme_on_scaffold = scaffold$set_theme_on_scaffold %||% TRUE,
      ggplot_theme = scaffold$ggplot_theme %||% "theme_minimal",
      notebook_format = scaffold$notebook_format %||% "quarto",
      positron = scaffold$positron %||% FALSE
    )), file.path(settings_dir, "scaffold.yml"))

    # Write quarto settings to split file
    yaml::write_yaml(list(quarto = quarto %||% list()), file.path(settings_dir, "quarto.yml"))

    # Write empty data catalog to split file
    yaml::write_yaml(list(data = list()), file.path(settings_dir, "data.yml"))

    message("  Created: settings/ directory with split configuration files")
  } else {
    # Single settings.yml file for presentation and course types
    config <- list(
      default = list(
        project_name = name,
        project_type = type,
        tools = if (length(tools) > 0) tools else NULL,

        # Author information
        author = .author_normalize(author),

        # Directories (inline for discoverability)
        directories = directories,
        extra_directories = if (length(extra_directories) > 0) extra_directories else NULL,
        render_dirs = render_dirs,
        quarto = quarto,

        # Package configuration
        packages = list(
          use_renv = packages$use_renv %||% FALSE,
          default_packages = .df_to_list_of_lists(packages$default_packages)
        ),

        # Git configuration
        git = list(
          enabled = git$initialize %||% git$use_git %||% TRUE,
          user_name = git$user_name %||% "",
          user_email = git$user_email %||% "",
          hooks = git$hooks
        ),

        # AI configuration
        ai = list(
          enabled = ai$enabled %||% FALSE,
          canonical_file = ai$canonical_file %||% "AGENTS.md",
          assistants = ai$assistants
        ),

        # Scaffold configuration
        scaffold = list(
          seed_on_scaffold = scaffold$seed_on_scaffold %||% FALSE,
          seed = scaffold$seed %||% "",
          set_theme_on_scaffold = scaffold$set_theme_on_scaffold %||% TRUE,
          ggplot_theme = scaffold$ggplot_theme %||% "theme_minimal",
          notebook_format = scaffold$notebook_format %||% "quarto",
          positron = scaffold$positron %||% FALSE
        ),

        # Data catalog (inline for course/presentation)
        data = list(),

        # Connections (inline for course/presentation)
        connections = connections %||% .default_connections_configuration(),

        security = security,
        data_hooks = if (length(data_hooks) > 0) data_hooks else NULL
      )
    )

    config_path <- file.path(project_dir, "settings.yml")
    yaml::write_yaml(config, config_path)
    message("  Created: settings.yml")
  }
}

.default_connections_configuration <- function() {
  list(
    options = list(
      default_connection = "framework"
    ),
    connections = list(
      framework = list(
        driver = "sqlite",
        database = "framework.db"
      )
    )
  )
}

.create_connections_file <- function(project_dir, connections, relative_path) {
  config <- connections

  if (is.null(config) || length(config) == 0) {
    config <- .default_connections_configuration()
  } else if (any(c("databases", "storage_buckets", "default_database", "default_storage_bucket") %in% names(config))) {
    # The spec's shape: wrap it, so settings_read() finds it under `connections`
    config <- list(connections = config)
  } else {
    config$options <- config$options %||% list()
    config$connections <- config$connections %||% list()
    if (is.null(config$options$default_connection) && length(config$connections) > 0) {
      config$options$default_connection <- names(config$connections)[1]
    }
  }

  target_path <- file.path(project_dir, relative_path)
  dir.create(dirname(target_path), recursive = TRUE, showWarnings = FALSE)

  yaml::write_yaml(config, target_path)
  message("  Created: ", relative_path)
}

.create_env_file <- function(project_dir, env_config = NULL) {
  env_lines <- env_resolve_lines(env_config)
  env_path <- file.path(project_dir, ".env")
  writeLines(env_lines, env_path)
  message("  Created: .env")
}

# Make sure .gitignore ignores .env before the first commit. Git lets a later
# line override an earlier one, so the last line that mentions .env decides:
# when there is none, or it is a negation (!.env), `.env` is appended.
#' @keywords internal
.ensure_secrets_ignored <- function(project_dir) {
  path <- file.path(project_dir, ".gitignore")
  lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character(0)
  env_lines <- grep("^!?/?(\\*\\*/)?(\\.env\\*?|\\*\\.env)$", trimws(lines), value = TRUE)
  last <- utils::tail(env_lines, 1)
  covered <- length(last) == 1 && !startsWith(last, "!")
  if (!covered) {
    writeLines(c(lines, "", "# Secrets (added by Framework)", ".env"), path)
    message("  Added .env to .gitignore")
  }
  invisible(!covered)
}

# Ask git itself whether .env is ignored. TRUE when there is no .env.
#' @keywords internal
.secrets_ignored_by_git <- function(project_dir) {
  if (!file.exists(file.path(project_dir, ".env"))) {
    return(TRUE)
  }
  status <- suppressWarnings(system2(
    "git", c("-C", shQuote(project_dir), "check-ignore", "-q", ".env"),
    stdout = FALSE, stderr = FALSE
  ))
  identical(as.integer(status), 0L)
}

#' Create .gitignore file
#' @keywords internal
.create_gitignore <- function(project_dir, content) {
  gitignore_path <- file.path(project_dir, ".gitignore")
  writeLines(content, gitignore_path)
  message("  Created: .gitignore")
}

#' Create AI context files
#'
#' AGENTS.md is always the canonical context file, and Framework skills are
#' installed into .claude/skills/. If the user also selected Claude Code or
#' Copilot, those files are written as thin pointers to AGENTS.md rather than
#' duplicated copies.
#'
#' @keywords internal
.create_ai_files <- function(project_dir, assistants, canonical_content, type,
                             project_name = NULL) {
  if (length(assistants) == 0) {
    assistants <- list("agents")
  }

  # Fall back to directory name if no project name given
  if (is.null(project_name) || !nzchar(project_name)) {
    project_name <- basename(normalizePath(project_dir))
  }

  # Try to read config for dynamic generation
  config <- tryCatch(
    settings_read(file.path(project_dir, "settings.yml")),
    error = function(e) NULL
  )

  # Generate canonical AGENTS.md content. An admin-customized cloud blueprint
  # master wins outright; otherwise generate as usual.
  cloud_master <- .fw_cloud_agents_override(type, project_name)
  if (!is.null(cloud_master)) {
    content <- cloud_master
  } else if (!is.null(config)) {
    content <- ai_generate_context(
      project_path = project_dir,
      project_name = project_name,
      project_type = type,
      config = config
    )
  } else {
    content <- .load_ai_template(type, project_name)
  }

  # If still empty, use provided canonical_content
  if (is.null(content) || !nzchar(content)) {
    content <- canonical_content
  }

  writeLines(content, file.path(project_dir, "AGENTS.md"))
  message("  Created: AGENTS.md")

  # Install Framework skills (detailed instructions loaded on demand)
  .ai_install_skills(project_dir, type)

  # Pointer stubs for assistants that look for their own file
  if ("claude" %in% assistants) {
    writeLines(.ai_pointer_stub(project_name), file.path(project_dir, "CLAUDE.md"))
    message("  Created: CLAUDE.md (points to AGENTS.md)")
  }

  if ("copilot" %in% assistants) {
    dir.create(file.path(project_dir, ".github"), recursive = TRUE, showWarnings = FALSE)
    writeLines(.ai_pointer_stub(project_name),
               file.path(project_dir, ".github", "copilot-instructions.md"))
    message("  Created: .github/copilot-instructions.md (points to AGENTS.md)")
  }
}


#' Pointer stub content for non-canonical AI files
#' @keywords internal
.ai_pointer_stub <- function(project_name) {
  sprintf("# %s

Project instructions live in @AGENTS.md (the canonical AI context file) and in
the skills under `.claude/skills/`. Read AGENTS.md before working here; do not
duplicate its content in this file.
", project_name)
}

#' Load template content from inst/templates
#' @keywords internal
.load_template_content <- function(template_name) {
  template_path <- system.file(sprintf("templates/%s", template_name), package = "framework")
  if (file.exists(template_path)) {
    return(paste(readLines(template_path, warn = FALSE), collapse = "\n"))
  }
  NULL
}

#' Create scaffold.R file
#' @keywords internal
.create_scaffold_file <- function(project_dir, scaffold) {
  scaffold_content <- c(
    "# scaffold.R",
    "# This file is sourced by framework::scaffold() to set up your project environment",
    "",
    "# Set random seed for reproducibility"
  )

  if (scaffold$seed_on_scaffold && nzchar(scaffold$seed)) {
    scaffold_content <- c(
      scaffold_content,
      sprintf('set.seed(%s)', scaffold$seed),
      sprintf('message("Random seed set to %s")', scaffold$seed)
    )
  } else {
    scaffold_content <- c(
      scaffold_content,
      "# set.seed(20241109)  # Uncomment and set your seed"
    )
  }

  scaffold_content <- c(
    scaffold_content,
    "",
    "# Set ggplot2 theme"
  )

  if (scaffold$set_theme_on_scaffold && nzchar(scaffold$ggplot_theme)) {
    scaffold_content <- c(
      scaffold_content,
      "if (requireNamespace('ggplot2', quietly = TRUE)) {",
      sprintf("  ggplot2::theme_set(ggplot2::%s())", scaffold$ggplot_theme),
      sprintf('  message("ggplot2 theme set to %s")', scaffold$ggplot_theme),
      "}"
    )
  } else {
    scaffold_content <- c(
      scaffold_content,
      "# if (requireNamespace('ggplot2', quietly = TRUE)) {",
      "#   ggplot2::theme_set(ggplot2::theme_minimal())",
      "# }"
    )
  }

  scaffold_path <- file.path(project_dir, "scaffold.R")
  writeLines(scaffold_content, scaffold_path)
  message("  Created: scaffold.R")
}

#' Convert string to kebab-case
#' @keywords internal
.to_kebab_case <- function(str) {
  # Convert to lowercase
  result <- tolower(str)
  # Remove non-alphanumeric characters except spaces, underscores, and hyphens
  result <- gsub("[^a-z0-9 _-]", "", result)
  # Replace spaces and underscores with hyphens
  result <- gsub("[ _]+", "-", result)
  # Replace multiple hyphens with single hyphen
  result <- gsub("-+", "-", result)
  # Remove leading/trailing hyphens
  result <- gsub("^-|-$", "", result)
  result
}

#' Create .Rproj file
#' @keywords internal
.create_rproj_file <- function(project_dir, name) {
  kebab_name <- .to_kebab_case(name)

  rproj_content <- c(
    "Version: 1.0",
    "",
    "RestoreWorkspace: No",
    "SaveWorkspace: No",
    "AlwaysSaveHistory: No",
    "",
    "EnableCodeIndexing: Yes",
    "UseSpacesForTab: Yes",
    "NumSpacesForTab: 2",
    "Encoding: UTF-8",
    "",
    "RnwWeave: knitr",
    "LaTeX: XeLaTeX"
  )

  rproj_path <- file.path(project_dir, sprintf("%s.Rproj", kebab_name))
  writeLines(rproj_content, rproj_path)
  message("  Created: ", sprintf("%s.Rproj", kebab_name))
}

#' Create .code-workspace file for VSCode/Positron
#' @keywords internal
.create_code_workspace <- function(project_dir, name) {
  kebab_name <- .to_kebab_case(name)

  # Create basic workspace configuration
  workspace_config <- list(
    folders = list(
      list(path = ".")
    ),
    settings = list(
      `r.rterm.option` = c("--no-save", "--no-restore"),
      `r.sessionWatcher` = TRUE,
      `r.alwaysUseActiveTerminal` = TRUE,
      `files.associations` = list(
        `*.qmd` = "quarto",
        `*.Rmd` = "rmarkdown"
      )
    )
  )

  workspace_path <- file.path(project_dir, sprintf("%s.code-workspace", kebab_name))
  workspace_json <- jsonlite::toJSON(workspace_config, pretty = TRUE, auto_unbox = TRUE)
  writeLines(workspace_json, workspace_path)
  message("  Created: ", sprintf("%s.code-workspace", kebab_name))
}

#' Initialize git repository
#' @keywords internal
.init_git_repo <- function(project_dir, hooks) {
  # Check git is available
  if (!nzchar(Sys.which("git"))) {
    message("  Git not found - skipping repository initialization")
    message("  Install git and run 'git init' manually to enable version control")
    return(invisible(NULL))
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd))
  setwd(project_dir)

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  message("  Initialized git repository")

  # Install git hooks if any are enabled
  # hooks_install() reads settings from config file, so just call it with force=TRUE
  if (length(hooks) > 0 && any(unlist(hooks))) {
    tryCatch({
      git_hooks_install(force = TRUE, verbose = FALSE)
      message("  Installed git hooks")
    }, error = function(e) {
      warning("Failed to install git hooks: ", e$message)
    })
  }

  # Never stage secrets, whatever .gitignore content the caller supplied
  .ensure_secrets_ignored(project_dir)
  if (!.secrets_ignored_by_git(project_dir)) {
    warning(
      "Not making the initial commit: git does not ignore .env, which holds secrets. ",
      "Fix .gitignore, then commit.",
      call. = FALSE
    )
    return(invisible(NULL))
  }

  # Stage all files
  add_result <- system2("git", c("add", "."), stdout = TRUE, stderr = TRUE)

  # Create initial commit with proper message formatting
  # Skip if git identity is missing to avoid hard failures
  user_name <- system2("git", c("config", "user.name"), stdout = TRUE, stderr = TRUE)
  user_email <- system2("git", c("config", "user.email"), stdout = TRUE, stderr = TRUE)
  missing_identity <- identical(attr(user_name, "status"), 1) || identical(attr(user_email, "status"), 1) ||
    (length(user_name) == 0 || !nzchar(user_name)) ||
    (length(user_email) == 0 || !nzchar(user_email))

  if (missing_identity) {
    message("  Skipping initial commit (git user.name/user.email not set). Configure git to enable auto-commit.")
  } else {
    msg_file <- tempfile("framework_init_commit_")
    writeLines("Initial commit from Framework", msg_file)
    on.exit(unlink(msg_file), add = TRUE)

    commit_result <- system2("git", c("commit", "-F", msg_file), stdout = TRUE, stderr = TRUE)
    status <- attr(commit_result, "status")
    if (is.null(status) || identical(status, 0)) {
      message("  Created initial commit")
    }
  }
}

#' Initialize renv
#' @keywords internal
.init_renv <- function(project_dir) {
  old_wd <- getwd()
  on.exit(setwd(old_wd))
  setwd(project_dir)

  if (requireNamespace("renv", quietly = TRUE)) {
    tryCatch({
      renv::init(bare = TRUE)
      message("  Initialized renv")
    }, error = function(e) {
      warning("Failed to initialize renv: ", e$message)
    })
  } else {
    warning("renv package not available - skipping renv initialization")
  }
}

#' Create stub files for specific project types
#' @keywords internal
.create_stub_files <- function(project_dir, type, name, author) {
  author_lines <- paste(.author_front_matter(author), collapse = "\n")

  # Presentation projects need a presentation.qmd file
  if (type == "presentation") {
    presentation_file <- file.path(project_dir, "presentation.qmd")
    presentation_content <- sprintf('---
title: "%s"
%s
date: "`r Sys.Date()`"
format:
  revealjs:
    theme: default
    transition: slide
    slide-number: true
    chalkboard: true
execute:
  echo: true
---

```{r}
#| label: setup
#| include: false

library(framework)
scaffold()
```

## Introduction

Welcome to your presentation!

Edit this file or create new presentations with `make_notebook(stub = "revealjs")`.

## Key Points

- Point 1
- Point 2
- Point 3

## Data Analysis

```{r}
# Load and analyze data
# data <- data_read("example")
summary(mtcars[, 1:3])
```

## Visualization

```{r}
plot(mtcars$mpg, mtcars$hp,
     xlab = "MPG", ylab = "Horsepower",
     main = "Example Plot")
```

## Conclusion

- Summary point 1
- Summary point 2
- Next steps

## Thank You!

Questions?
', name, author_lines)

    writeLines(presentation_content, presentation_file)
    message("  Created: presentation.qmd")
  }

  # Course projects might need similar stub files in the future
  # project and project_sensitive types don't need stub files
}
