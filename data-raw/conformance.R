# Generates the expected outputs for the conformance fixtures in
# inst/conformance/. Review the diff before committing: the expected outputs
# are the contract the Python package, fw, and framework-cloud are tested
# against.
#
# - merge/: each case's input is hand-written JSON; this script runs R's
#   merge (.spec_merge_layers, without package defaults) and writes the
#   result next to it.
# - create/r/: the cases are listed below. Each is resolved from layers
#   (structure, workflow, choices) and created; the fixture records the
#   layers, the resolved spec, and the files and folders created.
#
# Run from the package root:  Rscript data-raw/conformance.R

devtools::load_all(quiet = TRUE)

write_case <- function(case, path) {
  json <- jsonlite::toJSON(case, auto_unbox = TRUE, null = "null", pretty = TRUE)
  writeLines(json, path)
  message("Wrote ", path)
}

dir <- file.path("inst", "conformance", "merge")
for (path in list.files(dir, pattern = "\\.json$", full.names = TRUE)) {
  case <- jsonlite::read_json(path, simplifyVector = FALSE)
  case$expected <- framework:::.conformance_merge(case$layers)
  write_case(case, path)
}

# create/r/ ------------------------------------------------------------------

create_case <- function(structure, workflow, ide = "vscode", agents = TRUE,
                        notebook_format = NULL, description) {
  choices <- list(git = list(use_git = FALSE), scaffold = list(ide = ide))
  if (!is.null(notebook_format)) choices$scaffold$notebook_format <- notebook_format
  if (!agents) choices$ai <- list(enabled = FALSE)
  layers <- c(
    list(list(kind = "base", key = structure, layer = list(type = structure))),
    suppressMessages(framework:::.fw_workflow_layers(workflow, "r")),
    list(list(kind = "project", key = "choices", layer = choices))
  )
  spec <- spec_resolve(layers, name = "Fixture Study",
                       author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""))
  list(
    description = description,
    language = "r",
    layers = layers,
    spec = spec,
    expected = list(paths = framework:::.conformance_create(spec))
  )
}

cases <- list(
  "project-quarto" = list("project", "quarto", description = "Standard structure, Quarto workflow, VS Code, agents on."),
  "project-quarto-rmarkdown" = list("project", "quarto", notebook_format = "rmarkdown",
                                    description = "Standard structure, Quarto workflow writing R Markdown."),
  "project-jupyter" = list("project", "jupyter", description = "Standard structure, Jupyter workflow: Jupyter and Quarto on."),
  "project-scripts" = list("project", "scripts", description = "Standard structure, Scripts only: no Quarto or Jupyter files."),
  "project-quarto-rstudio" = list("project", "quarto", ide = "rstudio", description = "Editor rstudio: an .Rproj only."),
  "project-quarto-both" = list("project", "quarto", ide = "both", description = "Editor both: an .Rproj and a .code-workspace."),
  "project-quarto-none" = list("project", "quarto", ide = "none", description = "Editor none: no editor files."),
  "project-quarto-no-agents" = list("project", "quarto", agents = FALSE, description = "AI agents off: no AGENTS.md, stubs, or skills."),
  "project_sensitive-quarto" = list("project_sensitive", "quarto", description = "Privacy Sensitive structure, Quarto workflow, with agent guards."),
  "project_sensitive-jupyter" = list("project_sensitive", "jupyter", description = "Privacy Sensitive structure, Jupyter workflow."),
  "project_sensitive-scripts" = list("project_sensitive", "scripts", description = "Privacy Sensitive structure, Scripts only."),
  "presentation-quarto" = list("presentation", "quarto", description = "Presentation structure, Quarto workflow."),
  "course-quarto" = list("course", "quarto", description = "Course structure, Quarto workflow."),
  "bare-quarto" = list("bare", "quarto", description = "Bare structure with the Quarto workflow."),
  "bare-jupyter" = list("bare", "jupyter", description = "Bare structure with the Jupyter workflow."),
  "bare-scripts" = list("bare", "scripts", description = "Bare structure, Scripts only.")
)

dir <- file.path("inst", "conformance", "create", "r")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
unlink(list.files(dir, pattern = "\\.json$", full.names = TRUE))
for (id in names(cases)) {
  write_case(do.call(create_case, cases[[id]]), file.path(dir, paste0(id, ".json")))
}

# adopt/ ---------------------------------------------------------------------
# Each case's folders are written here by hand; the expected mapping comes
# from .adopt_map() with the shared rules in inst/adopt/rules.json.

adopt_cases <- list(
  "data-science-template" = list(
    description = "A common data science template: data/ splits into Framework's inputs, and data/ itself isn't listed.",
    folders = c("data", "data/raw", "data/interim", "data/processed", "data/external", "docs", "models",
                "notebooks", "references", "reports", "reports/figures", "src", "src/data", "src/features")
  ),
  "r-analysis" = list(
    description = "An R analysis with R/ functions, data-raw/, and output/ subfolders; tool folders are skipped.",
    folders = c(".Rproj.user", ".Rproj.user/shared", "R", "analysis", "data-raw", "figures", "output",
                "output/tables", "renv", "renv/library", "scratch")
  ),
  "pattern-priority" = list(
    description = "Several folders match inputs_raw; the rule's earliest pattern wins and the rest are extra directories.",
    folders = c("raw", "data", "data/raw", "inputs", "inputs/raw")
  ),
  "nested-under-matched" = list(
    description = "Folders inside a matched folder are covered by it; an unmatched folder with its own subfolders is listed once.",
    folders = c("inputs", "inputs/raw", "inputs/raw/2024", "inputs/raw/2025", "archive", "archive/2019", "archive/2020")
  ),
  "private-paths" = list(
    description = "Any path containing private, in any case, is a warning. data/Private/raw also matches the sensitive layout (inputs_private_raw), which makes the type project_sensitive.",
    folders = c("data", "data/Private", "data/Private/raw", "data/public", "outputs", "outputs/private", "scripts")
  ),
  "extra-keys" = list(
    description = "Extra directory keys: lowercased, runs of other characters as '_', 'dir_' before a leading digit, and numbered on collision.",
    folders = c("01 Admin", "Grant Docs", "Grant Docs/Budget 2024", "grant_docs", "IRB")
  ),
  "skip-and-depth" = list(
    description = "Skipped and hidden folders, and folders deeper than three levels, are left out.",
    folders = c(".git", ".git/objects", ".hidden", ".hidden/notes", "node_modules", "node_modules/pkg",
                "venv", "__pycache__", "a", "a/b", "a/b/c", "a/b/c/d", "notebooks", "notebooks/.ipynb_checkpoints")
  ),
  "case-insensitive" = list(
    description = "Matching ignores case; the folder's own spelling is kept.",
    folders = c("Data", "Data/Raw", "Figures", "Scripts", "Docs")
  ),
  "stata" = list(
    description = "A Stata project: do/ and logs/ map for Stata.",
    language = "stata",
    folders = c("do", "logs", "data", "data/raw", "data/clean", "output", "output/tables", "output/figures")
  ),
  "stata-folders-in-r" = list(
    description = "The same folders in an R project: do/ is a Stata key, so it becomes an extra directory.",
    language = "r",
    folders = c("do", "logs", "data", "data/raw", "data/clean", "output", "output/tables", "output/figures")
  ),
  "generated-folders" = list(
    description = "Framework's split settings folder, Quarto's *_files and *_cache render folders, and _site are never project folders. Rendered-notebook folders become render_dirs.",
    folders = c("settings", "report_files", "notebooks", "notebooks/02-summary_files", "notebooks/fit_cache",
                "outputs", "outputs/notebooks", "outputs/docs", "_site", "scripts")
  ),
  "sensitive-layout" = list(
    description = "The privacy-sensitive layout maps to the private and public keys and makes the project project_sensitive.",
    folders = c("inputs", "inputs/private", "inputs/private/raw", "inputs/public", "inputs/public/raw", "outputs",
                "outputs/private", "outputs/private/tables", "outputs/public", "outputs/public/figures", "functions")
  ),
  "course" = list(
    description = "Two or more course folders at the top level make a course: course rules apply first, data/ covers its subfolders, and modules/ is the notebooks folder.",
    folders = c("slides", "modules", "modules/01_intro", "assignments", "data", "data/raw", "readings", "scripts")
  ),
  "course-one-signal" = list(
    description = "One course-like folder is not enough for a course; modules/ stays an extra directory and data/raw is inputs_raw.",
    folders = c("modules", "data", "data/raw", "scripts")
  )
)

dir <- file.path("inst", "conformance", "adopt")
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
unlink(list.files(dir, pattern = "\\.json$", full.names = TRUE))
for (id in names(adopt_cases)) {
  case <- adopt_cases[[id]]
  language <- case$language %||% "r"
  case$folders <- as.list(case$folders)
  mapped <- framework:::.adopt_map(unlist(case$folders), language)
  case$expected <- mapped[c("type", "directories", "extra_directories", "render_dirs", "warnings")]
  # Empty maps serialize as {}
  for (k in c("directories", "extra_directories", "render_dirs")) {
    if (length(case$expected[[k]]) == 0) case$expected[[k]] <- stats::setNames(list(), character())
  }
  write_case(case, file.path(dir, paste0(id, ".json")))
}
