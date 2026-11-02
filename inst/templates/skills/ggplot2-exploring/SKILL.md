---
name: ggplot2-exploring
description: Use when plotting data in R to understand it - checking distributions, comparing groups, looking for relationships, trends, or problems in a dataset. Covers choosing the chart that answers the question and quick, accurate ggplot2 figures. For figures meant for a paper, report, or slides, use ggplot2-publishing instead.
metadata:
  title: Exploring data with ggplot2
  summary: Quick, accurate ggplot2 figures for understanding data.
---

# Exploring data with ggplot2

Exploratory figures are for the analyst and the team. Their job is to show the
data accurately so you can understand it. Make them quickly, make many, and do
not polish them.

## Rules

- Set the theme once, right after the setup code (after `scaffold()` in a
  Framework project), with `theme_set(theme_minimal())`. If the project defines
  its own theme, such as a `theme_*()` function in `functions/`, set that
  instead. Never leave ggplot2's default gray background.
- Compute the counts and summaries a figure needs in memory. Do not write a new
  dataset to `inputs/` or anywhere else just to draw figures.

## Choose the chart from the question

Decide what question the figure answers, then use the chart that answers it.
Position on a common scale is the most accurate way to compare values, so
prefer charts that put the values being compared on one shared axis.

| Question | Chart | ggplot2 |
|---|---|---|
| How is one numeric variable distributed? | Histogram | `geom_histogram()` |
| How does a numeric variable differ across groups? | Box plot, or violin plot with the points | `geom_boxplot()`, `geom_violin()`, `geom_jitter()` |
| How many are in each category? | Bar chart, sorted | `geom_col()` or `geom_bar()` |
| How do two numeric variables relate? | Scatterplot | `geom_point()`, optionally `geom_smooth()` |
| How does something change over time or another ordered variable? | Line chart | `geom_line()` with `geom_point()` |
| How do two estimates compare across many groups? | Dot plot | `geom_point()` with `geom_segment()` |
| Does a pattern differ across subgroups? | Small multiples | `facet_wrap()` or `facet_grid()` |

Avoid pie charts, stacked bars for comparing anything but the bottom segment,
dual y axes, and 3-D effects. They make comparisons harder to read.

## Make it accurate

- **Histograms:** try more than one bin width. The default of 30 bins can hide
  or invent features. Set `binwidth` in the units of the variable.
- **Group summaries:** a box plot hides how many observations each group has
  and whether the distribution has more than one peak. With a few hundred
  points or fewer, add the data with `geom_jitter(width = 0.2, alpha = 0.3)`.
- **Overplotting:** with many points, lower `alpha`, use smaller points, or use
  `geom_bin2d()` or `geom_hex()`.
- **Skewed variables:** use `scale_x_log10()` or `scale_y_log10()` for strongly
  right-skewed values such as income or counts. Say so in the axis label.
- **Bar charts:** a bar's length encodes its value, so the axis must start at
  zero. Use points instead of bars when zero is not meaningful.
- **Order:** sort categories by their value with `forcats::fct_reorder()`
  unless the categories have a natural order, such as age groups.
- **Missing values:** ggplot2 drops rows with missing values and warns.
  Read the warning and count what was dropped before you trust the figure.

## Keep it plain

- Label axes with readable names and units, using `labs()`. Variable names
  such as `sbp_mean` are not labels.
- Do not add titles, annotations, or custom colors to an exploratory figure.
  That is publication work.
- Do not save every exploratory figure. Show it in the notebook. Save a figure
  only when someone needs the file.

## Example

```r
theme_set(theme_minimal())

ggplot(survey, aes(x = systolic_bp)) +
  geom_histogram(binwidth = 5) +
  labs(x = "Systolic blood pressure (mmHg)", y = "People")

ggplot(survey, aes(x = age_group, y = systolic_bp)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.2, alpha = 0.2) +
  labs(x = "Age group", y = "Systolic blood pressure (mmHg)")
```

## In a Framework project

Projects with a `settings.yml` use the framework R package. Read data with
`data_read()`, not `read.csv()` or `readr`. If ggplot2 is not installed or
listed in the project's packages, add it with `package_add("ggplot2")` instead
of `install.packages()`. When a figure must be kept, save it with
`save_figure(plot, "name")`.
