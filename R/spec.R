#' Resolve a Project Spec from Layers
#'
#' Merges spec layers into one complete project spec, the input to
#' `project_create()`. This is the only implementation of the merge: the
#' framework.pub cloud and the `fw` CLI send unmerged layers, and R resolves
#' them.
#'
#' The package defaults for the project type are always the bottom layer. The
#' given layers are applied on top, in order. The project type is taken from
#' the last layer that sets `type` (default `"project"`).
#'
#' Merge rules:
#' - Objects merge by key, and a later layer wins.
#' - A key set to `NULL` (JSON `null`) removes it.
#' - Entries of `files`, `skills`, `extra_directories`,
#'   `packages$default_packages`, `connections$databases`, and
#'   `connections$storage_buckets` are replaced whole, never merged field by
#'   field.
#' - `git$gitignore_content` is concatenated, with a comment naming the layer
#'   each block came from. The base gitignore template is chosen after merging,
#'   from the project type and `security$sensitive`.
#' - Empty lists are no-ops, so an empty JSON object and an empty JSON array
#'   mean the same thing.
#'
#' @param layers A list of layers, bottom to top. Each element is either a
#'   layer (a named list in spec shape) or a list with `kind`, `key`,
#'   `version`, and `layer`, as in `.framework/layers.json`.
#' @param name Project name. Overrides any `name` in the layers.
#' @param author Optional author list (`name`, `email`, `affiliation`, and
#'   optionally `orcid`, `url`, and `affiliations`). Non-empty fields override
#'   the layers' `author`; `affiliations` replaces the whole list.
#' @param check If `TRUE` (default), stop when the resolved spec is invalid.
#'
#' @return The resolved spec as a named list. Attribute `"conflicts"` holds a
#'   data frame of keys set by more than one layer (`path`, `layers`).
#'
#' @examples
#' spec <- spec_resolve(
#'   list(list(security = list(sensitive = TRUE))),
#'   name = "My study"
#' )
#' spec$security$sensitive
#'
#' @seealso [project_create()]
#' @export
spec_resolve <- function(layers = list(), name, author = NULL, check = TRUE) {
  checkmate::assert_list(layers)
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_list(author, null.ok = TRUE)
  checkmate::assert_flag(check)

  entries <- .spec_normalize_layers(layers)

  type <- "project"
  language <- "r"
  for (entry in entries) {
    if (!is.null(entry$layer$type)) type <- entry$layer$type
    if (!is.null(entry$layer$language)) language <- entry$layer$language
  }
  if (!grepl("^[a-z][a-z0-9_]*$", type)) {
    stop(sprintf("Project type must be a lowercase id such as 'project', got '%s'", type), call. = FALSE)
  }
  checkmate::assert_choice(language, .spec_languages())
  if (!identical(language, "r")) {
    stop(.spec_language_message(language), call. = FALSE)
  }

  # The package defaults are layer 0; the merge itself is language-neutral
  # and shared with the Python package and fw (see inst/conformance/).
  state <- .spec_merge_layers(c(
    list(list(label = "package defaults", layer = .spec_package_defaults(type))),
    entries
  ))

  spec <- state$spec
  spec$type <- type
  spec$language <- language
  spec$name <- name
  if (!is.null(author)) spec$author <- .author_merge(spec$author, author)
  spec <- .spec_finalize(spec, state$gitignore)

  if (check) {
    problems <- spec_check(spec)
    if (length(problems) > 0) {
      stop(
        "The resolved project spec is invalid:\n",
        paste0("  - ", problems, collapse = "\n"),
        call. = FALSE
      )
    }
  }

  attr(spec, "conflicts") <- .spec_conflicts(state$setters)
  spec
}


#' Check a Resolved Project Spec
#'
#' Checks a resolved spec for the problems `project_create()` cannot recover
#' from: missing sections, unknown values, and paths that would write outside
#' the project. The JSON Schema in `inst/schema/spec.v1.json` describes the
#' same shape for other tools.
#'
#' @param spec A resolved spec, as returned by [spec_resolve()].
#' @return A character vector of problems, empty when the spec is valid.
#' @seealso [spec_resolve()]
#' @export
spec_check <- function(spec) {
  checkmate::assert_list(spec)
  problems <- character()
  add <- function(...) problems <<- c(problems, sprintf(...))

  required <- c(
    "spec_version", "name", "type", "language", "author", "directories", "extra_directories",
    "render_dirs", "packages", "git", "ai", "scaffold", "connections",
    "security", "env", "data_hooks", "files", "skills"
  )
  for (key in setdiff(required, names(spec))) add("missing section '%s'", key)
  unknown <- setdiff(names(spec), c(required, "quarto", "source", "tools", "core_files", "settings_layout"))
  for (key in unknown) add("unknown section '%s'", key)

  if (!identical(as.integer(spec$spec_version), 1L)) {
    add("spec_version must be 1, got %s", format(spec$spec_version))
  }
  # type is a label; behavior follows settings, tools, and core_files
  if (!is.null(spec$type) && !(is.character(spec$type) && length(spec$type) == 1 &&
                               grepl("^[a-z][a-z0-9_]*$", spec$type))) {
    add("type must be a lowercase id such as 'project', got '%s'", format(spec$type))
  }
  if (!is.null(spec$core_files) && !isTRUE(spec$core_files) && !isFALSE(spec$core_files)) {
    add("core_files must be true or false")
  }
  if (!is.null(spec$settings_layout) && !identical(spec$settings_layout, "split") &&
      !identical(spec$settings_layout, "flat")) {
    add("settings_layout must be 'split' or 'flat'")
  }
  for (tool in names(spec$tools)) {
    if (!grepl("^[a-z][a-z0-9_]*$", tool)) add("tools: invalid tool id '%s'", tool)
    if (!isTRUE(spec$tools[[tool]]) && !isFALSE(spec$tools[[tool]])) add("tools.%s must be true or false", tool)
  }
  if (!is.null(spec$language) && !identical(spec$language, "r")) {
    add(if (spec$language %in% .spec_languages()) .spec_language_message(spec$language)
        else sprintf("unknown language '%s'", spec$language))
  }

  for (path in .spec_map_paths) {
    value <- spec[[path]]
    if (length(value) > 0 && (!is.list(value) || is.null(names(value)) || any(!nzchar(names(value))))) {
      add("%s must be an object keyed by name, not a list", paste(path, collapse = "."))
    }
  }

  check_path <- function(path, where) {
    if (!.spec_is_safe_path(path)) add("%s: path '%s' must be relative and stay inside the project", where, path)
  }
  for (key in names(spec$directories)) check_path(spec$directories[[key]], paste0("directories.", key))
  for (key in names(spec$render_dirs)) check_path(spec$render_dirs[[key]], paste0("render_dirs.", key))
  for (key in names(spec$extra_directories)) {
    path <- spec$extra_directories[[key]]$path
    if (is.null(path)) add("extra_directories.%s: missing path", key) else check_path(path, paste0("extra_directories.", key))
  }
  for (path in names(spec$files)) {
    check_path(path, "files")
    if (!is.character(spec$files[[path]]$content)) add("files.%s: missing content", path)
  }

  for (pkg in names(spec$packages$default_packages)) {
    source <- spec$packages$default_packages[[pkg]]$source
    if (!isTRUE(source %in% c("cran", "github", "bioc"))) {
      add("packages.default_packages.%s: source must be cran, github, or bioc", pkg)
    }
  }

  notebook_format <- spec$scaffold$notebook_format
  if (!is.null(notebook_format) && !notebook_format %in% c("quarto", "rmarkdown")) {
    add("scaffold.notebook_format must be quarto or rmarkdown for R projects, got '%s'", notebook_format)
  }

  unknown_assistants <- setdiff(names(spec$ai$assistants), names(.ai_assistant_table()))
  for (a in unknown_assistants) add("ai.assistants: unknown assistant '%s'", a)
  if (!isTRUE(spec$ai$agents_md %in% c("stub", "none"))) add("ai.agents_md must be 'stub' or 'none'")

  for (skill in names(spec$skills)) {
    entry <- spec$skills[[skill]]
    if (!grepl("^[a-z0-9]+(-[a-z0-9]+)*$", skill)) add("skills: invalid skill name '%s'", skill)
    if (isTRUE(entry$package)) {
      if (!nzchar(system.file("templates", "skills", skill, "SKILL.md", package = "framework"))) {
        add("skills.%s: not shipped with this version of framework", skill)
      }
    } else if (is.character(entry$content)) {
      declared <- .spec_skill_name(entry$content)
      if (!identical(declared, skill)) {
        add("skills.%s: SKILL.md frontmatter name is '%s'", skill, declared %||% "missing")
      }
      for (path in names(entry$files)) check_path(path, paste0("skills.", skill, ".files"))
    } else {
      add("skills.%s: needs either package: true or content", skill)
    }
  }

  for (var in names(spec$env)) {
    if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", var)) add("env: invalid variable name '%s'", var)
    # Specs travel through the cloud and into git; secrets never do
    value <- spec$env[[var]]
    if (.fw_secret_name(var) &&
        length(value) > 0 && !is.na(value[1]) && nzchar(as.character(value[1]))) {
      add("env.%s: secret-looking variables must be empty in a spec; set the value in .env", var)
    }
  }
  for (key in names(spec$data_hooks)) {
    if (!grepl("^[^:]+\\.R::[A-Za-z.][A-Za-z0-9._]*$", spec$data_hooks[[key]])) {
      add("data_hooks.%s: expected 'path/to/file.R::function'", key)
    }
  }

  problems
}


# Internals -------------------------------------------------------------------

.spec_types <- function() c("project", "project_sensitive", "course", "presentation", "bare")

# What a spec's settings mean, with today's behavior for specs that predate
# core_files, settings_layout, and tools
.spec_default_settings_layout <- function(type) {
  if (type %in% c("project", "project_sensitive")) "split" else "flat"
}
.spec_core_files <- function(spec) {
  if (is.null(spec$core_files)) !identical(spec$type, "bare") else isTRUE(spec$core_files)
}
.spec_settings_layout <- function(spec) {
  spec$settings_layout %||% .spec_default_settings_layout(spec$type)
}
# A tool is on when the spec says so. renv also counts packages.use_renv,
# its older name
.spec_tool_on <- function(spec, id) {
  isTRUE(spec$tools[[id]]) || (identical(id, "renv") && isTRUE(spec$packages$use_renv))
}

# Project languages. R builds R projects, the Python package builds Python
# projects, and fw builds Stata projects (scaffolding only).
.spec_languages <- function() c("r", "python", "stata")

.spec_language_message <- function(language) {
  switch(language,
    python = "This is a Python project. Create it with the framework Python package or `fw new`.",
    stata = "This is a Stata project. Create it with `fw new` (the fw command-line tool).",
    sprintf("This framework package creates R projects only (got language '%s').", language)
  )
}

# The merge result in the conformance fixture format (inst/conformance/merge):
# the merged spec, the gitignore blocks in layer order, and the conflicts.
#' @keywords internal
.conformance_merge <- function(layers) {
  state <- .spec_merge_layers(.spec_normalize_layers(layers))
  conflicts <- .spec_conflicts(state$setters)
  list(
    spec = state$spec,
    gitignore_blocks = lapply(state$gitignore, function(b) list(label = b$label, text = b$text)),
    conflicts = lapply(seq_len(nrow(conflicts)), function(i) {
      list(path = conflicts$path[i], layers = conflicts$layers[i])
    })
  )
}

# Apply normalized layers in order: the merge rules shared by every engine.
# Returns the merged spec, the gitignore blocks (label + text, in layer
# order), and the setters used to report conflicts.
.spec_merge_layers <- function(entries) {
  state <- list(spec = list(), gitignore = list(), setters = list())
  for (entry in entries) {
    state <- .spec_apply_layer(state, entry$layer, entry$label)
  }
  state
}

# Entries whose values are replaced whole when a later layer sets them.
.spec_atomic_maps <- c(
  "files", "skills", "extra_directories", "packages/default_packages",
  "connections/databases", "connections/storage_buckets"
)

.spec_normalize_layers <- function(layers) {
  lapply(seq_along(layers), function(i) {
    entry <- layers[[i]]
    is_envelope_entry <- is.list(entry) && "layer" %in% names(entry) &&
      all(names(entry) %in% c("kind", "key", "version", "layer"))
    if (is_envelope_entry) {
      label <- paste(c(entry$kind %||% paste("layer", i), entry$key, if (!is.null(entry$version)) paste0("v", entry$version)), collapse = " ")
      list(label = label, layer = entry$layer %||% list())
    } else {
      list(label = paste("layer", i), layer = entry %||% list())
    }
  })
}

.spec_apply_layer <- function(state, layer, label) {
  for (path in .spec_map_paths) {
    value <- tryCatch(layer[[path]], error = function(e) NULL)
    if (is.list(value) && length(value) > 0 && is.null(names(value))) {
      stop(sprintf(
        "Layer '%s': %s must be an object keyed by name, not a list",
        label, paste(path, collapse = ".")
      ), call. = FALSE)
    }
  }

  gitignore <- layer$git$gitignore_content
  if (!is.null(gitignore) && nzchar(paste(gitignore, collapse = ""))) {
    state$gitignore[[length(state$gitignore) + 1]] <- list(label = label, text = paste(gitignore, collapse = "\n"))
  }
  if (!is.null(layer$git)) layer$git$gitignore_content <- NULL

  merged <- .spec_merge(state$spec, layer, path = character(), label = label, setters = state$setters)
  state$spec <- merged$value
  state$setters <- merged$setters
  state
}

# Recursively merge `layer` into `base`. Returns list(value, setters), where
# setters records which layer set each leaf and to what (for conflicts).
.spec_merge <- function(base, layer, path, label, setters) {
  base <- base %||% list()
  for (key in names(layer)) {
    key_path <- c(path, key)
    path_str <- paste(key_path, collapse = "/")
    value <- layer[[key]]

    if (is.null(value)) {
      base[[key]] <- NULL
      setters[[path_str]] <- c(setters[[path_str]], list(list(label = label, value = "<removed>")))
      next
    }

    parent_str <- paste(path, collapse = "/")
    atomic_entry <- parent_str %in% .spec_atomic_maps
    is_object <- is.list(value) && !is.null(names(value))

    if (!atomic_entry && is_object && (is.null(base[[key]]) || is.list(base[[key]]))) {
      merged <- .spec_merge(base[[key]], value, key_path, label, setters)
      base[[key]] <- merged$value
      setters <- merged$setters
    } else if (is.list(value) && length(value) == 0) {
      # Empty object or array: no-op, but make sure the section exists.
      if (is.null(base[[key]])) base[key] <- list(list())
    } else {
      base[[key]] <- value
      setters[[path_str]] <- c(setters[[path_str]], list(list(label = label, value = value)))
    }
  }
  list(value = base, setters = setters)
}

.spec_conflicts <- function(setters) {
  # A conflict is a key set to different values by more than one layer.
  # Package defaults are the baseline and never count.
  conflicting <- Filter(function(entries) {
    entries <- Filter(function(e) !identical(e$label, "package defaults"), entries)
    length(unique(vapply(entries, `[[`, "", "label"))) > 1 &&
      length(unique(lapply(entries, `[[`, "value"))) > 1
  }, setters)
  layers <- vapply(conflicting, function(entries) {
    labels <- vapply(entries, `[[`, "", "label")
    paste(unique(setdiff(labels, "package defaults")), collapse = ", ")
  }, character(1))
  data.frame(
    path = names(conflicting),
    layers = unname(layers),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

.spec_finalize <- function(spec, gitignore_blocks) {
  spec$spec_version <- 1L
  spec$security$sensitive <- isTRUE(spec$security$sensitive)
  if (spec$security$sensitive && !identical(spec$type, "bare") && is.null(spec$skills[["framework-sensitive-data"]])) {
    spec$skills[["framework-sensitive-data"]] <- list(package = TRUE)
  }

  # Assistants: keep only those set to TRUE
  assistants <- spec$ai$assistants %||% list()
  spec$ai$assistants <- assistants[vapply(assistants, isTRUE, logical(1))]
  spec$ai$agents_md <- spec$ai$agents_md %||% "stub"

  spec$git$gitignore_content <- .spec_gitignore(spec$type, spec$security$sensitive, gitignore_blocks)
  spec <- .spec_mark_maps(spec)

  order <- c(
    "spec_version", "name", "type", "language", "core_files", "settings_layout", "tools", "author", "directories", "extra_directories",
    "render_dirs", "packages", "git", "ai", "scaffold", "quarto", "connections",
    "security", "env", "data_hooks", "files", "skills", "source"
  )
  spec[c(intersect(order, names(spec)), setdiff(names(spec), order))]
}

# Paths whose values are JSON objects. R cannot tell an empty object from an
# empty array, so empty maps are given names to serialize as {}.
.spec_map_paths <- list(
  "tools", "directories", "extra_directories", "render_dirs", "env", "data_hooks",
  "files", "skills", c("packages", "default_packages"), c("git", "hooks"),
  c("ai", "assistants"), c("connections", "databases"),
  c("connections", "storage_buckets")
)

.spec_mark_maps <- function(spec) {
  for (path in .spec_map_paths) {
    value <- spec[[path]]
    if (is.null(value) || length(value) == 0) spec[[path]] <- stats::setNames(list(), character())
  }
  spec
}

.spec_gitignore <- function(type, sensitive, blocks) {
  template <- if (isTRUE(sensitive)) {
    "gitignore-sensitive"
  } else {
    switch(type,
      course = "gitignore-course",
      presentation = "gitignore-presentation",
      project_sensitive = "gitignore-sensitive",
      "gitignore-project"
    )
  }
  path <- system.file("templates", template, package = "framework")
  base <- if (nzchar(path)) paste(readLines(path, warn = FALSE), collapse = "\n") else ""
  extra <- vapply(blocks, function(b) sprintf("\n# --- from %s ---\n%s", b$label, b$text), character(1))
  paste(c(base, extra), collapse = "\n")
}

.spec_is_safe_path <- function(path) {
  is.character(path) && length(path) == 1 && nzchar(path) &&
    !grepl("^(/|[A-Za-z]:|~)", path) &&
    !grepl("\\\\", path) &&
    !any(strsplit(path, "/", fixed = TRUE)[[1]] == "..")
}

.spec_skill_name <- function(content) {
  lines <- strsplit(content, "\r?\n")[[1]]
  if (length(lines) == 0 || !identical(trimws(lines[1]), "---")) return(NULL)
  end <- which(trimws(lines[-1]) == "---")[1]
  if (is.na(end)) return(NULL)
  front <- tryCatch(yaml::yaml.load(paste(lines[2:end], collapse = "\n")), error = function(e) NULL)
  front$name
}

# The package defaults layer for a project type, built from
# inst/settings/global-settings-default.yml (never the user's own settings,
# which arrive as their own layer).
.spec_package_defaults <- function(type) {
  # Framework's own structures have defaults; any other label is a blueprint
  # whose structure layer brings its folders, so it starts like bare but
  # with core files
  known <- type %in% .spec_types()
  label <- type
  if (!known) type <- "bare"
  path <- system.file("settings", "global-settings-default.yml", package = "framework")
  config <- tryCatch(yaml::read_yaml(path), error = function(e) {
    stop(sprintf("Failed to read package defaults '%s': %s", path, conditionMessage(e)), call. = FALSE)
  })
  defaults <- config$defaults %||% list()
  type_config <- config$project_types[[type]] %||% list()

  packages <- list()
  for (pkg in defaults$packages$default_packages %||% list()) {
    packages[[pkg$name]] <- list(source = pkg$source %||% "cran", auto_attach = isTRUE(pkg$auto_attach))
  }

  assistants <- list()
  for (a in defaults$ai$assistants %||% list()) assistants[[a]] <- TRUE

  skills <- list()
  if (!identical(type, "bare")) {
    for (s in .ai_skills_for_type(type)) skills[[s]] <- list(package = TRUE)
  }

  core_files <- !identical(label, "bare")
  list(
    core_files = core_files,
    settings_layout = .spec_default_settings_layout(label),
    # Framework's structures other than bare include Quarto
    tools = list(quarto = known && core_files, renv = isTRUE(defaults$packages$use_renv)),
    author = list(name = "", email = "", affiliation = ""),
    directories = if (identical(type, "bare")) list() else type_config$directories %||% list(),
    extra_directories = list(),
    render_dirs = .default_render_dirs_for_type(type),
    packages = list(use_renv = isTRUE(defaults$packages$use_renv), default_packages = packages),
    git = list(use_git = defaults$git$initialize %||% TRUE, hooks = defaults$git$hooks %||% list()),
    ai = list(enabled = isTRUE(defaults$ai$enabled), assistants = assistants, agents_md = "stub"),
    scaffold = utils::modifyList(defaults$scaffold %||% list(), type_config$scaffold %||% list()),
    quarto = .spec_quarto_defaults(defaults$quarto, type),
    connections = .spec_connections_from_settings(defaults$connections),
    security = list(sensitive = identical(type, "project_sensitive")),
    env = .spec_env_from_raw(defaults$env$raw),
    data_hooks = list(),
    files = list(),
    skills = skills
  )
}

.spec_quarto_defaults <- function(quarto, type) {
  quarto <- quarto %||% list()
  root <- .default_root_render_dir_for_type(type)
  if (!is.null(root)) quarto$render_dir <- root
  quarto
}

# Convert the settings-file connection shape to the spec shape.
.spec_connections_from_settings <- function(connections) {
  connections <- connections %||% list()
  if (!is.null(connections$databases) || !is.null(connections$storage_buckets)) {
    return(connections)
  }
  list(
    default_database = connections$options$default_connection,
    default_storage_bucket = NULL,
    databases = connections$connections %||% list(),
    storage_buckets = list()
  )
}

.spec_env_from_raw <- function(raw) {
  if (is.null(raw) || !nzchar(raw)) return(list())
  lines <- trimws(strsplit(raw, "\r?\n")[[1]])
  lines <- lines[nzchar(lines) & !startsWith(lines, "#") & grepl("=", lines, fixed = TRUE)]
  env <- list()
  for (line in lines) {
    eq <- regexpr("=", line, fixed = TRUE)
    env[[substr(line, 1, eq - 1)]] <- substr(line, eq + 1, nchar(line))
  }
  env
}


#' Whether an environment variable name looks like it holds a secret
#'
#' Specs and global settings may name these variables but must leave them
#' empty. The pattern is shared with framework-py and framework-cloud.
#' @keywords internal
.fw_secret_name <- function(name) {
  grepl("PASSWORD|SECRET|TOKEN|ACCESS_KEY|API_KEY|PRIVATE_KEY|CREDENTIAL", toupper(name))
}

#' Secret-looking variables with values in .env text or a named list
#' @keywords internal
.fw_secret_env_values <- function(raw = NULL, variables = NULL) {
  found <- character()
  for (name in names(variables)) {
    value <- variables[[name]]
    if (.fw_secret_name(name) && length(value) > 0 && !is.na(value[1]) &&
        nzchar(as.character(value[1]))) {
      found <- c(found, name)
    }
  }
  if (!is.null(raw)) {
    lines <- trimws(strsplit(raw, "\n")[[1]])
    lines <- sub("^export\\s+", "", lines)
    m <- regmatches(lines, regexec("^([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.*)$", lines))
    for (hit in m) {
      if (length(hit) < 3) next
      value <- gsub("^[\"']|[\"']$", "", sub("(^|\\s+)#.*$", "", trimws(hit[3])))
      if (.fw_secret_name(hit[2]) && nzchar(value)) found <- c(found, hit[2])
    }
  }
  unique(found)
}
