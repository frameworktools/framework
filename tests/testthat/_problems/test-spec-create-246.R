# Extracted from test-spec-create.R:246

# prequel ----------------------------------------------------------------------
fake_checkout <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(dir, ".git"))
  dir.create(file.path(dir, ".github", "workflows"), recursive = TRUE)
  writeLines("name: scaffold", file.path(dir, ".github", "workflows", "framework-scaffold.yml"))
  writeLines("# My Study", file.path(dir, "README.md"))
  dir.create(file.path(dir, ".framework"))
  dir
}
write_layers <- function(dir, layers, name = "My Study") {
  envelope <- list(
    spec_version = 1,
    name = name,
    author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""),
    layers = layers
  )
  path <- file.path(dir, ".framework", "layers.json")
  jsonlite::write_json(envelope, path, auto_unbox = TRUE, null = "null")
  path
}
sensitive_layers <- function() {
  list(
    list(kind = "base", key = "project", version = 1, layer = list(type = "project")),
    list(kind = "facet", key = "restricted-data", version = 1, layer = list(
      security = list(sensitive = TRUE),
      directories = list(
        inputs_raw = NULL,
        inputs_private_raw = "inputs/private/raw",
        outputs_private_tables = "outputs/private/tables"
      )
    )),
    list(kind = "facet", key = "manuscript", version = 1, layer = list(
      extra_directories = list(manuscript = list(label = "Manuscript", path = "manuscript")),
      files = list(`manuscript/manuscript.qmd` = list(
        template = TRUE,
        content = "---\ntitle: \"{{project_name}}\"\nauthor: \"{{ author }}\"\n---\n{{< include _common.qmd >}}\n"
      ))
    )),
    list(kind = "facet", key = "claude-code", version = 1, layer = list(
      ai = list(enabled = TRUE, assistants = list(claude = TRUE))
    )),
    list(kind = "facet", key = "codex", version = 1, layer = list(
      ai = list(assistants = list(codex = TRUE))
    )),
    list(kind = "project", key = "my-study", layer = list())
  )
}

# test -------------------------------------------------------------------------
skip_on_cran()
create <- function(layers) {
    dir <- fake_checkout()
    suppressMessages(project_create_from_layers(write_layers(dir, layers), path = dir, interactive = FALSE))
    dir
  }
dir <- create(list(list(kind = "base", key = "project", layer = list(type = "project"))))
expect_true(file.exists(file.path(dir, "settings", "packages.yml")))
