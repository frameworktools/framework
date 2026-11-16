---
id: templates
title: Templates
section: features
position: 6
description: 'Customizing notebook, script, and presentation templates'
---
## Resolution order

`make_notebook()`, `make_script()`, and `make_presentation()` resolve templates in order:

1. Project `stubs/` directory (`<project>/stubs/`)
2. User templates directory (`templates/` inside `fw_config_dir()`)
3. Built-in package templates

Project stubs apply to one repository, while user templates apply across every project you work in.

## Template variables

Framework substitutes these placeholders when generating a file:

| Placeholder | Value |
|-------------|-------|
| `{{title}}` | Title derived from the name (`bp-summary` becomes `Bp summary`; names with spaces or capitals keep their casing) or the explicit `title` argument |
| `{{filename}}` | File stem without extension |
| `{{author}}` | Author name from project settings, falling back to user settings |
| `{{email}}` | Author email |
| `{{affiliation}}` | Author affiliation |
| `{{date}}` | Current date (`YYYY-MM-DD`) |

Both `{{title}}` and `{{ title }}` forms are supported, along with `{filename}` and `{date}`.

## Built-in template names

| Name | File | Used by |
|------|------|---------|
| `notebook` | `notebook-default.qmd` | `make_notebook()` and `make_qmd()` (default stub) |
| `script` | `script-default.R` | `make_script()` |
| `presentation` | `notebook-revealjs.qmd` | `make_presentation()` and `make_revealjs()` |

Jupyter notebooks (`.ipynb`) do not use text stubs; Framework generates a title Markdown cell followed by a `framework::scaffold()` code cell.

## User-level templates

Inspect, write, or reset templates in `fw_config_dir()` by name:

```r
read_framework_template("notebook")
write_framework_template("notebook", contents)
reset_framework_template("notebook")
```

Until you write a custom file, Framework reads the built-in template directly so package updates take effect automatically. `reset_framework_template()` overwrites the user copy with the built-in template.

## Project-level stubs

Copy built-in stubs into a project's `stubs/` folder to customize them for that repository:

```r
stubs_publish()             # Copy all stubs
stubs_publish("notebooks")  # Copy notebook stubs only
stubs_list()                # List available stubs
```

Stub filenames follow `notebook-{name}.qmd`, `notebook-{name}.Rmd`, and `script-{name}.R`. Select a named stub when creating a file:

```r
make_notebook("report", stub = "minimal")
```

## Example templates

`notebook-default.qmd`:

````qmd
---
title: "{{ title }}"
author: "{{ author }}"
date: "{{ date }}"
format:
  html:
    toc: true
    code-fold: true
---

```{r}
#| label: setup
library(framework)
scaffold()
```

## Analysis
````

`script-default.R`:

```r
# {{ title }}
# Author: {{ author }}
# Created: {{ date }}

library(framework)
scaffold()
```

Generate files from the active templates with:

```r
make_notebook("01-exploration")
make_script("process-data")
make_presentation("quarterly-review")
```
