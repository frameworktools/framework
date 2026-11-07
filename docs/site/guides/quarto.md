---
id: quarto
title: Quarto integration
section: features
position: 7
description: 'Quarto configuration for notebooks and presentations'
---
## Overview

Framework integrates with [Quarto](https://quarto.org), the open-source scientific publishing system. It writes the project's Quarto configuration, separates sources from rendered output, and sets defaults for notebooks and presentations.

Quarto is a tool you can turn on or off per project (`tools.quarto` in `settings.yml`). With it off, Framework writes no Quarto configuration and `make_notebook()` makes Jupyter notebooks, R Markdown, or scripts instead.

## Render directories

Framework separates source files from rendered output. The `.qmd` source stays in its directory while rendered HTML or PDF output goes to a render directory.

**Rationale:**
- Keep your working directories clean
- Rendered files are typically gitignored (they're regenerated)
- Rendered output has a consistent location
- Multiple formats can coexist without clutter

### Directories by project type

| Project Type | Source Directory | Render Directory |
|--------------|------------------|------------------|
| Standard Project | `notebooks/` | `outputs/notebooks/` |
| Privacy Sensitive | `notebooks/` | `outputs/private/notebooks/` |
| Course/Teaching | `slides/` | `rendered/slides/` |

Render directories are listed under `render_dirs` in `settings.yml`.

## Quarto configuration

Framework writes one `_quarto.yml` at the project root when it creates the project. Quarto keeps each file's folder under the project's `output-dir`, so `notebooks/analysis.qmd` renders to `outputs/notebooks/analysis.html`:

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

A folder that needs its own format, such as a course's `slides/`, gets a `_metadata.yml` that inherits from the root.

### Generated files

```text
my-project/
├── _quarto.yml              # Project config
├── notebooks/
│   └── analysis.qmd
└── outputs/
    └── notebooks/           # Rendered output appears here
```

### Customization

The generated files are yours. Framework does not change them after creation:

```yaml
# _quarto.yml
project:
  type: default
  output-dir: outputs

format:
  html:
    theme: cosmo              # Changed from default
    toc: true
    toc-depth: 4              # Deeper TOC
    code-fold: true           # Enable code folding
    code-tools: true          # Show code tools
    embed-resources: true
    highlight-style: github
```

### Quarto settings

The defaults Framework writes come from the `quarto` section of the project settings (`settings/quarto.yml` in split-settings projects):

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

Changing these settings does not rewrite existing files. Run `quarto_regenerate()` to apply them.

## New Quarto files

### Notebooks

Create new notebooks with `make_notebook()`:

```r
make_notebook("exploration")
make_notebook("modeling", subdir = "analysis")
```

This creates a `.qmd` file from your notebook template in the configured notebooks directory. Use `make_rmd()` or a `.Rmd` name for R Markdown.

The title comes from the name: a name with spaces or capitals is kept as typed, and otherwise `-` and `_` become spaces and the first letter is capitalized. A lowercase file name can't carry acronyms, so pass `title`, which is used exactly as typed (the file name still comes from the name). `make_qmd()`, `make_rmd()`, `make_revealjs()`, `make_presentation()`, and `make_script()` take it too:

```r
make_notebook("bp-for-ldl-and-hba1c", title = "BP for LDL and HbA1c")
```

For a Jupyter notebook for the R kernel, pass `type = "jupyter"` or a `.ipynb` name:

```r
make_notebook("exploration.ipynb")
```

Projects with the Quarto tool off and the Jupyter tool on make Jupyter notebooks by default. Quarto renders an `.ipynb` from the outputs saved in it, so run the notebook before rendering.

### Presentations

For presentation projects or course slides:

```r
make_presentation("quarterly-review")
```

Presentations use RevealJS format by default.

## Rendering

### From R

```r
# Render a single file
quarto::quarto_render("notebooks/analysis.qmd")

# Render and save to outputs
save_notebook("notebooks/analysis.qmd")
```

### From the terminal

```bash
# Render one file (uses _quarto.yml settings)
quarto render notebooks/analysis.qmd

# Render entire project
quarto render
```

## Tables and interactive figures

`show_table()` shows a data frame as a Markdown pipe table, which Quarto makes a real table in HTML, PDF, and Word, styled like the rest of the page. framework-py's `show_table()` gives the same Markdown for the same data.

````markdown
```{r}
#| label: tbl-arms
#| tbl-cap: Patients by arm
show_table(counts, digits = 1, big_mark = ",")
```

@tbl-arms shows the arms.
````

`digits` sets the decimal places of doubles, `big_mark` the thousands separator, and `na` what a missing value shows. `caption` adds a caption when the chunk has no `tbl-cap`. Row names aren't shown; make them a column first if you need them. Every row is shown, so summarize large data first.

### plotly and other htmlwidgets with embed-resources

With `embed-resources: true`, Quarto copies every script a page loads into the page. Each htmlwidget, such as a plotly figure, brings its JavaScript libraries, and plotly's full bundle is several megabytes, so a page with many figures grows large. Two ways to keep it small:

- `plotly::partial_bundle(p)` swaps the full plotly.js for a smaller bundle with only the trace types the figure uses.
- Set `embed-resources: false` (or render with `self_contained = FALSE` from R Markdown) for pages with many widgets. Libraries are then saved once, in the page's `_files/` folder, which must travel with the page.

## Format-specific settings

### HTML documents

Default settings for analysis notebooks:

```yaml
format:
  html:
    theme: default
    embed-resources: true    # Standalone files
    toc: true                # Table of contents
    toc-depth: 3
    code-fold: false
    code-tools: false
    highlight-style: github
```

### RevealJS presentations

Default settings for slides:

```yaml
format:
  revealjs:
    theme: default
    incremental: false       # All bullets at once
    slide-number: true
    transition: slide
    background-transition: fade
    controls: true
    progress: true
    center: true
    highlight-style: github
```

## Configuration regeneration

To rewrite the Quarto files from the current settings, run:

```r
quarto_regenerate(".")
```

**Warning:** This overwrites any manual customizations. Framework backs up existing files to `.quarto_backups/` first. Pass `backup = FALSE` to skip the backup. Projects made before the single root config have a `_quarto.yml` in each render folder. `quarto_regenerate()` removes those and writes the root file.

---

<div style="display: flex; justify-content: space-between">

[← Templates](guide:templates)

[Viewing work →](guide:viewing-work)

</div>
