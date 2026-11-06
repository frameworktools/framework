---
id: installation
title: Installation
section: getting_started
position: 1
description: 'Requirements, installation, and updates'
---
> [!NOTE]
> Framework 2.0 will be on CRAN soon. Until then, install it from GitHub:
> `remotes::install_github("frameworktools/framework")`. The CRAN version is 1.x, which these docs don't cover.

## Requirements

- **R** version 4.1 or higher.
- Any editor, including the console.

Framework works with [Positron](https://positron.posit.co/), [VS Code](https://code.visualstudio.com/), and [RStudio](https://posit.co/products/open-source/rstudio/).

## GitHub installation

Install Framework 2.0 from GitHub with the `remotes` package:

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

Development builds of 2.0 report a version such as `1.9.0.9003`.

## Updates

Reinstall from GitHub to update:

```r
remotes::install_github("frameworktools/framework")
```

---

<div style="display: flex; justify-content: flex-end">

[Setup →](guide:setup)

</div>
