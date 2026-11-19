# Skill sync follow-ups

Problems found while reviewing `skills_copy()` that also exist on main, or
that the agreed behavior leaves open. Each line names where to start.

- R/skill_pull.R:296: with `overwrite = TRUE`, adding an assistant folder replaces an edited built-in and fills the new folder with the shipped copy. This is the agreed behavior; revisit the UX.
- R/skill_sync.R:583: a copy tracking another identity or variant is now always kept; there is no supported way to switch a copy to a new identity or variant on purpose.

Fixed in R 2.0.19; framework-py and fw still need the same fixes: inline setup text no longer replaces a built-in tracked on Cloud, an offline pull reports every Cloud-tracked skill as unavailable, and `upgrade()` leaves a skill alone when its copies differ.
