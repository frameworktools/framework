---
id: project-types
title: Project types
section: project_types
position: 10
description: 'Framework project structures and type labels'
---
## Project composition

A project's `type` identifies the blueprint used to create it. Each project combines three layers:

- **Structure**: directories and starter files.
- **Tools**: Quarto, `renv`, `targets`, Jupyter, and manuscript or slide extensions.
- **Sets**: package sets and AI skill sets.

Built-in and Cloud structures:

| Type | Purpose |
|------|---------|
| **Standard project** (`project`) | General data analysis, pipelines, and reporting |
| **Privacy-sensitive project** (`project_sensitive`) | Research separating private and public inputs and outputs |
| **Course** (`course`) | Academic courses with slides, assignments, readings, and modules |
| **Presentation** (`presentation`) | Standalone RevealJS decks and single-file reports |
| **Shiny app** (`shiny`) | Interactive Shiny web apps. See [Shiny app](guide:shiny-app). |
| **Plumber API** (`plumber`) | HTTP APIs built with Plumber. See [Plumber API](guide:plumber-api). |
| **Bare** (`bare`) | Minimal configuration without preset directories |

The `shiny` and `plumber` blueprints are served from Framework Cloud and require `cloud_login()`.

Any lowercase blueprint ID works as `type`. Offline, an unrecognized ID emits a warning and builds the standard `project` layout.

## Structure layouts

### Standard project (`project`)

Default layout for research projects, pipelines, and exploratory analysis:

```text
my-analysis/
├── docs/
├── functions/
├── inputs/
│   ├── raw/
│   ├── intermediate/
│   └── final/
├── logs/
├── notebooks/
├── outputs/
│   └── notebooks/
├── scratch/
├── scripts/
├── settings/
├── _quarto.yml
├── scaffold.R
└── settings.yml
```

### Privacy-sensitive project (`project_sensitive`)

Separates restricted files from shareable artifacts and enables stricter Git and agent rules:

```text
my-study/
├── docs/
├── functions/
├── inputs/
│   ├── private/
│   │   ├── raw/
│   │   ├── intermediate/
│   │   └── final/
│   └── public/
│       ├── raw/
│       ├── intermediate/
│       └── final/
├── logs/
├── notebooks/
├── outputs/
│   └── private/
│       └── notebooks/
├── scratch/
├── scripts/
├── settings/
├── _quarto.yml
├── scaffold.R
└── settings.yml
```

### Course (`course`)

Organizes teaching materials across lectures, assignments, readings, and modules:

```text
my-course/
├── assignments/
├── cache/
├── course_docs/
├── data/
├── functions/
├── modules/
├── readings/
├── scripts/
├── slides/
├── _quarto.yml
├── scaffold.R
└── settings.yml
```

### Presentation (`presentation`)

Minimal layout centered on a single Quarto document:

```text
my-presentation/
├── cache/
├── data/
├── functions/
├── outputs/
├── scripts/
├── _quarto.yml
├── presentation.qmd
├── scaffold.R
└── settings.yml
```

### Bare (`bare`)

Writes only `settings.yml`, `.gitignore`, `.framework/spec.json`, and an `.Rproj` file, leaving directory organization to you.

## Creating projects

### Framework Cloud

When signed in with `cloud_login()`, `new_project()` resolves your default Cloud blueprint and registers the created project on Framework Cloud.

To build a project already defined on Framework Cloud from its project token:

```r
framework::setup("fw_...")
```

### R constructors

```r
new_project("sales-analysis", "~/code/sales-analysis")
new_project_sensitive("medical-study", "~/code/medical")
new_course("data-science-101", "~/teaching/ds101")
new_presentation("q4-report", "~/presentations/q4")
new_project("my-layout", "~/code/my-layout", type = "bare")
```

### Tools and sets

Attach tools and package sets to any structure:

```r
new_project(
  "study", "~/code/study",
  tools = "targets",
  package_sets = "tidyverse-analysis"
)

# Override a structure's default tools
new_project("study", "~/code/study", tools = c(quarto = FALSE, renv = TRUE))
```

| Tool | Effect |
|------|--------|
| `quarto` | Quarto notebooks and `_quarto.yml` (enabled on all structures except `bare`) |
| `quarto_manuscript` | Adds a `manuscript/` directory with a Quarto manuscript (enables `quarto`) |
| `quarto_slides` | Adds a `slides/` directory configured for Quarto RevealJS (enables `quarto`) |
| `renv` | Initializes `renv` for package version locking |
| `targets` | Adds `targets` and `tarchetypes` and writes a starter `_targets.R` |
| `jupyter` | Configures Jupyter notebooks with the `IRkernel` R kernel |

Skill sets default to `framework` and `ggplot2`. Pass `offline = TRUE` to skip Framework Cloud requests.

## Shared components

Every non-bare structure includes:

- `settings.yml` (plus `settings/*.yml` on `project` and `project_sensitive`).
- Git repository initialization with a type-specific `.gitignore`.
- `_quarto.yml` when `quarto` is enabled.
- `AGENTS.md`, assistant pointer files such as `CLAUDE.md`, and skills in `.claude/skills/` or `.agents/skills/`.
- `.framework/spec.json` recording the resolved structure, tools, and sets.
- Gitignored `.env` template.
