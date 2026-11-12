---
id: new-project
title: New projects
section: getting_started
position: 5
description: 'Project creation from the R console and Framework Cloud'
---
## Project creation

```r
framework::new_project()
```

`new_project()` prompts for a project name, then shows where the project would go: a folder named for the project in the current directory. It asks:

```text
Create the project here (/Users/you/code/my-analysis)? [y/n]
```

Enter or `y` uses that folder. `n` asks for the folder to put the project in:

```text
Where should the project go? Leave blank to use the current directory (/Users/you/code):
```

The project folder is created inside the folder you type, unless that path already ends in the project's name. `~` is expanded. Framework prints the full path before it creates anything.

Pass the name and location directly to skip the prompts:

```r
new_project("my-analysis", "~/code/my-analysis")
```

Non-interactive sessions must pass both. Without `location`, they stop instead of choosing a folder.

## Tools and sets

Turn on tools and add Framework's package and skill sets:

```r
new_project(
  "study", "~/code/study",
  tools = "targets",
  package_sets = "tidyverse-analysis"
)
```

- `tools`: `quarto`, `quarto_manuscript`, `quarto_slides`, `targets`, `renv`, or `jupyter`. A tool's requirements are added with a message. A named logical such as `c(quarto = FALSE, targets = TRUE)` also turns a structure's tool off.
- `package_sets`: package sets such as `tidyverse-analysis`.
- `skill_sets`: AI skill sets. The default installs `framework` and `ggplot2`. Sensitive projects also get the sensitive-data skill.
- `workflow`: `"quarto"`, `"jupyter"`, or `"scripts"`.

Quarto is on for every structure except bare.

## Framework Cloud

After `cloud_login()`, `new_project()` uses your Cloud defaults and registers the
project with the same blueprint, tools, package sets, and skill sets used to
create it locally. Without `type`, your default blueprint on Framework Cloud is
used. It saves a project token in the ignored `.env` file so the
project can publish results and share its data ledger. Bare projects are
registered without creating a token file. Datasets stay on your machine.

When Framework Cloud can't be reached, a project with no choices beyond its name
uses your cached Cloud defaults. Otherwise an interactive session asks before
using Framework's built-in defaults, and a non-interactive session stops.

Use `offline = TRUE` to create locally without contacting Cloud. If registration
fails after the local project is created, Framework reports the failure and
keeps the local project.

Signed out, `new_project()` uses Framework's built-in defaults and creates a
Standard Project unless you pass `type`.

To create a project defined on Framework Cloud, pass its project token:

```r
new_project(key = "fw_...", location = "~/code/study")
```

The name and type come from the cloud project. `setup("fw_...")` does the same.
See [Setup](guide:setup).

## Project types

Framework has five structures. Four have their own function, and all work as `type` in `new_project()`:

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

### Bare project

No structure or starter files. Bring your own layout:

```r
new_project("my-tool", type = "bare")
```

Any lowercase id also works as `type`. It labels the blueprint the project came from. Signed out, an unknown type warns and builds the standard layout. See [Project types](guide:project-types).

## Created files

When you create a project, Framework:

1. Creates the directory structure for its type
2. Writes `settings.yml`. Standard and sensitive projects split sections into `settings/*.yml`
3. Writes `.env` and a `.gitignore` for the project type that ignores `.env`
4. Writes `scaffold.R` and a VS Code/Positron `.code-workspace` file
5. Writes `_quarto.yml` when the Quarto tool is on
6. Adds `AGENTS.md`, a `CLAUDE.md` that points to it, and Framework skills in `.claude/skills/`
7. Records the resolved project spec in `.framework/spec.json`
8. Initializes git and makes the first commit
   - If git identity isn’t configured, the initial commit is skipped with a note
   - Set `git config user.name` and `git config user.email`. The next `scaffold()` makes the first commit

Sensitive projects also get `.claude/settings.json`, which keeps Claude Code out of the private folders.

---

<div style="display: flex; justify-content: space-between">

[← settings.yml](guide:settings-yml)

[scaffold() →](guide:scaffold)

</div>
