#' Register a Local Project on Framework Cloud and Link It
#'
#' Creates the Cloud project for a folder that is already a Framework project
#' (one you adopted with [adopt()] or brought up to date with [upgrade()]),
#' links the folder to it, and sends its spec, in one step:
#'
#' 1. When the project's folders differ from its type's built-in layout,
#'    saves them as a structure (`POST /api/v1/structures`), so the Cloud
#'    project describes the folder as it is.
#' 2. Creates the project (`POST /api/v1/projects`) with that structure, the
#'    language, tools, and settings, marked `adopted` so Cloud doesn't
#'    scaffold a new repository.
#' 3. Writes the project token and server to `.env` (`FW_PROJECT_TOKEN`,
#'    `FW_CLOUD_URL`), making sure git ignores `.env` first.
#' 4. Sends `.framework/spec.json` (`PUT /api/v1/project/spec`).
#'
#' It needs `.framework/spec.json` (run `upgrade(dry_run = FALSE)` first for
#' an older project), refuses a project that already has a token in `.env`,
#' and refuses when git tracks `.env`. When a step after creating the project
#' fails, it names the project and the commands that finish linking.
#'
#' @param path The project folder (default: the working directory).
#' @param name The Cloud project's name. Default: the spec's name.
#' @param description An optional description.
#' @param dry_run If TRUE, print the requests without sending them.
#' @param include_private A project whose path has a folder named `private`
#'   asks before registering in an interactive session and stops otherwise;
#'   TRUE registers it anyway.
#'
#' @return Invisibly, a list with `slug`, `url`, `structure`, `linked`, and
#'   `spec_pushed`; with `dry_run = TRUE`, the request bodies.
#'
#' @seealso [adopt()], [upgrade()], [cloud_login()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' cloud_register("~/projects/old-study", dry_run = TRUE)
#' cloud_register("~/projects/old-study")
#' }
#' }
#'
#' @export
cloud_register <- function(path = ".", name = NULL, description = NULL, dry_run = FALSE,
                           include_private = FALSE) {
  checkmate::assert_directory_exists(path)
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(description, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  checkmate::assert_flag(include_private)
  root <- normalizePath(path, winslash = "/", mustWork = TRUE)

  if (length(.fw_settings_files(root)) == 0) {
    stop("Not a Framework project: ", root, ". Run framework::adopt() first.", call. = FALSE)
  }
  spec_path <- file.path(root, ".framework", "spec.json")
  if (!file.exists(spec_path)) {
    stop("This project has no .framework/spec.json. Run framework::upgrade(\"", path,
         "\", dry_run = FALSE) to write one, then run this again.", call. = FALSE)
  }
  spec <- jsonlite::read_json(spec_path, simplifyVector = FALSE)
  if (!is.null(.fw_project_env_value("FW_PROJECT_TOKEN", root))) {
    stop("This project is already linked to Framework Cloud (FW_PROJECT_TOKEN is in .env). ",
         "Nothing was changed.", call. = FALSE)
  }
  .cloud_register_private_check(root, include_private)
  .fw_refuse_tracked_env(root)

  url <- .fw_cloud_url()
  name <- name %||% spec$name %||% basename(root)
  bodies <- .cloud_register_bodies(spec, name, description)

  if (dry_run) {
    message("Framework Cloud requests for ", name, " (dry run: nothing sent):")
    if (!is.null(bodies$structure)) {
      message("\nPOST ", url, "/api/v1/structures")
      message(jsonlite::toJSON(bodies$structure, auto_unbox = TRUE, pretty = TRUE, null = "null"))
    }
    project <- bodies$project
    if (!is.null(bodies$structure)) project$structure <- "<key of the structure above>"
    message("\nPOST ", url, "/api/v1/projects")
    message(jsonlite::toJSON(project, auto_unbox = TRUE, pretty = TRUE, null = "null"))
    message("\nThen FW_PROJECT_TOKEN and FW_CLOUD_URL go into .env, and:")
    message("PUT ", url, "/api/v1/project/spec  {\"spec\": <.framework/spec.json>}")
    return(invisible(bodies))
  }

  token <- .fw_require_token(url)
  structure <- bodies$project$structure
  if (!is.null(bodies$structure)) {
    saved <- .fw_api("/api/v1/structures", token = token, method = "POST", body = bodies$structure, url = url)
    structure <- saved$key
    bodies$project$structure <- structure
    message("[ok] Saved the folder layout as structure ", structure)
  }
  created <- .fw_api("/api/v1/projects", token = token, method = "POST", body = bodies$project, url = url)
  slug <- created$slug %||% created$project$slug
  project_token <- created$token %||% created$pull_token
  message("[ok] Created ", slug, " on ", .fw_cloud_host(url))

  finish <- function(step, e) {
    message("Created ", slug, " on Framework Cloud, but ", step, " failed: ", conditionMessage(e))
    message("Finish linking with:\n  fw project link --from ", slug, "\n  fw project push-spec")
  }
  linked <- tryCatch({
    if (is.null(project_token) || !nzchar(project_token)) stop("the response had no project token")
    .fw_write_project_token(root, project_token, url)
    TRUE
  }, error = function(e) {
    finish("writing the project token", e)
    FALSE
  })
  pushed <- linked && tryCatch({
    .fw_api("/api/v1/project/spec", token = project_token, method = "PUT", body = list(spec = spec), url = url)
    message("[ok] Sent .framework/spec.json")
    TRUE
  }, error = function(e) {
    message("Linked ", slug, ", but sending the spec failed: ", conditionMessage(e))
    message("Send it with:\n  fw project push-spec")
    FALSE
  })

  invisible(list(slug = slug, url = created$url, structure = structure, linked = linked,
                 spec_pushed = pushed))
}

# The request bodies: the structure to save (NULL when the folders are the
# type's built-in layout) and the project to create
#' @keywords internal
.cloud_register_bodies <- function(spec, name, description = NULL) {
  type <- spec$type %||% "bare"
  directories <- spec$directories %||% list()
  extra <- spec$extra_directories %||% list()
  structure <- NULL
  key <- paste0("framework/", type)
  if (!.cloud_builtin_layout(type, directories, extra)) {
    structure <- list(name = paste(name, "layout"), directories = .adopt_named(directories))
    if (length(extra) > 0) {
      structure$extra_directories <- lapply(extra, function(e) list(label = e$label %||% e$path, path = e$path))
    }
    key <- NULL
  }
  tools <- Filter(function(v) isTRUE(v) || isFALSE(v), spec$tools %||% list())
  project <- list(
    name = name,
    description = description,
    language = spec$language %||% "r",
    structure = key,
    tools = .adopt_named(tools),
    settings = list(
      sensitive = isTRUE(spec$security$sensitive),
      git = isTRUE(spec$git$use_git),
      ai = isTRUE(spec$ai$enabled)
    ),
    adopted = TRUE
  )
  list(structure = structure, project = Filter(Negate(is.null), project))
}

# Whether directories and extra_directories are exactly a built-in type's
#' @keywords internal
.cloud_builtin_layout <- function(type, directories, extra) {
  if (length(extra) > 0 || !type %in% .spec_types()) return(FALSE)
  builtin <- if (identical(type, "bare")) list() else .spec_package_defaults(type)$directories
  same <- function(x) {
    x <- unlist(x)
    if (length(x) == 0) return(character())
    x[order(names(x))]
  }
  identical(same(directories), same(builtin))
}

# A project path with a folder named private (or ..._private): ask in an
# interactive session, stop otherwise, unless include_private = TRUE
#' @keywords internal
.cloud_register_private_check <- function(root, include_private) {
  parts <- strsplit(.fw_strip_system_private(root), "/", fixed = TRUE)[[1]]
  if (include_private || !any(.fw_is_private_folder_name(parts))) return(invisible(TRUE))
  if (rlang::is_interactive() &&
      isTRUE(.adopt_ask(paste0(root, " is inside a private folder. Register it on Framework Cloud anyway?"),
                        default = FALSE))) {
    return(invisible(TRUE))
  }
  stop("This project is inside a private folder, so it was not registered. ",
       "Pass include_private = TRUE to register it anyway.", call. = FALSE)
}
