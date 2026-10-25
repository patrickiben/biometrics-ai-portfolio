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
# 1. Copies every file git tracks (or would track), except .git*, apps/ and any earlier _site/
#    build, into <outdir>, so the site matches what the branch build serves today. From apps/
#    it publishes only the launch page's shared style and script (apps/_shared/launch.css, .js).
# 2. For each app listed by an apps/<name>/launch.json, stages a copy of its source folder with
#    the shared R helper (apps/_shared/portfolio_app.R) next to app.R, and exports it with
#    shinylive::export(stage, <outdir>, subdir = "apps/<name>"). All apps share one copy of the
#    Shinylive and webR assets at <outdir>/shinylive/.
# 3. The export's page is the launch page (apps/_shared/launch_template/index.html) filled from
#    launch.json: title, what the app shows, what to try, an optional screenshot, the synthetic
#    data note, the expected first-load size and time, and the live app area with its status line.
# 4. Checks the result and stops on any problem. The workflow then runs the browser smoke test
#    (.github/pages/smoke/smoke.mjs) on the output before anything is deployed.
#
# The build output is never committed. Synthetic data only.
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1]] else "_site"

SHINYLIVE <- "0.5.0"       # CRAN release of 2026-06-08; pinned in pages.yml as well
ASSETS    <- "0.10.12"     # the assets that shinylive 0.5.0 ships with (webR 0.6.0)
SHARED    <- "apps/_shared"
HELPER    <- file.path(SHARED, "portfolio_app.R")
TEMPLATE  <- file.path(SHARED, "launch_template")
PUBLISHED_SHARED <- file.path(SHARED, c("launch.css", "launch.js"))
LOAD_TIMEOUT_S <- 60       # the launch page explains the delay after this many visible seconds
BUSY_TIMEOUT_S <- 45       # and warns when one update keeps R busy this long
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

# the apps: one launch.json each --------------------------------------------
specs <- sort(Sys.glob("apps/*/launch.json"))
specs <- specs[basename(dirname(specs)) != "_shared"]
if (!length(specs)) fail("no apps/<name>/launch.json found")
APPS <- lapply(specs, function(f) {
  s <- jsonlite::read_json(f, simplifyVector = FALSE)
  s$name <- basename(dirname(f))
  miss <- setdiff(c("source", "title", "summary", "try", "first_load", "links", "smoke"), names(s))
  if (length(miss)) fail(f, " lacks: ", paste(miss, collapse = ", "))
  if (!file.exists(file.path(s$source, "app.R"))) fail(f, ": no app.R in ", s$source)
  if (!length(s$smoke$outputs)) fail(f, ": smoke$outputs lists no output to check")
  s
})
names(APPS) <- vapply(APPS, `[[`, "", "name")

# 1. static site ------------------------------------------------------------
files <- system2("git", c("-c", "core.quotepath=off", "ls-files", "--cached", "--others", "--exclude-standard"),
                 stdout = TRUE)
files <- files[(!grepl("^(\\.git|apps/|_site/)", files) | files %in% PUBLISHED_SHARED) &
               file.exists(files) & !dir.exists(files)]
for (d in unique(dirname(files))) dir.create(file.path(out, d), recursive = TRUE, showWarnings = FALSE)
ok <- file.copy(files, file.path(out, files), copy.date = TRUE)
if (!all(ok)) fail("could not copy: ", paste(files[!ok], collapse = ", "))
cat(sprintf("Copied %d static files into %s\n", length(files), out))

# 2 and 3. the apps ---------------------------------------------------------
stage_root <- tempfile("portfolio-stage-")   # a fresh folder: nothing beside the staged apps
dir.create(stage_root)
for (a in APPS) {
  t0 <- Sys.time()
  stage <- file.path(stage_root, a$name)
  dir.create(stage)
  src <- list.files(a$source, all.files = FALSE, full.names = TRUE, no.. = TRUE)
  if (!all(file.copy(src, stage, recursive = TRUE, copy.date = TRUE))) fail(a$name, ": could not stage ", a$source)
  if (!file.copy(HELPER, file.path(stage, "portfolio_app.R"))) fail(a$name, ": could not add ", HELPER)
  config <- jsonlite::toJSON(list(app = a$name, relPath = "../../", download_mb = a$first_load$download_mb,
                                  timeout_s = LOAD_TIMEOUT_S, busy_timeout_s = BUSY_TIMEOUT_S),
                             auto_unbox = TRUE)
  params <- list(title = a$title, summary = a$summary, try = a$try, links = a$links,
                 screenshot = a$screenshot, source = a$source,
                 download_mb = a$first_load$download_mb, first_s = a$first_load$first_s,
                 revisit_s = a$first_load$revisit_s,
                 launch_config = gsub("</", "<\\/", as.character(config), fixed = TRUE))
  shinylive::export(stage, out, subdir = file.path("apps", a$name), quiet = FALSE,
                    assets_version = ASSETS, template_dir = TEMPLATE, template_params = params)
  if (length(a$screenshot)) {
    shot <- file.path("apps", a$name, a$screenshot$src)
    if (!file.copy(shot, file.path(out, shot))) fail(a$name, ": the screenshot ", shot, " is missing")
  }
  cat(sprintf("Exported %s from %s in %.0f s\n", a$name, a$source,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

unlink(stage_root, recursive = TRUE)

# 4. checks -----------------------------------------------------------------
problems <- character()
need <- function(cond, msg) if (!isTRUE(cond)) problems <<- c(problems, msg)
need(file.exists(file.path(out, "index.html")), "the home page is missing")
need(file.exists(file.path(out, "shinylive-sw.js")), "the Shinylive service worker is missing")
need(file.exists(file.path(out, "shinylive", "shinylive.js")), "the Shinylive loader is missing")
need(dir.exists(file.path(out, "shinylive", "webr")), "the shared webR assets are missing")
for (f in PUBLISHED_SHARED) need(file.exists(file.path(out, f)), paste0(f, " is missing"))
for (a in APPS) {
  d <- file.path(out, "apps", a$name)
  page <- if (file.exists(file.path(d, "index.html"))) paste(readLines(file.path(d, "index.html"), warn = FALSE), collapse = "\n") else ""
  app_json <- if (file.exists(file.path(d, "app.json"))) paste(readLines(file.path(d, "app.json"), warn = FALSE), collapse = "") else ""
  app_r <- paste(readLines(file.path(a$source, "app.R"), warn = FALSE), collapse = "\n")
  need(nzchar(app_json), paste0(a$name, ": app.json is missing"))
  need(grepl('"name":"portfolio_app.R"', app_json, fixed = TRUE), paste0(a$name, ": app.json lacks the shared helper"))
  need(grepl("portfolio_app.R", app_r, fixed = TRUE) && grepl("app_status_ui(", app_r, fixed = TRUE),
       paste0(a$name, ": app.R does not use the shared helper (source it and add app_status_ui())"))
  need(grepl(FAVICON, page, fixed = TRUE), paste0(a$name, ": the launch page has no favicon link"))
  need(grepl('id="launch-config"', page, fixed = TRUE) && grepl("../../apps/_shared/launch.js", page, fixed = TRUE),
       paste0(a$name, ": the page is not the launch page"))
  need(grepl(a$title, page, fixed = TRUE), paste0(a$name, ": the launch page lacks its title"))
  need(!grepl("{{", page, fixed = TRUE), paste0(a$name, ": the launch page has an unfilled template field"))
  need(!dir.exists(file.path(d, "shinylive")), paste0(a$name, ": has its own copy of the assets"))
  for (l in a$links) need(file.exists(file.path(d, sub("[#?].*$", "", l$href))),
                          paste0(a$name, ": the link ", l$href, " does not resolve in the build"))
}
if (length(problems)) fail("site build failed:\n- ", paste(problems, collapse = "\n- "))
mb <- sum(file.info(list.files(out, recursive = TRUE, full.names = TRUE, all.files = TRUE))$size) / 1e6
cat(sprintf("Site built in %s: %d apps (%s), %.0f MB\n", out, length(APPS),
            paste(names(APPS), collapse = ", "), mb))
