#' Generate AI Context File
#'
#' Generates the canonical AI context file (AGENTS.md) for a project. The file
#' is intentionally thin: it carries project-specific facts (environment,
#' packages, directories) plus an index of the Framework skills installed in
#' `.claude/skills/`, which hold the detailed workflow instructions.
#'
#' @param project_path Path to the project directory (default: current directory)
#' @param project_name Name of the project (for header)
#' @param project_type Project type: "project", "project_sensitive", "course", "presentation"
#' @param config Project configuration (if NULL, reads from settings.yml)
#' @param skills Character vector of the skills installed in the project, for
#'   the skills table. NULL lists the default skills for `project_type`.
#' @param skills_dir Folder the skills are installed in, for the paths in the
#'   skills table.
#'
#' @return Character string with the complete AI context content
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Generate AI context for current project
#' content <- ai_generate_context()
#'
#' # Generate for a specific project type
#' content <- ai_generate_context(project_type = "project_sensitive")
#' }
#' }
ai_generate_context <- function(project_path = ".",
                        project_name = NULL,
                        project_type = NULL,
                        config = NULL,
                        skills = NULL,
                        skills_dir = ".claude/skills") {
  # Read config if not provided
  if (is.null(config)) {
    config <- tryCatch(
      settings_read(file.path(project_path, "settings.yml")),
      error = function(e) list()
    )
  }

  # Get project name from config or directory

if (is.null(project_name)) {
    project_name <- config$project_name %||% basename(normalizePath(project_path))
  }

  # Get project type from config
  if (is.null(project_type)) {
    project_type <- config$project_type %||% "project"
  }

  # Build sections
  sections <- list()

  # 1. Header (static, user-editable area)
  sections$header <- .generate_header_section(project_name)

  # 2. Skills index (static per type) - detailed instructions live in skills
  sections$skills <- paste0(
    "## Skills\n\n",
    .generate_skills_section(project_type, skills = skills, skills_dir = skills_dir)
  )

  # 3. Framework Environment (regeneratable) - add heading with marker
  sections$environment <- paste0(
    "## Framework Environment <!-- @framework:regenerate -->\n\n",
    .generate_environment_section(config, project_type)
  )

  # 4. Installed Packages (regeneratable) - add heading with marker
  sections$packages <- paste0(
    "## Installed Packages <!-- @framework:regenerate -->\n\n",
    .generate_packages_section(config)
  )

  # 5. Data Management (regeneratable) - add heading with marker
  sections$data <- paste0(
    "## Data Management <!-- @framework:regenerate -->\n\n",
    .generate_data_section(config, project_type)
  )

  # 6. Project-type specific content (static per type)
  sections$type_specific <- .generate_project_type_section(
    project_type, sensitive = isTRUE(config$security$sensitive)
  )

  # 7. Project Notes (user-editable, never touched)
  sections$notes <- .generate_notes_section()

  # Combine all sections
  paste(unlist(sections), collapse = "\n\n")
}


#' Regenerate Dynamic Sections in AI Context File
#'
#' Updates only the sections marked with `<!-- @framework:regenerate -->` in an
#' existing AI context file, preserving user customizations in unmarked sections.
#'
#' @param project_path Path to the project directory
#' @param sections Which sections to regenerate. NULL = all regeneratable sections.
#'   Options: "environment", "packages", "data", "functions"
#' @param ai_file Name of the AI context file (default: from settings or "CLAUDE.md")
#'
#' @return Invisible TRUE on success
#' @export
#'
#' @examples
#' \donttest{
#' if (file.exists("CLAUDE.md")) {
#'   # Regenerate all dynamic sections
#'   ai_regenerate_context()
#'
#'   # Regenerate only packages section
#'   ai_regenerate_context(sections = "packages")
#' }
#' }
ai_regenerate_context <- function(project_path = ".",
                          sections = NULL,
                          ai_file = NULL) {
  # Determine AI file path
  if (is.null(ai_file)) {
    config <- tryCatch(
      settings_read(file.path(project_path, "settings.yml")),
      error = function(e) list()
    )
    ai_file <- config$ai$canonical_file %||% "AGENTS.md"
    if (!file.exists(file.path(project_path, ai_file)) &&
        file.exists(file.path(project_path, "CLAUDE.md"))) {
      # Older projects used CLAUDE.md as the canonical file
      ai_file <- "CLAUDE.md"
    }
  }

  ai_path <- file.path(project_path, ai_file)

  if (!file.exists(ai_path)) {
    stop("AI context file not found: ", ai_path)
  }

  # Read existing content
  content <- paste(readLines(ai_path, warn = FALSE), collapse = "\n")

  # Read config for regeneration
  config <- tryCatch(
    settings_read(file.path(project_path, "settings.yml")),
    error = function(e) list()
  )
  project_type <- config$project_type %||% "project"

  # Define section generators
  generators <- list(
    environment = function() .generate_environment_section(config, project_type),
    packages = function() .generate_packages_section(config),
    data = function() .generate_data_section(config, project_type),
    functions = function() .generate_function_reference()
  )

  # Section heading mappings
  heading_map <- list(
    environment = "Framework Environment",
    packages = "Installed Packages",
    data = "Data Management",
    functions = "Function Reference"
  )

  # Determine which sections to regenerate
  if (is.null(sections)) {
    sections <- names(generators)
  }

  # Regenerate each section
  for (section in sections) {
    if (section %in% names(generators)) {
      heading <- heading_map[[section]]
      new_content <- generators[[section]]()
      content <- .replace_section(content, heading, new_content)
    }
  }

  # Write updated content
  writeLines(content, ai_path)
  message("\u2713 Regenerated AI context: ", ai_file)

  invisible(TRUE)
}


# =============================================================================
# Internal Section Generators
# =============================================================================

#' Generate header section
#' @keywords internal
.generate_header_section <- function(project_name) {
  sprintf("# %s

This file provides guidance to AI assistants working with this Framework project.
It is the canonical context file; detailed workflow instructions live in the
skills listed below. Edit the sections without regeneration markers freely -
they won't be overwritten.
", project_name)
}


#' Generate Framework Environment section
#' @keywords internal
.generate_environment_section <- function(config, project_type) {
  # Get configuration values
  seed <- config$scaffold$seed %||% config$seed %||% "123"
  seed_enabled <- config$scaffold$seed_on_scaffold %||% FALSE
  theme <- config$scaffold$ggplot_theme %||% "theme_minimal"
  theme_enabled <- config$scaffold$set_theme_on_scaffold %||% FALSE
  functions_dir <- config$directories$functions %||% "functions"

  # Build scaffold steps description
  scaffold_steps <- c(
    "1. **Sets the working directory** to the project root (handles nested notebook execution)",
    "2. **Loads environment variables** from `.env` (database credentials, API keys)",
    "3. **Installs missing packages** listed in settings.yml"
  )

  # Add auto-attach step if packages exist
  scaffold_steps <- c(scaffold_steps,
    "4. **Attaches packages** marked with `auto_attach: true` (see Packages section below)"
  )

  # Add functions sourcing
  scaffold_steps <- c(scaffold_steps,
    sprintf("5. **Sources all functions** from `%s/` directory - they are globally available", functions_dir)
  )

  # Add seed step if enabled
  if (seed_enabled) {
    scaffold_steps <- c(scaffold_steps,
      sprintf("6. **Sets random seed to %s** for reproducibility", seed)
    )
  }

  # Add theme step if enabled
  if (theme_enabled) {
    next_num <- length(scaffold_steps) + 1
    scaffold_steps <- c(scaffold_steps,
      sprintf("%d. **Sets ggplot2 theme** to `%s()`", next_num, theme)
    )
  }

  # Build critical rules
  critical_rules <- c(
    "**DO NOT** call `library()` for packages listed in the auto-attach section below.",
    "They are already loaded by scaffold(). Calling library() again wastes time and clutters output."
  )

  if (seed_enabled) {
    critical_rules <- c(critical_rules, "",
      sprintf("**DO NOT** call `set.seed()` after scaffold(). The seed is already set to %s.", seed),
      "If you need a different seed for a specific operation, document why."
    )
  }

  critical_rules <- c(critical_rules, "",
    sprintf("**DO NOT** use `source()` to load functions from the %s/ directory.", functions_dir),
    "They are auto-loaded by scaffold(). Just call them directly."
  )

  sprintf('This project uses Framework for reproducible data analysis. **Every notebook and script
MUST begin with `scaffold()`** which initializes the environment.

### What scaffold() Does

When you call `scaffold()`, it automatically:

%s

### CRITICAL RULES

%s
', paste(scaffold_steps, collapse = "\n"), paste(critical_rules, collapse = "\n"))
}


#' Generate Installed Packages section
#' @keywords internal
.generate_packages_section <- function(config) {
  # Get packages from config
  packages <- config$packages$default_packages %||% list()

  if (length(packages) == 0) {
    return("No packages configured. Use `package_add(\"name\")` to add packages.")
  }

  # Separate auto-attached and installed-only packages
  auto_names <- c()
  installed_names <- c()

  for (pkg in packages) {
    pkg_name <- pkg$name %||% pkg
    if (is.character(pkg_name)) {
      auto_attach <- pkg$auto_attach %||% pkg$attached %||% FALSE
      if (isTRUE(auto_attach)) {
        auto_names <- c(auto_names, pkg_name)
      } else {
        installed_names <- c(installed_names, pkg_name)
      }
    }
  }

  # Build compact output
  lines <- c()

  if (length(auto_names) > 0) {
    lines <- c(lines, sprintf("**Auto-attached** (loaded by scaffold): %s", paste(auto_names, collapse = ", ")))
  }

  if (length(installed_names) > 0) {
    lines <- c(lines, sprintf("**Installed** (call library() when needed): %s", paste(installed_names, collapse = ", ")))
  }

  lines <- c(lines, "", "Add packages with `package_add(\"name\")` or `package_add(\"name\", auto_attach = TRUE)`.")

  paste(lines, collapse = "\n")
}


#' Generate Data Management section
#' @keywords internal
.generate_data_section <- function(config, project_type) {
  # Get directory paths from config
  dirs <- config$directories %||% list()

  # Build directory table dynamically from config
  dir_table <- .build_directory_table(dirs, project_type)

  sprintf('**All data I/O MUST use `data_read()` and `data_save()`** - see the
`framework-data` skill for the full rules. This project\'s data directories:

%s
', dir_table)
}


#' Build directory table from config
#' @keywords internal
.build_directory_table <- function(dirs, project_type) {
  if (length(dirs) == 0) {
    # Return sensible defaults based on project type
    return(.default_directory_table(project_type))
  }

  # Map directory keys to human-readable purposes
  purpose_map <- list(
    # Standard project directories
    inputs_raw = "Raw data (immutable)",
    inputs_intermediate = "Intermediate/cleaned data",
    inputs_final = "Analysis-ready data",
    outputs_tables = "Output tables",
    outputs_figures = "Output figures",
    outputs_models = "Saved models",
    outputs_reports = "Reports",
    cache = "Cache files",
    scratch = "Scratch/temporary",
    logs = "Logs",
    notebooks = "Notebooks",
    scripts = "Scripts",
    functions = "Helper functions",
    docs = "Documentation",

    # Sensitive project directories
    inputs_private_raw = "Private raw data (PII/PHI)",
    inputs_public_raw = "Public raw data",
    inputs_private_intermediate = "Private intermediate",
    inputs_public_intermediate = "Public intermediate",
    inputs_private_final = "Private analysis-ready",
    inputs_public_final = "Public analysis-ready",
    outputs_private_tables = "Private tables",
    outputs_public_tables = "Public tables",
    outputs_private_figures = "Private figures",
    outputs_public_figures = "Public figures",
    outputs_private_models = "Private models",
    outputs_public_models = "Public models",
    outputs_private_reports = "Private reports",
    outputs_public_reports = "Public reports",

    # Course directories
    data = "Data files",
    slides = "Lecture slides",
    assignments = "Assignments",
    course_docs = "Course documents",
    readings = "Reading materials",
    modules = "Course modules",

    # Presentation directories
    presentation_source = "Presentation source",
    rendered_slides = "Rendered slides",
    outputs = "Output files"
  )

  # Filter to only data-related directories for the table
  data_dirs <- c(
    "inputs_raw", "inputs_intermediate", "inputs_final",
    "inputs_private_raw", "inputs_public_raw",
    "inputs_private_intermediate", "inputs_public_intermediate",
    "inputs_private_final", "inputs_public_final",
    "outputs_tables", "outputs_figures", "outputs_models", "outputs_reports",
    "outputs_private_tables", "outputs_public_tables",
    "outputs_private_figures", "outputs_public_figures",
    "data", "outputs"
  )

  # Build table rows
  rows <- character()
  for (key in names(dirs)) {
    if (key %in% data_dirs && !is.null(dirs[[key]]) && nzchar(dirs[[key]])) {
      purpose <- purpose_map[[key]] %||% key
      path <- dirs[[key]]
      rows <- c(rows, sprintf("| %s | `%s/` |", purpose, path))
    }
  }

  if (length(rows) == 0) {
    return(.default_directory_table(project_type))
  }

  paste(c("| Purpose | Directory |", "|---------|-----------|", rows), collapse = "\n")
}


#' Get default directory table for project type
#' @keywords internal
.default_directory_table <- function(project_type) {
 switch(project_type,
    "project_sensitive" = '| Purpose | Directory |
|---------|-----------|
| Private raw data | `inputs/private/raw/` |
| Public raw data | `inputs/public/raw/` |
| Private intermediate | `inputs/private/intermediate/` |
| Public intermediate | `inputs/public/intermediate/` |
| Private final | `inputs/private/final/` |
| Public final | `inputs/public/final/` |
| Private outputs | `outputs/private/` |
| Public outputs | `outputs/public/` |',
    "presentation" = '| Purpose | Directory |
|---------|-----------|
| Data files | `data/` |
| Output files | `outputs/` |',
    "course" = '| Purpose | Directory |
|---------|-----------|
| Course data | `data/` |
| Lecture slides | `slides/` |
| Assignments | `assignments/` |
| Course documents | `course_docs/` |',
    # Default: standard project
    '| Purpose | Directory |
|---------|-----------|
| Raw data (immutable) | `inputs/raw/` |
| Intermediate data | `inputs/intermediate/` |
| Analysis-ready data | `inputs/final/` |
| Output tables | `outputs/tables/` |
| Output figures | `outputs/figures/` |'
  )
}


#' Generate Function Reference section
#' @keywords internal
.generate_function_reference <- function() {
  '### Data Functions

#### data_read(path)
Read data from catalog or file path. Supports CSV, RDS, Excel, Stata, SPSS, SAS.

```r
df <- data_read("inputs.raw.survey")      # From catalog
df <- data_read("inputs/raw/file.csv")    # Direct path
```

#### data_save(data, path, locked = FALSE)
Save data with integrity tracking.

```r
data_save(df, "inputs/intermediate/cleaned.csv")
data_save(df, "inputs/final/analysis_ready.csv", locked = TRUE)
```

### Cache Functions

#### cache_remember(name, expr)
Compute once, cache result. Use for expensive operations.

```r
model <- cache_remember("my_model", {
  # This only runs if cache doesn\'t exist or is expired
  train_expensive_model(data)
})
```

#### cache_get(name) / cache(name, value)
Manual cache read/write.

```r
cache("processed_data", large_dataframe)  # Write
df <- cache_get("processed_data")          # Read (NULL if missing)
```

### Output Functions

#### save_table(data, name, format = "csv") / save_figure(plot, name) / save_model(model, name)
Save outputs to outputs/tables/, outputs/figures/, and outputs/models/.

```r
save_table(summary_df, "quarterly_summary")
save_table(report_df, "annual_report", format = "xlsx")
save_figure(plot, "enrollment_trend")
save_model(model, "regression_model")
result_list()    # Everything saved so far
```

### Query Functions

#### db_query(sql, connection) / db_execute(sql, connection)
Run SQL on a connection from settings.

```r
users <- db_query("SELECT * FROM users WHERE active = 1", "main_db")
db_execute("UPDATE runs SET done = 1 WHERE id = 42", "main_db")
```

### Notebook/Script Creation

#### make_notebook(name) / make_script(name)
Create new files from templates.

```r
make_notebook("01-data-cleaning")     # Creates notebooks/01-data-cleaning.qmd
make_script("data-processing")        # Creates scripts/data-processing.R
```
'
}


#' Generate project-type specific section
#' @keywords internal
.generate_project_type_section <- function(project_type, sensitive = FALSE) {
  # Sensitive data is a setting, whatever structure the project uses
  if (isTRUE(sensitive)) project_type <- "project_sensitive"
  switch(project_type,
    "project_sensitive" = '## Privacy Requirements

**This is a privacy-sensitive project.** Before ANY data operation, output, or
commit, follow the `framework-sensitive-data` skill. Never commit or publish
anything under a `private/` directory.
',
    "course" = '## Course Structure

This is a teaching/course project with the following layout:

- `slides/` - Lecture materials (Quarto revealjs format)
- `assignments/` - Student exercises and homework
- `modules/` - Course modules/lessons
- `course_docs/` - Syllabus, policies, schedules
- `data/` - Datasets for demonstrations and exercises
- `readings/` - Reading materials and references

### Creating Course Materials

```r
# Create a new lecture
make_notebook("lecture-01-intro", dir = "slides", stub = "revealjs")

# Create an assignment
make_notebook("hw-01-basics", dir = "assignments")
```
',
    "presentation" = '## Presentation Workflow

This is a presentation project with minimal structure.

### Main File

Edit `presentation.qmd` for your slides.

### Rendering

```bash
quarto render presentation.qmd
```

### Creating Additional Presentations

```r
make_notebook("backup-slides", stub = "revealjs")
```
',
    # Default: standard project
    '## Workflow Guidelines

Follow the standard Framework workflow (see the `framework-workflow` skill):
import with `data_read()`, clean and save with `data_save()`, analyze from
final datasets, export with `save_table()`, `save_figure()`, or `save_model()`.
'
  )
}


#' Generate notes section (user-editable)
#' @keywords internal
.generate_notes_section <- function() {
  '## Project Notes

*Add your project-specific notes, conventions, and documentation here.*
*This section is never modified by `ai_regenerate_context()`.*
'
}


# =============================================================================
# Section Parsing and Replacement
# =============================================================================

#' Parse markdown into sections based on ## headings
#' @keywords internal
.parse_sections <- function(content) {
  lines <- strsplit(content, "\n")[[1]]

  sections <- list()
  current_heading <- NULL
  current_content <- character()
  current_marker <- FALSE

  for (line in lines) {
    # Check if this is a ## heading
    if (grepl("^## ", line)) {
      # Save previous section
      if (!is.null(current_heading)) {
        sections[[current_heading]] <- list(
          content = paste(current_content, collapse = "\n"),
          regenerate = current_marker
        )
      }

      # Start new section
      current_heading <- sub("^## ", "", line)
      current_heading <- sub(" <!--.*-->$", "", current_heading)
      current_marker <- grepl("<!-- @framework:regenerate -->", line)
      current_content <- character()
    } else {
      current_content <- c(current_content, line)
    }
  }

  # Save last section
  if (!is.null(current_heading)) {
    sections[[current_heading]] <- list(
      content = paste(current_content, collapse = "\n"),
      regenerate = current_marker
    )
  }

  sections
}


#' Replace content of a specific section
#' @keywords internal
.replace_section <- function(content, heading, new_content) {
  # Escape special regex characters in heading
  escaped_heading <- gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", heading)

  # Build pattern to find section - use [\s\S]*? for multiline matching
  # (?s) enables DOTALL mode where . matches newlines
  pattern <- sprintf(
    "(?s)(## %s <!-- @framework:regenerate -->)(.*?)((?=\n## )|$)",
    escaped_heading
  )

  # Check if section exists with marker
  if (!grepl(pattern, content, perl = TRUE)) {
    # Section doesn't exist or doesn't have marker - don't modify
    return(content)
  }

  # Build replacement (keep heading, replace content)
  replacement <- sprintf("## %s <!-- @framework:regenerate -->\n\n%s",
                        heading, trimws(new_content))

  # Replace using perl regex for non-greedy matching
  gsub(pattern, replacement, content, perl = TRUE)
}
