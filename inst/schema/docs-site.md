# Framework docs sites (v1)

Framework for R, Framework for Python (`framework-py`), the Framework CLI (`fw`), and Framework for Stata publish documentation sites from one directory format. Framework Cloud renders them at:

- `r.framework.pub` (product `r`)
- `py.framework.pub` (product `py`)
- `cli.framework.pub` (product `cli`)
- `stata.framework.pub` (product `stata`)

Each repository stores its site sources in `docs/site/`. Release workflows attach `docs-site.tar.gz` to the GitHub release, and Framework Cloud imports the archive. `docs-reference.v1.json` is canonical in the R repository under `inst/schema/` and copied into the other repositories by asset sync.

## Directory layout

```text
docs/site/
  site.yml          # Hand-authored site metadata and section order
  guides/*.md       # Hand-authored Markdown guides
  images/           # Optional images: png, jpg, svg, webp, or gif
  reference.json    # Generated at release; not committed
```

### site.yml

```yaml
product: py                      # r, py, cli, or stata
title: Framework for Python
tagline: Structured data science projects in Python
repository: https://github.com/frameworktools/framework-py
install: uv add framework-py     # Displayed on the home page; or a list of options:
# install:
#   - title: Install latest
#     note: Recommended.         # Optional line under the title
#     code: uv add framework-py
sections:                        # Ordered top-bar dropdowns and sidebar groups
  - id: getting_started
    title: Getting started
  - id: features
    title: Features
  - id: reference
    title: Reference
    reference: true              # Populated from reference.json categories
```

Each section appears as a dropdown in the top bar and a group in the sidebar. Guide sections order their pages by `position` and display each guide's `title` and `description`. Reference sections list categories from `reference.json` with their descriptions. Framework Cloud renders the product switcher across R, Python, CLI, and Stata automatically.

### Guides

Each `guides/<id>.md` file uses CommonMark, GFM tables, and YAML frontmatter:

```markdown
---
id: data-management                 # URL-safe slug: /guides/{id}
title: Data management
description: Data files and the declarative data catalog
section: features                   # Section id from site.yml
position: 3                         # Order within the section
---
```

- Use `##` (H2) and `###` (H3) headings in the body to populate page navigation. Omit `#` (H1) headings because the page title comes from frontmatter.
- Name a language on every fenced code block (`python`, `r`, `sh`, `yaml`, `text`, and others).
- Format callouts with GitHub alert syntax (`> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`).
- Omit manual previous/next links; Framework Cloud generates them from `section` and `position`.

### Links

Guides, Markdown fields in `reference.json`, and `see_also` entries use these link forms:

| Target | Form |
|--------|------|
| Guide in the same product | `guide:data-management` |
| Reference entry in the same product | `ref:data_read` |
| Section anchor on a page | `guide:data-management#saving-data` |
| Page in another product | `r:guide:setup`, `py:ref:data_read`, `cli:ref:project-bootstrap`, `stata:ref:fw_use` |
| External URL | Full `https://` URL |

`ref:` takes the entry's `id`. Framework Cloud rewrites these schemes into URLs and reports unresolved targets during import. An unprefixed `see_also` string resolves to a reference entry name in the same product.

### Images

Place images in `docs/site/images/` and link them relative to the guide with alt text: `![Data catalog](images/catalog.png)`. Framework Cloud serves them from `/images/`. Reference entries can use the same relative paths.

### reference.json

Release builds generate `reference.json` and validate it against `docs-reference.v1.json`. Only public exports appear in `reference.json`.

- Top-level fields: `schema` (`"docs-reference.v1"`), `product`, `version`, `categories`, and `entries`.
- `categories`: `id`, `title`, one-line `description`, `position`, and optional `common` entry names shown first.
- `entries`: required `id`, `name`, `kind` (`function`, `class`, or `command`), `category`, and one-line `summary`. Optional fields:
  - `title`, `usage`, `description`, `details`, `returns`, and `note`
  - `parameters` (`name`, `type`, `default`, `required`, `env`, and `description`)
  - `sections` (with `subsections`)
  - `examples` (`title`, `code`, and `runnable`)
  - `see_also` (strings or `{title, url}` objects)
  - `aliases`, `lifecycle` (`stable`, `deprecated`, or `experimental`), `replaced_by`, and `since`
- Prose fields accept Markdown.

Generator sources by product:

- **R** runs `docs_export()` over roxygen metadata:
  - `@description` populates `description` and `@details` populates `details`.
  - `\section` and `\subsection` populate `sections`.
  - `\dontrun` sets `runnable: false`.
  - Parameter defaults come from function usage; parameter types are omitted.
- **Python** inspects exported functions and classes:
  - Google-style docstrings populate `summary`, `description`, `details`, and `parameters` (`Args:`).
  - Type annotations populate `type`, and signatures populate `default`.
- **CLI (`fw`)** walks the Cobra command tree:
  - Commands export with `kind: command` and hyphenated IDs (`project bootstrap` becomes `project-bootstrap`).
  - Flags populate `parameters`, including `env` when an environment variable backs a flag.
- **Stata** compiles `docs/site/reference.yml` and checks `.sthlp` coverage.

## Release archive

`docs-site.tar.gz` contains a single top-level `docs-site/` directory with `site.yml`, `guides/`, optional `images/`, and `reference.json`. Each release workflow builds the archive, validates `reference.json` against the JSON schema, and uploads `docs-site.tar.gz` to the GitHub release. Framework Cloud imports the latest release per product and indexes guide titles, descriptions, headings, reference names, summaries, and parameters for `⌘K` search.
