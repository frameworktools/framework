---
name: framework-publishing
description: Use when publishing saved files or rendered notebooks in a project that uses the Framework package. Covers publish(), publish_notebook(), destinations, and private-file checks.
metadata:
  title: "Framework: publishing artifacts"
  summary: Publish saved artifacts and notebooks through Framework.
---

# Framework: publishing artifacts

`publish()` and `publish_notebook()` upload to the project's storage bucket
when one is configured, or to Framework Cloud when the project was set up
from it.

```r
publish("outputs/report.html")                       # upload a file
publish_notebook("notebooks/analysis.qmd")           # render and upload
publish("outputs/charts/", dest = "reports/charts/") # upload a folder
publish("outputs/report.html", to = "github")        # GitHub Pages
```

`to = "github"` commits the file to `published/` and pushes. It makes a public
website, even from a private repository. Publish there only when the user asks.

The publish functions warn about any source in a private folder and ask the
user to confirm. In a script they stop. Leave `include_private` off, and let
the user answer the prompt.
