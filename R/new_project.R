#' Create a New Framework Project
#'
#' Convenience wrapper for creating Framework projects from the command line.
#' Uses global settings configured via `setup()` as defaults, prompts for
#' missing required values (name and location).
#'
#' @param name Project name. If NULL (default), prompts interactively.
#' @param location Directory path where project will be created. If NULL (default),
#'   prompts interactively.
#' @param type Project type: one of Framework's structures, "project",
#'   "project_sensitive", "course", "presentation", or "bare". NULL (default)
#'   uses your default blueprint on Framework Cloud when you are signed in,
#'   and "project" otherwise.
#' @param tools Tools to turn on, such as `"quarto"`, `"quarto_slides"`,
#'   `"targets"`, `"renv"`, or `"jupyter"`: a character vector, or a named
#'   logical that can also turn a structure's tool off, as in
#'   `c(quarto = FALSE, targets = TRUE)`. Tools a tool needs are added. NULL
#'   (default) keeps the structure's tools: Quarto for every structure except
#'   bare.
#' @param package_sets Character vector of package sets to add, such as
#'   `"tidyverse-analysis"`.
#' @param skill_sets Character vector of AI skill sets to install, such as
#'   `"framework"` and `"ggplot2"`. NULL (default) installs both. A
#'   sensitive project also gets the sensitive-data skill.
#' @param workflow How notebooks are written: `"quarto"`, `"jupyter"`
#'   (Quarto stays on for rendering), or `"scripts"` (plain R scripts, no
#'   notebook tools). NULL (default) keeps your default, or the structure's:
#'   Quarto for every structure except bare.
#' @param offline When you are signed in to Framework Cloud, `new_project()`
#'   sends your choices to it and builds the project it resolves. If the
#'   cloud can't be reached, your saved cloud defaults are used when you
#'   made no choices beyond the name. Otherwise an interactive session asks
#'   before using Framework's built-in defaults, and a non-interactive one
#'   stops. Successful projects are registered with their choices on Cloud
#'   and linked through a project token in the ignored `.env` file.
#'   `offline = TRUE` skips the cloud: saved defaults when there are
#'   any, else the built-ins. Not signed in, the built-ins are used.
#' @param browse Whether to open the project folder after creation (default: TRUE in
#'   interactive sessions)
#' @param ... Ignored, with a warning.
#'
#' @return Invisibly returns the result from `project_create()` (list with success,
#'   path, and project_id)
#'
#' @details
#' This function is designed for the streamlined workflow:
#' ```r
#' remotes::install_github("table1/framework")
#' framework::setup()        # One-time global configuration
#' framework::new_project()  # Create projects using saved defaults
#' ```
#'
#' Global settings from `tools::R_user_dir("framework", "config")` are used for:
#' - Author information (name, email, affiliation
#' - Default packages
#' - Directory structure
#' - Git settings
#' - AI assistant configuration
#' - Quarto format preferences
#'
#' @seealso [setup()] for initial configuration, [project_create()] for full control
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Interactive - prompts for name and location
#' new_project()
#'
#' # With name and location specified
#' new_project("my-analysis", "~/projects/my-analysis")
#'
#' # Create a sensitive data project
#' new_project("medical-study", "~/projects/medical", type = "project_sensitive")
#' }
#' }
#'
#' @param key Optional Framework Cloud project token.
#' @param url Optional Framework Cloud server URL for `key`.
#' @export
new_project <- function(name = NULL, location = NULL, type = NULL, browse = interactive(),
                        tools = NULL, package_sets = NULL, skill_sets = NULL,
                        workflow = NULL, offline = FALSE, key = NULL, url = NULL, ...) {
  if (!is.null(key)) {
    checkmate::assert_string(key, min.chars = 1)
    checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
    if (!is.null(name) || !is.null(type)) {
      stop("With `key`, the name and type come from the cloud project; leave `name` and `type` out.", call. = FALSE)
    }
    return(.cloud_setup(token = key, location = location, browse = browse, url = url))
  }
  # Check global config exists
  config_dir <- fw_config_dir()
  settings_path <- file.path(config_dir, "settings.yml")

  if (!file.exists(settings_path)) {
    message("Global settings not found. Initializing defaults...")
    init_global_config()
  }

  config <- get_default_global_config()

  # Prompt for name if not provided
  if (is.null(name)) {
    if (!interactive()) {
      stop("Project name is required in non-interactive mode")
    }
    name <- readline("Project name: ")
    if (nchar(trimws(name)) == 0) {
      stop("Project name cannot be empty")
    }
    name <- trimws(name)
  }

  # Prompt for location if not provided
  if (is.null(location)) {
    if (!interactive()) {
      stop("Project location is required in non-interactive mode")
    }
    # Suggest a default location based on name
    suggested <- file.path("~", "projects", gsub(" ", "-", tolower(name)))
    location <- readline(paste0("Project location [", suggested, "]: "))
    if (nchar(trimws(location)) == 0) {
      location <- suggested
    }
    location <- trimws(location)
  }

  # Expand path

  location <- path.expand(location)

  # Framework's five structures, or any blueprint label (lowercase id)
  checkmate::assert_string(type, pattern = "^[a-z][a-z0-9_]*$", null.ok = TRUE)
  checkmate::assert_string(workflow, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(offline)
  checkmate::assert(
    checkmate::check_character(tools, null.ok = TRUE),
    checkmate::check_logical(tools, names = "unique", any.missing = FALSE),
    checkmate::check_list(tools, types = "logical", names = "unique"),
    .var.name = "tools"
  )
  checkmate::assert_character(package_sets, null.ok = TRUE)
  checkmate::assert_character(skill_sets, null.ok = TRUE)
  if (length(list(...)) > 0) {
    warning("Ignoring extra arguments to new_project(): ", paste(names(list(...)), collapse = ", "),
            call. = FALSE)
  }

  # Signed in: Framework Cloud resolves the choices. Not signed in, or
  # offline after saying so: Framework's built-ins and local settings.
  choices <- .fw_new_choices(name, type, workflow, tools, package_sets, skill_sets)
  envelope <- .fw_new_envelope(choices, offline = offline)

  args <- .project_args_from_config(config, type %||% "project")
  if (!is.null(envelope)) {
    layers <- envelope$layers %||% list()
    language <- .fw_envelope_language(layers)
    if (!identical(language, "r")) {
      stop(.spec_language_message(language), call. = FALSE)
    }
    spec <- spec_resolve(layers, name = name, author = envelope$author %||% args$author)
  } else {
    type <- type %||% "project"
    # Offline or signed out, only Framework's structures and the project types
    # in your global settings have a layout. Anything else is likely a typo.
    if (!type %in% c(.spec_types(), names(config$project_types))) {
      warning(sprintf(
        "Unknown project type '%s': building Framework's default layout with that label. Framework's types are %s.",
        type, paste(.spec_types(), collapse = ", ")
      ), call. = FALSE)
    }
    layers <- .new_project_layers(args, type, NULL, tools, package_sets, skill_sets, workflow)
    spec <- spec_resolve(layers, name = name, author = args$author)
  }
  type <- spec$type
  spec$source <- list(origin = "r", framework_version = as.character(utils::packageVersion("framework")))

  message("Creating ", type, " project: ", name)
  message("Location: ", location)

  result <- .project_create_from_spec(spec, location)

  # The user's own .env, comments and values included. It stays on this
  # machine, so it never goes through the spec, which can't carry secrets
  if (isTRUE(result$success) && .spec_core_files(spec) && !is.null(args$env)) {
    .create_env_file(result$path, args$env)
  }

  # Register the resolved choices on Cloud. Offline creation stays local.
  # Bare projects are registered without writing a token or creating .env.
  if (result$success && !isTRUE(offline)) {
    .fw_cloud_register_project(result$path, name, type, choices = choices)
  }

  # Open project folder if requested
  if (browse && result$success) {
    if (Sys.info()["sysname"] == "Darwin") {
      system2("open", location)
    } else if (Sys.info()["sysname"] == "Windows") {
      shell.exec(location)
    } else {
      system2("xdg-open", location)
    }
  }

  if (result$success) {
    message("\nProject created successfully!")
    message("Next steps:")
    message("  1. Open the project in your IDE")
    message("  2. Run scaffold() to set up your environment")
    message("  3. Start working with make_notebook() or make_script()")
  }

  invisible(result)
}


#' Create a Sensitive Data Project
#'
#' Shorthand for `new_project(..., type = "project_sensitive")`. Creates a project
#' with additional privacy protections for handling sensitive data.
#'
#' @inheritParams new_project
#'
#' @return Invisibly returns the result from `project_create()`
#'
#' @seealso [new_project()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' new_project_sensitive("medical-study", "~/projects/medical")
#' }
#' }
#'
#' @export
new_project_sensitive <- function(name = NULL, location = NULL, browse = interactive(), ...) {
  new_project(name = name, location = location, type = "project_sensitive", browse = browse, ...)
}


#' Create a Presentation Project
#'
#' Shorthand for `new_project(..., type = "presentation")`. Creates a project
#' optimized for RevealJS presentations.
#'
#' @inheritParams new_project
#'
#' @return Invisibly returns the result from `project_create()`
#'
#' @seealso [new_project()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' new_presentation("quarterly-review", "~/projects/q4-review")
#' }
#' }
#'
#' @export
new_presentation <- function(name = NULL, location = NULL, browse = interactive(), ...) {
  new_project(name = name, location = location, type = "presentation", browse = browse, ...)
}


#' Create a Course Project
#'
#' Shorthand for `new_project(..., type = "course")`. Creates a project
#' structured for teaching materials with slides, assignments, and modules.
#'
#' @inheritParams new_project
#'
#' @return Invisibly returns the result from `project_create()`
#'
#' @seealso [new_project()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' new_course("stats-101", "~/projects/stats-101")
#' }
#' }
#'
#' @export
new_course <- function(name = NULL, location = NULL, browse = interactive(), ...) {
  new_project(name = name, location = location, type = "course", browse = browse, ...)
}


#' Create a New Project (Master Wrapper)
#'
#' Flexible project creation interface. Alias for `new_project()` that accepts
#' type as a parameter.
#'
#' @inheritParams new_project
#' @param type Project type, as in [new_project()]. NULL (default): signed
#'   in to Framework Cloud, your default blueprint is used. Not signed in,
#'   an interactive session asks, with the Standard Project ("project")
#'   first, and a non-interactive one makes a "project". Pass
#'   `type = "bare"` for a bare project.
#' @param key A Framework Cloud project token. When given, the project's
#'   definition is fetched from the cloud (as with `setup("fw_...")`) and
#'   `name` and `type` come from it. The token is saved in the new project's
#'   `.env` for [publish()] and the ledger.
#' @param url With `key`: the Framework Cloud server that issued the token.
#'   Defaults to `FW_CLOUD_URL`, then the server you last logged in to with
#'   [cloud_login()], then <https://framework.pub>.
#'
#' @return Invisibly returns the result from `project_create()`
#'
#' @seealso [new_project()], [new_project_sensitive()], [new_presentation()], [new_course()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Create different project types
#' new("analysis", "~/projects/analysis")
#' new("study", "~/projects/study", type = "project_sensitive")
#' new("slides", "~/projects/slides", type = "presentation")
#' new("course-materials", "~/projects/course", type = "course")
#'
#' # A project defined on Framework Cloud
#' new(key = "1|fw_abc123...", location = "~/projects/study")
#' }
#' }
#'
#' @details `new_project()` is the preferred name. `new()` remains available for
#'   existing scripts. Its name can mask `methods::new()` when attached.
#' @export
new <- function(name = NULL, location = NULL, type = NULL, browse = interactive(),
                key = NULL, url = NULL, ...) {
  if (!is.null(key)) {
    return(new_project(name = name, location = location, type = type, browse = browse,
                       key = key, url = url, ...))
  }
  # Signed in, Framework Cloud supplies the default blueprint
  if (is.null(type) && is.null(.fw_cloud_token())) {
    # The Standard Project is the default; bare stays available on request
    valid_types <- c("project", "project_sensitive", "course", "presentation", "bare")
    if (interactive()) {
      labels <- c("Standard Project (project)", "project_sensitive", "course", "presentation",
                  "bare (no blueprint - bring your own structure)")
      choice <- utils::menu(labels, title = "Project type:")
      if (choice == 0) {
        stop("Project creation cancelled")
      }
      type <- valid_types[choice]
    } else {
      type <- "project"
    }
  }
  new_project(name = name, location = location, type = type, browse = browse, ...)
}

# The layers new_project() resolves: the user's settings, the structure,
# an older cloud blueprint when one is found, then tools and sets. Package
# defaults come first inside spec_resolve().
#' @keywords internal
.new_project_layers <- function(args, type, blueprint = NULL, tools = NULL,
                                package_sets = NULL, skill_sets = NULL, workflow = NULL) {
  defaults <- .spec_package_defaults(type)
  # The user's lists replace the package's: anything the user removed from
  # their packages or directories is removed here too
  replace <- function(user, default) {
    out <- user
    for (key in setdiff(names(default), names(user))) out[key] <- list(NULL)
    out
  }

  packages <- list()
  for (pkg in args$packages$default_packages %||% list()) {
    if (is.character(pkg)) pkg <- list(name = pkg)
    if (is.null(pkg$name)) next
    packages[[pkg$name]] <- list(source = pkg$source %||% "cran", auto_attach = isTRUE(pkg$auto_attach))
  }
  assistants <- list()
  for (a in unlist(args$ai$assistants)) assistants[[a]] <- TRUE

  user <- list(
    packages = list(use_renv = isTRUE(args$packages$use_renv),
                    default_packages = replace(packages, defaults$packages$default_packages)),
    ai = list(enabled = isTRUE(args$ai$enabled), assistants = replace(assistants, defaults$ai$assistants)),
    git = list(use_git = isTRUE(args$git$use_git), hooks = args$git$hooks %||% list()),
    scaffold = Filter(Negate(is.null), args$scaffold)
  )
  if (length(args$packages$default_packages) == 0) user$packages$default_packages <- NULL
  if (length(args$directories) > 0 && !identical(type, "bare")) {
    user$directories <- replace(args$directories, defaults$directories)
  }
  if (!is.null(args$connections)) {
    user$connections <- .spec_connections_from_settings(args$connections)
  }
  if (!is.null(args$publish)) user$publish <- args$publish
  if (isTRUE(args$packages$use_renv)) user$tools <- list(renv = TRUE)

  layers <- list(
    list(kind = "settings", key = "user", layer = user),
    list(kind = "base", key = type, layer = list(type = type))
  )

  if (!is.null(blueprint)) {
    structure <- blueprint$structure %||% list()
    bp <- list()
    if (length(structure$directories) > 0) bp$directories <- replace(structure$directories, defaults$directories)
    if (length(structure$render_dirs) > 0) bp$render_dirs <- structure$render_dirs
    if (!is.null(structure$quarto$render_dir)) bp$quarto <- list(render_dir = structure$quarto$render_dir)
    if (length(blueprint$skills) > 0) {
      bp$skills <- lapply(blueprint$skills, function(content) list(content = content))
    }
    layers <- c(layers, list(list(kind = "blueprint", key = type, layer = bp)))
  }

  # The workflow sits above the structure; tools and sets chosen here win
  if (!is.null(workflow)) {
    checkmate::assert_string(workflow, min.chars = 1)
    layers <- c(layers, .fw_workflow_layers(workflow))
  }

  # tools is a vector of ids to turn on, or a named logical that can also
  # turn a structure's tool off, as in framework-py
  off <- character()
  if (!is.character(tools) && !is.null(tools)) {
    flags <- unlist(tools)
    off <- names(flags)[!flags]
    tools <- names(flags)[flags]
  }
  # Skill sets replace the default skills when given
  sets_layers <- .fw_definition_layers(tools = tools %||% character(),
                                       package_sets = package_sets %||% character(),
                                       skill_sets = skill_sets %||% character())
  if (!is.null(skill_sets)) {
    drop <- setdiff(names(defaults$skills), "framework-sensitive-data")
    layers <- c(layers, list(list(kind = "settings", key = "skill sets",
                                  layer = list(skills = stats::setNames(rep(list(NULL), length(drop)), drop)))))
  }
  layers <- c(layers, sets_layers)
  if (length(off) > 0) {
    unknown <- setdiff(off, names(.fw_features()))
    if (length(unknown) > 0) stop("Unknown tool(s): ", paste(unknown, collapse = ", "), call. = FALSE)
    on <- .fw_resolve_tools(tools %||% character())
    needed <- intersect(off, unlist(lapply(.fw_features()[on], function(f) unlist(f$requires))))
    if (length(needed) > 0) {
      stop("Can't turn off ", paste(needed, collapse = ", "), ": another tool you chose needs it.", call. = FALSE)
    }
    layers <- c(layers, list(list(kind = "facet", key = "framework/tools-off",
                                  layer = list(tools = stats::setNames(as.list(rep(FALSE, length(off))), off)))))
  }
  layers
}

# Map a (possibly cloud-overlaid) global config to project_create() arguments.
# Shared by new_project() and the cloud project setup path in R/cloud.R.
#' @keywords internal
.project_args_from_config <- function(config, type) {
  defaults <- config$defaults %||% list()

  project_type_config <- config$project_types[[type]] %||% config$project_types$project %||% list()

  ai_config <- list(
    enabled = isTRUE(defaults$ai_support),
    assistants = defaults$ai_assistants %||% list(),
    canonical_content = ""
  )
  if (ai_config$enabled && length(ai_config$assistants) == 0) {
    ai_config$assistants <- list("claude")
  }

  list(
    author = config$author %||% list(name = "", email = "", affiliation = ""),
    packages = list(
      use_renv = isTRUE(defaults$use_renv),
      default_packages = defaults$packages %||% list()
    ),
    directories = project_type_config$directories %||% defaults$directories %||% list(),
    ai = ai_config,
    git = list(
      use_git = isTRUE(defaults$use_git),
      hooks = defaults$git_hooks %||% list(),
      gitignore_content = ""
    ),
    scaffold = list(
      seed_on_scaffold = isTRUE(defaults$seed_on_scaffold),
      seed = as.character(defaults$seed %||% ""),
      set_theme_on_scaffold = TRUE,
      ggplot_theme = "theme_minimal",
      ide = defaults$ide %||% "vscode"
    ),
    publish = config$publish %||% defaults$publish,
    connections = defaults$connections,
    env = defaults$env
  )
}
