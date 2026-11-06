# {{PROJECT_NAME}}: project setup
#
# Project type: {{PROJECT_TYPE}}
#
# Framework sets up a project with new_project(). This script repeats the
# setup on another machine, such as after `git clone`. Run it from the
# project folder. Every step is safe to repeat.

# 1. Install Framework if it is missing
if (!requireNamespace("framework", quietly = TRUE)) {
  install.packages("framework")
}

# 2. Prepare the project: .env, folders, framework.db, packages, git hooks
framework::bootstrap()

# 3. Load the project: packages, functions, and settings
framework::scaffold()
