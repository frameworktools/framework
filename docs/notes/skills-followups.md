# Skill sync follow-ups

Problems found while reviewing `skills_copy()` that also exist on main, or
that the agreed behavior leaves open. Each line names where to start.

- R/skill_pull.R:296: with `overwrite = TRUE`, adding an assistant folder replaces an edited built-in and fills the new folder with the shipped copy. This is the agreed behavior; revisit the UX.
- R/skill_sync.R:583: a copy tracking another identity or variant is now always kept; there is no supported way to switch a copy to a new identity or variant on purpose.
- R/skill_pull.R:136: inline setup content can replace a built-in tracked on Cloud (a `framework:` ID), because only personal IDs are protected here.
- R/skill_pull.R:547: an offline pull uses the package skills only, so custom Cloud skills in the setup are left out of the report.
- R/upgrade.R:1031: `upgrade()` judges each skill folder alone and can write into a skill whose copies have diverged.
