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
code <- '
dag <- dagify(
  cancer ~ tar + age + asbestos + income,
  tar ~ smoking,
  smoking ~ age + ses,
  income ~ ses,
  exposure = "smoking",
  outcome = "cancer",
  latent = "ses",
  labels = c(
    smoking = "Smoking",
    cancer = "Lung cancer",
    tar = "Tar in lungs",
    age = "Age",
    asbestos = "Asbestos exposure",
    income = "Household income",
    ses = "Socioeconomic status"
  )
)'
eval(parse(text = code))

# dagitty's adjustment sets, which the DAG carries: {age, income}
print(dagitty::adjustmentSets(dag))

url <- publish_dag(
  dag,
  code = trimws(code),
  slug = "smoking-lung-cancer-dag",
  title = "Smoking and lung cancer",
  description = "Smoking acts on lung cancer through tar. Socioeconomic status is unmeasured.",
  visibility = "unlisted"
)
cat(url, "\n")
