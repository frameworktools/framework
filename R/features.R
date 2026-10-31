# Framework's tools (inst/features/<id>.json) and its bundled skill and
# package sets (inst/sets/). Each holds a layer in the spec layer format, so
# offline new() and framework.pub build the same projects. These files are
# canonical here; framework-cloud, framework-py, and fw copy them.

#' @keywords internal
.fw_read_definitions <- function(...) {
  dir <- system.file(..., package = "framework")
  paths <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  defs <- lapply(paths, jsonlite::read_json, simplifyVector = FALSE)
  stats::setNames(defs, vapply(defs, `[[`, "", "id"))
}

#' @keywords internal
.fw_features <- function() .fw_read_definitions("features")

#' @keywords internal
.fw_skill_sets <- function() .fw_read_definitions("sets", "skills")

#' @keywords internal
.fw_package_sets <- function() .fw_read_definitions("sets", "packages")

# The tools to turn on: the ones asked for plus what they require, checked
# for language and conflicts
#' @keywords internal
.fw_resolve_tools <- function(tools, language = "r") {
  features <- .fw_features()
  unknown <- setdiff(tools, names(features))
  if (length(unknown) > 0) {
    stop("Unknown tool(s): ", paste(unknown, collapse = ", "),
         ". Available: ", paste(names(features), collapse = ", "), call. = FALSE)
  }
  wanted <- character()
  add <- function(id) {
    if (id %in% wanted) return()
    for (dep in unlist(features[[id]]$requires)) add(dep)
    wanted <<- c(wanted, id)
  }
  for (id in tools) add(id)
  for (id in wanted) {
    if (!language %in% unlist(features[[id]]$language)) {
      stop("The ", features[[id]]$name, " tool isn't available for ", language, " projects.", call. = FALSE)
    }
    clash <- intersect(unlist(features[[id]]$conflicts), wanted)
    if (length(clash) > 0) {
      stop("The ", id, " tool can't be used with ", paste(clash, collapse = ", "), ".", call. = FALSE)
    }
  }
  wanted
}

# Envelope entries for tools and sets, in the order framework.pub uses:
# tools, then package sets, then skill sets
#' @keywords internal
.fw_definition_layers <- function(tools = character(), package_sets = character(),
                                  skill_sets = character(), language = "r") {
  entries <- list()
  features <- .fw_features()
  for (id in .fw_resolve_tools(tools, language)) {
    entries <- c(entries, list(list(kind = "facet", key = paste0("framework/tool-", id), layer = features[[id]]$layer)))
    extra <- features[[id]]$language_layers[[language]]
    if (length(extra) > 0) {
      entries <- c(entries, list(list(kind = "facet", key = paste0("framework/tool-", id, "-", language), layer = extra)))
    }
  }
  pick <- function(ids, sets, label, prefix) {
    unknown <- setdiff(ids, names(sets))
    if (length(unknown) > 0) {
      stop("Unknown ", label, ": ", paste(unknown, collapse = ", "),
           ". Available: ", paste(names(sets), collapse = ", "), call. = FALSE)
    }
    lapply(ids, function(id) list(kind = "facet", key = paste0("framework/", prefix, id), layer = sets[[id]]$layer))
  }
  c(entries,
    pick(package_sets, .fw_package_sets(), "package set(s)", "packages-"),
    pick(skill_sets, .fw_skill_sets(), "skill set(s)", "skills-"))
}
