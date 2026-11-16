---
id: shiny-app
title: Shiny app
section: project_types
position: 15
description: 'Shiny web app blueprint with app.R, R/ helpers, and www/ assets'
---
## Blueprint overview

The Shiny app blueprint (`shiny`) scaffolds a runnable Shiny application. Because the blueprint is hosted on Framework Cloud, sign in with `cloud_login()` before creating one.

## Project creation

Create the project from R after signing in:

```r
framework::cloud_login()
framework::new_project("my-app", type = "shiny")
```

You can also open **Blueprints** on Framework Cloud, select **Shiny app**, and click **Create project**. When signed out, `type = "shiny"` emits a warning and builds a layout with only the core project files, without the blueprint's folders or starter files.

## Starter files

```text
my-app/
├── app.R          # UI and server definition
├── R/             # Helper functions loaded automatically by Shiny
├── www/           # Static assets (images, CSS, JavaScript)
├── tests/
├── data/
├── scripts/
├── README.md
└── settings.yml
```

Starter `app.R`:

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

## Default packages

The blueprint includes the `shiny-r` package set (`shiny`, `bslib`, `bsicons`, `DT`, and `plotly`). Add the same set to an existing project with:

```r
framework::package_set_add("shiny-r")
```

## Running the application

Start the app from the project root:

```r
shiny::runApp()
```

Keep domain functions in `R/` so unit tests in `tests/` can call them without launching a Shiny session.
