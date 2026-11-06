---
id: templates
title: Templates
section: features
position: 6
description: 'Customizing notebook, script, and project templates'
---
## Overview

Framework uses templates to generate new notebooks, scripts, and presentations. You can customize these templates to match your workflow.

## Template sources

`make_notebook()`, `make_script()`, and `make_presentation()` look for a template in this order:

1. The project's `stubs/` folder
2. Your templates, in the `templates/` folder of your Framework settings
3. Framework's built-in stubs

Project stubs apply to one project. Your templates apply to every project you create files in.

## Template variables

Templates support variable substitution. When you create a new file, these placeholders are replaced with actual values:

| Variable | Description |
|----------|-------------|
| `{{title}}` | File name as given, without extension |
| `{{filename}}` | Same as `{{title}}` |
| `{{author}}` | Author name |
| `{{email}}` | Author email |
| `{{affiliation}}` | Author affiliation |
| `{{date}}` | Current date (YYYY-MM-DD) |

Author values come from the project's author settings, then your global settings. Framework accepts both `{{title}}` and `{{ title }}`. The single-brace forms `{filename}` and `{date}` also work.

## Template types

Three templates are used:

| Name | File | Used by |
|------|------|---------|
| `notebook` | `notebook-default.qmd` | `make_notebook()` and `make_qmd()` with the default stub |
| `script` | `script-default.R` | `make_script()` |
| `presentation` | `notebook-revealjs.qmd` | `make_presentation()` and `make_revealjs()` |

Jupyter notebooks (`.ipynb`) do not use templates. They start with a title cell and a `framework::scaffold()` cell.

## Your templates

Read, write, and reset your templates by name:

```r
read_framework_template("notebook")
write_framework_template("notebook", contents)
reset_framework_template("notebook")
```

They are stored in the `templates/` folder of `fw_config_dir()`. Until you write one, Framework uses its built-in version, so package updates still reach you.

## Project stubs

Copy Framework's stubs into the project's `stubs/` folder to customize them there:

```r
stubs_publish()             # all stubs
stubs_publish("notebooks")  # notebook stubs only
stubs_list()                # available stubs
```

Stub files are named `notebook-{name}.qmd`, `notebook-{name}.Rmd`, and `script-{name}.R`. Pick one with the `stub` argument:

```r
make_notebook("report", stub = "minimal")
```

## Customization

Save your version with `write_framework_template()`, or edit the file in the `templates/` folder of `fw_config_dir()`.

### Notebook template

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

## Overview

Your analysis starts here.
````

### Script template

`script-default.R`:

```r
# {{ title }}
# Author: {{ author }}
# Created: {{ date }}

library(framework)
scaffold()

# Your code here
```

## Template use

Templates are used automatically when you create new files:

```r
make_notebook("01-exploration")
make_script("process-data")
make_presentation("quarterly-review")
```

## Template reset

`reset_framework_template()` restores a template to Framework's default. Deleting the file from the `templates/` folder has the same effect.

---

<div style="display: flex; justify-content: space-between">

[← Functions](guide:functions)

[Quarto integration →](guide:quarto)

</div>
