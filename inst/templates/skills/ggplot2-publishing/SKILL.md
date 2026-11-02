---
name: ggplot2-publishing
description: Use when making or polishing an R ggplot2 figure for an audience - a paper, report, poster, slides, or a figure the user calls final. Covers titles that state the finding, direct labels, color used to highlight, honest scales, a reusable theme, accessibility, and saving at the right size. For quick figures to understand data, use ggplot2-exploring.
metadata:
  title: Publication figures with ggplot2
  summary: Polished ggplot2 figures for papers, reports, and slides.
---

# Publication figures with ggplot2

A publication figure starts as an accurate exploratory figure and adds what a
reader needs to understand it without the analyst in the room. Change the
presentation, never the data or the comparison the figure makes.

## Start from the right chart

Keep the chart type that answered the question during exploration. If the
comparison that matters is not on a common scale, change the chart before
polishing it. See the ggplot2-exploring skill for choosing a chart.

## State the finding

- **Title:** write the result as a sentence, such as "Blood pressure rises
  with age in every group". A title that names the variables ("Systolic blood
  pressure by age") makes the reader find the point alone.
- **Subtitle:** say what is measured, for whom, and when.
- **Caption:** give the data source, the sample size, and any caveat a reader
  needs, such as how missing values were handled.
- **Axes:** use plain names with units, such as "Income per person (US
  dollars, log scale)".

Do not invent a finding. If the analysis has not established a result, use a
descriptive title and say so to the user.

## Label directly

- Put labels next to the lines or points they name, and remove the legend
  with `theme(legend.position = "none")`. Use `geom_text()` or `geom_label()`
  at the end of each line, or `ggrepel::geom_text_repel()` when labels would
  overlap.
- Label only the values that support the point. Labeling every point is
  clutter.
- Use `annotate()` for a short note at a specific place, and
  `geom_hline()` or `geom_vline()` for a reference value, such as a clinical
  threshold. Label the reference line.

## Use color to highlight

- Give color one job. Show most of the data in gray and the groups the finding
  is about in a strong color.
- For categories, use a palette that people with color vision deficiency can
  read, such as Okabe-Ito or `scale_color_viridis_d()`. For ordered values,
  use `scale_fill_viridis_c()` or a single-hue sequential scale.
- Never let color carry information alone. Pair it with labels, position,
  or shape.

## Keep the scales honest

- Bars start at zero.
- Use the same axis limits across panels that the reader will compare, which
  is the default in `facet_wrap()`. Use `scales = "free"` only when the panels
  are not meant to be compared, and say so in the caption.
- Format numbers with the scales package: `scales::label_percent()`,
  `scales::label_comma()`, or `scales::label_dollar()`.
- Order categories by value with `forcats::fct_reorder()` unless they have a
  natural order.

## Use one theme for the whole project

Define the project's look once as a function and use it in every figure. In a
Framework project, put it in `functions/` (for example `functions/theme_project.R`)
so `scaffold()` loads it. If the project already has a theme, use it.

```r
theme_project <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold"),
      plot.title.position = "plot",
      plot.caption = element_text(color = "gray40", hjust = 0),
      panel.grid.minor = element_blank()
    )
}
```

## Size it for where it goes

Set the size when saving, and check the saved file. Text that is readable on
screen can be unreadable at column width.

| Destination | Width × height (inches) | Format |
|---|---|---|
| Journal, one column | 3.5 × 3 | pdf or tiff at 300 dpi or more, as the journal requires |
| Journal, two columns | 7 × 4.5 | pdf or tiff |
| Report or web page | 8 × 5 | png at 300 dpi or svg |
| Slide | 10 × 5.6 | png or svg |

Increase `base_size` for slides and posters so text stays readable.

## Example

```r
highlight <- c("65 and older")

ggplot(bp_by_year, aes(x = year, y = mean_sbp, group = age_group)) +
  geom_line(color = "gray75") +
  geom_line(data = subset(bp_by_year, age_group %in% highlight), color = "#0072B2", linewidth = 1) +
  geom_text(
    data = subset(bp_by_year, year == max(year)),
    aes(label = age_group), hjust = 0, nudge_x = 0.3, size = 3.5
  ) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.15))) +
  labs(
    title = "Blood pressure rose fastest among adults 65 and older",
    subtitle = "Mean systolic blood pressure (mmHg) by age group, 2010-2020",
    caption = "Source: example health survey, n = 6,100 adults.",
    x = NULL, y = NULL
  ) +
  theme_project() +
  theme(legend.position = "none")
```

## Check before you finish

- **Point:** does the title or caption make the finding clear?
- **Data:** is the unit of observation clear?
- **Labels:** are all labels readable, with units?
- **Scale:** does each axis support the claim honestly?
- **Color:** does color have one job, and does the figure still work in grayscale?
- **Size:** is the text readable at the size the figure will be printed or shown?

## In a Framework project

Save figures with `save_figure(plot, "name", width = , height = )`, which
writes to the project's figures directory and records the file. Use
`format = "pdf"` for journals. Read data with `data_read()` and add packages
with `package_add()`. Compute the summaries a figure needs in memory. Do not
save a new dataset just to draw a figure.

Only a privacy-sensitive project (`project_type: project_sensitive` in
`settings.yml`) has private and public figure folders. There, figures are
private by default. Pass `public = TRUE` only when the user confirms the
figure contains no restricted data. Other projects have one figures folder,
so do not mention privacy.
