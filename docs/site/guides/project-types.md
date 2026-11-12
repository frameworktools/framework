---
id: project-types
title: Project types
section: project_types
position: 10
description: 'Framework project structures and type labels'
---
## Overview

A project's type is a label for the blueprint it came from. Framework builds each project from three parts:

- **Structure**: the folders and starter files.
- **Tools**: Quarto, renv, targets, Jupyter, and others.
- **Sets**: package sets and AI skill sets.

Framework ships five structures with the package, and two R app structures
on Framework Cloud:

| Type | Best For |
|------|----------|
| **Standard Project** (`project`) | Data analysis, research, reporting |
| **Privacy Sensitive Project** (`project_sensitive`) | Research with private/public data separation |
| **Course/Teaching** (`course`) | Academic courses with lectures and assignments |
| **Presentation** (`presentation`) | Slides and presentations |
| **Shiny app** (`shiny`) | Shiny apps. See [Shiny app](guide:shiny-app). |
| **Plumber API** (`plumber`) | Web APIs. See [Plumber API](guide:plumber-api). |
| **Bare** (`bare`) | Your own structure |

The app types come from Framework Cloud, so they need `cloud_login()` first.

Any lowercase id works as `type`. A Framework Cloud blueprint can use its own label. Offline, an unknown label builds the default layout and warns.

## Type comparison

### Standard project (default)

This type has organized data, work, and output directories.

Use for most data analysis work:
- Research projects
- Data pipelines
- Exploratory data analysis

**Default structure:**
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

### Privacy-sensitive project

This type separates private and public data and adds stricter privacy controls.

Use for research involving sensitive or protected data:
- Research with sensitive data, such as protected health information
- Projects requiring clear public/private separation

**Default structure:**
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

### Course/Teaching

This type has a structure for teaching materials, such as lecture slides, student assignments, and course materials.

**Default structure:**
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

### Presentation

This type has a minimal structure for slides and presentations.

**Default structure:**
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

### Bare

This type writes only `settings.yml`, `.gitignore`, and `.framework/spec.json`. It has no folders, starter files, `.env`, or Quarto configuration. Use it to bring your own structure.

## Project creation

### Framework Cloud

Signed in with `cloud_login()`, `new_project()` uses your default blueprint on Framework Cloud. It registers the new project there.

To set up a project already defined on Framework Cloud, pass its project token:

```r
framework::setup("fw_...")
```

### Programmatic creation

```r
# Create a standard project
new_project("sales-analysis", "~/code/sales-analysis")

# Create a privacy sensitive project
new_project_sensitive("medical-study", "~/code/medical")

# Create a course
new_course("data-science-101", "~/teaching/ds101")

# Create a presentation
new_presentation("q4-report", "~/presentations/q4")

# Create a bare project
new_project("my-layout", "~/code/my-layout", type = "bare")
```

### Tools and sets

Add tools and sets to any structure:

```r
new_project(
  "study", "~/code/study",
  tools = "targets",
  package_sets = "tidyverse-analysis"
)

# Turn a structure's tool off
new_project("study", "~/code/study", tools = c(quarto = FALSE, renv = TRUE))
```

| Tool | Effect |
|------|--------|
| `quarto` | Quarto notebooks and `_quarto.yml`. On for every structure except bare. |
| `quarto_manuscript` | A manuscript folder with a Quarto manuscript. Needs `quarto`. |
| `quarto_slides` | A slides folder that renders with Quarto RevealJS. Needs `quarto`. |
| `renv` | renv records package versions. |
| `targets` | The targets and tarchetypes packages and a starter `_targets.R`. |
| `jupyter` | Jupyter notebooks with the IRkernel kernel. |

A tool's requirements are added with a message. Skill sets default to `framework` and `ggplot2`. Pass `offline = TRUE` to skip Framework Cloud.

## Shared features

All project types except bare include:

- **Configuration** (`settings.yml`): project settings. Standard and privacy-sensitive projects split sections into `settings/*.yml`.
- **Git integration**: version control with a type-specific `.gitignore`.
- **Quarto support**: document rendering.
- **AI assistant context**: `AGENTS.md`, a `CLAUDE.md` that points to it, and skills in `.claude/skills/`.
- **Project spec**: `.framework/spec.json` records the structure, tools, and sets.
- **Environment file**: `.env`, ignored by git.

---

<div style="display: flex; justify-content: space-between">

[← Publishing](guide:publishing)

[Standard project →](guide:standard-project)

</div>
