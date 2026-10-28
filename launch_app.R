#!/usr/bin/env Rscript
# Open the toolkit's synthetic Shiny examples from any working directory.
# MIT license: see LICENSE. Package installation is explicit and user-local.

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  source_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(source_arg) != 1L) stop("Run this launcher with Rscript launch_app.R.", call. = FALSE)
  script <- normalizePath(sub("^--file=", "", source_arg), winslash = "/", mustWork = TRUE)
  root <- dirname(script)
  apps <- list(
    trialmon = list(path = "sasr_monitoring_wiki/trialmon_shiny", title = "Synthetic safety review", packages = c("shiny", "bslib", "DT", "htmltools")),
    lifecycle = list(path = "lifecycle_dashboard/shiny", title = "Study lifecycle monitor", packages = c("shiny", "bslib", "ggplot2", "htmltools")),
    uat = list(path = "uat_irt/shiny", title = "IRT / RTSM UAT tracker", packages = c("shiny", "bslib", "DT", "ggplot2", "htmltools")),
    risk = list(path = "risk_monitor/shiny", title = "Operational risk signals", packages = c("shiny", "bslib", "DT", "htmltools")),
    hours = list(path = "budget_reconciliation/shiny", title = "Hours reconciliation", packages = c("shiny", "bslib", "DT", "ggplot2", "htmltools"))
  )
  help <- function() {
    cat("Trial biostatistics toolkit: local evaluation apps\n\n",
        "  Rscript launch_app.R --list\n",
        "  Rscript launch_app.R --check [app-id]\n",
        "  Rscript launch_app.R <app-id> [--install] [--no-browser] [--port NUMBER]\n\n",
        "--install downloads missing/incompatible packages from CRAN into a user library.\n",
        "It never installs into the system library. Without --install no downloads occur.\n",
        "Set BIOMETRICS_R_LIB to choose that user library. --check never launches an app.\n",
        "Apps bind only to 127.0.0.1. Stop with Ctrl+C. R >= 4.1 is required.\n",
        "Use an absolute path to launch_app.R when running outside the repository.\n", sep = "")
  }
  if (!length(args) || any(args %in% c("--help", "-h"))) {
    help()
    return(0L)
  }
  install <- check <- listing <- no_browser <- FALSE
  selected <- NULL
  port <- NULL
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg == "--install") install <- TRUE
    else if (arg == "--check") check <- TRUE
    else if (arg == "--list") listing <- TRUE
    else if (arg == "--no-browser") no_browser <- TRUE
    else if (arg == "--port") {
      if (i == length(args) || !grepl("^[0-9]{1,5}$", args[[i + 1L]])) stop("--port requires an integer from 1 to 65535.", call. = FALSE)
      i <- i + 1L
      port <- as.integer(args[[i]])
      if (port < 1L || port > 65535L) stop("--port requires an integer from 1 to 65535.", call. = FALSE)
    } else if (startsWith(arg, "-")) stop(paste("Unknown option:", arg, "(use --help)."), call. = FALSE)
    else if (!is.null(selected)) stop("Choose only one app ID, or use --check to inspect all apps.", call. = FALSE)
    else selected <- arg
    i <- i + 1L
  }
  if (listing) {
    if (check || install || !is.null(selected) || !is.null(port) || no_browser) stop("Use --list by itself.", call. = FALSE)
    for (id in names(apps)) cat(sprintf("%-10s %-30s %s\n", id, apps[[id]]$title, apps[[id]]$path))
    return(0L)
  }
  if (!is.null(selected) && !selected %in% names(apps)) stop(paste0("Unknown app ID: ", selected, ". Use --list."), call. = FALSE)
  if (is.null(selected) && !check) stop("Choose an app ID, or use --check to inspect all apps.", call. = FALSE)
  if (getRversion() < "4.1.0") stop("These apps require R 4.1 or later (they use the native R pipe).", call. = FALSE)
  ids <- if (is.null(selected)) names(apps) else selected
  for (id in ids) if (!file.exists(file.path(root, apps[[id]]$path, "app.R"))) stop(paste("App source is missing:", apps[[id]]$path, "Keep the complete repository checkout."), call. = FALSE)
  if (!file.exists(file.path(root, "apps/_shared/portfolio_app.R"))) stop("Shared app helpers are missing. Keep the complete repository checkout.", call. = FALSE)

  user_library <- Sys.getenv("BIOMETRICS_R_LIB", unset = "")
  if (!nzchar(user_library)) user_library <- file.path(tools::R_user_dir("biometrics-toolkit", "cache"), "library", paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][1L], sep = "."))
  user_library <- path.expand(user_library)
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", user_library)) user_library <- file.path(getwd(), user_library)
  user_library <- normalizePath(user_library, winslash = "/", mustWork = FALSE)
  if (dir.exists(user_library)) .libPaths(c(user_library, .libPaths()))
  # Check actual exported APIs as well as package presence, so an older installed
  # Shiny/bslib does not appear ready and then fail with an undefined function.
  apis <- list(shiny = c("runApp", "shinyApp"), bslib = c("page_sidebar", "sidebar", "layout_columns", "value_box", "card", "card_header", "bs_theme"), DT = c("datatable", "renderDT", "DTOutput"), ggplot2 = c("ggplot", "theme_minimal"), htmltools = c("tagList", "HTML"))
  if (any(ids %in% c("trialmon", "lifecycle", "uat"))) apis$shiny <- c(apis$shiny, "useBusyIndicators")
  if ("trialmon" %in% ids) apis$bslib <- c(apis$bslib, "navset_card_tab", "nav_panel")
  packages <- unique(unlist(lapply(apps[ids], function(app) app$packages), use.names = FALSE))
  missing <- character()
  cat("Repository: ", root, "\nR: ", as.character(getRversion()), "\nUser package library: ", user_library, "\n", sep = "")
  for (package in packages) {
    available <- requireNamespace(package, quietly = TRUE)
    absent_apis <- if (available) setdiff(apis[[package]], getNamespaceExports(package)) else character()
    if (!available || length(absent_apis)) {
      missing <- c(missing, package)
      cat(package, if (!available) "MISSING or cannot load" else paste("INCOMPATIBLE: missing", paste(absent_apis, collapse = ", ")), "\n")
    } else cat(package, as.character(utils::packageVersion(package)), "at", find.package(package), "\n")
  }
  if (length(missing) && install) {
    # Never silently target an administrator's or system package library.
    protected <- normalizePath(c(.Library, .Library.site), winslash = "/", mustWork = FALSE)
    if (any(vapply(protected, function(path) identical(user_library, path) || startsWith(user_library, paste0(path, "/")), logical(1)))) stop("BIOMETRICS_R_LIB must be a separate user library, not a system/site library.", call. = FALSE)
    if (!dir.exists(user_library) && !dir.create(user_library, recursive = TRUE, showWarnings = FALSE)) stop("Cannot create the user package library. Set BIOMETRICS_R_LIB to a writable location.", call. = FALSE)
    if (file.access(user_library, 2L) != 0L) stop("User package library is not writable. Set BIOMETRICS_R_LIB to a writable location.", call. = FALSE)
    cat("Installing into the user library: ", paste(missing, collapse = ", "), "\n", sep = "")
    # On Linux, fs >= 2.1 otherwise requires a separately installed libuv SDK.
    # Its bundled build avoids needing administrator access; honor an explicit choice.
    if (identical(Sys.info()[["sysname"]], "Linux") && !nzchar(Sys.getenv("USE_BUNDLED_LIBUV")))
      Sys.setenv(USE_BUNDLED_LIBUV = "1")
    utils::install.packages(missing, lib = user_library, repos = "https://cloud.r-project.org", dependencies = NA)
    # Restart after installing: old loaded namespaces/DLLs must not shadow a
    # newly installed version, especially on Windows.
    Sys.setenv(BIOMETRICS_R_LIB = user_library)
    status <- system2(file.path(R.home("bin"), "Rscript"), args = shQuote(c(script, args[args != "--install"])))
    return(as.integer(status))
  }
  if (length(missing)) stop(paste0("Missing or incompatible dependencies: ", paste(missing, collapse = ", "), ". Re-run this command with --install, or have your approved R environment supply them."), call. = FALSE)
  cat("Evaluation environment: package versions are reported above, not locked for a study.\n")
  for (id in ids) cat("Ready: ", id, " -> ", file.path(root, apps[[id]]$path), "\n", sep = "")
  if (check) return(0L)
  cat("Opening synthetic example on 127.0.0.1. Stop with Ctrl+C.\n")
  shiny::runApp(appDir = file.path(root, apps[[selected]]$path), host = "127.0.0.1", port = port, launch.browser = !no_browser)
  0L
}

status <- tryCatch(main(), error = function(error) {
  cat("Toolkit launcher: ", conditionMessage(error), "\n", sep = "", file = stderr())
  1L
}, interrupt = function(interrupt) 0L)
quit(save = "no", status = status)
