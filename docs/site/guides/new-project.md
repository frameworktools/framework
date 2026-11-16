---
id: new-project
title: New projects
section: getting_started
position: 5
description: 'Project creation from the R console and Framework Cloud'
---
## Interactive creation

```r
framework::new_project()
```

`new_project()` prompts for a project name and proposes a folder named for the project in the current working directory:

```text
Create the project here (/Users/you/code/my-analysis)? [y/n]
```

When a Projects folder is set in Framework Cloud Settings, `new_project()` proposes a path inside that folder instead:

```text
Create the project in /Users/you/research/my-analysis? [y/n]
```

Framework creates the Projects folder if it does not exist. When signed out or offline, `new_project()` reads the Projects folder from the last `cloud_sync()` mirror if available.

Press Enter or `y` to accept the proposed path. Enter `n` to type another parent directory:

```text
Where should the project go? Leave blank to use the current directory (/Users/you/code):
```

Framework creates the project folder inside the directory you enter unless that path already ends with the project name. `~` expands to your home directory, and Framework prints the resolved path before writing files.

## Direct arguments

Pass `name` and `location` to skip interactive prompts:

```r
new_project("my-analysis", "~/code/my-analysis")
```

Non-interactive sessions require both `name` and `location`.

## Tools and sets

Enable tools and attach package or skill sets during project creation:

```r
new_project(
  "study", "~/code/study",
  tools = "targets",
  package_sets = "tidyverse-analysis"
)
```

- `tools`: `"quarto"`, `"quarto_manuscript"`, `"quarto_slides"`, `"targets"`, `"renv"`, or `"jupyter"`. Required companion tools are added automatically with a message. Pass a named logical vector such as `c(quarto = FALSE, targets = TRUE)` to disable a structure's default tool.
- `package_sets`: built-in or Cloud package sets such as `"tidyverse-analysis"`.
- `skill_sets`: AI skill sets. Defaults to `"framework"` and `"ggplot2"`, plus the sensitive-data skill on sensitive projects.
- `workflow`: `"quarto"`, `"jupyter"`, or `"scripts"`.

Quarto is enabled by default for every built-in structure except `bare`.

## Framework Cloud integration

After `cloud_login()`, `new_project()` resolves your Cloud defaults and registers the project on Framework Cloud with the chosen blueprint, tools, package sets, and skill sets. When `type` is omitted, Framework uses your default Cloud blueprint. Registered projects, bare ones included, receive `FW_PROJECT_TOKEN` and `FW_CLOUD_URL` in `.env` for artifact publishing and data ledger sync. Data files remain local.

If Framework Cloud cannot be reached, `new_project()` uses your cached Cloud defaults when no custom options were passed. Otherwise interactive sessions ask before falling back to built-in defaults, and non-interactive sessions stop with an error.

Pass `offline = TRUE` to create a project locally without contacting Framework Cloud. If Cloud registration fails after local files are written, Framework reports the error and keeps the local project.

When signed out, `new_project()` uses built-in defaults and creates a `project` layout unless `type` is given.

To materialize a project already created in the Framework Cloud web interface, pass its project token:

```r
new_project(key = "fw_...", location = "~/code/study")
```

`setup("fw_...")` runs the same flow. See [Setup](guide:setup).

## Built-in project types

Each structure works as `type` in `new_project()`, and four have dedicated constructors:

```r
new_project("my-analysis")                  # Standard project (type = "project")
new_project_sensitive("medical-study")      # Privacy-sensitive (type = "project_sensitive")
new_presentation("quarterly-review")        # RevealJS deck (type = "presentation")
new_course("stats-101")                     # Course materials (type = "course")
new_project("my-tool", type = "bare")       # Minimal files only
```

Any lowercase blueprint identifier works as `type`. When signed out, an unknown `type` emits a warning and builds the standard `project` layout. See [Project types](guide:project-types).

## Generated files

Creating a project performs these steps:

1. Creates the directory tree for the selected structure.
2. Writes `settings.yml` (and `settings/*.yml` for `project` and `project_sensitive`).
3. Writes `.env` (except on `bare`) and a type-specific `.gitignore` that excludes `.env`.
4. Writes `scaffold.R` and a VS Code / Positron `.code-workspace` file.
5. Writes `_quarto.yml` when the `quarto` tool is enabled.
6. Writes `AGENTS.md`, assistant pointer files such as `CLAUDE.md`, and skill files in `.claude/skills/` or `.agents/skills/`.
7. Records the resolved project specification in `.framework/spec.json`.
8. Initializes a Git repository and creates the initial commit when `user.name` and `user.email` are configured. If Git identity is missing, Framework skips the commit with a note and creates it on the next `scaffold()` after `git config user.name` and `git config user.email` are set.

Privacy-sensitive projects with Claude Code enabled also receive `.claude/settings.json` rules that block agent access to private directories and `.env`.
