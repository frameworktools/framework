---
id: installation
title: Installation
section: getting_started
position: 1
description: 'Requirements, GitHub and CRAN installation, and package updates'
---
## Requirements

- **R** version 4.1 or later.
- Any R environment, including [Positron](https://positron.posit.co/), [VS Code](https://code.visualstudio.com/), [RStudio](https://posit.co/products/open-source/rstudio/), or a terminal console.

## Latest version

Install the newest version from GitHub with `remotes`. This is the recommended installation:

```r
install.packages("remotes")
remotes::install_github("frameworktools/framework")
```

## CRAN version

CRAN releases lag behind GitHub. Install the CRAN version with:

```r
install.packages("framework")
```

## Optional packages

- **httr2**: required for Framework Cloud operations, including `cloud_login()`, `setup("fw_...")`, and Cloud publishing.
- **keyring**: stores Framework Cloud credentials in Windows Credential Manager or the Linux Secret Service. Without `keyring`, Framework stores credentials in a permission-restricted file inside the configuration directory. macOS uses the system Keychain directly.

```r
install.packages(c("httr2", "keyring"))
```

## Verification

Load the package and check the installed version:

```r
library(framework)
packageVersion("framework")
```

Framework 2.0 reports version `2.0.0` or later.

## Package updates

Re-run `remotes::install_github("frameworktools/framework")` to update a GitHub installation.

Update a CRAN installation with `update.packages()`:

```r
update.packages()
```
