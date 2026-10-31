# Framework Package Cheatsheet

Quick reference for the most commonly used Framework functions.

---

## Getting Started

### Project Setup
```r
new()                            # Create new Framework project (interactive)
new("my-project", "~/projects/my-project", type = "project")  # Standard project
new_course("stats-101", "~/projects/stats-101")               # Course
new_presentation("talk", "~/projects/talk")                   # Presentation
new_project("study", "~/projects/study", tools = c("targets", "renv"),
            package_sets = "tidyverse-analysis")              # With tools and package sets
new(key = "1|fw_...")              # Project defined on Framework Cloud
bootstrap()                      # Prepare a cloned project (.env, folders, packages, hooks)
scaffold()                       # Load project environment (use in notebooks)
standardize_wd()                 # Normalize working directory for notebooks
```

### Notebook & Script Creation
```r
make_notebook("1-init")          # Create notebooks/1-init.qmd (defaults to Quarto)
make_qmd("analysis")             # Explicit Quarto notebook
make_rmd("report")               # Explicit RMarkdown notebook
make_revealjs("slides")          # Create reveal.js presentation
make_presentation("deck")        # Alias for make_revealjs()
make_script("process-data")      # Create scripts/process-data.R
stubs_list()                     # Show available stubs
stubs_publish()                  # Publish stubs for customization
```

---

## Data Management

### Loading Data
```r
# From data catalog (dot notation)
data_read("inputs_raw.dataset")           # Load from data catalog
data_read("inputs_intermediate.cleaned")  # Load intermediate data
data_info("source.public.example")        # Get data specification

# Direct file path (bypass catalog)
data_read("path/to/file.csv")             # Read CSV directly
data_read("data/results.rds")             # Read RDS directly
```

### Saving Data
```r
data_save(df, "outputs_private.output")   # Save to catalog
data_save(df, "outputs_private.secret", encrypted=TRUE)  # Encrypted save
```

### Data Cache
```r
cache_remember("key", expr)      # Cache expensive computation
cache_get("key")                 # Retrieve from cache
cache("key", value)              # Store in cache
cache_forget("key")              # Delete cached item
cache_flush()                    # Clear all cache
```

---

## Database Operations

### Connection Configuration (settings.yml)
```yaml
connections:
  db:
    driver: postgresql           # postgresql, sqlite, mysql, etc.
    host: !expr Sys.getenv("DB_HOST")
    database: !expr Sys.getenv("DB_NAME")
    user: !expr Sys.getenv("DB_USER")
    password: !expr Sys.getenv("DB_PASS")
```

### Using Connections
```r
db_connect("db")                 # Get database connection
db_query("SELECT * FROM users", "db")  # Run query
db_execute("UPDATE ...", "db")   # Execute non-query
db_list()                        # List configured connections
```

### Database Introspection
```r
conn <- db_connect("db")
DBI::dbListTables(conn)          # List tables in database
DBI::dbListFields(conn, "users") # List columns in table
```

---

## Configuration

### Reading Settings
`settings()` reads the project's settings with dot notation:

```r
settings("notebooks")                 # Smart lookup (checks directories section)
settings("directories.notebooks")     # Explicit nested value with dot notation
settings("connections.db.host")       # Access deep nested values
settings("seed")                      # Get random seed
settings("missing", default = "x")    # Provide fallback for missing keys
```

### Settings Helper (Alternative)
```r
settings()                          # View entire settings (pretty-printed in console)
settings("directories")             # Get all directories
settings("directories.notebooks")   # Get nested value with dot notation
settings("notebooks")               # Smart lookup (checks directories section)
settings("connections.db.host")     # Access deep nested values
settings("missing", default = "x")  # Provide fallback for missing keys
```

### Reading/Writing Config Files
```r
settings_read()                  # Read settings.yml
settings_read("custom.yml")      # Read specific config file
settings_write(config, "file")   # Write settings back
```

### AI Assistant Support
```r
ai_generate_context()            # Generate AGENTS.md (canonical AI context)
ai_regenerate_context()          # Refresh dynamic sections of AGENTS.md
ai_skills_update()               # Refresh .claude/skills/ after package upgrade
```

---

## Package Management

### Package Configuration in settings.yml
```yaml
packages:
  # Simple CRAN packages
  - dplyr
  - ggplot2

  # Version pinning
  - dplyr@1.1.0

  # GitHub packages (shorthand)
  - tidyverse/dplyr
  - tidyverse/dplyr@main    # specific branch/tag

  # Bioconductor packages
  - bioc::DESeq2

  # Explicit specification (for auto_attach control)
  - name: purrr
    auto_attach: true        # Load with scaffold()
  - name: httr2
    auto_attach: false       # Install but don't attach
```

### renv Integration (Optional)
```r
renv_enable()                    # Enable renv for project
renv_disable()                   # Disable renv
renv_enabled()                   # Check if renv is enabled
```

### Package Operations
```r
package_add("janitor")           # Record in settings and install
package_add("forcats", auto_attach = TRUE)  # Loaded by scaffold()
package_add("dplyr@1.1.0")       # Pin a version
packages_install()               # Install all configured packages
packages_list()                  # List configured packages
packages_snapshot()              # Save package versions (renv)
packages_restore()               # Restore saved versions (renv)
packages_status()                # Check package status (renv)
packages_update()                # Update packages (renv)
```

---

## Results Management

### Saving Outputs
```r
save_table(df, "summary")                            # outputs/tables/
save_figure(plot, "trend")                           # outputs/figures/
save_model(model, "my_model")                        # outputs/models/ (rds)
result_list()                                        # List saved outputs
result_list(type = "model")                          # Only models
```

---

## Utilities

### Scratch Space
```r
scratch_capture(df)              # Save to scratch/
scratch_capture(df, "data")      # Save as scratch/data.tsv
scratch_clean()                  # Clean scratch directory
```

### Date/Time
```r
now()                            # Current timestamp (formatted)
```

---

## Publishing to S3

### Setup
Configure S3 connection in `config.yml`:
```yaml
connections:
  s3_public:
    driver: s3
    bucket: my-bucket
    region: us-east-1
    prefix: framework-outputs     # Optional prefix for all uploads
    default: true                 # Mark as default S3 connection
```

Add credentials to `.env`:
```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

### Publishing Files
```r
publish("outputs/report.html")                    # Upload file to S3
publish("outputs/data.csv", dest = "data/v2.csv") # Custom destination
publish_dir("outputs/charts/")                    # Upload entire directory
```

### Publishing Notebooks
```r
publish_notebook("notebooks/analysis.qmd")        # Render & publish
# -> https://bucket.s3.region.amazonaws.com/prefix/analysis/index.html

publish_notebook("report.qmd", dest = "reports/2024/q4")  # Custom path
publish_notebook("report.qmd", self_contained = FALSE)    # With assets
```

### Publishing to GitHub Pages
```r
publish("outputs/report.html", to = "github")             # published/report/, commit, push
publish_notebook("report.qmd", to = "github", slug = "q4") # -> https://<owner>.github.io/<repo>/q4/
```
Turn on "Publish with GitHub Pages" for the project in Framework Cloud first.
The site is public, even from a private repository.

### Publishing Data
```r
publish_data(my_df, "datasets/results.csv")       # Publish data frame
publish_data(my_df, "data.rds", format = "rds")   # As RDS
publish_data("outputs/model.rds", "models/v2.rds") # Existing file
```

### Utilities
```r
storage_test()                    # Test S3 connection
storage_test("backup_s3")         # Test specific connection
publish_list()                    # List published files
publish_list("reports/")          # List with prefix filter
```

---

## Advanced Features

### Output Capture
```r
capture_output(expr)             # Capture console output
```

---

## Alphabetical Function Reference

| Function | Purpose |
|----------|---------|
| `ai_generate_context()` | Generate AGENTS.md (canonical AI context) |
| `ai_regenerate_context()` | Refresh dynamic sections of AGENTS.md |
| `ai_skills_update()` | Refresh Framework skills in .claude/skills/ |
| `ai_sync_context()` | Deprecated: sync legacy AI context files |
| `bootstrap()` | Prepare a cloned project |
| `cache()` | Store value in cache |
| `cache_flush()` | Clear all cache |
| `cache_forget()` | Delete cached item |
| `cache_get()` | Retrieve from cache |
| `cache_list()` | List cached items |
| `cache_remember()` | Cache expensive computation |
| `capture_output()` | Capture console output |
| `config_sync()` | Copy settings and logins from the Python package and fw into R |
| `data_add()` | Add data to catalog |
| `data_info()` | Get data specification |
| `data_read()` | Load from data catalog or file path |
| `data_save()` | Save to data catalog |
| `db_connect()` | Get database connection |
| `db_execute()` | Execute non-query SQL |
| `db_query()` | Execute query and return results |
| `db_list()` | List configured database connections |
| `db_transaction()` | Run code in a database transaction |
| `db_with()` | Execute code with a connection |
| `git_add()` | Stage files for commit |
| `git_commit()` | Commit staged changes |
| `git_diff()` | Show changes |
| `git_hooks_enable()` | Enable git hooks |
| `git_hooks_disable()` | Disable git hooks |
| `git_hooks_install()` | Install git hooks |
| `git_hooks_list()` | List installed hooks |
| `git_log()` | Show commit history |
| `git_pull()` | Pull from remote |
| `git_push()` | Push to remote |
| `git_security_audit()` | Audit for security issues |
| `git_status()` | Show repository status |
| `gui()` | Launch Framework GUI (needs the `plumber` package) |
| `make_notebook()` | Create notebook from stub |
| `make_presentation()` | Create presentation (reveal.js) |
| `make_qmd()` | Create Quarto notebook |
| `make_revealjs()` | Create reveal.js presentation |
| `make_rmd()` | Create RMarkdown notebook |
| `make_script()` | Create script from stub |
| `new()` | Create new project (interactive) |
| `new_course()` | Create course project |
| `new_presentation()` | Create presentation project |
| `new_project()` | Create standard project |
| `new_project_sensitive()` | Create project for sensitive data |
| `now()` | Current timestamp |
| `package_add()` | Record a package in settings and install it |
| `packages_install()` | Install configured packages |
| `packages_list()` | List configured packages |
| `packages_restore()` | Restore package versions (renv) |
| `packages_snapshot()` | Save package versions (renv) |
| `packages_status()` | Check package status (renv) |
| `packages_update()` | Update packages (renv) |
| `project_info()` | Display project information |
| `project_list()` | List registered projects |
| `publish()` | Upload file or directory to S3, Framework Cloud, or GitHub Pages |
| `publish_data()` | Publish data frame or file to S3 |
| `publish_dir()` | Upload directory to S3 |
| `publish_list()` | List published files in S3 |
| `publish_notebook()` | Render and publish Quarto notebook to S3, Framework Cloud, or GitHub Pages |
| `quarto_generate_all()` | Generate all _quarto.yml files |
| `quarto_regenerate()` | Regenerate _quarto.yml with backup |
| `renv_disable()` | Disable renv integration |
| `renv_enable()` | Enable renv integration |
| `renv_enabled()` | Check renv status |
| `result_list()` | List saved results |
| `save_figure()` | Save figure to outputs |
| `save_model()` | Save model to outputs |
| `save_notebook()` | Save notebook output |
| `save_report()` | Save report to outputs |
| `save_table()` | Save table to outputs |
| `scaffold()` | Load project environment |
| `scratch_capture()` | Save to scratch space |
| `scratch_clean()` | Clean scratch directory |
| `settings()` | Access project settings |
| `settings_read()` | Read configuration file |
| `settings_write()` | Write configuration file |
| `project_create_from_layers()` | Create a project from a framework.pub layers file |
| `setup()` | Configure global Framework settings |
| `spec_check()` | List problems in a resolved project spec |
| `spec_resolve()` | Merge project spec layers into one spec |
| `standardize_wd()` | Normalize working directory |
| `status()` | Show project status |
| `storage_test()` | Test S3 connection |
| `stubs_list()` | List available stubs |
| `stubs_path()` | Get stubs directory path |
| `stubs_publish()` | Publish stubs for customization |

---

## Configuration File Examples

### settings.yml (Single File Approach)
```yaml
default:
  project_name: "MyProject"

  packages:
    - dplyr
    - ggplot2
    - tidyr

  connections:
    framework:
      type: sqlite
      database: framework.db

  data:
    inputs.reference.example:
      path: inputs/reference/example.csv
      type: csv
```

### settings/ Directory (Multi-File Approach)
```
settings/
  packages.yml
  connections.yml
  data.yml
```

### Stub Template Example (stubs/notebook-analysis.qmd)
```yaml
---
title: "{filename}"
date: "{date}"
format: html
---

```{{r}}
library(framework)
scaffold()
standardize_wd()

# Your analysis code
```
```

---

## Directory Structure

### Project Type (Default)
```
project/
  ├── settings.yml              # Main configuration
  ├── .env                    # Environment variables (secrets)
  ├── framework.db            # Framework metadata database
  ├── inputs/
  │   ├── raw/
  │   ├── intermediate/
  │   ├── final/
  │   └── reference/
  ├── outputs/
  │   ├── private/            # Résultats internes (tables, figures, cache)
  │   └── public/             # Livrables validés
  ├── notebooks/              # Quarto/RMarkdown notebooks
  ├── scripts/                # Scripts R
  ├── functions/              # Fonctions personnalisées
  ├── docs/                   # Documentation
  ├── stubs/                  # Modèles personnalisés (optionnel)
  └── settings/               # Fichiers de configuration (optionnel)
```

### Course Type
```
course/
  ├── settings.yml
  ├── .env
  ├── framework.db
  ├── assignments/
  ├── course_docs/
  ├── data/
  ├── readings/
  └── slides/
```

### Presentation Type
```
presentation/
  ├── settings.yml
  ├── .env
  ├── framework.db
  └── presentation.qmd
```

---

## Quick Tips

1. **Quarto First**: Framework defaults to `.qmd` (Quarto) notebooks. Use `.Rmd` for RMarkdown.

2. **Data Paths**: Use dot notation for data catalog: `"category.subcategory.name"`

3. **Custom Stubs**: Run `stubs_publish()` then edit `stubs/` directory

4. **Encryption**: Requires `sodium` package. Use `encrypted=TRUE` parameter.

5. **renv**: Optional and opt-in. Enable with `renv_enable()` for reproducibility.

6. **Working Directory**: Call `standardize_wd()` in notebooks to normalize paths

7. **Database**: Framework creates `framework.db` for internal metadata tracking

8. **Functions Directory**: All `.R` files in `functions/` are auto-sourced by `scaffold()`

9. **Noun-Prefix Pattern**: Functions are grouped by noun (`query_*`, `result_*`, `scratch_*`, `stubs_*`)

10. **Project Types**: Choose `project`, `course`, or `presentation` based on your needs
