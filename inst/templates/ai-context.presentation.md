# {ProjectName}

This file provides guidance to AI assistants working with this Framework
presentation project. It is the canonical context file; detailed workflow
instructions live in the skills listed below.

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

## Presentation Workflow

Edit `presentation.qmd` for your slides, then render with:

```bash
quarto render presentation.qmd
```

Create additional decks with `make_notebook("backup-slides", stub = "revealjs")`.

## Project Notes

*Add your presentation-specific notes here.*
