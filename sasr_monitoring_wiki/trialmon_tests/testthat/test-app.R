# The console as a visitor first sees it: every output has content with the starting inputs, each
# empty state explains itself, the Start here card is there and complete, each "Try this" step
# changes what it says, every click says what it did, the colors are the site's, the plots' text
# fits the device, and the launch page's smoke-test values match what the server computes.
# Driven with shiny::testServer.
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
  sys.source(file.path(APP_DIR, "R", "logic.R"), envir = v)
  sys.source(file.path(APP_DIR, "R", "app_view.R"), envir = v)
  v
}
LAUNCH <- jsonlite::read_json(file.path(APP_DIR, "..", "..", "apps", "trialmon", "launch.json"))
START <- list(ctcae = "6.0", window = 30, alp = FALSE, meddra = "29.1", pid = "CP101-014", mode = "light",
              kri = "SF-RATE", kri_level = "AMBER")

# a click on the eDISH plot at data point (x, y), as the browser sends it (image pixels from the
# plot's coordmap, log axes included)
click_at <- function(cm, x, y) {
  p <- cm$panels[[1]]
  px <- function(v, lo, hi, rlo, rhi, lg) { if (!is.null(lg)) v <- log(v, lg); rlo + (v - lo) / (hi - lo) * (rhi - rlo) }
  list(x = x, y = y, coords_img = list(x = px(x, p$domain$left, p$domain$right, p$range$left, p$range$right, p$log$x),
                                       y = px(y, p$domain$bottom, p$domain$top, p$range$bottom, p$range$top, p$log$y)),
       img_css_ratio = list(x = 1, y = 1), domain = p$domain, range = p$range, log = p$log, mapping = p$mapping)
}
strip <- function(x) trimws(gsub("[[:space:]]+", " ", gsub("<[^>]+>", "", as.character(x))))

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
  card <- sub("</details>.*", "", sub('.*class="tm-start"', "", h))
  steps <- sub(".*Try this", "", card)
  try_items <- regmatches(steps, gregexpr("<li>.*?</li>", steps))[[1]]
  # the card's steps are the launch page's steps: as many, naming the same participants and numbers
  expect_length(try_items, length(LAUNCH$try))
  expect_match(card, sprintf("%s things to try", c("one", "two", "three", "four", "five")[length(LAUNCH$try)]), fixed = TRUE)
  key <- function(x) sort(unique(unlist(regmatches(x, gregexpr("CP101-[0-9]{3}|v5\\.0|\\b[0-9]+ to [0-9]+\\b|Study tier|Liver \\(eDISH\\)", x)))))
  for (i in seq_along(try_items)) expect_equal(key(strip(try_items[i])), key(LAUNCH$try[[i]]), info = LAUNCH$try[[i]])
  # the legend lists every rule that can put a row on the worklist, under its level
  for (i in seq_len(nrow(WORKLIST_RULES)))
    expect_match(card, htmltools::htmlEscape(WORKLIST_RULES$phrase[i]), fixed = TRUE, info = WORKLIST_RULES$phrase[i])
  expect_match(card, "it still counts in the roll-up", fixed = TRUE)          # watch is a flag, not a note
  expect_false(grepl("not yet a flag", card, fixed = TRUE))
})

test_that("every worklist row, under any setting or what-if, matches a legend entry of its own level", {
  rows <- list()
  for (ct in c("6.0", "5.0")) for (w in c(14, 30, 60)) for (alp in c(FALSE, TRUE))
    rows[[length(rows) + 1]] <- trialmon_worklist(TM, trialmon_settings(ct, w, alp))
  for (lvl in c("RED", "AMBER")) { st <- S0; st$LEVEL[] <- lvl; rows[[length(rows) + 1]] <- trialmon_worklist(TM, study = st) }
  for (co in list(list(n = 3, n_dlt = 1), list(n = 3, n_dlt = 2)))      # a cohort to expand and one over the MTD
    rows[[length(rows) + 1]] <- trialmon_worklist(do.call(with_cohort, c(list(TM, "C4"), co)))
  wl <- do.call(rbind, rows)
  wl <- rbind(wl, data.frame(tier = "Participant", id = "X", sev = c("RED", "AMBER"),            # grades 4 and 3, as the
                             check = c("Lab grade 4 or higher", "Lab grade 3 or higher"),      # worklist writes them
                             value = "", rule = ""))
  combos <- unique(wl[, c("tier", "check", "sev")])
  phrase <- worklist_rule(combos)
  expect_false(any(is.na(phrase)), info = paste(apply(combos[is.na(phrase), ], 1, paste, collapse = " / "), collapse = "; "))
  expect_true(all(c("RED", "AMBER", "watch") %in% combos$sev))
  expect_true(all(WORKLIST_RULES$phrase %in% phrase))                       # and every legend entry can fire
})

test_that("the Try this steps each change what they say they change", {
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    wl <- roll()$worklist
    # first load: CP101-014's first row is the highlighted one, and the status line says so
    expect_equal(pid_row(), 1L); expect_equal(wl$id[1], "CP101-014")
    expect_match(strip(output$wl_status$html), "Open now: CP101-014 RED, highlighted below.", fixed = TRUE)
    packet0 <- output$packet$html
    # step 1: CP101-004's row is the first AMBER row; clicking it opens CP101-004's packet
    i <- which(wl$tier == "Participant" & wl$id == "CP101-004")[1]
    expect_equal(i, which(wl$sev == "AMBER")[1])
    session$setInputs(worklist_rows_selected = i)
    expect_equal(asked(), "CP101-004")
    session$setInputs(pid = asked())                                         # what the browser does next
    expect_match(output$packet$html, "CP101-004: C2, 30 mg")
    expect_false(identical(output$packet$html, packet0))
    expect_equal(pid_row(), i)
    expect_match(strip(output$wl_status$html), "Open now: CP101-004 AMBER", fixed = TRUE)
    # step 2: exactly two points in the shaded box, CP101-014 (potential Hy's Law) and CP101-004
    # (its TBL peaked before the AT elevation, so not)
    h <- liver(); box <- h[h$peak_at >= 3 & h$peak_tbl > 2, ]
    expect_equal(sort(box$USUBJID), c("CP101-004", "CP101-014"))
    expect_equal(box$hys[box$USUBJID == "CP101-014"], TRUE); expect_equal(box$hys[box$USUBJID == "CP101-004"], FALSE)
    tr <- liver_trajectory(TM, "CP101-004")
    expect_lt(tr$ADY[tr$test == "TBL"][which.max(tr$xuln[tr$test == "TBL"])], box$at3x_day[box$USUBJID == "CP101-004"])
    expect_match(strip(output$edish_msg$html), "2 points sit in the shaded box: CP101-004 AMBER and CP101-014 RED.", fixed = TRUE)
    cm <- output$edish$coordmap
    session$setInputs(edish_click = click_at(cm, 5.6, 3.1))                  # CP101-014
    expect_equal(asked(), "CP101-014")
    session$setInputs(pid = asked())
    expect_match(strip(output$edish_msg$html), "Now showing CP101-014 RED", fixed = TRUE)
    expect_match(output$traj$alt, "CP101-014"); expect_match(output$packet$html, "CP101-014: C4")
    session$setInputs(edish_click = click_at(cm, 3.3, 2.4))                  # then CP101-004, to compare
    expect_equal(asked(), "CP101-004")
    session$setInputs(pid = asked())
    expect_match(strip(output$edish_msg$html), "Now showing CP101-004 AMBER", fixed = TRUE)
    expect_match(output$traj$alt, "CP101-004")
    # step 3: CTCAE v5.0 adds CP101-013 at AMBER, 7 -> 8
    expect_equal(roll()$amber, 7)
    session$setInputs(ctcae = "5.0")
    expect_equal(roll()$amber, 8); expect_equal(output$v_amber, "8")
    new <- roll()$worklist[roll()$worklist$id == "CP101-013", ]
    expect_equal(new$sev, "AMBER"); expect_match(new$value, "Neutrophil count decreased grade 3")
    session$setInputs(ctcae = "6.0")
    # step 4: an indicator set to RED turns the study tier RED, marked as a what-if; Reset undoes it
    expect_match(output$v_study$html, ">AMBER<")
    session$setInputs(kri_level = "RED")
    expect_match(output$v_study$html, ">RED<")
    expect_match(study_view()$Level[study_view()$ID == "SF-RATE"], "what-if")
    session$setInputs(kri_reset = 1)
    expect_match(output$v_study$html, ">AMBER<")
  })
})

test_that("every click says what it did: the open participant, a missed point, a cohort or study row", {
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    cm <- output$edish$coordmap
    session$setInputs(edish_click = click_at(cm, 5.6, 3.1))                  # CP101-014, already open
    expect_equal(pid(), "CP101-014")
    expect_match(strip(output$edish_msg$html), "CP101-014 RED is already the participant in the sidebar", fixed = TRUE)
    session$setInputs(edish_click = click_at(cm, 1.5, 3))                    # nothing there
    expect_match(strip(output$edish_msg$html), "No point within reach of that click.", fixed = TRUE)
    session$setInputs(pid = "CP101-009")                                     # chosen in the sidebar instead
    expect_match(strip(output$edish_msg$html), "Click a point to open that participant. Ringed: CP101-009 AMBER", fixed = TRUE)
    # the highlight follows the sidebar: CP101-009's first worklist row
    expect_equal(roll()$worklist$id[pid_row()], "CP101-009")
    # a Cohort row: explained above the table and in a notice; the packet stays
    j <- which(roll()$worklist$tier == "Cohort")[1]
    session$setInputs(worklist_rows_selected = j)
    expect_equal(pid(), "CP101-009")
    expect_match(strip(output$wl_status$html), "Cohort C4 (120 mg) is a cohort flag, not a participant, so the sidebar packet still shows CP101-009.", fixed = TRUE)
    expect_match(strip(output$wl_status$html), "Its DLT tally is on Dose escalation.", fixed = TRUE)
    expect_match(told(), "is a cohort flag, not a participant")
    k <- which(roll()$worklist$tier == "Study")[1]
    session$setInputs(worklist_rows_selected = k)
    expect_match(strip(output$wl_status$html), "is a study indicator, not a participant", fixed = TRUE)
    # choosing a participant again clears the note
    session$setInputs(pid = "CP101-006")
    expect_match(strip(output$wl_status$html), "Open now: CP101-006 AMBER, highlighted below.", fixed = TRUE)
    # a participant with no flag has no row, and the status says so
    session$setInputs(pid = "CP101-001")
    expect_length(pid_row(), 0)
    expect_match(strip(output$wl_status$html), "which has no flag, so no row is highlighted", fixed = TRUE)
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

test_that("a selected table row keeps readable text in both modes (accent behind, ink on it)", {
  e <- view_env()
  lum <- function(h) { v <- grDevices::col2rgb(h)[, 1] / 255; v <- ifelse(v <= .03928, v / 12.92, ((v + .055) / 1.055)^2.4)
                       sum(c(.2126, .7152, .0722) * v) }
  ratio <- function(a, b) { l <- sort(c(lum(a), lum(b)), decreasing = TRUE); (l[1] + .05) / (l[2] + .05) }
  css <- e$tm_css()
  expect_match(css, "html .table.dataTable{--dt-row-selected:var(--tm-sel);--dt-row-selected-text:var(--tm-sel-text)", fixed = TRUE)
  expect_gte(ratio(e$PORTFOLIO_TOKENS$light[["accent"]], "#FFFFFF"), 4.5)
  expect_gte(ratio(e$PORTFOLIO_TOKENS$dark[["accent"]], "#12171D"), 4.5)
  expect_match(css, "--tm-sel-text:18,23,29", fixed = TRUE)                    # dark ink on the light dark-mode accent
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

test_that("every word in the plots fits the device and covers no other label: phone, laptop column, wide", {
  e <- view_env()
  h <- hys_screen(TM$adlb)
  overlap <- function(b) {
    out <- character()
    for (i in seq_len(nrow(b) - 1)) for (j in (i + 1):nrow(b)) {
      a <- max(0, min(b$x1[i], b$x1[j]) - max(b$x0[i], b$x0[j])) * max(0, min(b$y1[i], b$y1[j]) - max(b$y0[i], b$y0[j]))
      if (a > 1e-4) out <- c(out, paste(b$label[i], "/", b$label[j]))
    }
    out
  }
  draw <- function(what, w, ht, dark, sel = "CP101-014") {
    f <- tempfile(fileext = ".png"); on.exit(unlink(f))
    grDevices::png(f, width = w, height = ht, res = 96)
    r <- switch(what, edish = e$tm_plot_edish(h, edish_limits(h), e$tm_palette(dark), sel),
                traj = e$tm_plot_traj(liver_trajectory(TM, sel), sel, e$tm_palette(dark)),
                ladder = e$tm_plot_ladder(dlt_state(TM), e$tm_palette(dark)))
    grDevices::dev.off()
    attr(r, "boxes")
  }
  for (dark in c(FALSE, TRUE)) for (w in c(320, 360, 470, 560, 800)) for (what in c("edish", "traj", "ladder")) {
    ht <- if (what == "edish") 430 else 300
    b <- draw(what, w, ht, dark)
    txt <- b[b$kind != "ref", ]
    info <- paste(what, w, if (dark) "dark" else "light")
    expect_gt(nrow(txt), 8)
    expect_true(all(txt$x0 >= -.01 & txt$x1 <= w / 96 + .01 & txt$y0 >= -.01 & txt$y1 <= ht / 96 + .01),
                info = paste(info, paste(txt$label[!(txt$x0 >= -.01 & txt$x1 <= w / 96 + .01 & txt$y0 >= -.01 & txt$y1 <= ht / 96 + .01)], collapse = ", ")))
    expect_equal(overlap(txt), character(), info = info)
    if (what == "edish") {
      note <- txt[grepl("^Check", txt$label), ]
      expect_equal(nrow(note), 1)
      expect_gt(note$x0, b$x0[b$kind == "ref"], label = paste(info, "the box prompt starts right of the 3x line"))
      labs <- txt$label[txt$kind == "label"]
      expect_true(all(c("014", "004", "009") %in% sub("^CP101-", "", labs)), info = info)
      if (w >= 400) expect_true(all(c("CP101-014", "CP101-004", "CP101-009", "CP101-011") %in% labs), info = info)  # full IDs off a phone
      if (w >= 400) expect_true("3x ULN" %in% txt$label, info = info)
    }
    if (what == "ladder") expect_true(any(grepl("pending", txt$label)), info = info)
  }
  # the ringed participant changes nothing about the fit
  for (sel in c("CP101-004", "CP101-011")) expect_equal(overlap(draw("edish", 470, 430, FALSE, sel)[draw("edish", 470, 430, FALSE, sel)$kind != "ref", ]), character())
})

test_that("small formats: the liver table shows one decimal; count columns do not wrap", {
  shiny::testServer(APP_DIR, {
    do.call(session$setInputs, START)
    d <- liver_view()
    expect_equal(d$`R ratio`[d$Participant == "CP101-014"], "4.0")             # as the packet and the worklist write it
    expect_match(output$packet$html, "R 4.0, mixed", fixed = TRUE)
  })
  css <- view_env()$tm_css()
  expect_match(css, "#ae_tbl td:not(:first-child)", fixed = TRUE)
  expect_match(css, "white-space:nowrap", fixed = TRUE)
})
