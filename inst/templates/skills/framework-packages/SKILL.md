---
name: framework-packages
description: Use when adding, installing, or managing R packages in a project that uses the Framework package. Covers package_add(), the project's package list, auto-attached packages, and renv.
metadata:
  title: "Framework: package management"
  summary: Add packages through Framework so the project records them.
---

# Framework: package management

The project's packages are listed in the settings. `scaffold()` installs them
and attaches the ones marked `auto_attach: true`. A package installed with
`install.packages()` is not recorded, so the next machine will not have it.

## Adding packages

Prefer `package_add()`.

```r
package_add("janitor")                      # record and install
package_add("forcats", auto_attach = TRUE)  # also attach in scaffold()
package_add("tidyverse/dplyr@main")         # from GitHub
package_add("dplyr@1.1.0")                  # a pinned version
package_add("arrow", install = FALSE)       # record only
```

`packages_list()` shows the project's packages. `packages_install()` installs
any that are missing, for example after cloning.

Packages without `auto_attach` are installed but not loaded. Load them with
`library()` where they are used.

## renv

When the project uses renv, Framework installs through it.
`packages_snapshot()` records versions, `packages_restore()` restores them,
and `packages_status()` reports drift.
