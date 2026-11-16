---
id: quarto
title: Quarto integration
section: features
position: 7
description: 'Quarto configuration, render directories, and Markdown tables'
---
## Quarto tool

Framework integrates with [Quarto](https://quarto.org) to separate source documents from rendered deliverables and configure HTML and RevealJS defaults. Control Quarto per project with `tools.quarto` in `settings.yml`. When `tools.quarto` is `false`, Framework omits `_quarto.yml` and `make_notebook()` creates Jupyter notebooks, R Markdown files, or R scripts instead.

## Render directories

Quarto writes rendered HTML and PDF files to `output-dir` while `.qmd` sources stay in their working directories:

| Project type | Source directory | Render directory |
|--------------|------------------|------------------|
| Standard project (`project`) | `notebooks/` | `outputs/notebooks/` |
| Privacy-sensitive (`project_sensitive`) | `notebooks/` | `outputs/private/notebooks/` |
| Course (`course`) | `slides/` | `rendered/slides/` |

Render mappings are recorded under `render_dirs` in `settings.yml`.

## Generated configuration

Project creation writes a root `_quarto.yml` file. Quarto preserves relative source paths beneath `output-dir`, so `notebooks/analysis.qmd` renders to `outputs/notebooks/analysis.html`:

```yaml
project:
  type: default
  output-dir: outputs

format:
  html:
    theme: default
    toc: true
    toc-depth: 3
    code-fold: false
    code-tools: false
    embed-resources: true
    highlight-style: github
```

Subdirectories that require a distinct format, such as `slides/` in a course project, receive a `_metadata.yml` file that inherits from `_quarto.yml`.

Framework does not overwrite `_quarto.yml` after project creation; edit it directly to adjust themes, table-of-contents depth, or code folding.

### Quarto settings section

Initial `_quarto.yml` values come from the `quarto` block in `settings/quarto.yml` (or `settings.yml`):

```yaml
quarto:
  html:
    theme: default
    embed_resources: true
    toc: true
    toc_depth: 3
    code_fold: false
    code_tools: false
    highlight_style: github
  revealjs:
    theme: default
    incremental: false
    slide_number: true
    transition: slide
```

Run `quarto_regenerate(".", overwrite = TRUE)` to rewrite `_quarto.yml` from updated `quarto` settings; without `overwrite`, it only creates missing files and adds missing keys. `quarto_regenerate()` backs up existing files to `.framework/backups/<timestamp>/` unless `backup = FALSE`, and with `overwrite = TRUE` removes legacy per-directory `_quarto.yml` files that the single root configuration replaces.

## Creating documents

### Notebooks

```r
make_notebook("exploration")
make_notebook("modeling", subdir = "analysis")
```

Use `make_rmd()` (or pass a `.Rmd` extension) for R Markdown, and `make_notebook("exploration.ipynb")` (or `type = "jupyter"`) for an R-kernel Jupyter notebook. Execute `.ipynb` cells before rendering because Quarto renders saved cell outputs without running the notebook.

Pass `title` to preserve acronyms or custom capitalization while deriving the filename from the first argument (`make_qmd()`, `make_rmd()`, `make_revealjs()`, `make_presentation()`, and `make_script()` accept `title` as well):

```r
make_notebook("bp-for-ldl-and-hba1c", title = "BP for LDL and HbA1c")
```

### Slide decks

```r
make_presentation("quarterly-review")
make_revealjs("week-01", dir = "slides")
```

## Rendering documents

From R:

```r
quarto::quarto_render("notebooks/analysis.qmd")
save_notebook("notebooks/analysis.qmd")
```

From a terminal:

```sh
quarto render notebooks/analysis.qmd
quarto render
```

## Markdown tables and interactive widgets

### show_table()

`show_table()` formats a data frame as a Markdown pipe table so Quarto renders native HTML, PDF, and Word tables (matching `framework.show_table()` in Python):

````markdown
```{r}
#| label: tbl-arms
#| tbl-cap: Patients by arm
show_table(counts, digits = 1, big_mark = ",")
```

@tbl-arms summarizes enrollment by arm.
````

`digits` sets decimal places for numeric columns, `big_mark` sets the thousands separator, `na` sets the missing-value string, and `caption` supplies a table caption when `tbl-cap` is not set. Row names are omitted; convert them to a column first if needed, and aggregate large data frames before calling `show_table()`.

### htmlwidgets and embed-resources

With `embed-resources: true`, Quarto inlines every JavaScript bundle into the output HTML. Pages containing multiple `plotly` or `htmlwidgets` figures can grow by several megabytes per widget. Reduce output size in either of two ways:

- Call `plotly::partial_bundle(p)` to include only the trace bundles required by the figure.
- Set `embed-resources: false` so shared widget assets write once into `<document>_files/` alongside the HTML file.
