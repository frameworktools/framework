---
id: new-project
title: New projects
section: getting_started
position: 5
description: 'Project creation from the GUI or the R console'
---
## Project creation

After running `setup()`, create a new project from the GUI or command line.

### GUI

Click **+ New Project** in the GUI sidebar, or run:

```r
framework::gui()
```

![New Project GUI](images/new-project-gui.png)

### Command line

```r
framework::new_project()
```

This prompts for a project name and location, then creates a fully configured project using your saved defaults.

You can also specify the name and location directly:

```r
new_project("my-analysis", "~/code/my-analysis")
```

## Framework Cloud

After `cloud_login()`, `new_project()` uses your Cloud defaults and registers the
project with the same blueprint, tools, package sets, and skill sets used to
create it locally. It saves a project token in the ignored `.env` file so the
project can publish results and share its data ledger. Bare projects are
registered without creating a token file. Datasets stay on your machine.

Use `offline = TRUE` to create locally without contacting Cloud. If registration
fails after the local project is created, Framework reports the failure and
keeps the local project.

## Project types

Framework supports four project types, each with its own function:

### Standard project

The default type, with a full structure for data analysis:

```r
new_project("my-analysis")
```

### Sensitive data project

Separate private and public directories with stricter privacy controls:

```r
new_project_sensitive("medical-study")
```

### Presentation

A minimal structure for RevealJS slides:

```r
new_presentation("quarterly-review")
```

### Course

A structure for teaching materials with slides, assignments, and modules:

```r
new_course("stats-101")
```

## Created files

When you create a project, Framework:

1. Creates the directory structure based on your defaults
2. Generates a `settings.yml` with your configuration
3. Sets up `.gitignore` with default patterns
4. Creates IDE workspace files (VS Code/Positron)
5. Adds AI assistant configuration (CLAUDE.md) if enabled
6. Initializes git if configured
   - If git identity isn’t configured, the initial commit is skipped with a note
   - Set `git config user.name` and `git config user.email` to enable auto-commit

---

<div style="display: flex; justify-content: space-between">

[← settings.yml](guide:settings-yml)

[scaffold() →](guide:scaffold)

</div>
