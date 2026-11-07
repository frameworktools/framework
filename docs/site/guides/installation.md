---
id: installation
title: Installation
section: getting_started
position: 1
description: 'Requirements, installation, and updates'
---
## Requirements

- **R** version 4.1 or higher.
- Any editor, including the console.

Framework works with [Positron](https://positron.posit.co/), [VS Code](https://code.visualstudio.com/), and [RStudio](https://posit.co/products/open-source/rstudio/).

## Installation

Install Framework from CRAN:

```r
install.packages("framework")
```

## Development version

The development version on GitHub has fixes and features not yet on CRAN. Install it with the `remotes` package:

```r
install.packages("remotes")
remotes::install_github("frameworktools/framework")
```

## Optional packages

- **httr2**: required for Framework Cloud features, such as `cloud_login()`, `setup("fw_...")`, and publishing to Framework Cloud.
- **keyring**: stores the Framework Cloud login in Windows Credential Manager or the Linux Secret Service. Without it, the login is kept in a permission-restricted file. macOS uses the Keychain directly.

```r
install.packages(c("httr2", "keyring"))
```

## Installation check

After installation, verify Framework is working:

```r
library(framework)
packageVersion("framework")
```

Framework 2.0 reports version 2.0.0 or later.

## Updates

Update from CRAN with your other packages:

```r
update.packages()
```

For the development version, install from GitHub again:

```r
remotes::install_github("frameworktools/framework")
```

---

<div style="display: flex; justify-content: flex-end">

[Setup →](guide:setup)

</div>
