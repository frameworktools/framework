#' Bring an Older Framework Project Up to the Current Layout
#'
#' `upgrade()` updates a project made by an earlier version of Framework so it
#' works like a new one, without touching your code, data, or notes. It first
#' prints a plan; with `dry_run = FALSE` it backs up every file it rewrites to
#' `.framework/backups/<timestamp>/` (which git ignores) and applies the plan.
#' Running it again changes nothing.
#'
#' The plan covers:
#'
#' - **Settings**: a 1.x `config.yml` becomes `settings.yml`. Missing current
#'   sections are added: `tools:` (Quarto and renv, from the files present)
#'   and `security:`. A `project_sensitive` project, or one with the private
#'   folder layout, gets `security: sensitive: true`. Keys outside `default:`,
#'   which Framework ignores, are reported, not moved.
#' - **Connections**: the old layouts (`options: default_connection:` with
#'   connections listed flat, or the empty hybrid of both) are rewritten as
#'   `connections:` with `default_database`, `databases`, and
#'   `storage_buckets`. A password written into the settings is reported (by
#'   key, never by value) and left where it is.
#' - **Spec**: `.framework/spec.json` is written from the settings when it is
#'   missing, and refreshed when its folders, type, author, security, tools,
#'   connections, or copy of `.gitignore` no longer match, so `fw project push-spec` and
#'   [cloud_register()] work. It holds only what `spec.v1` allows (see
#'   `inst/schema/spec.v1.json`), so keys an earlier `upgrade()` wrote that
#'   Framework Cloud refuses (`scaffold.positron`, `source.upgraded_from`)
#'   are dropped.
#' - **.gitignore**: the rules of the current template for the project's type
#'   that it lacks (Quarto's `/.quarto/` and `**/*.quarto_ipynb`,
#'   `framework.db`, private folders) and folder publishing destinations are
#'   appended in one block. No line is ever removed, and a rule that would
#'   ignore files git tracks is left out and reported.
#' - **AI files**: AGENTS.md becomes the canonical context file, with
#'   CLAUDE.md a one-line `@AGENTS.md` pointer, when CLAUDE.md held the full
#'   guide; the marked sections are regenerated. A hand-written AGENTS.md is
#'   left alone and reported. Sensitive projects get the Claude Code guards
#'   that keep agents out of private folders.
#' - **Skills**: Framework skills that match a version the package has
#'   shipped are updated, in the assistants' skills folders and in
#'   `.agents/skills`; missing ones for the project type are added;
#'   locally edited ones are kept and listed. A project with no skills folder
#'   gets none, except that a sensitive project gets
#'   `framework-sensitive-data` (in its assistants' skills folder, or
#'   `.claude/skills`).
#' - **Quarto**: missing Quarto files are created, and an existing
#'   `_quarto.yml` at most gains missing keys (see [quarto_regenerate()]).
#'   Custom Quarto configuration is never replaced, and per-folder
#'   `_quarto.yml` files are kept and listed.
#'
#' @param path The project folder (default: the working directory).
#' @param dry_run If TRUE (default), print the plan and change nothing.
#' @param backup If TRUE (default), copy every file before it is rewritten or
#'   removed. Skills replaced by an update are always backed up, to
#'   `.framework/skills-backups/`.
#' @param type Change the project's type: "project", "project_sensitive",
#'   "course", "presentation", or "bare". NULL (default) keeps it. Making a
#'   project `project_sensitive` sets `security: sensitive: true`, adds the
#'   private and public folders of that layout it lacks (folders it has keep
#'   their keys and paths), and then gets the sensitive `.gitignore` rules,
#'   agent guards, and skill like any sensitive project. The plan says where
#'   `save_table()`, `save_figure()`, `save_model()`, and `save_report()`
#'   will write from then on (`outputs/private/...`), and lists the data and
#'   render folders that aren't private. A sensitive project made another
#'   type stays sensitive.
#'
#' @return Invisibly, a list with `actions` (a data frame: `step`, `path`,
#'   `change`), `notes`, `applied`, and `backup_location`.
#'
#' @seealso [adopt()] for a folder that isn't a Framework project yet, and
#'   [cloud_register()] to link a project to Framework Cloud.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' upgrade("~/projects/old-study")                  # print the plan
#' upgrade("~/projects/old-study", dry_run = FALSE) # apply it
#' upgrade("~/projects/old-study", type = "project_sensitive") # plan making it sensitive
#' }
#' }
#'
#' @export
upgrade <- function(path = ".", dry_run = TRUE, backup = TRUE, type = NULL) {
  checkmate::assert_directory_exists(path)
  checkmate::assert_flag(dry_run)
  checkmate::assert_flag(backup)
  checkmate::assert_choice(type, .spec_types(), null.ok = TRUE)
  root <- normalizePath(path, winslash = "/", mustWork = TRUE)

  found <- .fw_settings_files(root)
  if (length(found) == 0) {
    stop("Not a Framework project (no settings.yml or Framework config.yml): ", root,
         ". To make it one, use framework::adopt().", call. = FALSE)
  }

  ctx <- new.env(parent = emptyenv())
  ctx$root <- root
  ctx$pending <- list()
  ctx$actions <- list()
  ctx$skills <- list()
  ctx$notes <- character()
  ctx$main <- basename(found[1])
  ctx$type <- type

  .upgrade_settings_file(ctx)
  .upgrade_settings(ctx)
  .upgrade_connections(ctx)
  .upgrade_gitignore(ctx)
  .upgrade_ai(ctx)
  .upgrade_skills(ctx)
  .upgrade_quarto(ctx)
  .upgrade_spec(ctx)

  actions <- .upgrade_action_table(ctx)
  .upgrade_print(ctx, actions, dry_run, path)

  result <- list(actions = actions, notes = ctx$notes, applied = FALSE, backup_location = NULL)
  if (dry_run || nrow(actions) == 0) return(invisible(result))

  rewritten <- names(ctx$pending)
  if (backup) {
    rel <- .fw_backup_dir(root)
    copied <- .fw_backup_files(root, rewritten, rel)
    if (length(copied) > 0) result$backup_location <- file.path(root, rel)
  }
  for (file in rewritten) {
    target <- file.path(root, file)
    lines <- ctx$pending[[file]]
    if (is.null(lines)) {
      unlink(target)
    } else {
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      .fw_write_text(paste0(paste(lines, collapse = "\n"), "\n"), target)
    }
  }
  for (skill in ctx$skills) skill$run()

  result$applied <- TRUE
  message("[ok] Upgraded ", root, if (!is.null(result$backup_location)) {
    paste0(". Backups: ", sub(paste0(root, "/"), "", result$backup_location, fixed = TRUE))
  })
  message("Review the changes (git diff), then commit them.")
  invisible(result)
}

# --- The virtual project: planned writes over the files on disk -----------

# A file's lines as planned, else as on disk, else NULL
#' @keywords internal
.upgrade_read <- function(ctx, file) {
  if (file %in% names(ctx$pending)) return(ctx$pending[[file]])
  path <- file.path(ctx$root, file)
  if (file.exists(path) && !dir.exists(path)) readLines(path, warn = FALSE, encoding = "UTF-8") else NULL
}

# Plan writing `lines` to `file` (NULL removes it), with what changes
#' @keywords internal
.upgrade_write <- function(ctx, step, file, lines, change) {
  current <- .upgrade_read(ctx, file)
  if (!is.null(lines) && identical(current, lines)) return(invisible(FALSE))
  ctx$pending[file] <- list(lines)
  ctx$actions[[length(ctx$actions) + 1]] <- list(step = step, path = file, change = change)
  invisible(TRUE)
}

#' @keywords internal
.upgrade_note <- function(ctx, ...) {
  ctx$notes <- c(ctx$notes, paste0(...))
}

# A YAML file's content, keeping !expr tags, or NULL
#' @keywords internal
.upgrade_yaml <- function(ctx, file) {
  lines <- .upgrade_read(ctx, file)
  if (is.null(lines)) return(NULL)
  tryCatch(yaml::yaml.load(paste(lines, collapse = "\n"), handlers = .fw_yaml_read_handlers()),
           error = function(e) NULL)
}

# The main settings file's section that holds the settings: default:, or
# the whole file when it has no environment sections
#' @keywords internal
.upgrade_section <- function(raw) {
  if (is.list(raw) && .has_environment_sections(raw)) raw$default %||% list() else raw %||% list()
}

# The split file that holds `key`, or NULL when the key is inline
#' @keywords internal
.upgrade_split_file <- function(ctx, key) {
  section <- .upgrade_section(.upgrade_yaml(ctx, ctx$main))
  value <- section[[key]]
  if (is.character(value) && length(value) == 1 && grepl("\\.ya?ml$", value, ignore.case = TRUE)) {
    sub("^\\./", "", value)
  }
}

# The settings as written (env() and !expr unevaluated): the main section
# with split files read in and stray connection keys lifted
#' @keywords internal
.upgrade_settings_raw <- function(ctx) {
  section <- .upgrade_section(.upgrade_yaml(ctx, ctx$main))
  for (key in names(section)) {
    value <- section[[key]]
    if (!is.character(value) || length(value) != 1 || !grepl("\\.ya?ml$", value, ignore.case = TRUE)) next
    split <- .upgrade_yaml(ctx, sub("^\\./", "", value))
    if (is.null(split)) {
      section[[key]] <- NULL
      next
    }
    if (is.list(split) && key %in% names(split)) {
      extra <- split[setdiff(names(split), key)]
      section[key] <- list(split[[key]])
      for (k in names(extra)) if (is.null(section[[k]])) section[k] <- list(extra[[k]])
    } else {
      section[key] <- list(split)
    }
  }
  .fw_lift_connections(section)
}

# --- Steps -------------------------------------------------------------------

# A 1.x config.yml becomes settings.yml
#' @keywords internal
.upgrade_settings_file <- function(ctx) {
  if (!identical(ctx$main, "config.yml")) return(invisible())
  lines <- .upgrade_read(ctx, "config.yml")
  .upgrade_write(ctx, "settings", "settings.yml", lines, "create from config.yml (same content)")
  .upgrade_write(ctx, "settings", "config.yml", NULL, "remove (now settings.yml)")
  ctx$main <- "settings.yml"
}

# Missing current sections: tools and security
#' @keywords internal
.upgrade_settings <- function(ctx) {
  raw <- .upgrade_yaml(ctx, ctx$main)
  if (!is.list(raw)) {
    .upgrade_note(ctx, ctx$main, " couldn't be read as YAML, so the settings were not upgraded.")
    return(invisible())
  }
  scoped <- .has_environment_sections(raw)
  if (scoped) {
    ignored <- .fw_ignored_settings_keys(raw, "default")
    if (length(ignored) > 0) {
      .upgrade_note(ctx, ctx$main, " has keys outside default: (", paste(ignored, collapse = ", "),
                    "). Framework ignores them; move them under default: to use them.")
    }
  }
  section <- .upgrade_section(raw)
  settings <- .upgrade_settings_raw(ctx)
  ctx$before <- settings
  keys <- function(key) if (scoped) c("default", key) else key
  text <- paste(.upgrade_read(ctx, ctx$main), collapse = "\n")
  changes <- character()
  to_sensitive <- identical(ctx$type, "project_sensitive")

  if (!is.null(ctx$type) && !identical(settings$project_type %||% "project", ctx$type)) {
    text <- .fw_yaml_set_text(text, keys("project_type"), ctx$type)
    changes <- c(changes, sprintf("set project_type: %s (was %s)", ctx$type, settings$project_type %||% "project"))
    if (.fw_settings_sensitive(settings) && !to_sensitive) {
      .upgrade_note(ctx, "The project stays sensitive (security: sensitive: true): a type is only a label. ",
                    "Set sensitive: false by hand once it holds no sensitive data.")
    }
  }

  if (is.null(section$tools)) {
    tools <- list(
      quarto = file.exists(file.path(ctx$root, "_quarto.yml")) || length(settings$render_dirs) > 0,
      renv = file.exists(file.path(ctx$root, "renv.lock")) || isTRUE(settings$packages$use_renv)
    )
    text <- .fw_yaml_set_text(text, keys("tools"), tools)
    changes <- c(changes, sprintf("add tools (quarto: %s, renv: %s)",
                                  tolower(tools$quarto), tolower(tools$renv)))
  }

  sensitive <- .fw_settings_sensitive(settings) || to_sensitive
  flag <- if (is.list(section$security)) section$security$sensitive else NULL
  if (to_sensitive && isFALSE(flag)) {
    security <- section$security
    security$sensitive <- TRUE
    text <- .fw_yaml_set_text(text, keys("security"), security)
    changes <- c(changes, "set security.sensitive: true")
  } else if (is.null(section$security) || (is.list(section$security) && is.null(flag))) {
    security <- if (is.list(section$security)) section$security else list()
    security$sensitive <- sensitive
    text <- .fw_yaml_set_text(text, keys("security"), security)
    why <- if (identical(settings$project_type, "project_sensitive") || to_sensitive) {
      "; project_type is project_sensitive"
    } else if (sensitive) {
      "; the folders use the private layout"
    } else {
      ""
    }
    changes <- c(changes, sprintf("add security (sensitive: %s%s)", tolower(sensitive), why))
  } else if (sensitive && isFALSE(flag)) {
    .upgrade_note(ctx, "project_type is project_sensitive but security: sensitive: is false. ",
                  "Framework treats the project as sensitive; set it to true to match.")
  }

  if (length(changes) > 0) {
    lines <- strsplit(sub("\n$", "", text), "\n", fixed = TRUE)[[1]]
    .upgrade_write(ctx, "settings", ctx$main, lines, paste(changes, collapse = "; "))
  }
  if (to_sensitive) .upgrade_private_directories(ctx)
  .upgrade_sensitive_notes(ctx)
  invisible()
}

# A project becoming sensitive gets the private and public folders of the
# project_sensitive layout it lacks. Folders it has keep their keys and
# paths, so code that names them keeps working.
#' @keywords internal
.upgrade_private_directories <- function(ctx) {
  settings <- .upgrade_settings_raw(ctx)
  current <- .configured_directories(settings)
  template <- spec_resolve(list(list(type = "project_sensitive")), name = "template", check = FALSE)$directories
  wanted <- template[grepl("_(private|public)_", names(template)) & !names(template) %in% names(current) &
                       !unlist(template) %in% unlist(current)]
  if (length(wanted) == 0) return(invisible())
  file <- .upgrade_split_file(ctx, "directories")
  if (!is.null(file)) {
    raw <- .upgrade_yaml(ctx, file)
    keys <- if (is.list(raw) && "directories" %in% names(raw)) "directories" else NULL
    existing <- if (is.null(keys)) raw else raw$directories
  } else {
    file <- ctx$main
    raw <- .upgrade_yaml(ctx, file)
    keys <- if (.has_environment_sections(raw)) c("default", "directories") else "directories"
    existing <- .upgrade_section(raw)$directories
  }
  if (!is.list(existing)) existing <- list()
  value <- c(existing, wanted)
  text <- paste(.upgrade_read(ctx, file), collapse = "\n")
  new <- if (is.null(keys)) .fw_as_yaml(value) else .fw_yaml_set_text(text, keys, value)
  lines <- strsplit(sub("\n$", "", new), "\n", fixed = TRUE)[[1]]
  .upgrade_write(ctx, "settings", file, lines,
                 sprintf("add the private and public folders of the sensitive layout: %s",
                         .fw_rules_summary(names(wanted), n = 4)))
}

# What changes for a project that becomes sensitive: where save_table()
# and friends write, and the folders that hold data but aren't private
#' @keywords internal
.upgrade_sensitive_notes <- function(ctx) {
  after <- .upgrade_settings_raw(ctx)
  if (!.fw_settings_sensitive(after)) return(invisible())
  before <- ctx$before
  old <- .upgrade_old_spec(ctx)
  if (is.null(ctx$type) && is.list(old) && is.list(old$security)) {
    # Made sensitive by hand since the last upgrade(): compare with the spec
    # that upgrade() recorded then
    if (isTRUE(old$security$sensitive)) return(invisible())
    before <- list(project_type = old$type, security = list(sensitive = FALSE),
                   directories = old$directories)
  } else if (.fw_settings_sensitive(before)) {
    return(invisible())
  }
  before$security <- list(sensitive = FALSE)
  if (identical(before$project_type, "project_sensitive")) before$project_type <- "project"

  kinds <- c(tables = "save_table()", figures = "save_figure()", models = "save_model()",
             reports = "save_report()")
  moved <- character()
  for (kind in names(kinds)) {
    from <- .fw_output_dir_for(before, kind)
    to <- .fw_output_dir_for(after, kind)
    if (!identical(from, to)) moved <- c(moved, sprintf("%s to %s (was %s)", kinds[[kind]], to, from))
  }
  if (length(moved) > 0) {
    .upgrade_note(ctx, "Sensitive projects keep outputs private by default, so these now write to private ",
                  "folders: ", paste(moved, collapse = "; "), ". Code that reads the old folders reads stale ",
                  "copies; point it at the new ones, or pass public = TRUE for output that may be shared.")
  }

  dirs <- .configured_directories(after)
  keys <- names(dirs)
  open <- dirs[(grepl("^(inputs|outputs)_", keys) | keys %in% c("cache", "scratch")) &
                 !grepl("private|public", keys) &
                 !vapply(dirs, function(p) any(.fw_is_private_folder_name(strsplit(p, "/", fixed = TRUE)[[1]])),
                         logical(1))]
  if (length(open) > 0) {
    .upgrade_note(ctx, "These folders may hold restricted data but aren't private, so Framework's private-data ",
                  "checks and agent guards don't cover them: ",
                  paste(sprintf("%s (%s)", names(open), unlist(open)), collapse = ", "),
                  ". Move their data under a private folder (inputs/private/..., outputs/private/...) and update ",
                  "the code that reads it, or rename each key to its private form (inputs_raw to ",
                  "inputs_private_raw) and keep the path.")
  }
  render <- Filter(function(p) is.character(p) && !any(.fw_is_private_folder_name(strsplit(p, "/", fixed = TRUE)[[1]])),
                   after$render_dirs %||% list())
  if (length(render) > 0) {
    .upgrade_note(ctx, "Rendered notebooks can show restricted data, but these render folders aren't private: ",
                  paste(sprintf("render_dirs.%s (%s)", names(render), unlist(render)), collapse = ", "),
                  ". Point them under outputs/private/ (and the output-dir in each _quarto.yml).")
  }
  invisible()
}

# The spec recorded in .framework/spec.json (as on disk or planned), or NULL
#' @keywords internal
.upgrade_old_spec <- function(ctx) {
  lines <- .upgrade_read(ctx, ".framework/spec.json")
  if (is.null(lines)) return(NULL)
  tryCatch(jsonlite::fromJSON(paste(lines, collapse = "\n"), simplifyVector = FALSE), error = function(e) NULL)
}

# Old connection layouts become connections: {default_database, databases,
# storage_buckets}
#' @keywords internal
.upgrade_connections <- function(ctx) {
  file <- .upgrade_split_file(ctx, "connections")
  if (is.null(file)) {
    connections <- .upgrade_section(.upgrade_yaml(ctx, ctx$main))$connections
    if (is.list(connections) && .upgrade_legacy_connections(list(connections = connections))) {
      .upgrade_note(ctx, "The connections in ", ctx$main, " use the old layout. Move them under ",
                    "connections: databases:, with default_database for the default.")
    }
    .upgrade_secret_note(ctx, list(connections = connections), ctx$main)
    return(invisible())
  }
  raw <- .upgrade_yaml(ctx, file)
  if (is.null(raw)) return(invisible())
  if (!.upgrade_legacy_connections(raw)) {
    .upgrade_secret_note(ctx, raw, file)
    return(invisible())
  }

  migrated <- .upgrade_migrate_connections(raw)
  text <- .fw_as_yaml(list(connections = migrated))
  lines <- strsplit(sub("\n$", "", text), "\n", fixed = TRUE)[[1]]
  default <- migrated$default_database
  change <- sprintf("rewrite in the current layout: %d database(s)%s",
                    length(migrated$databases),
                    if (!is.null(default)) paste0(", default_database: ", default) else "")
  .upgrade_write(ctx, "connections", file, lines, change)
  .upgrade_secret_note(ctx, list(connections = migrated), file)
  invisible()
}

# Whether a connections file (or list(connections = ...)) uses an old layout
#' @keywords internal
.upgrade_legacy_connections <- function(raw) {
  if (!is.list(raw)) return(FALSE)
  top <- names(raw)
  if (any(c("options", "databases", "storage_buckets", "default_database", "default_storage_bucket") %in% top)) {
    return(TRUE)
  }
  connections <- raw$connections
  if (!is.list(connections) || length(connections) == 0) return(!is.null(connections) && !is.list(connections))
  current <- c("databases", "storage_buckets", "default_database", "default_storage_bucket")
  any(!names(connections) %in% current)
}

# The current connections block from any older layout
#' @keywords internal
.upgrade_migrate_connections <- function(raw) {
  connections <- if (is.list(raw$connections)) raw$connections else list()
  options <- if (is.list(raw$options)) raw$options else list()
  current <- c("databases", "storage_buckets", "default_database", "default_storage_bucket")
  flat <- connections[!names(connections) %in% current]
  flat <- Filter(function(x) is.list(x) && !is.null(names(x)), flat)
  is_bucket <- function(x) identical(tolower(x$driver %||% ""), "s3") || !is.null(x$bucket)

  databases <- c(
    if (is.list(connections$databases)) connections$databases,
    if (is.list(raw$databases)) raw$databases,
    Filter(Negate(is_bucket), flat)
  )
  buckets <- c(
    if (is.list(connections$storage_buckets)) connections$storage_buckets,
    if (is.list(raw$storage_buckets)) raw$storage_buckets,
    Filter(is_bucket, flat)
  )
  pick <- function(...) {
    for (v in list(...)) if (is.character(v) && length(v) == 1 && !is.na(v) && nzchar(v)) return(v)
    NULL
  }
  out <- list()
  out["default_database"] <- list(pick(connections$default_database, raw$default_database,
                                       options$default_connection, options$default_database))
  bucket <- pick(connections$default_storage_bucket, raw$default_storage_bucket,
                 options$default_s3_connection, options$default_storage_bucket)
  if (!is.null(bucket)) out$default_storage_bucket <- bucket
  out$databases <- if (length(databases) > 0) databases[!duplicated(names(databases))] else .adopt_named(list())
  out$storage_buckets <- if (length(buckets) > 0) buckets[!duplicated(names(buckets))] else .adopt_named(list())
  out
}

#' @keywords internal
.upgrade_secret_note <- function(ctx, raw, file) {
  plain <- .upgrade_untag(raw)
  keys <- .fw_secret_keys(plain)
  if (length(keys) > 0) {
    .upgrade_note(ctx, file, " has a password or token written in (", paste(keys, collapse = ", "),
                  "). Move the value to .env and write env(\"NAME\") instead; upgrade() leaves it as it is.")
  }
}

# Values with !expr tags as "!expr ..." strings, as settings_read() sees them
#' @keywords internal
.upgrade_untag <- function(x) {
  if (is.list(x)) {
    nms <- names(x)
    x <- lapply(x, .upgrade_untag)
    names(x) <- nms
    return(x)
  }
  if (identical(attr(x, "tag"), "!expr")) return(paste("!expr", as.character(x)))
  x
}

# Append the current template's missing rules to .gitignore
#' @keywords internal
.upgrade_gitignore <- function(ctx) {
  settings <- .upgrade_settings_raw(ctx)
  type <- settings$project_type %||% "project"
  sensitive <- .fw_settings_sensitive(settings)
  template <- .spec_gitignore(type, sensitive, list())
  dirs <- .configured_directories(settings)
  private <- dirs[grepl("private", names(dirs)) & !grepl("public", names(dirs))]
  private <- private[!vapply(private, function(p) .fw_outside_root(ctx$root, p), logical(1))]
  published <- tryCatch(.folder_destinations(settings, ctx$root), error = function(e) character())
  folders <- .fw_unignored_folders(ctx$root, c(unname(unlist(private)), unname(published)))
  wanted <- c(.fw_gitignore_rules(template), if (length(folders) > 0) paste0("/", folders, "/"))

  plan <- .fw_gitignore_missing(ctx$root, wanted)
  if (length(plan$skipped) > 0) {
    .upgrade_note(ctx, ".gitignore: left out ", paste(sprintf("%s (git tracks %s)", names(plan$skipped),
                                                             plan$skipped), collapse = ", "),
                  " so no tracked file is hidden.")
  }
  if (length(plan$add) == 0) return(invisible())
  lines <- .upgrade_read(ctx, ".gitignore") %||% character()
  if (length(lines) > 0 && nzchar(trimws(lines[length(lines)]))) lines <- c(lines, "")
  lines <- c(lines, "# Added by framework::upgrade()", plan$add)
  .upgrade_write(ctx, "gitignore", ".gitignore", lines,
                 sprintf("add %d rule(s): %s", length(plan$add), .fw_rules_summary(plan$add)))
  invisible()
}

# AGENTS.md canonical, CLAUDE.md a pointer, marked sections regenerated, and
# the Claude Code guards for sensitive projects
#' @keywords internal
.upgrade_ai <- function(ctx) {
  settings <- .upgrade_settings_raw(ctx)
  agents <- .upgrade_read(ctx, "AGENTS.md")
  claude <- .upgrade_read(ctx, "CLAUDE.md")
  if (!isTRUE(settings$ai$enabled) && is.null(agents) && is.null(claude)) return(invisible())
  if (!isTRUE(settings$ai$enabled)) return(invisible())

  marked <- function(lines) any(grepl("<!-- @framework:regenerate -->", lines, fixed = TRUE))
  pointer <- function(lines) {
    !is.null(lines) && length(lines) <= 10 && any(grepl("@AGENTS.md", lines, fixed = TRUE))
  }
  canonical <- settings$ai$canonical_file %||% "AGENTS.md"
  target <- NULL

  if (!is.null(claude) && !pointer(claude) && marked(claude)) {
    if (is.null(agents) || (marked(agents) && identical(canonical, "CLAUDE.md"))) {
      .upgrade_write(ctx, "ai", "AGENTS.md", claude,
                     if (is.null(agents)) "create from CLAUDE.md (AGENTS.md becomes the canonical file)"
                     else "replace with CLAUDE.md, the canonical copy (AGENTS.md becomes canonical)")
      .upgrade_write(ctx, "ai", "CLAUDE.md", "@AGENTS.md", "replace with a pointer to AGENTS.md")
      target <- "AGENTS.md"
    } else if (marked(agents)) {
      .upgrade_write(ctx, "ai", "CLAUDE.md", "@AGENTS.md",
                     "replace with a pointer to AGENTS.md (a stale copy of it)")
      target <- "AGENTS.md"
    } else {
      .upgrade_note(ctx, "AGENTS.md is your own file and CLAUDE.md holds Framework's guide, so both were ",
                    "kept and CLAUDE.md stays canonical. To switch, move your notes into CLAUDE.md, rename ",
                    "it AGENTS.md, and run upgrade() again.")
      target <- "CLAUDE.md"
      canonical <- "CLAUDE.md"
    }
  } else if (!is.null(agents) && marked(agents)) {
    target <- "AGENTS.md"
  }
  if (identical(target, "AGENTS.md") && !identical(canonical, "AGENTS.md")) {
    .upgrade_set_setting(ctx, "ai", "canonical_file", "AGENTS.md", "ai")
  }

  if (!is.null(target)) {
    config <- tryCatch(suppressWarnings(suppressMessages(
      .upgrade_in_dir(ctx$root, .upgrade_planned_settings(ctx))
    )), error = function(e) NULL)
    if (!is.null(config)) {
      lines <- .upgrade_read(ctx, target)
      regenerated <- suppressMessages(.ai_regenerate_content(paste(lines, collapse = "\n"), config,
                                                             ai_file = target))
      new <- strsplit(regenerated$content, "\n", fixed = TRUE)[[1]]
      # Blank lines alone (the generator spaces sections its own way) are
      # no reason to rewrite the file
      if (!identical(new[nzchar(trimws(new))], lines[nzchar(trimws(lines))])) {
        .upgrade_write(ctx, "ai", target, new,
                       paste0("regenerate marked sections (", paste(regenerated$done, collapse = ", "), ")"))
      }
    }
  }

  assistants <- unlist(settings$ai$assistants)
  if (.fw_settings_sensitive(settings) && "claude" %in% assistants) {
    .upgrade_agent_guards(ctx, settings)
  }
  invisible()
}

# The settings as they will be after the plan (settings_read() on a copy
# of the settings files with the planned changes), so regenerated sections
# describe the upgraded project in one pass
#' @keywords internal
.upgrade_planned_settings <- function(ctx) {
  tmp <- tempfile("fw-upgrade-settings-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  split <- list.files(file.path(ctx$root, "settings"), pattern = "\\.ya?ml$", recursive = TRUE,
                      ignore.case = TRUE)
  files <- unique(c(ctx$main, if (length(split) > 0) file.path("settings", split),
                    grep("^settings/", names(ctx$pending), value = TRUE)))
  for (file in files) {
    lines <- .upgrade_read(ctx, file)
    if (is.null(lines)) next
    dir.create(dirname(file.path(tmp, file)), recursive = TRUE, showWarnings = FALSE)
    writeLines(lines, file.path(tmp, file), useBytes = TRUE)
  }
  settings_read(file.path(tmp, ctx$main))
}

#' @keywords internal
.upgrade_in_dir <- function(dir, code) {
  old <- setwd(dir)
  on.exit(setwd(old), add = TRUE)
  force(code)
}

# Set `section.key` where the section lives: its split file, or inline
#' @keywords internal
.upgrade_set_setting <- function(ctx, section, key, value, step) {
  file <- .upgrade_split_file(ctx, section)
  if (!is.null(file)) {
    text <- paste(.upgrade_read(ctx, file), collapse = "\n")
    raw <- .upgrade_yaml(ctx, file)
    keys <- if (is.list(raw) && section %in% names(raw)) c(section, key) else key
  } else {
    file <- ctx$main
    text <- paste(.upgrade_read(ctx, file), collapse = "\n")
    raw <- .upgrade_yaml(ctx, file)
    scoped <- .has_environment_sections(raw)
    current <- .upgrade_section(raw)[[section]]
    if (!is.list(current)) current <- list()
    current[[key]] <- value
    keys <- if (scoped) c("default", section) else section
    value <- current
  }
  new <- .fw_yaml_set_text(text, keys, value)
  lines <- strsplit(sub("\n$", "", new), "\n", fixed = TRUE)[[1]]
  .upgrade_write(ctx, step, file, lines, sprintf("set %s.%s: %s", section, key, format(value)[1]))
}

# Claude Code deny rules for the private folders of a sensitive project
#' @keywords internal
.upgrade_agent_guards <- function(ctx, settings) {
  dirs <- unlist(.configured_directories(settings), use.names = FALSE)
  spec <- list(directories = as.list(dirs), extra_directories = list())
  restricted <- sub("/$", "", .spec_restricted_paths(spec))
  if (length(restricted) == 0) return(invisible())
  deny <- c(unlist(lapply(restricted, function(p) c(sprintf("Read(/%s/**)", p), sprintf("Edit(/%s/**)", p)))),
            "Read(/.env)")
  sandbox_deny <- c(paste0("./", restricted), "./.env")
  lines <- .upgrade_read(ctx, ".claude/settings.json")
  current <- if (!is.null(lines)) {
    tryCatch(jsonlite::fromJSON(paste(lines, collapse = "\n"), simplifyVector = FALSE), error = function(e) NULL)
  } else {
    list()
  }
  if (is.null(current)) {
    .upgrade_note(ctx, ".claude/settings.json isn't valid JSON, so the guards for private folders weren't added.")
    return(invisible())
  }
  new <- current
  new$permissions$deny <- as.list(unique(c(unlist(current$permissions$deny), deny)))
  new$sandbox$enabled <- TRUE
  new$sandbox$failIfUnavailable <- TRUE
  new$sandbox$filesystem$denyRead <- as.list(unique(c(unlist(current$sandbox$filesystem$denyRead), sandbox_deny)))
  if (identical(new, current)) return(invisible())
  json <- strsplit(as.character(jsonlite::toJSON(new, auto_unbox = TRUE, pretty = 2)), "\n", fixed = TRUE)[[1]]
  .upgrade_write(ctx, "ai", ".claude/settings.json", json,
                 paste("keep Claude Code out of", paste(restricted, collapse = ", ")))
}

# Framework skills: update shipped versions, add missing ones, list edits.
# A project with no skills folder gets none, except a sensitive project,
# which gets framework-sensitive-data.
#' @keywords internal
.upgrade_skills <- function(ctx) {
  settings <- .upgrade_settings_raw(ctx)
  if (!isTRUE(settings$ai$enabled)) return(invisible())
  type <- if (.fw_settings_sensitive(settings)) "project_sensitive" else settings$project_type %||% "project"
  table <- .ai_assistant_table()
  assistants <- intersect(unlist(settings$ai$assistants), names(table))
  dirs <- if (length(assistants) == 0) ".agents/skills" else unique(vapply(table[assistants], `[[`, "", "skills_dir"))
  # Skills copied to .agents/skills (read by Codex and others) are kept
  # current too, whatever the assistants
  if (dir.exists(file.path(ctx$root, ".agents", "skills"))) dirs <- unique(c(dirs, ".agents/skills"))
  # A project with no skills folder never used skills; installing them is
  # ai_skills_update()'s job, not an upgrade's
  skills <- .ai_skills_for_type(type)
  # A skills folder holding only framework-sensitive-data is the one an
  # earlier upgrade() made for a sensitive project, so it doesn't count
  uses_skills <- vapply(dirs, function(d) {
    length(setdiff(list.dirs(file.path(ctx$root, d), full.names = FALSE, recursive = FALSE),
                   "framework-sensitive-data")) > 0
  }, logical(1))
  existing <- dirs[uses_skills]
  if (length(existing) == 0) {
    if (!identical(type, "project_sensitive")) {
      .upgrade_note(ctx, "This project has no Framework skills. framework::ai_skills_update() installs ",
                    "the ones for its type (", type, ").")
      return(invisible())
    }
    # A sensitive project gets the sensitive-data skill whatever it had: it
    # tells agents to stay out of private data. Its folder is the one the
    # assistants read, .claude/skills when none is set.
    if (length(assistants) == 0) dirs <- ".claude/skills"
    skills <- "framework-sensitive-data"
    .upgrade_note(ctx, "This project has no other Framework skills; upgrade() adds or keeps ",
                  "framework-sensitive-data. framework::ai_skills_update() installs the others for its ",
                  "type (", type, ").")
  } else {
    dirs <- existing
  }
  edited <- character()
  for (skill in skills) {
    source <- system.file("templates", "skills", skill, package = "framework")
    if (!nzchar(source)) next
    for (dir in dirs) {
      relative <- file.path(dir, skill)
      status <- tryCatch(.skill_package_status(source, ctx$root, relative, skill), error = function(e) "edited")
      if (status %in% c("create", "update")) {
        change <- if (identical(status, "create")) "add" else "update (an unedited older version)"
        ctx$actions[[length(ctx$actions) + 1]] <- list(step = "skills", path = relative, change = change)
        local({
          src <- source; rel <- relative; name <- skill; root <- ctx$root
          ctx$skills[[length(ctx$skills) + 1]] <- list(run = function() .skill_package_install(src, root, rel, name))
        })
      } else if (status %in% c("edited", "account")) {
        edited <- c(edited, relative)
      }
    }
  }
  if (length(edited) > 0) {
    .upgrade_note(ctx, "Skills kept because they were edited (or come from your account): ",
                  paste(edited, collapse = ", "), ". ai_skills_update() leaves them too.")
  }
  invisible()
}

# Missing Quarto files and keys, never replacing custom configuration
#' @keywords internal
.upgrade_quarto <- function(ctx) {
  settings <- .upgrade_settings_raw(ctx)
  has_root <- file.exists(file.path(ctx$root, "_quarto.yml"))
  if (!has_root && (length(settings$render_dirs) == 0 || isFALSE(settings$tools$quarto))) return(invisible())
  changes <- .quarto_changes(ctx$root, settings$project_type %||% "project", settings$render_dirs,
                             settings$quarto, settings$directories)
  for (file in names(changes$write)) {
    exists <- file.exists(file.path(ctx$root, file))
    .upgrade_write(ctx, "quarto", file, changes$write[[file]],
                   if (exists) "add missing keys (your other keys and comments stay)" else "create")
  }
  for (file in changes$kept) {
    .upgrade_note(ctx, file, " makes ", dirname(file), "/ a separate Quarto project and was kept. ",
                  "quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.")
  }
  invisible()
}

# .framework/spec.json from the upgraded settings
#' @keywords internal
.upgrade_spec <- function(ctx) {
  settings <- .upgrade_settings_raw(ctx)
  built <- tryCatch(.upgrade_spec_from_settings(ctx, settings), error = function(e) e)
  if (inherits(built, "error")) {
    .upgrade_note(ctx, ".framework/spec.json was not written: ", conditionMessage(built))
    return(invisible())
  }
  file <- ".framework/spec.json"
  existing <- .upgrade_read(ctx, file)
  if (is.null(existing)) {
    spec <- built
    change <- "create from the settings"
  } else {
    old <- tryCatch(jsonlite::fromJSON(paste(existing, collapse = "\n"), simplifyVector = FALSE),
                    error = function(e) NULL)
    if (is.null(old)) {
      .upgrade_note(ctx, ".framework/spec.json isn't valid JSON; fix or remove it, then run upgrade() again.")
      return(invisible())
    }
    # Refresh what the settings decide; keep the rest (files, skills, env)
    spec <- old
    derived <- c("name", "type", "author", "tools", "directories", "extra_directories", "render_dirs",
                 "security", "connections")
    stale <- derived[!vapply(derived, function(k) .upgrade_same_json(old[[k]], built[[k]]), logical(1))]
    for (k in stale) spec[k] <- list(built[[k]])
    # The copy of .gitignore follows the file; git's other settings stay
    if (!identical(old$git$gitignore_content, built$git$gitignore_content)) {
      if (!is.list(spec$git)) spec$git <- built$git
      spec$git$gitignore_content <- built$git$gitignore_content
      stale <- c(stale, "git.gitignore_content")
    }
    # Keys an earlier upgrade() wrote that spec.v1 has no place for, which
    # Framework Cloud refuses (scaffold.positron, source.upgraded_from)
    pruned <- .spec_schema_prune(spec)
    spec <- pruned$spec
    if (length(stale) == 0 && length(pruned$dropped) == 0) return(invisible())
    change <- paste(c(
      if (length(stale) > 0) paste("refresh", paste(stale, collapse = ", "), "from the settings"),
      if (length(pruned$dropped) > 0) paste("drop", paste(pruned$dropped, collapse = ", "),
                                            "(not part of spec.v1, so Framework Cloud refuses them)")
    ), collapse = "; ")
  }
  lines <- tryCatch(suppressMessages(.spec_record_lines(spec)), error = function(e) e)
  if (inherits(lines, "error")) {
    .upgrade_note(ctx, ".framework/spec.json was not written: ", conditionMessage(lines))
    return(invisible())
  }
  .upgrade_write(ctx, "spec", file, lines, change)
  invisible()
}

#' @keywords internal
.upgrade_same_json <- function(a, b) {
  norm <- function(x) {
    if (is.null(x) || length(x) == 0) return("{}")
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  }
  identical(norm(a), norm(b))
}

# A spec built from settings as written, without secrets
#' @keywords internal
.upgrade_spec_from_settings <- function(ctx, settings) {
  type <- settings$project_type %||% "project"
  name <- settings$project_name %||% basename(ctx$root)
  sensitive <- .fw_settings_sensitive(settings)
  table <- .ai_assistant_table()
  assistants <- intersect(unlist(settings$ai$assistants), names(table))
  layer <- list(
    type = type,
    core_files = TRUE,
    settings_layout = if (dir.exists(file.path(ctx$root, "settings"))) "split" else "flat",
    tools = Filter(function(v) isTRUE(v) || isFALSE(v), settings$tools %||% list()),
    security = list(sensitive = sensitive),
    git = list(use_git = file.exists(file.path(ctx$root, ".git"))),
    ai = list(enabled = isTRUE(settings$ai$enabled),
              assistants = stats::setNames(as.list(rep(TRUE, length(assistants))), assistants))
  )
  spec <- spec_resolve(list(list(kind = "project", key = "upgraded", layer = layer)), name = name, check = FALSE)

  dirs <- .configured_directories(settings)
  dirs <- dirs[vapply(dirs, .spec_is_safe_path, logical(1))]
  spec$directories <- .adopt_named(dirs)
  extra <- list()
  for (e in settings$extra_directories %||% list()) {
    if (is.list(e) && is.character(e$path) && .spec_is_safe_path(e$path)) {
      key <- e$key %||% .adopt_extra_key(e$path, names(extra))
      extra[[key]] <- list(label = e$label %||% basename(e$path), path = e$path)
    }
  }
  if (!is.null(names(settings$extra_directories))) {
    for (key in names(settings$extra_directories)) {
      e <- settings$extra_directories[[key]]
      if (is.list(e) && is.character(e$path)) extra[[key]] <- list(label = e$label %||% key, path = e$path)
    }
  }
  spec$extra_directories <- .adopt_named(extra)
  render <- Filter(function(p) is.character(p) && length(p) == 1 && .spec_is_safe_path(p),
                   settings$render_dirs %||% list())
  spec$render_dirs <- .adopt_named(render)

  packages <- list()
  for (pkg in settings$packages$default_packages %||% list()) {
    if (is.character(pkg)) pkg <- list(name = pkg)
    if (!is.list(pkg) || is.null(pkg$name)) next
    packages[[pkg$name]] <- list(source = pkg$source %||% "cran", auto_attach = isTRUE(pkg$auto_attach))
  }
  spec$packages <- list(use_renv = isTRUE(settings$packages$use_renv), default_packages = .adopt_named(packages))
  spec$connections <- .upgrade_spec_connections(settings$connections)
  if (is.list(settings$scaffold)) {
    spec$scaffold <- utils::modifyList(spec$scaffold %||% list(), .upgrade_spec_scaffold(settings$scaffold))
    if (!is.null(spec$scaffold$notebook_format)) spec$scaffold$workflow <- NULL
  }
  if (is.list(settings$quarto)) spec$quarto <- settings$quarto
  if (is.list(settings$author)) {
    author <- Filter(function(v) !is.null(v) && !(is.character(v) && length(v) == 1 && is.na(v)), settings$author)
    author <- lapply(author, function(v) if (is.character(v) || is.list(v)) v else as.character(v))
    spec$author <- utils::modifyList(spec$author, author)
  }
  spec$skills <- .upgrade_spec_skills(ctx, assistants)
  spec$env <- .adopt_named(list())
  spec$files <- .adopt_named(list())
  gitignore <- .upgrade_read(ctx, ".gitignore")
  spec$git$gitignore_content <- paste(gitignore %||% character(), collapse = "\n")
  spec$source <- list(origin = "r")
  # Settings may hold more than the spec has room for (an author's extra
  # fields); the spec keeps what spec.v1 allows
  spec <- .spec_schema_prune(spec)$spec
  problems <- c(spec_check(spec), .spec_schema_problems(spec))
  if (length(problems) > 0) stop(paste(unique(problems), collapse = "; "), call. = FALSE)
  spec
}

# The settings' scaffold options that spec.v1 holds, with values of the
# schema's types. Older settings/scaffold.yml files carry options the spec
# has no place for (positron: yes); positron: yes becomes ide: positron
# when no IDE is set, and the rest stay in the settings only.
#' @keywords internal
.upgrade_spec_scaffold <- function(scaffold) {
  schema <- .spec_schema()
  props <- schema$properties$scaffold$properties
  if (isTRUE(scaffold$positron) && is.null(scaffold$ide)) scaffold$ide <- "positron"
  out <- list()
  for (key in setdiff(intersect(names(scaffold), names(props)), "workflow")) {
    value <- scaffold[[key]]
    if (identical(props[[key]]$type, "string") && (is.numeric(value) || is.logical(value)) && length(value) == 1) {
      value <- as.character(value)
    }
    if (length(.spec_schema_check(value, props[[key]], schema)) == 0) out[key] <- list(value)
  }
  out
}

# Connections for the spec: env() and !expr stay as written; a password or
# token written in becomes env("<NAME>_<KEY>"), since specs travel to Cloud
#' @keywords internal
.upgrade_spec_connections <- function(connections) {
  connections <- .upgrade_untag(connections %||% list())
  if (.upgrade_legacy_connections(list(connections = connections))) {
    connections <- .upgrade_migrate_connections(list(connections = connections))
  }
  scrub <- function(conns) {
    for (name in names(conns)) {
      conn <- conns[[name]]
      if (!is.list(conn)) next
      for (key in names(conn)) {
        if (.fw_credential_key(key) &&
            .fw_literal_secret(conn[[key]])) {
          # env("NAME", "default") keeps its variable and loses the default,
          # which Framework Cloud refuses on a credential
          call <- .fw_env_call(conn[[key]])
          var <- call$name %||% toupper(gsub("[^A-Za-z0-9]+", "_", paste(name, key, sep = "_")))
          conn[[key]] <- sprintf('env("%s")', var)
        }
      }
      conns[[name]] <- conn
    }
    conns
  }
  out <- list(
    default_database = connections$default_database,
    default_storage_bucket = connections$default_storage_bucket,
    databases = .adopt_named(scrub(connections$databases %||% list())),
    storage_buckets = .adopt_named(scrub(connections$storage_buckets %||% list()))
  )
  Filter(Negate(is.null), out)
}

# Package skills present in the project, for the spec
#' @keywords internal
.upgrade_spec_skills <- function(ctx, assistants) {
  table <- .ai_assistant_table()
  dirs <- unique(c(".claude/skills", ".agents/skills",
                   vapply(table[assistants], `[[`, "", "skills_dir")))
  shipped <- list.dirs(system.file("templates", "skills", package = "framework"), full.names = FALSE,
                       recursive = FALSE)
  skills <- list()
  for (skill in shipped) {
    present <- any(dir.exists(file.path(ctx$root, dirs, skill))) ||
      any(vapply(ctx$actions, function(a) identical(a$step, "skills") && identical(basename(a$path), skill),
                 logical(1)))
    if (present) skills[[skill]] <- list(package = TRUE)
  }
  .adopt_named(skills)
}

# --- Output --------------------------------------------------------------------

#' @keywords internal
.upgrade_action_table <- function(ctx) {
  if (length(ctx$actions) == 0) {
    return(data.frame(step = character(), path = character(), change = character(), stringsAsFactors = FALSE))
  }
  data.frame(
    step = vapply(ctx$actions, `[[`, "", "step"),
    path = vapply(ctx$actions, `[[`, "", "path"),
    change = vapply(ctx$actions, `[[`, "", "change"),
    stringsAsFactors = FALSE
  )
}

#' @keywords internal
.upgrade_print <- function(ctx, actions, dry_run, path) {
  message("Upgrade plan for ", ctx$root)
  if (nrow(actions) == 0) {
    message("  Nothing to change: the project is up to date.")
  } else {
    width <- max(nchar(actions$path))
    for (i in seq_len(nrow(actions))) {
      message(sprintf("  %-11s %-*s  %s", actions$step[i], width, actions$path[i], actions$change[i]))
    }
  }
  if (length(ctx$notes) > 0) {
    message("Notes:")
    for (note in ctx$notes) message("  - ", note)
  }
  if (dry_run && nrow(actions) > 0) {
    message("Dry run: nothing was changed. Apply with framework::upgrade(\"", path,
            "\", dry_run = FALSE); every file it rewrites is backed up to .framework/backups/ first.")
  }
}
