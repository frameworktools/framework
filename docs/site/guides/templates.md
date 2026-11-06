---
id: templates
title: Templates
section: features
position: 6
description: 'Customizing notebook, script, and project templates'
---
## Overview

Framework uses templates to generate new notebooks, scripts, and project files. You can customize these templates to match your workflow.

## GUI editor

Edit templates in the GUI. Run `setup()` and click **Templates** in the sidebar:

```r
framework::setup()
```

![Templates GUI](images/templates-gui.png)

The GUI provides a code editor for each template type with syntax highlighting and a **Reset to default** button if you want to start over.

## Template variables

Templates support variable substitution. When you create a new file, these placeholders are replaced with actual values:

| Variable | Description |
|----------|-------------|
| `{{title}}` | File or project title |
| `{{author}}` | Author name |
| `{{email}}` | Author email |
| `{{affiliation}}` | Author affiliation |
| `{{date}}` | Current date |
| `{{github_username}}` | GitHub username |
| `{{github_email}}` | GitHub email |

## Template types

Framework manages several template types:

- **notebook**: Quarto notebooks (`.qmd`)
- **script**: R scripts (`.R`)
- **presentation**: RevealJS slides
- **gitignore**: `.gitignore` files per project type
- **ai_canonical**: AI assistant instruction files (CLAUDE.md, etc.)

## Template location

Templates are stored in `~/.config/framework/templates/`. Framework copies default templates here on first use, then uses your customized versions.

```text
~/.config/framework/
└── templates/
    ├── notebook-default.qmd
    ├── script-default.R
    ├── presentation-default.qmd
    ├── gitignore-project
    ├── gitignore-sensitive
    ├── gitignore-course
    ├── gitignore-presentation
    ├── ai-context.project.md
    ├── ai-context.project_sensitive.md
    └── ai-context.course.md
```

## Customization

### Notebook template

Edit `~/.config/framework/templates/notebook-default.qmd`:

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

Variables like `{{ title }}` and `{{ author }}` are replaced when creating new files. Framework also accepts the compact `{{title}}` style, so either spacing works in custom templates.

### Script template

Edit `~/.config/framework/templates/script-default.R`:

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

To restore a template to its default, delete it from `~/.config/framework/templates/`. Framework will recreate it from the default on next use.

You can also use the **Reset to default** button in the GUI.

---

<div style="display: flex; justify-content: space-between">

[← Functions](guide:functions)

[Quarto integration →](guide:quarto)

</div>
