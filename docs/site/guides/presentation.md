---
id: presentation
title: Presentation
section: project_types
position: 14
description: 'Minimal structure for slides and presentations'
---
## Overview

The **Presentation** type is a minimal structure for focused, single-output work like conference presentations, standalone reports, or one-off analyses.

## Directory structure

```text
my-presentation/
├── cache/               # Cached computations
├── data/                # Data files
├── functions/           # Custom R functions (auto-loaded)
├── outputs/             # Saved outputs
├── scripts/             # Automation scripts
├── _quarto.yml          # Quarto configuration (RevealJS)
├── AGENTS.md            # AI assistant guide
├── presentation.qmd     # Main document
├── scaffold.R           # Project startup code
└── settings.yml         # Configuration
```

## Presentation creation

```r
new_presentation("quarterly-report", "~/presentations/q4")
```

This creates the structure above with a starter `presentation.qmd`. Add more decks with `make_revealjs()`.

## Configuration

Example `settings.yml`:

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

### 1. Setup

The starter `presentation.qmd` runs `scaffold()` in a hidden setup chunk:

````qmd
```{r}
#| label: setup
#| include: false

library(framework)
scaffold()
```
````

### 2. Editing

Work directly in `presentation.qmd`:

````qmd
---
title: "Q4 Sales Analysis"
author: "Your Name"
format: revealjs
---

## Overview

Key findings from Q4 sales data.

## Revenue Growth

```{r}
sales_plot
```
````

### 3. Rendering

```bash
quarto render presentation.qmd
```

The rendered file is written next to the source.

Or in R:

```r
quarto::quarto_render("presentation.qmd")
```

## Output formats

Change the format in the YAML header:

### Reveal.js slides
```yaml
format: revealjs
```

### HTML document
```yaml
format: html
```

### PDF report
```yaml
format: pdf
```

### Word document
```yaml
format: docx
```

## Best practices

### Scope

The presentation type is for single deliverables. For multi-document projects, use the standard **Project** type.

### Functions

`scaffold()` loads every `.R` file in `functions/`. Put reusable code there:

```r
# functions/plots.R
create_revenue_chart <- function(data) {
  ggplot(data, aes(x = month, y = revenue)) +
    geom_col(fill = "steelblue") +
    theme_minimal()
}
```

### Caching

Speed up rendering:

```r
# In presentation.qmd
summary_stats <- cache_remember("summary", {
  expensive_calculations()
})
```

## Suitable uses

**Good for:**
- Conference talks
- Committee presentations
- Executive summaries
- One-time reports
- Quick analyses

**Consider Standard Project for:**
- Ongoing analyses
- Multiple deliverables
- Complex data pipelines
- Collaborative work

---

<div style="display: flex; justify-content: space-between">

[← Course/Teaching](guide:course-teaching)

</div>
