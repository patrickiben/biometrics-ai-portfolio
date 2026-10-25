#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# Build the whole GitHub Pages site into one folder: the static pages, plus three R Shiny
# apps that run in the visitor's browser with Shinylive (webR). Used by
# .github/workflows/pages.yml, and locally to check the site before a merge.
#
#   Rscript .github/pages/build_site.R <outdir>     (from the repository root)
#
# Locally, <outdir> must be outside the checkout (for example ../portfolio-site), so the build is
# never committed and package_qc.py and the harness never scan it. Only the Pages workflow
# (GITHUB_ACTIONS=true) builds into _site/ inside its own checkout on the runner.
#
# 1. Copies every file git tracks (or would track), except .git*, the apps/ placeholders and
#    any earlier _site/ build, into <outdir>, so the site matches what the branch build serves today.
# 2. Exports each app with shinylive::export(app_dir, <outdir>, subdir = "apps/<name>"). All
#    three share one copy of the Shinylive and webR assets at <outdir>/shinylive/.
# 3. Gives each app's wrapper page a title and a data: URI favicon (no /favicon.ico 404).
# 4. Checks the result and stops on any problem.
#
# The build output is never committed. Synthetic data only.
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1]] else "_site"

SHINYLIVE <- "0.5.0"       # CRAN release of 2026-06-08; pinned in pages.yml as well
ASSETS    <- "0.10.12"     # the assets that shinylive 0.5.0 ships with (webR 0.6.0)
APPS <- data.frame(
  name  = c("trialmon", "uat_irt", "lifecycle_dashboard"),
  dir   = c("sasr_monitoring_wiki/trialmon_shiny", "uat_irt/shiny", "lifecycle_dashboard/shiny"),
  title = c("TRIALMON safety review console (synthetic data)",
            "IRT/RTSM UAT tracker (synthetic data)",
            "Study Lifecycle Monitor (synthetic data)"),
  stringsAsFactors = FALSE)
FAVICON <- '<link rel="icon" href="data:,">'

fail <- function(...) stop(paste0(...), call. = FALSE)
if (!file.exists(".github/pages/build_site.R")) fail("run this from the repository root")
if (as.character(utils::packageVersion("shinylive")) != SHINYLIVE)
  fail("shinylive ", SHINYLIVE, " is required; found ", as.character(utils::packageVersion("shinylive")))
if (file.exists(out)) fail(out, " already exists; remove it first so two builds never mix")
dir.create(out, recursive = TRUE)
root <- normalizePath(".")
if (startsWith(paste0(normalizePath(out), "/"), paste0(root, "/")) &&
    !identical(Sys.getenv("GITHUB_ACTIONS"), "true")) {
  unlink(out, recursive = TRUE)   # the empty folder made just above
  fail(out, " is inside the checkout; build outside it, for example ../portfolio-site")
}

# 1. static site ------------------------------------------------------------
files <- system2("git", c("-c", "core.quotepath=off", "ls-files", "--cached", "--others", "--exclude-standard"),
                 stdout = TRUE)
files <- files[!grepl("^(\\.git|apps/|_site/)", files) & file.exists(files) & !dir.exists(files)]
for (d in unique(dirname(files))) dir.create(file.path(out, d), recursive = TRUE, showWarnings = FALSE)
ok <- file.copy(files, file.path(out, files), copy.date = TRUE)
if (!all(ok)) fail("could not copy: ", paste(files[!ok], collapse = ", "))
cat(sprintf("Copied %d static files into %s\n", length(files), out))

# 2 and 3. the apps ---------------------------------------------------------
for (i in seq_len(nrow(APPS))) {
  t0 <- Sys.time()
  shinylive::export(APPS$dir[i], out, subdir = file.path("apps", APPS$name[i]), quiet = FALSE,
                    assets_version = ASSETS,
                    template_params = list(title = APPS$title[i], include_in_head = FAVICON))
  cat(sprintf("Exported %s from %s in %.0f s\n", APPS$name[i], APPS$dir[i],
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# 4. checks -----------------------------------------------------------------
problems <- character()
need <- function(cond, msg) if (!isTRUE(cond)) problems <<- c(problems, msg)
need(file.exists(file.path(out, "index.html")), "the home page is missing")
need(file.exists(file.path(out, "shinylive-sw.js")), "the Shinylive service worker is missing")
need(dir.exists(file.path(out, "shinylive", "webr")), "the shared webR assets are missing")
for (i in seq_len(nrow(APPS))) {
  a <- file.path(out, "apps", APPS$name[i])
  page <- if (file.exists(file.path(a, "index.html"))) readLines(file.path(a, "index.html"), warn = FALSE) else ""
  need(file.exists(file.path(a, "app.json")), paste0(APPS$name[i], ": app.json is missing"))
  need(any(grepl(FAVICON, page, fixed = TRUE)), paste0(APPS$name[i], ": the wrapper page has no favicon link"))
  need(any(grepl("../../shinylive/shinylive.js", page, fixed = TRUE)),
       paste0(APPS$name[i], ": the wrapper page does not load the shared assets"))
  need(!dir.exists(file.path(a, "shinylive")), paste0(APPS$name[i], ": has its own copy of the assets"))
}
if (length(problems)) fail("site build failed:\n- ", paste(problems, collapse = "\n- "))
mb <- sum(file.info(list.files(out, recursive = TRUE, full.names = TRUE, all.files = TRUE))$size) / 1e6
cat(sprintf("Site built in %s: %d apps, %.0f MB\n", out, nrow(APPS), mb))
