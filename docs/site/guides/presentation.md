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
├── presentation.qmd     # Main document
└── settings.yml         # Configuration
```

Optional directories available in the GUI: `data/`, `functions/`, `outputs/`, `scripts/`

## Presentation creation

```r
new_presentation("quarterly-report", "~/presentations/q4")
```

This creates a minimal structure with a main `presentation.qmd` file.

## Configuration

Example `settings.yml`:

```yaml
default:
  project_type: presentation

  directories:
    data: data

  packages:
    - name: dplyr
      auto_attach: true
    - name: ggplot2
      auto_attach: true
```

## Workflow

### 1. Setup

```r
library(framework)
scaffold()
```

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

Even in minimal projects, extract reusable code by enabling the `functions/` directory:

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
