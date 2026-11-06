# Package-internal environment for runtime state
# This avoids writing to .GlobalEnv which CRAN discourages
.framework_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname)
 {
  # Initialize internal state storage
  .framework_env$pools <- new.env(parent = emptyenv())
  .framework_env$initialized <- TRUE
  .fw_install_plot_hooks()
}

# Remember which graphics system drew the last new page. save_figure() uses
# this when the device keeps no display list (for example Rscript's
# Rplots.pdf), so it never saves an older ggplot in place of a base plot.
.fw_install_plot_hooks <- function() {
  for (hook in c("plot.new", "persp", "grid.newpage")) {
    current <- getHook(hook)
    if (is.function(current)) current <- list(current)
    kept <- Filter(function(f) !isTRUE(attr(f, "framework_plot_hook")), current)
    system <- if (hook == "grid.newpage") "grid" else "base"
    marker <- local({
      drawn_by <- system
      function(...) .framework_env$last_plot_system <- drawn_by
    })
    attr(marker, "framework_plot_hook") <- TRUE
    setHook(hook, NULL, "replace")
    for (f in c(kept, list(marker))) setHook(hook, f)
  }
  invisible(TRUE)
}

.onAttach <- function(libname, pkgname) {
  # Silent load - framework is ready to use
  invisible()
}
