---
id: course-teaching
title: Course/Teaching
section: project_types
position: 13
description: 'Project structure for lectures, assignments, and course materials'
---
## Structure

The course project (`course`) organizes lecture slides, student assignments, modules, readings, and course documents in a single repository.

```text
my-course/
├── assignments/         # Student assignments
├── cache/               # Cached computations (gitignored)
├── course_docs/         # Syllabi, schedules, and policies
├── data/                # Shared course datasets
├── functions/           # Reusable R functions sourced by scaffold()
├── modules/             # Default make_notebook() directory
├── readings/            # Reading notes and materials
├── scripts/             # Automation and grading scripts
├── slides/              # Lecture decks
│   └── _metadata.yml    # RevealJS defaults for slides/
├── _quarto.yml          # Root Quarto configuration
├── AGENTS.md            # AI assistant context
├── scaffold.R           # Project startup script
└── settings.yml         # Course configuration
```

`framework.db` is created on the first call to `scaffold()`, `bootstrap()`, or a `save_*()` function.

## Creating course files

Relative `dir` paths resolve from the project root regardless of the current working directory.

### Lecture slides

```r
make_revealjs("intro-to-r", dir = "slides/week-01")
```

### Assignments

```r
make_notebook("assignment-01", dir = "assignments")
```

### Course documents

```r
make_notebook("syllabus", dir = "course_docs")
```

### Modules

Calling `make_notebook()` without `dir` writes into `modules/`:

```r
make_notebook("week-01-exercises")
```

## Configuration

Course projects keep all settings in a single `settings.yml`:

```yaml
default:
  project_type: course
  tools:
    quarto: true
    renv: false

  directories:
    data: data
    slides: slides
    assignments: assignments
    course_docs: course_docs
    readings: readings
    notebooks: modules
    cache: cache
    functions: functions
    scripts: scripts

  render_dirs:
    slides: rendered/slides
    assignments: rendered/assignments
    course_docs: rendered/course_docs
    modules: rendered/modules

  packages:
    use_renv: false
    default_packages:
      - name: dplyr
        auto_attach: true
      - name: ggplot2
        auto_attach: true
      - name: palmerpenguins
        auto_attach: false
```

## Directory conventions

Organize subdirectories under `slides/` and `assignments/` either by week (`week-01-introduction/`, `week-02-data-types/`) or by topic (`foundations/`, `visualization/`).

Pair student prompts and instructor keys in per-assignment folders:

```text
assignments/assignment-01/
├── instructions.qmd
└── solution.qmd
```

Put shared grading or plotting helpers in `functions/*.R` so `scaffold()` loads them automatically.

## Rendering

Quarto writes rendered HTML and PDF output into `rendered/` (`rendered/slides/`, `rendered/assignments/`, and matching folders). The course `.gitignore` excludes `rendered/` by default; distribute outputs with `publish()` or edit `.gitignore` if you commit rendered HTML.

```sh
quarto render slides/week-01/lecture.qmd
```
