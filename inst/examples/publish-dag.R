# Publish a causal diagram to Framework Cloud.
#
# Run it from a Framework project linked to Framework Cloud, whose .env has
# FW_PROJECT_TOKEN and FW_CLOUD_URL. In R:
#
#   source(system.file("examples", "publish-dag.R", package = "framework"))
#
# Needs dagitty and ggdag. Publishes an unlisted DAG and prints its URL.

library(framework)
library(ggdag)

# The code that builds the graph. It runs below, and the DAG shows it.
# coords are written for ggdag, with y pointing up: age sits above smoking
# and cancer. With ggdag loaded, publish_dag() keeps that picture.
code <- '
dag <- dagify(
  cancer ~ smoking + age,
  smoking ~ age,
  exposure = "smoking",
  outcome = "cancer",
  labels = c(smoking = "Smoking", cancer = "Lung cancer", age = "Age"),
  coords = list(
    x = c(smoking = 0, age = 1, cancer = 2),
    y = c(smoking = 0, age = 1, cancer = 0)
  )
)'
eval(parse(text = code))

# dagitty's adjustment sets, which the DAG carries: { age }
print(dagitty::adjustmentSets(dag))

url <- publish_dag(
  dag,
  code = trimws(code),
  slug = "smoking-lung-cancer-dag",
  title = "Smoking and lung cancer",
  description = "Age confounds the effect of smoking on lung cancer.",
  visibility = "unlisted"
)
cat(url, "\n")
