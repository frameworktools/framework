---
id: course-teaching
title: Course/Teaching
section: project_types
position: 13
description: 'Project structure for teaching materials'
---
## Overview

The **Course/Teaching** type is designed for educators creating academic courses. It provides organized directories for slides, assignments, and course materials.

## Directory structure

```text
my-course/
├── assignments/         # Student assignments
├── cache/               # Cached computations
├── course_docs/         # Course documentation
├── data/                # Shared datasets
├── functions/           # Custom R functions (auto-loaded)
├── modules/             # Notebooks (the default make_notebook() folder)
├── readings/            # Assigned readings
├── scripts/             # Automation scripts
├── slides/              # Lecture presentations
│   └── _metadata.yml    # RevealJS format for everything in slides/
├── _quarto.yml          # Quarto configuration
├── AGENTS.md            # AI assistant guide
├── scaffold.R           # Project startup code
└── settings.yml         # Course configuration
```

`framework.db` is created by the first `scaffold()`, `bootstrap()`, or saved output.

## Course content

### Slides

Create lecture slides with Quarto RevealJS:

```r
make_revealjs("intro-to-r", dir = "slides/week-01")
```

### Assignments

Create assignment notebooks:

```r
make_notebook("assignment-01", dir = "assignments")
```

### Course documents

Create syllabi and schedules:

```r
make_notebook("syllabus", dir = "course_docs")
```

### Modules

`make_notebook()` without `dir` writes to `modules/`:

```r
make_notebook("week-01-exercises")
```

## Configuration

Example `settings.yml` for a course:

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

Course settings live in one `settings.yml`.

## Content organization

### By week

```text
slides/
├── week-01-introduction/
├── week-02-data-types/
├── week-03-data-wrangling/
└── week-04-visualization/
```

### By module

```text
slides/
├── foundations/
├── data-manipulation/
└── visualization/
```

## Teaching workflow

### 1. Lectures

Create slides in `slides/`:

```r
make_revealjs("data-wrangling", dir = "slides/week-03")
```

### 2. Assignments

Build assignments with instructions:

```text
assignments/assignment-01/
├── instructions.qmd  # Student-facing
└── solution.qmd      # Answer key
```

### 3. Rendering

Quarto renders into `rendered/`. Slides go to `rendered/slides/`, assignments to `rendered/assignments/`. The course `.gitignore` ignores `rendered/`; publish rendered files with `publish()` or remove that line to commit them.

```bash
quarto render slides/week-01/lecture.qmd
```

## Best practices

### Consistent naming

Use consistent prefixes:
```text
week-01-*, week-02-*, ...
assignment-01, assignment-02, ...
```

### Reusable functions

`scaffold()` loads every `.R` file in `functions/`. Put shared code there:

```r
# functions/grading.R
calculate_grade <- function(scores, weights) {
  sum(scores * weights) / sum(weights)
}
```

---

<div style="display: flex; justify-content: space-between">

[← Privacy-sensitive project](guide:privacy-sensitive-project)

[Presentation →](guide:presentation)

</div>
