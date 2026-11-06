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
├── course_docs/         # Course documentation
├── data/                # Shared datasets
├── readings/            # Assigned readings
├── slides/              # Lecture presentations
├── framework.db         # Metadata database
└── settings.yml         # Course configuration
```

Optional directories available in the GUI: `functions/`, `modules/`, `scripts/`

## Course content

### Slides

Create lecture slides with Quarto RevealJS:

```r
make_notebook("intro-to-r", subdir = "slides/week-01")
```

### Assignments

Create assignment notebooks:

```r
make_notebook("assignment-01", subdir = "assignments")
```

### Course documents

Create syllabi and schedules:

```r
make_notebook("syllabus", subdir = "course_docs")
```

## Configuration

Example `settings.yml` for a course:

```yaml
default:
  project_type: course

  directories:
    data: data
    slides: slides
    assignments: assignments
    course_docs: course_docs
    readings: readings

  packages:
    - name: dplyr
      auto_attach: true
    - name: ggplot2
      auto_attach: true
    - name: palmerpenguins
      auto_attach: false
```

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
make_notebook("data-wrangling", subdir = "slides/week-03")
```

### 2. Assignments

Build assignments with instructions:

```text
assignments/assignment-01/
├── instructions.qmd  # Student-facing
└── solution.qmd      # Answer key
```

### 3. Rendering

Slides render to `rendered/slides/`, assignments to `rendered/assignments/`.

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

Enable and use `functions/` for common code:

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
