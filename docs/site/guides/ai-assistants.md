---
id: ai-assistants
title: AI assistants
section: features
position: 11
description: 'AGENTS.md context files, assistant skills, and Framework Cloud skill sync'
---
## Context and skills

Each Framework project generates a single canonical instruction file (`AGENTS.md`) alongside on-demand skills (`SKILL.md`) so coding agents understand the project's directory layout, package configuration, and data catalog.

## Generated files

- `AGENTS.md`: canonical project instructions. Edit custom rules directly here.
- Pointer files: `CLAUDE.md` (`@AGENTS.md`) or `.github/copilot-instructions.md`, depending on configured assistants.
- Skills: task-specific `SKILL.md` guides loaded on demand by assistants.

Because `AGENTS.md` is canonical, no file-sync hook is needed; the 1.x `ai_sync` hook was removed in 2.0 and `ai_sync_context()` is deprecated.

## Supported coding assistants

| Assistant | Skills directory | Pointer file |
|-----------|------------------|--------------|
| Claude Code | `.claude/skills/` | `CLAUDE.md` |
| OpenAI Codex | `.agents/skills/` | Reads `AGENTS.md` directly |
| GitHub Copilot | `.agents/skills/` | `.github/copilot-instructions.md` |

Claude Code is enabled by default. Configured assistants are listed under `ai.assistants` in `settings/ai.yml` (or `settings.yml`). When no assistant is selected, skills install into `.agents/skills/`.

## Built-in skills

- `framework-workflow`: project conventions and `scaffold()` initialization
- `framework-data`: data catalog reads, saves, and hashes
- `framework-packages`: `package_add()`, package sets, and `renv`
- `framework-outputs`: `save_table()`, `save_figure()`, `save_model()`, and `save_notebook()`
- `framework-cache`: `cache_remember()` and cache invalidation
- `framework-databases`: `db_query()` and connection configuration
- `framework-publishing`: `publish()` destinations and visibility rules
- `ggplot2-figures`: exploratory and publication figures in `ggplot2`
- `framework-sensitive-data`: private and public directory rules (privacy-sensitive projects)

`AGENTS.md` includes a table of installed skills and relative paths so tools without native skill discovery can read them.

## Syncing skills with Framework Cloud

### Pulling project skills

`pull_skills()` updates a project's skills from its setup on Framework Cloud using `FW_PROJECT_TOKEN` in `.env`:

```r
pull_skills(dry_run = TRUE)
pull_skills()
```

Missing skills are added, and unedited skills update to their latest versions (built-in skills from the installed R package, custom Cloud skills from Framework Cloud when signed in with `cloud_login()`, or the version pinned in the project setup when signed out).

Locally edited skills are kept and reported:

```text
Skills: 2 added, 3 updated, 5 up to date, 1 locally edited (kept)
  Edited: ggplot2-publishing — .claude/skills/ggplot2-publishing has local edits, which were kept. pull_skills(overwrite = TRUE) replaces them with the built-in version.
```

Pass `overwrite = TRUE` to replace locally edited skills after backing them up to `.framework/skills-backups/`. Skills removed from the Cloud setup are listed without being deleted locally, and the Skills table in `AGENTS.md` is refreshed. Offline or without `FW_PROJECT_TOKEN`, `pull_skills()` refreshes built-in package skills for the project's type. `ai_skills_update()` is an alias for `pull_skills()`.

A skill whose tracked copies in `.claude/skills/` and `.agents/skills/` differ, or with a tracked copy missing, is not pulled. Its copies and its entry in `.framework/skills.lock.json` are left as they are, and the message gives the `skills_copy()` call that reconciles it. The same applies when you add an assistant folder and the existing copy is locally edited or tracks your own or a Cloud skill. A skill that tracks your own Cloud skill is never replaced by a built-in or by setup content. With `overwrite = TRUE`, an edited copy of your own skill is reset (after a backup) to that same skill's Cloud version, the same or a newer one; another identity never replaces it. Pull reads only the enabled assistants' skills folders and the paths the lock tracks. No skill moves to an older version. When a skill is reported as diverged, nothing is written for it in any folder. Offline, a skill tracked on Cloud is left as it is and reported as not pulled. When every tracked copy of a skill is missing, `pull_skills()` installs it again and reports it as restored.

### Pushing edited project skills

`push_skills()` publishes locally edited skills recorded in `.framework/skills.lock.json` to your Framework Cloud account (requires `cloud_login()`):

```r
push_skills(dry_run = TRUE)
push_skills()
```

`push_skills()` shows what each new version affects and prompts `Continue? [y/n]` (pass `confirm = TRUE` in non-interactive sessions). If a skill changed on Cloud since the last pull, pushing stops with `"Pull first"` unless `force = TRUE`. Edited built-in Framework skills are saved as private forks under your account rather than modifying built-in skills.

### Copying skills between assistant folders

A project can keep the same skill in `.claude/skills/` (Claude Code) and `.agents/skills/` (Codex and Copilot). `pull_skills()` writes the same copy to both. After you edit one copy, the copies differ. `skills_sync()` stops for that skill with "Assistant skill copies diverged", `push_skills()` reports it as failed and continues with the others, and `pull_skills()` leaves it as it is. A missing tracked copy counts as diverged too. `skills_copy()` copies the version to keep over the others:

```r
skills_copy(from = "claude", dry_run = TRUE)
skills_copy(from = "claude")                      # to every other assistant folder
skills_copy(from = "claude", to = "agents", skills = "ggplot2-figures")
skills_copy(from_dir = ".claude/skills", to_dir = "some/other/skills")
```

`from` and `to` take `"claude"` or `"agents"`. `"codex"` and `"copilot"` also name `.agents/skills/`. `from_dir` and `to_dir` take project-relative folders. They can't be empty, the same folder, or one inside the other. The target can't be in or contain `.framework/`.

A skill is a folder with a regular `SKILL.md` file. Folders whose names start with `.` are skipped, because copies are staged in them. `skills_copy()` copies `SKILL.md` and its syncable companion files, with executable modes. Excluded files, such as `.env`, are not copied and stay in the target. Other files that are only in a replaced copy are removed from it and kept in the backup. Each replaced copy is backed up to `.framework/skills-backups/` and keeps its folder permissions. The output names the backup folder. Identical copies are left alone. Skills only in a target folder are listed, left alone, and not read. When the source skill is tracked in `.framework/skills.lock.json`, a real run adds each copy's path to its entry, so the copies sync as one skill. The entry keeps its last synced version, so `push_skills()` then pushes the edited skill. A dry run, or an untracked source, leaves the lock alone. A folder name or matching bytes never join a path to a skill.

A real run takes the skill sync lock, then checks every source and target before anything is written. If a copy fails or is interrupted, the copies already made are undone. A copy that can't be restored is named with its backup.

### Syncing an individual skill folder

`skills_sync()` synchronizes any single skill directory (and companion files) with your Framework Cloud account:

```r
skills_sync(".claude/skills/my-review-checklist", dry_run = TRUE)
skills_sync(".claude/skills/my-review-checklist")
```

Unregistered skills become private account skills on Cloud. If both local and Cloud copies changed, `skills_sync()` stops and reports the conflict until you pass `resolve = "local"` or `resolve = "remote"`. Replaced files are backed up first.

### Known limits

- Use one skill per folder name in a project.
- Copy skills between assistant folders with `skills_copy()`. A copy made by hand isn't tracked, and `pull_skills()` leaves it alone.
- On macOS, folder names that differ only in letter case are the same folder. Use one spelling.
- A skill command that refuses changes nothing. Its message says what to do next.

## Privacy-sensitive projects

Privacy-sensitive projects list restricted paths in `AGENTS.md` and install `framework-sensitive-data`. When Claude Code is selected, Framework also writes `.claude/settings.json` with `deny` rules and sandboxing that block access to private directories and `.env`. Other assistants receive the `AGENTS.md` instructions and skill only.

## Regenerating AGENTS.md sections

Blocks delimited by `<!-- @framework:regenerate -->` update from current project metadata while leaving hand-written sections intact:

```r
ai_regenerate_context()
ai_regenerate_context(sections = "packages")
```

`ai_regenerate_context()` refreshes environment details, installed packages, and data catalog entries, and continues to support legacy 1.x projects where `CLAUDE.md` was canonical.
