---
id: shiny-app
title: Shiny app
section: project_types
position: 15
description: 'A Shiny app with app.R, functions in R/, and static files in www/'
---
## Overview

The Shiny app type (`shiny`) starts a Shiny app that runs as created. It
comes from Framework Cloud, so you need to be signed in to create one.

## Creating the project

Sign in once, then create the project from R:

```r
framework::cloud_login()
framework::new_project("my-app", type = "shiny")
```

You can also open **Blueprints** on Framework Cloud, choose **Shiny app**, and
select **New project**. Signed out, `type = "shiny"` builds Framework's default
layout with a warning.

## Starter files

```text
my-app/
├── app.R          # the interface and the server
├── R/             # functions; Shiny loads them on its own
├── www/           # images, CSS, and other static files
├── tests/
├── data/
├── scripts/
├── README.md
└── settings.yml
```

`app.R` is a `bslib` page with a sidebar slider and a histogram:

```r
library(shiny)
library(bslib)

ui <- page_sidebar(
  title = "my-app",
  sidebar = sidebar(
    sliderInput("n", "Points", min = 10, max = 500, value = 100)
  ),
  card(
    card_header("A random sample"),
    plotOutput("plot")
  )
)

server <- function(input, output, session) {
  output$plot <- renderPlot({
    hist(rnorm(input$n), main = NULL, xlab = "Value")
  })
}

shinyApp(ui, server)
```

## Packages

The project starts with the **Shiny app in R** package set: shiny, bslib,
bsicons, DT, and plotly. To add the same set to an existing project:

```r
framework::package_set_add("shiny-r")
```

## Running the app

From the project folder:

```r
shiny::runApp()
```

Put shared logic in `R/`, so tests can call it without starting the app.
