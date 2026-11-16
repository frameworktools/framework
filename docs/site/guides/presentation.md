---
id: presentation
title: Presentation
section: project_types
position: 14
description: 'Minimal structure for slides and single-file reports'
---
## Structure

The presentation project (`presentation`) provides a compact layout for conference talks, seminars, and standalone Quarto reports.

```text
my-presentation/
├── cache/               # Cached computations (gitignored)
├── data/                # Datasets
├── functions/           # Reusable R functions sourced by scaffold()
├── outputs/             # Saved figures and tables
├── scripts/             # Data preparation scripts
├── _quarto.yml          # Quarto RevealJS configuration
├── AGENTS.md            # AI assistant context
├── presentation.qmd     # Primary slide deck
├── scaffold.R           # Project startup script
└── settings.yml         # Project configuration
```

## Creating a presentation project

```r
new_presentation("quarterly-report", "~/presentations/q4")
```

`new_presentation()` creates the directory structure and a starter `presentation.qmd`. Add extra slide decks with `make_revealjs()`.

## Configuration

Presentation projects store settings in a single `settings.yml`:

```yaml
default:
  project_type: presentation
  tools:
    quarto: true
    renv: false

  directories:
    presentation_source: presentation.qmd
    rendered_slides: '.'
    data: data
    cache: cache
    scripts: scripts
    functions: functions
    outputs: outputs

  packages:
    use_renv: false
    default_packages:
      - name: dplyr
        auto_attach: true
      - name: ggplot2
        auto_attach: true
```

## Workflow

### Setup chunk

The starter `presentation.qmd` initializes Framework in a hidden setup chunk:

````qmd
```{r}
#| label: setup
#| include: false

library(framework)
scaffold()
```
````

### Slide authoring

Edit slides directly in `presentation.qmd`:

````qmd
---
title: "Q4 Sales Analysis"
author: "Your Name"
format: revealjs
---

## Overview

Summary of Q4 regional revenue.

## Revenue by region

```{r}
sales_plot
```
````

Put plotting helpers in `functions/*.R` and wrap slow calculations in `cache_remember()` so slide renders stay fast.

### Rendering

Render from the terminal or from R:

```sh
quarto render presentation.qmd
```

```r
quarto::quarto_render("presentation.qmd")
```

Rendered output is written alongside `presentation.qmd`.

## Output formats

Set `format` in YAML frontmatter to switch deliverables:

- `format: revealjs` for HTML slides
- `format: html` for standalone web reports
- `format: pdf` for PDF handouts or reports
- `format: docx` for Word documents

For multi-notebook studies or staged data pipelines, use the `project` structure instead.
