# API Helper Functions
# Internal utilities for API endpoints

#' Determine if a project field uses split file or inline settings
#'
#' @param project_path Path to project directory
#' @param field_name Name of the field to check (e.g., "packages", "connections")
#' @return List with use_split, main_file, split_file, and has_default
#' @keywords internal
.uses_split_file <- function(project_path, field_name) {
  settings_file <- NULL
  if (file.exists(file.path(project_path, "settings.yml"))) {
    settings_file <- file.path(project_path, "settings.yml")
  } else if (.fw_is_framework_config(file.path(project_path, "config.yml"))) {
    settings_file <- file.path(project_path, "config.yml")
  } else {
    return(list(use_split = FALSE, main_file = NULL, split_file = NULL))
  }

  tryCatch({
    settings_raw <- yaml::read_yaml(settings_file)
    has_default <- !is.null(settings_raw$default)
    settings <- settings_raw$default %||% settings_raw

    field_value <- settings[[field_name]]

    # Check if field references a .yml file (split file approach)
    if (is.character(field_value) && length(field_value) == 1 && grepl("\\.yml$", field_value)) {
      split_path <- file.path(project_path, field_value)
      return(list(
        use_split = TRUE,
        main_file = settings_file,
        split_file = split_path,
        has_default = has_default
      ))
    } else {
      # Inline approach
      return(list(
        use_split = FALSE,
        main_file = settings_file,
        split_file = NULL,
        has_default = has_default
      ))
    }
  }, error = function(e) {
    return(list(use_split = FALSE, main_file = settings_file, split_file = NULL))
  })
}
