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
- `framework-outputs`: Saving outputs, caching, database queries, and publishing
- `ggplot2-exploring`: Quick, accurate figures for understanding data
- `ggplot2-publishing`: Figures for papers, reports, and slides
- `framework-sensitive-data`: Rules for restricted data (sensitive projects only)

`AGENTS.md` lists the installed skills with their paths. Assistants that don't discover skills on their own can follow those paths.

After upgrading the framework package, refresh the shipped skills:

```r
ai_skills_update()
```

Unchanged skills get the new version. Skills you edited locally are kept. Custom skills are left alone.

### Skill sync with Framework Cloud

`skills_sync()` synchronizes a skill folder with your Framework Cloud account. Sign in first with `cloud_login()`.

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
