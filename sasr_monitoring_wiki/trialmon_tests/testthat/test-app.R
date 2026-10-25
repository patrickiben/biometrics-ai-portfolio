# The console as a visitor first sees it: every output has content with the starting inputs, each
# empty state explains itself, the Start here card is there, the colors are the site's, and the
# launch page's smoke-test values match what the server computes. Driven with shiny::testServer.
suppressPackageStartupMessages(library(shiny))

app_ui_html <- function() {
  e <- new.env(); old <- setwd(APP_DIR); on.exit(setwd(old))
  sys.source("app.R", envir = e)
  list(env = e, html = as.character(htmltools::renderTags(e$ui)$html))
}
# the view helpers (palette, CSS, plots) with the shared helper they build on
view_env <- function() {
  v <- new.env(parent = globalenv())
  sys.source(file.path(APP_DIR, "..", "..", "apps", "_shared", "portfolio_app.R"), envir = v)
  sys.source(file.path(APP_DIR, "R", "app_view.R"), envir = v)
  v
}
LAUNCH <- jsonlite::read_json(file.path(APP_DIR, "..", "..", "apps", "trialmon", "launch.json"))
START <- list(ctcae = "6.0", window = 30, alp = FALSE, meddra = "29.1", pid = "CP101-014", mode = "light",
              kri = "SF-RATE", kri_level = "AMBER")

# the ids of every output the UI declares, read from the rendered page
output_ids <- function(html) {
  m <- regmatches(html, gregexpr('<[^>]+class="[^"]*(shiny-[a-z-]*output|html-widget-output)[^"]*"[^>]*>', html))[[1]]
  ids <- sub('.*\\bid="([^"]+)".*', "\\1", m[grepl('\\bid="', m)])
  unique(ids)
}

# what an output holds, as text a person would read (plots: the image size)
output_text <- function(x) {
  if (is.list(x) && !is.null(x$src)) return(sprintf("image %sx%s", x$width, x$height))
  if (is.list(x) && !is.null(x$html)) return(as.character(x$html))
  if (is.list(x) && !is.null(x$x)) return(as.character(jsonlite::toJSON(x$x$data, auto_unbox = TRUE)))
  paste(as.character(unlist(x)), collapse = " ")
}

test_that("every output the UI declares has content on first load, with no error", {
  ids <- output_ids(app_ui_html()$html)
  expect_true(length(ids) >= 24)
  expect_true(all(unlist(LAUNCH$smoke$outputs) %in% ids))
  for (t in LAUNCH$smoke$tabs) expect_true(all(unlist(t$outputs) %in% ids), info = t$tab)
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    for (id in ids) {
      v <- tryCatch(output[[id]], error = function(e) e)
      expect_false(inherits(v, "error"), info = paste(id, if (inherits(v, "error")) conditionMessage(v)))
      if (!inherits(v, "error")) expect_gt(nchar(trimws(gsub("<[^>]+>", "", output_text(v)))), 0)
    }
  })
})

test_that("the launch page's smoke-test values are what the server computes on first load", {
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    got <- list(v_overall = roll()$overall, v_part = roll()$participant, v_study = roll()$study,
                v_red = as.character(roll()$red), v_amber = as.character(roll()$amber),
                v_watch = as.character(roll()$watch), v_n = as.character(nrow(TM$adsl)))
    for (id in names(LAUNCH$smoke$expect)) expect_equal(got[[id]], LAUNCH$smoke$expect[[id]], info = id)
    expect_match(output$v_overall$html, ">RED<")
    expect_equal(output$v_n, "18")
  })
})

test_that("the Start here card says what the console shows, what each color means and what to try", {
  h <- app_ui_html()$html
  expect_match(h, 'class="tm-start" open', fixed = TRUE)
  expect_match(h, "Start here", fixed = TRUE)
  for (l in c("RED", "AMBER", "watch", "GREEN")) expect_match(h, sprintf('class="sev sev-%s">%s<', l, l), fixed = TRUE)
  expect_match(h, "18 dosed participants in 4 cohorts, 10 to 120 mg", fixed = TRUE)
  expect_equal(lengths(regmatches(h, gregexpr("<li>", sub(".*Try this", "", sub("</details>.*", "", h))))), 3)
})

test_that("the Start here card's suggestions do what it says", {
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    expect_equal(roll()$amber, 7)
    expect_true(liver()$hys[liver()$USUBJID == "CP101-014"])                  # the shaded-box point
    expect_true(liver()$peak_at[liver()$USUBJID == "CP101-014"] >= 3 && liver()$peak_tbl[liver()$USUBJID == "CP101-014"] > 2)
    session$setInputs(ctcae = "5.0")
    expect_equal(roll()$amber, 8)
    new <- roll()$worklist[roll()$worklist$id == "CP101-013", ]
    expect_equal(new$sev, "AMBER"); expect_match(new$value, "Neutrophil count decreased grade 3")
  })
})

test_that("empty and invalid states explain themselves instead of leaving a panel blank", {
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    session$setInputs(window = 200)
    expect_equal(settings()$hys_window, 30)
    expect_match(output$window_note, "from 1 to 90; until then the default of 30 days is used")
    session$setInputs(window = 14)
    expect_match(output$window_note, "In use: TBL within 14 days")
    session$setInputs(pid = "")
    expect_match(output$packet$html, "Pick a participant above")
    expect_error(output$traj, "Pick a participant in the sidebar")
    session$setInputs(pid = "CP101-009")
    expect_match(output$packet$html, "CP101-009: C3")
  })
})

test_that("an error in one panel names what failed (guard), and req()/validate() pass through", {
  e <- tryCatch(guard("the eDISH plot", stop("boom")), error = function(e) e)
  expect_match(conditionMessage(e), "While computing the eDISH plot: boom")
  expect_s3_class(tryCatch(guard("x", explain_empty(FALSE, "why")), error = function(e) e), "shiny.silent.error")
})

test_that("the look: site color tokens in light and dark, the precompiled theme, no ggplot2 to load", {
  css <- view_env()$tm_css()
  for (tok in c("#F6F7F8", "#FFFFFF", "#18212B", "#0757BF", "#12171D", "#1A2129", "#E6EAEE", "#7DB5FF"))
    expect_match(css, tok, fixed = TRUE)
  expect_match(css, "html[data-bs-theme=dark]{", fixed = TRUE)
  code <- readLines(file.path(APP_DIR, "app.R"))
  expect_true(any(grepl("theme = bs_theme(version = 5)", code, fixed = TRUE)))   # no Sass compile in the browser
  expect_false(any(grepl("library(ggplot2)", code, fixed = TRUE)))
})

test_that("level colors meet WCAG AA (4.5:1) on their chips and on the page surfaces, in both modes", {
  e <- view_env()
  expect_length(e$TM_SEV$light, 4); expect_length(e$TM_SEV$dark, 4)
  lum <- function(h) { v <- grDevices::col2rgb(h)[, 1] / 255; v <- ifelse(v <= .03928, v / 12.92, ((v + .055) / 1.055)^2.4)
                       sum(c(.2126, .7152, .0722) * v) }
  ratio <- function(a, b) { l <- sort(c(lum(a), lum(b)), decreasing = TRUE); (l[1] + .05) / (l[2] + .05) }
  for (mode in c("light", "dark")) for (lv in names(e$TM_SEV[[mode]])) {
    s <- e$TM_SEV[[mode]][[lv]]; t <- e$PORTFOLIO_TOKENS[[mode]]
    for (bg in c(s[["bg"]], t[["bg"]], t[["surface"]], t[["surface2"]]))
      expect_gte(ratio(s[["fg"]], bg), 4.5, label = paste(mode, lv, bg))
  }
})

test_that("the three plots draw in base graphics, light and dark, wide and phone-sized", {
  e <- view_env()
  h <- hys_screen(TM$adlb)
  for (dark in c(FALSE, TRUE)) for (w in c(800, 340)) {
    f <- tempfile(fileext = ".png")
    grDevices::png(f, width = w, height = 430, res = 96)
    scr <- e$tm_plot_edish(h, edish_limits(h), e$tm_palette(dark), "CP101-014")
    e$tm_plot_traj(liver_trajectory(TM, "CP101-014"), "CP101-014", e$tm_palette(dark))
    e$tm_plot_ladder(dlt_state(TM), e$tm_palette(dark))
    grDevices::dev.off()
    expect_gt(file.size(f), 5000)
    expect_equal(sum(scr == "Potential Hy's Law"), 1)
    unlink(f)
  }
})
