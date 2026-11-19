# ggplot plot descriptions

Publishing a ggplot writes `figure.phiz.json` beside `figure.svg` (or
`figure.png`). The file is a phiz plot description, format 1, defined by
phiz's `schema/plot-description.schema.json` and `docs/descriptions.qmd`.
Framework Cloud compiles it with phiz into a live Vega-Lite chart. The image
stays as the static fallback.

The translator is `R/artifact_phiz.R`. Tests are in
`tests/testthat/test-artifact-phiz.R` and validate every written description
against a copy of the schema in `tests/testthat/fixtures/`. Set
`FW_PHIZ_PATH` to a phiz checkout with `vendor/` installed, and the tests also
compile the descriptions with phiz.

## Transport

- `publish()` to Framework Cloud sends the file as the multipart field
  `plot_description` (`application/json`) beside `file`.
- Named destinations (`.fw_bundle_build()`) include it as a bundle file.

## Translation rules

- The plot is built with `ggplot2::ggplot_build()`. Each layer's built data
  becomes an identity layer with its own `data`. Smooths become a `line` and
  a `ribbon`. Histograms become binned `col` layers from R's bins.
- The plot is built a second time with every non-position scale passing its
  values through unmapped. That build gives each row's level (or number) for
  colour, fill, shape, and linetype, so legends show the variable's values.
  The two builds must agree row for row.
- Positions return to the data scale: discrete levels, inverse-transformed
  numbers (log10, sqrt, reverse), and ISO strings for dates and date-times.
  Dates are written as local times (`2024-01-01T00:00:00`) so browsers west of
  UTC do not show the previous day.
- Theme chrome is dropped. The legend position, legend direction, a hidden
  legend title, axis label angles, and hidden axis titles carry over.
- ggplot2's default hue palette and default continuous gradient become no
  palette. Other discrete palettes are written as `values` (level to hex).
  Viridis keeps its scheme name. Two- and three-color gradients keep their
  colors with Lab interpolation.
- Author constants carry over: colour, fill, alpha, size, linewidth,
  linetype, and shape. Sizes use the SVG's units, where a point is a pixel.

## Refusals

Any of these writes no description:

- geoms other than those listed in `.fw_phiz_geoms`, extension geoms and stats
  (ggrepel and others), and patchwork
- `geom_abline()` (phiz's abline needs plot-level data)
- coordinate systems other than Cartesian, flip, and fixed
- mapped size, alpha, or other aesthetics beyond position, colour, fill,
  shape, linetype, label, and group
- missing values in a legend aesthetic, and gaps inside a line
- jitter without a seed, since the SVG and the description would differ
- custom guides, secondary axes, plot tags, plotmath, legends inside the
  panel, and hidden axis or facet labels
- facet panels not in sorted order, facet labellers other than
  `label_value` and `label_both`, and grids with several variables on a side
- shape or linetype palettes other than ggplot2's defaults, and continuous
  color palettes other than the default, viridis, and two- or three-color
  gradients
