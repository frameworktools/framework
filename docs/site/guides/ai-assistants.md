---
id: ai-assistants
title: AI assistants
section: features
position: 11
description: 'Context files and skills for AI coding assistants'
---
## Overview

Framework gives AI coding assistants project-specific context. Each project gets one `AGENTS.md` and a set of skills. Assistants learn your environment, data catalog, and directory structure from them.

## Project files

New projects get:

- **`AGENTS.md`**: The canonical context file. Edit this one.
- **`CLAUDE.md`**: One line, `@AGENTS.md`, so Claude Code reads `AGENTS.md`.
- **Skills**: Focused instruction files (`SKILL.md`) that assistants load on demand.

There is one context file, so nothing needs syncing. The `ai_sync` git hook was removed in 2.0, and `ai_sync_context()` is deprecated.

## Supported assistants

| Assistant | Skills folder | Pointer file |
|-----------|---------------|--------------|
| Claude Code | `.claude/skills/` | `CLAUDE.md` |
| OpenAI Codex | `.agents/skills/` | None. Codex reads `AGENTS.md`. |
| GitHub Copilot | `.agents/skills/` | `.github/copilot-instructions.md` |

Claude Code is the default. The project's assistants are recorded under `ai.assistants` in `settings.yml` (or `settings/ai.yml`). With no assistant selected, skills go to `.agents/skills/`.

## Skills

Framework ships these skills:

- `framework-workflow`: Project conventions and the scaffold workflow
- `framework-data`: The data catalog, reading, and saving
- `framework-packages`: Adding and installing packages
- `framework-outputs`: Saving tables, figures, models, and notebooks
- `framework-cache`: Caching computations
- `framework-databases`: Querying configured databases
- `framework-publishing`: Publishing artifacts
- `ggplot2-figures`: Accurate figures, from exploring data to publication
- `framework-sensitive-data`: Private and public folders (sensitive projects only)

`AGENTS.md` lists the installed skills with their paths. Assistants that don't discover skills on their own can follow those paths.

### Updating skills

`pull_skills()` brings a project's skills up to date with its setup on Framework Cloud:

```r
pull_skills(dry_run = TRUE)   # Show what would change
pull_skills()
```

The skill list comes from the project's current setup on Cloud, as edited there with Edit project. The project token in `.env` reads it. Missing skills are added. Unedited skills get their latest versions: Framework's from the installed package, and Cloud skills from Cloud. Getting a Cloud skill's latest version needs `cloud_login()`. Without it, the version in the project's setup is used.

Skills you edited locally are kept and listed. `pull_skills(overwrite = TRUE)` replaces them too, after backing them up to `.framework/skills-backups/`. Skills no longer in the setup are never deleted, only listed. The Skills table in `AGENTS.md` is refreshed.

```text
Skills: 2 added, 3 updated, 5 up to date, 1 locally edited (kept)
  Kept (locally edited): ggplot2-publishing — pull_skills(overwrite = TRUE) replaces it
```

Offline, or without a project token, `pull_skills()` uses the package skills for the project's type and says so. `ai_skills_update()` does the same as `pull_skills()`.

### Sending edited skills to Cloud

`push_skills()` sends locally edited skills to Cloud as new versions of your own skills. Sign in first with `cloud_login()`.

```r
push_skills(dry_run = TRUE)
push_skills()
```

Before pushing, it names what each new version affects and asks `Continue? [y/n]`. Without a console, pass `confirm = TRUE`. A skill that changed on Cloud since the last pull is refused with "Pull first"; `force = TRUE` pushes it anyway. Built-in Framework skills never change: an edited one is saved as your own copy. Only skills recorded in `.framework/skills.lock.json` are pushed. `skills_sync()` adds another.

### Skill sync with Framework Cloud

`skills_sync()` synchronizes one skill folder with your Framework Cloud account. Sign in first with `cloud_login()`.

```r
skills_sync(".claude/skills/my-review-checklist")

# Preview without writing files or Cloud versions
skills_sync(".claude/skills/my-review-checklist", dry_run = TRUE)
```

A skill Cloud doesn't know yet becomes a private account skill. When the local and Cloud copies both changed, sync stops and reports a conflict. Pass `resolve = "local"` or `resolve = "remote"` to choose one. Replaced files are backed up first.

## Sensitive projects

Sensitive projects name the folders agents must not read in `AGENTS.md`. They also get the `framework-sensitive-data` skill. With Claude Code selected, Framework writes `.claude/settings.json` with deny rules and a sandbox that keep Claude Code out of private folders and `.env`. Other assistants get the `AGENTS.md` rule and the skill only.

## Context regeneration

Sections marked with `<!-- @framework:regenerate -->` are updated when your project changes. Your other sections are preserved.

Update the generated sections:

```r
ai_regenerate_context()

# Only the packages section
ai_regenerate_context(sections = "packages")
```

This refreshes the environment, installed packages, and data catalog sections. Older projects that use `CLAUDE.md` as the canonical file still work.

---

<div style="display: flex; justify-content: space-between">

[← Git integration](guide:git)

[Caching →](guide:caching)

</div>
