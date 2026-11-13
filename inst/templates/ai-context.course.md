# {ProjectName}

This file provides guidance to AI assistants working with this Framework course
project. It is the canonical context file; detailed workflow instructions live
in the skills listed below. Edit freely - add course notes at the bottom.

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

## Course Structure

- `slides/` - Lecture materials (Quarto revealjs format)
- `assignments/` - Student exercises and homework
- `modules/` - Course modules/lessons
- `course_docs/` - Syllabus, policies, schedules
- `data/` - Datasets for demonstrations and exercises
- `readings/` - Reading materials and references

Create materials with Framework helpers:

```r
make_notebook("lecture-01-intro", dir = "slides", stub = "revealjs")
make_notebook("hw-01-basics", dir = "assignments")
```

## Project Notes

*Add your course-specific notes, conventions, and documentation here.*
