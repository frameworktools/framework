# {ProjectName}

This file provides guidance to AI assistants working with this Framework project.
It is the canonical context file; detailed workflow instructions live in the
skills listed below. Edit freely - add project-specific notes at the bottom.

## Skills

Detailed instructions live in skill files, loaded on demand. Claude Code discovers
them automatically; other agents should read the relevant SKILL.md before working
on a matching task.

| Skill | Covers | Path |
|-------|--------|------|
| `framework-workflow` | scaffold() initialization, critical rules, creating notebooks/scripts | `.claude/skills/framework-workflow/SKILL.md` |
| `framework-data` | reading and saving data with data_read() and data_save() | `.claude/skills/framework-data/SKILL.md` |
| `framework-packages` | adding and managing R packages with package_add() | `.claude/skills/framework-packages/SKILL.md` |
| `framework-outputs` | results, caching, database queries, publishing | `.claude/skills/framework-outputs/SKILL.md` |

## Framework Environment

This project uses the Framework R package. Start each notebook and script with
`scaffold()`, which sets the working directory, loads `.env`, installs and
attaches the project's packages, and sources the functions folder.

## Project Notes

*Add your project-specific notes, conventions, and documentation here.*
