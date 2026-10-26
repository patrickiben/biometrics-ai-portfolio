#!/usr/bin/env Rscript
# Server tests for the Study Lifecycle Monitor, driven headless with shiny::testServer (no browser).
# Needs the app's packages: shiny, bslib, ggplot2. No testthat.
# Run:  Rscript lifecycle_dashboard/tests/test-server.R   (or from this folder)

app <- Find(function(d) file.exists(file.path(d, "app.R")),
            c("../shiny", "lifecycle_dashboard/shiny", "shiny"))
stopifnot("found the app folder" = !is.null(app))
app <- normalizePath(app)
html_of <- function(x) paste(as.character(x$html %||% x), collapse = "")
plot_ok <- function(x) is.list(x) && grepl("^data:image/png;base64,", x$src %||% "")
validation_message <- function(expr) tryCatch({ force(expr); NA_character_ },
  error = function(e) if (inherits(e, "shiny.silent.error") || inherits(e, "validation")) conditionMessage(e) else stop(e))

# The what-if sliders open on the selected study's own values, so the first values a browser
# sends cannot rewrite that study (the app used to show At risk 0 for a moment at startup).
e <- new.env()
old <- setwd(app); sys.source("app.R", envir = e); setwd(old)
ui <- as.character(e$ui)
slider_from <- function(id) as.numeric(sub('.*data-from="([0-9.]+)".*', "\\1",
  regmatches(ui, regexpr(sprintf('<input[^>]*id="%s"[^>]*>', id), ui))))
s0 <- e$seed$studies[e$seed$studies$id == "CP-108", ]
stopifnot(
  "open-queries slider starts at CP-108's value" = slider_from("openq") == s0$open_queries,
  "double-programming slider starts at CP-108's value" = slider_from("dblprog") == s0$dbl_prog_pct,
  "the in-app guidance is on the page" = grepl("Start here", ui, fixed = TRUE) && grepl("How to read the colors", ui, fixed = TRUE),
  "the header says the data are synthetic, with the snapshot date" =
    grepl("Synthetic data", ui, fixed = TRUE) && grepl("Snapshot 21 Jun 2026", ui, fixed = TRUE),
  "the shared startup card is on the page" = grepl('id="pf-startup"', ui, fixed = TRUE),
  "light and dark follow the site's choice" = grepl('class="bp-theme-input"', ui, fixed = TRUE) &&
    grepl('class="bp-theme-toggle"', ui, fixed = TRUE) && !grepl("bslib-input-dark-mode", ui, fixed = TRUE)
)

seed <- e$seed   # app.R's globals are not visible inside testServer, so pass the seed in
shiny::testServer(app, {
  k0 <- lifecycle_kpis(score_portfolio(seed), seed)
  # the values a browser sends when the page opens
  session$setInputs(study = "CP-108", openq = s0$open_queries, dblprog = s0$dbl_prog_pct)
  stopifnot(
    "opening the app leaves the data as loaded" = identical(rv$studies, seed$studies),
    "KPIs at startup match the logic"            = identical(kpi()[c("at_risk", "open_q")], k0[c("at_risk", "open_q")]),
    "CP-108 is at risk at startup"              = kpi()$at_risk >= 1
  )
  # every panel has content on first load
  stopifnot(
    "KPI values" = identical(c(output$k_n, output$k_risk, output$k_watch, output$k_q, output$k_del, output$k_dbl),
                             c("8", "1", "3", "135", "46%", "8 days")),
    "KPI lines name the studies" = output$k_risk_sub == "CP-108" && output$k_watch_sub == "CP-107, CP-105, CP-106" &&
      output$k_dbl_sub == "CP-105 on 29 Jun 2026",
    "the heatmap has a row per study, CP-108 selected" =
      lengths(regmatches(html_of(output$heat), gregexpr("<tr class=\"is-selected\"|<tr data-study", html_of(output$heat)))) == 8 &&
      grepl('class="is-selected" data-study="CP-108"', html_of(output$heat), fixed = TRUE),
    "signals are listed" = grepl("TLF production behind", html_of(output$signals), fixed = TRUE),
    "the signals header counts them" = grepl("^13 signals: 5 red, 8 amber", output$signals_hdr),
    "the lock-at-risk signal shows both severities" =
      identical(sort(sg()$sev[sg()$title == "DB lock at risk"]), c("amber", "red")),
    "the detail header names the study and its status" =
      grepl("CP-108", html_of(output$detail_hdr), fixed = TRUE) && grepl("Overall 67", html_of(output$detail_hdr), fixed = TRUE),
    "the score breakdown shows the weighted parts" = grepl("26.7 + 0.0 + 27.0 + 12.9", html_of(output$breakdown), fixed = TRUE),
    "the breakdown explains a locked study's timeline" =
      grepl("DB locked 70 days ago; next report: TLFs, 40 days overdue (+45)", html_of(output$breakdown), fixed = TRUE),
    "the TLF funnel" = grepl("5 (7%)", html_of(output$funnel), fixed = TRUE),
    "the deliverables register agrees with the funnel" = grepl("1 of 20", html_of(output$deliv), fixed = TRUE) &&
      grepl("59% of 94", html_of(output$deliv), fixed = TRUE),
    "the inputs table" = lengths(regmatches(html_of(output$inputs), gregexpr("<tr", html_of(output$inputs)))) == 9,
    "no what-if at startup" = grepl("No what-if", html_of(output$whatif_state), fixed = TRUE),
    "the trend note explains a locked study's zero line" =
      grepl("CP-108 locked its database on 12 Apr 2026, before these weeks", html_of(output$trend_note), fixed = TRUE),
    "the milestone track draws" = plot_ok(output$milestones),
    "the query trend draws" = plot_ok(output$trend)
  )
  # a what-if moves the score and says so everywhere; reset restores the data
  session$setInputs(openq = 150)
  stopifnot("what-if raises portfolio open queries" = kpi()$open_q == k0$open_q - s0$open_queries + 150,
            "the sidebar lists the what-if" = grepl("CP-108 open queries 0 \u2192 150", html_of(output$whatif_state), fixed = TRUE),
            "the heatmap marks the study" = grepl("What-if", html_of(output$heat), fixed = TRUE),
            "the KPI line says so" = grepl("(with what-if)", output$k_q_sub, fixed = TRUE),
            "the trend still draws" = plot_ok(output$trend))
  session$setInputs(reset = 1)
  stopifnot("reset restores the data" = identical(rv$studies, seed$studies))
  # clicking a study elsewhere selects it (in a browser; here only the observer runs)
  session$setInputs(pick = "CP-103")
  session$setInputs(pick = "not-a-study")
  # the guidance: CP-103 at 120 open queries turns amber, On watch 3 -> 4
  session$setInputs(study = "CP-103", openq = 42, dblprog = 41)
  stopifnot("switching study leaves the data as loaded" = identical(rv$studies, seed$studies))
  stopifnot("CP-103's trend note gives its lock" =
              grepl("CP-103 locks its database on 24 Jul 2026, 33 days after the snapshot", html_of(output$trend_note), fixed = TRUE),
            "before the lock the funnel says the TLFs are dry runs" = grepl("dry runs", html_of(output$funnel), fixed = TRUE))
  session$setInputs(openq = 120)
  stopifnot("On watch goes to 4" = output$k_watch == "4", "CP-103 amber" = st()$rag[st()$id == "CP-103"] == "amber",
            "its backlog signal follows the what-if and turns red" =
              identical(sg()$sev[sg()$who == "CP-103" & sg()$title == "Query backlog rising"], "red") &&
              grepl("^13 signals: 6 red, 7 amber", output$signals_hdr),
            "the trend still draws" = plot_ok(output$trend))
  # A slider moved right after a study switch, before the browser has applied the sliders' new
  # values, must not write the previous study's values into the new one.
  session$setInputs(reset = 1)
  session$setInputs(openq = 42)                        # the browser applies Reset's slider update
  stopifnot("reset, then the sliders catch up" = identical(rv$studies, seed$studies))
  session$setInputs(study = "CP-105")                  # the sliders still show CP-103's 42 and 41
  session$setInputs(dblprog = 70)                      # a quick drag, with the stale open queries
  stopifnot("a stale slider value writes nothing" = identical(rv$studies, seed$studies))
  session$setInputs(openq = 17, dblprog = 43)          # the browser applies the update for CP-105
  stopifnot("the update leaves CP-105 as loaded" = identical(rv$studies, seed$studies))
  session$setInputs(dblprog = 70)
  i105 <- rv$studies$id == "CP-105"
  stopifnot("now the what-if lands on CP-105" = rv$studies$dbl_prog_pct[i105] == 70 && rv$studies$open_queries[i105] == 17,
            "and only on CP-105" = identical(rv$studies[!i105, ], seed$studies[!i105, ]))
})

# A temporary copy of the app with edited data. The copy gets the shared helper next to app.R,
# as the Pages build does before the Shinylive export.
app_copy <- function(edit) {
  tmp <- file.path(tempfile("lifecycle-"), "shiny")
  dir.create(tmp, recursive = TRUE)
  invisible(file.copy(list.files(app, full.names = TRUE), tmp, recursive = TRUE))
  stopifnot("copied the shared helper" =
    file.copy(file.path(app, "..", "..", "apps", "_shared", "portfolio_app.R"), tmp))
  edit(file.path(tmp, "data"))
  tmp
}

# Data without CP-108 (for example a CTMS export): the app still starts, on the first study.
tmp <- app_copy(function(dd) for (f in list.files(dd, pattern = "[.]csv$", full.names = TRUE))
  writeLines(gsub("CP-108", "CP-208", readLines(f), fixed = TRUE), f))
e2 <- new.env()
old <- setwd(tmp); built <- tryCatch({ sys.source("app.R", envir = e2); TRUE },
                                    error = function(err) conditionMessage(err)); setwd(old)
stopifnot("the app builds when the data have no CP-108" = isTRUE(built))
ui <- as.character(e2$ui)
first <- sort(e2$seed$studies$id)[1]
s1 <- e2$seed$studies[e2$seed$studies$id == first, ]
stopifnot(
  "the renamed data have no CP-108"              = !"CP-108" %in% e2$seed$studies$id,
  "it opens on the first study"                  = e2$OPEN_ID == first,
  "open-queries slider starts at that study's value" = slider_from("openq") == s1$open_queries,
  "double-programming slider starts at that study's value" = slider_from("dblprog") == s1$dbl_prog_pct
)
seed2 <- e2$seed
shiny::testServer(tmp, {
  session$setInputs(study = first, openq = s1$open_queries, dblprog = s1$dbl_prog_pct)
  stopifnot("opening the app leaves the renamed data as loaded" = identical(rv$studies, seed2$studies),
            "the KPIs compute"                                  = kpi()$n == nrow(seed2$studies))
})
unlink(dirname(tmp), recursive = TRUE)

# Empty states: a study with no milestones, trend or deliverables rows, and a portfolio with no
# signals, each say why the panel is empty instead of leaving it blank.
tmp <- app_copy(function(dd) {
  rd <- function(f) utils::read.csv(file.path(dd, f), stringsAsFactors = FALSE)
  wr <- function(x, f) utils::write.csv(x, file.path(dd, f), row.names = FALSE)
  s <- rd("studies.csv"); s$phase <- "Conduct"; s$days_to_dbl <- 90L; s$open_queries <- 5L; wr(s, "studies.csv")
  m <- rd("milestones.csv"); m$status <- "done"; wr(m[m$study_id != "CP-108", ], "milestones.csv")
  q <- rd("query_trend.csv"); q$open_queries <- 5L; wr(q[q$study_id != "CP-108", ], "query_trend.csv")
  dl <- rd("deliverables.csv"); wr(dl[dl$study_id != "CP-108", ], "deliverables.csv")
})
shiny::testServer(tmp, {
  session$setInputs(study = "CP-108", openq = 7, dblprog = 42)
  stopifnot(
    "no signals: says why and what to try" = grepl("No early-warning signals", html_of(output$signals), fixed = TRUE) &&
      output$signals_hdr == "None above the thresholds",
    "no milestones: says why" = grepl("No milestones for CP-108", validation_message(output$milestones), fixed = TRUE),
    "no deliverables: says why" = grepl("No deliverables register rows for CP-108", validation_message(output$deliv), fixed = TRUE),
    "the trend still draws the portfolio" = plot_ok(output$trend),
    "the other panels still fill" = nzchar(output$k_n) && grepl("CP-108", html_of(output$heat), fixed = TRUE)
  )
})
unlink(dirname(tmp), recursive = TRUE)

cat("Lifecycle server: all tests passed\n")
