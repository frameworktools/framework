# show_table(): the same Markdown as framework-py's show_table() (parity D12).
# The vectors come from framework-py's tests/test_display.py.

test_that("show_table is a pipe table", {
  skip_if_not_installed("knitr")
  frame <- data.frame(
    arm = c("a", "b|c", NA),
    n = c(1234567L, 12L, -4500L),
    rate = c(0.5, NaN, Inf),
    flag = c(TRUE, FALSE, TRUE)
  )
  shown <- show_table(frame, caption = "Counts  by arm", digits = 2, big_mark = ",", na = "NA")
  expect_s3_class(shown, "knit_asis")
  expect_identical(as.character(unclass(shown)), paste0(
    "| arm | n | rate | flag |\n",
    "|:---|---:|---:|:---|\n",
    "| a | 1,234,567 | 0.50 | TRUE |\n",
    "| b\\|c | 12 | NA | FALSE |\n",
    "| NA | -4,500 | Inf | TRUE |\n",
    "\n",
    ": Counts by arm\n"
  ))
  expect_output(print(shown), "| a | 1,234,567 | 0.50 | TRUE |", fixed = TRUE)
})

test_that("show_table defaults and other inputs", {
  skip_if_not_installed("knitr")
  md <- function(x) as.character(unclass(x))
  frame <- data.frame(x = c(1, 2.5, 1e-7), row.names = c("p", "q", "r"))
  # Row names aren't shown: R has no index
  expect_identical(md(show_table(frame)), "| x |\n|---:|\n| 1 |\n| 2.5 |\n| 1e-07 |\n")
  expect_identical(md(show_table(data.frame(n = 1:2))), "| n |\n|---:|\n| 1 |\n| 2 |\n")
  expect_identical(sum(gregexpr("---:", md(show_table(matrix(1:2, nrow = 1))), fixed = TRUE)[[1]] > 0), 2L)
  expect_identical(
    md(show_table(data.frame(big = c(1234567.25, -1e20, -1500), when = as.Date("2026-11-07") + 0:2,
                             note = c("two\n lines", " x ", NA), stringsAsFactors = FALSE),
                  big_mark = ",")),
    paste0("| big | when | note |\n|---:|:---|:---|\n",
           "| 1,234,567.25 | 2026-11-07 | two lines |\n",
           "| -100,000,000,000,000,000,000 | 2026-11-08 | x |\n",
           "| -1,500 | 2026-11-09 |  |\n")
  )
  expect_identical(md(show_table(data.frame(f = factor(c("lo", "hi")), z = c(0, 1)), digits = 0)),
                   "| f | z |\n|:---|---:|\n| lo | 0 |\n| hi | 1 |\n")
  expect_error(show_table(list(x = 1)), "data frame")
  expect_error(show_table(frame, digits = -1), "digits")
  expect_error(show_table(frame, digits = 1.5), "digits")
})

test_that("Jupyter shows show_table as Markdown", {
  skip_if_not_installed("knitr")
  skip_if_not_installed("repr")
  shown <- show_table(data.frame(n = 1L))
  expect_identical(repr::repr_markdown(shown), "| n |\n|---:|\n| 1 |\n")
})
