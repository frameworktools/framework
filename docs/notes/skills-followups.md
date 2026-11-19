# Skill sync follow-ups

Open items after skills lock v2 (`docs/architecture/skills-lock-v2.md`).
Each line names where to start.

- R/skill_plan.R (`.skill_plan_entry()`, the overwrite branch): with `overwrite = TRUE`, adding an assistant folder replaces an edited copy and fills the new folder with the source's version. This is the agreed behavior (spec open question 2); revisit the UX once per-copy rows show the effect in dry runs.

Fixed in R 2.0.19; framework-py and fw still need the same fixes: inline setup text no longer replaces a built-in tracked on Cloud, an offline pull reports every Cloud-tracked skill as unavailable, and `upgrade()` leaves a skill alone when its copies differ.
