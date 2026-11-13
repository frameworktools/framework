---
name: ggplot2-figures
description: Use when making a ggplot2 figure in R, from a quick look at the data to a figure for a paper, report, poster, or slides. Covers choosing the chart, accurate defaults, titles and labels, accessible color, honest scales, themes, and saving.
metadata:
  title: Figures with ggplot2
  summary: Accurate ggplot2 figures, from exploring data to publication.
---

# Figures with ggplot2

## Chart choice

Values on a shared axis are the easiest to compare.

| Question | Chart | ggplot2 |
|---|---|---|
| Distribution of one numeric variable | Histogram | `geom_histogram()` |
| A numeric variable across groups | Box plot, or violin plot with the points | `geom_boxplot()`, `geom_violin()`, `geom_jitter()` |
| Counts by category | Bar chart, sorted | `geom_col()` or `geom_bar()` |
| Two numeric variables | Scatterplot | `geom_point()`, optionally `geom_smooth()` |
| Change over time or another ordered variable | Line chart | `geom_line()` with `geom_point()` |
| Two estimates across many groups | Dot plot | `geom_point()` with `geom_segment()` |
| A pattern across subgroups | Small multiples | `facet_wrap()` or `facet_grid()` |

Avoid dual y axes and 3-D effects. In a stacked bar, only the bottom segment
sits on a shared baseline.

## Accuracy

- **Histograms:** try more than one bin width. The default of 30 bins can
  hide or invent features. Set `binwidth` in the units of the variable.
- **Group summaries:** a box plot hides group size and multiple peaks. With a
  few hundred points or fewer, add them with
  `geom_jitter(width = 0.2, alpha = 0.3)`.
- **Overplotting:** lower `alpha`, use smaller points, or use `geom_bin2d()`
  or `geom_hex()`.
- **Skewed variables:** use `scale_x_log10()` or `scale_y_log10()` for
  strongly right-skewed values. Say so in the axis label.
- **Bars:** a bar's length encodes its value, so the axis starts at zero. Use
  points when zero is not meaningful.
- **Order:** sort categories by value with `forcats::fct_reorder()` unless
  they have a natural order.
- **Missing-value codes:** check the codebook for codes such as -99 before
  plotting, and recode them to missing.
- **Missing values:** ggplot2 drops rows with missing values and warns. Count
  what was dropped before you trust the figure.
- **Panels:** panels that readers compare share axis limits, the
  `facet_wrap()` default. Use `scales = "free"` only for panels not meant to
  be compared, and say so in the caption.

## Titles and labels

- **Axes:** use plain names with units, such as "Income per person (US
  dollars, log scale)". Replace column names such as `sbp_mean`.
- **Title:** a title that states the finding, such as "Blood pressure rises
  with age in every group", can help a figure communicate its result. Make
  sure it suits the venue. Some journals and readers prefer a matter-of-fact
  title that names the variables, such as "Systolic blood pressure by age".
  Follow the venue's style, and ask the user when it is unclear. Do not
  invent a finding.
- **Subtitle and caption:** say what is measured, for whom, and when. Give
  the data source, the sample size, and caveats such as the handling of
  missing values.
- **Direct labels:** with a few series, label lines or points directly with
  `geom_text()` or `geom_label()` and remove the legend. Use
  `ggrepel::geom_text_repel()` when labels overlap.
- **Reference values:** draw them with `geom_hline()` or `geom_vline()`, and
  label the line.
- **Uncertainty:** show it with the same method and interval level as the
  analysis. Label a confidence interval as uncertainty in the estimate.

## Color

- For categories, use a palette readable with color vision deficiency, such
  as Okabe-Ito or `scale_color_viridis_d()`. For ordered values, use
  `scale_fill_viridis_c()` or a single-hue sequential scale.
- Pair color with labels, position, or shape, so the figure still works in
  grayscale.

## Themes

A shared theme is a good tactic when a project makes many figures. It keeps
them consistent and saves repeating the same settings. Define the look once as
a function and apply it to each figure. If the project already has a theme,
use it. A one-off figure can set its theme directly.

## Saving

Set the width and height when saving, and check the saved file. Text that
reads well on screen can be too small at column width. In a Framework project,
save figures with `save_figure(plot, "name", width = , height = )`.
