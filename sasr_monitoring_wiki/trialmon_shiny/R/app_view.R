# ---------------------------------------------------------------------------
# app_view.R: how the TRIALMON console looks, on SYNTHETIC data. The palette (the site's color
# tokens plus the four review levels), the page CSS, the level chips, the "Start here" card,
# small table helpers and the three plots. No screening rule lives here: those are in logic.R.
#
# Needs portfolio_app.R first (PORTFOLIO_TOKENS, PORTFOLIO_SANS, PORTFOLIO_MONO: the site.css
# tokens). Uses shiny tags and base graphics only.
#
# Why plain CSS over the precompiled Bootstrap theme, and base graphics: in the browser (webR),
# a custom bslib theme is compiled with Sass every time the app starts (about 0.6 s on a fast
# laptop, measured 2026-10-25) and loading ggplot2 takes about 0.65 s more, before any result
# shows. Bootstrap 5.3 reads its colors from CSS variables, so the site tokens below restyle the
# precompiled theme at no cost, and the three plots draw in base graphics, which R has loaded
# already.
# ---------------------------------------------------------------------------

TM_LEVELS <- c("RED", "AMBER", "watch", "GREEN")     # worst first, as the worklist ranks them

# the four review levels: fg for text and plot marks, bg and line for the chips (WCAG AA or
# better against the chip and the page surfaces in both modes)
TM_SEV <- list(
  light = list(RED = c(fg = "#B42318", bg = "#FDECEA", line = "#EFB1A9"),
               AMBER = c(fg = "#8A5300", bg = "#FCF1DD", line = "#E6C68A"),
               watch = c(fg = "#0B4F9C", bg = "#E5EEFA", line = "#A7C3E8"),
               GREEN = c(fg = "#1D5E35", bg = "#E3F2E8", line = "#9CCBAD")),
  dark = list(RED = c(fg = "#FF9B8F", bg = "#3A1D1B", line = "#7A3B34"),
              AMBER = c(fg = "#F3C169", bg = "#33280F", line = "#7A6024"),
              watch = c(fg = "#A9CCFF", bg = "#1A2B40", line = "#36557D"),
              GREEN = c(fg = "#93DBAE", bg = "#17301F", line = "#2F6B45")))

# what each level means in this console (the Start here card)
TM_LEVEL_TEXT <- c(
  RED = "review now: potential Hy's Law, a serious AE, QTcF > 500 ms",
  AMBER = "confirm or look closer: ALT or AST > 3x ULN, QTcF > 480 ms",
  watch = "noted, not yet a flag: QTcF > 450 ms",
  GREEN = "no flag")

# colors for plots: the site tokens, the level colors and one color per liver test
tm_palette <- function(dark = FALSE) {
  t <- portfolio_colors(dark)
  sev <- vapply(TM_SEV[[if (isTRUE(dark)) "dark" else "light"]], function(s) s[["fg"]], "")
  lab <- if (isTRUE(dark)) c(ALT = "#7DB5FF", AST = "#C9A8F5", ALP = "#A9B3BD", TBL = "#E0935F")
         else c(ALT = "#0757BF", AST = "#7A4FB3", ALP = "#5F6B78", TBL = "#B5561F")
  list(fg = t$text, muted = t$muted, line = t$line, surface = t$surface, accent = t$accent, sev = sev, lab = lab)
}

# ---- page CSS ---------------------------------------------------------------------------------
.tm_rgb <- function(h) paste(col2rgb(h), collapse = ",")

tm_css <- function() {
  mode_vars <- function(mode) {
    t <- PORTFOLIO_TOKENS[[mode]]; s <- TM_SEV[[mode]]
    hover <- if (mode == "dark") "#A9CCFF" else "#05479C"
    ink <- if (mode == "dark") "#12171D" else "#FFFFFF"
    sev <- paste(vapply(names(s), function(k) sprintf("--tm-%s:%s;--tm-%s-bg:%s;--tm-%s-line:%s;",
                                                    k, s[[k]][["fg"]], k, s[[k]][["bg"]], k, s[[k]][["line"]]), ""),
                 collapse = "")
    paste0(
      "--tm-bg:", t[["bg"]], ";--tm-surface:", t[["surface"]], ";--tm-surface2:", t[["surface2"]],
      ";--tm-text:", t[["text"]], ";--tm-muted:", t[["muted"]], ";--tm-line:", t[["line"]],
      ";--tm-accent:", t[["accent"]], ";--tm-accent-rgb:", .tm_rgb(t[["accent"]]),
      ";--tm-accent-hover:", hover, ";--tm-accent-ink:", ink, ";", sev,
      "--bs-body-bg:", t[["bg"]], ";--bs-body-bg-rgb:", .tm_rgb(t[["bg"]]),
      ";--bs-body-color:", t[["text"]], ";--bs-body-color-rgb:", .tm_rgb(t[["text"]]),
      ";--bs-emphasis-color:", t[["text"]], ";--bs-emphasis-color-rgb:", .tm_rgb(t[["text"]]),
      ";--bs-secondary-color:", t[["muted"]], ";--bs-tertiary-color:", t[["muted"]],
      ";--bs-border-color:", t[["line"]], ";--bs-border-color-translucent:", t[["line"]],
      ";--bs-secondary-bg:", t[["surface2"]], ";--bs-tertiary-bg:", t[["surface2"]],
      ";--bs-primary:", t[["accent"]], ";--bs-primary-rgb:", .tm_rgb(t[["accent"]]),
      ";--bs-link-color:", t[["accent"]], ";--bs-link-color-rgb:", .tm_rgb(t[["accent"]]),
      ";--bs-link-hover-color:", hover, ";--bs-link-hover-color-rgb:", .tm_rgb(hover),
      ";--bs-focus-ring-color:rgba(", .tm_rgb(t[["accent"]]), ",.3);",
      "--dt-row-selected:", .tm_rgb(t[["accent"]]), ";--dt-row-selected-text:", ink, ";--dt-row-selected-link:", ink, ";")
  }
  paste0(
    "html:root,html[data-bs-theme=light]{", mode_vars("light"), "--tm-sans:", PORTFOLIO_SANS,
    ";--tm-mono:", PORTFOLIO_MONO, ";--bs-body-font-family:var(--tm-sans);--bs-font-sans-serif:var(--tm-sans);",
    "--bs-font-monospace:var(--tm-mono)}\n",
    "html[data-bs-theme=dark]{", mode_vars("dark"), "}\n", TM_CSS_RULES)
}

TM_CSS_RULES <- "
body{font-family:var(--tm-sans);background:var(--tm-bg);color:var(--tm-text)}
.bslib-page-sidebar{--bslib-page-sidebar-title-bg:var(--tm-surface);--bslib-page-sidebar-title-color:var(--tm-text)}
.bslib-page-sidebar .bslib-page-title{border-bottom:1px solid var(--tm-line)}
.bslib-page-title{font-size:1.15rem;font-weight:700}
.bslib-sidebar-layout{--bslib-sidebar-bg:var(--tm-surface);--bslib-sidebar-fg:var(--tm-text);--bslib-sidebar-border:1px solid var(--tm-line)}
.card{--bs-card-bg:var(--tm-surface);--bs-card-border-color:var(--tm-line);--bs-card-cap-bg:var(--tm-surface)}
.nav-tabs{--bs-nav-tabs-border-color:var(--tm-line);--bs-nav-tabs-link-active-bg:var(--tm-surface);--bs-nav-tabs-link-active-color:var(--tm-text);
 --bs-nav-tabs-link-active-border-color:var(--tm-line) var(--tm-line) var(--tm-surface);--bs-nav-tabs-link-hover-border-color:var(--tm-line)}
.nav-link{--bs-nav-link-color:var(--tm-accent);--bs-nav-link-hover-color:var(--tm-accent-hover)}
.nav-tabs .nav-link.active{font-weight:600}
.btn-primary{--bs-btn-color:var(--tm-accent-ink);--bs-btn-bg:var(--tm-accent);--bs-btn-border-color:var(--tm-accent);
 --bs-btn-hover-color:var(--tm-accent-ink);--bs-btn-hover-bg:var(--tm-accent-hover);--bs-btn-hover-border-color:var(--tm-accent-hover);
 --bs-btn-active-color:var(--tm-accent-ink);--bs-btn-active-bg:var(--tm-accent-hover);--bs-btn-active-border-color:var(--tm-accent-hover);
 --bs-btn-focus-shadow-rgb:var(--tm-accent-rgb)}
.btn-outline-primary{--bs-btn-color:var(--tm-accent);--bs-btn-border-color:var(--tm-accent);--bs-btn-hover-color:var(--tm-accent-ink);
 --bs-btn-hover-bg:var(--tm-accent);--bs-btn-hover-border-color:var(--tm-accent);--bs-btn-active-color:var(--tm-accent-ink);
 --bs-btn-active-bg:var(--tm-accent);--bs-btn-active-border-color:var(--tm-accent);--bs-btn-focus-shadow-rgb:var(--tm-accent-rgb)}
.btn-outline-secondary{--bs-btn-color:var(--tm-text);--bs-btn-border-color:var(--tm-line);--bs-btn-hover-color:var(--tm-text);
 --bs-btn-hover-bg:var(--tm-surface2);--bs-btn-hover-border-color:var(--tm-muted);--bs-btn-active-color:var(--tm-text);
 --bs-btn-active-bg:var(--tm-surface2);--bs-btn-active-border-color:var(--tm-muted);--bs-btn-focus-shadow-rgb:var(--tm-accent-rgb)}
.form-control,.form-select,.selectize-input,.selectize-control.single .selectize-input{background-color:var(--tm-surface);border-color:var(--tm-line);color:var(--tm-text)}
.selectize-dropdown,.selectize-dropdown.form-control{background-color:var(--tm-surface);color:var(--tm-text);border-color:var(--tm-line)}
.selectize-dropdown .active:not(.selected){background:rgba(var(--tm-accent-rgb),.12);color:var(--tm-text)}
.selectize-dropdown .selected{background:var(--tm-accent);color:var(--tm-accent-ink)}
.form-control:focus,.form-select:focus,.selectize-input.focus,.form-check-input:focus{border-color:var(--tm-accent);box-shadow:0 0 0 .2rem rgba(var(--tm-accent-rgb),.25)}
.form-check-input:checked,.shiny-input-container .checkbox input:checked,.shiny-input-container .radio input:checked,
.shiny-input-container .radio-inline input:checked,.shiny-input-container .checkbox-inline input:checked{background-color:var(--tm-accent);border-color:var(--tm-accent)}
.form-label,.control-label{font-weight:600;font-size:.9rem}
.table{--bs-table-bg:transparent;--bs-table-color:var(--tm-text);--bs-table-border-color:var(--tm-line);
 --bs-table-striped-bg:rgba(var(--bs-emphasis-color-rgb),.035);--bs-table-striped-color:var(--tm-text);
 --bs-table-hover-bg:rgba(var(--tm-accent-rgb),.07);--bs-table-hover-color:var(--tm-text)}
table.dataTable,.shiny-table{font-size:.9rem}
table.dataTable caption,.dataTables_wrapper caption{caption-side:bottom;font-size:.82rem;color:var(--tm-muted);padding:.4rem 0 0}
table.dataTable thead th,.shiny-table thead th{font-size:.8rem;font-weight:700;color:var(--tm-muted);vertical-align:bottom}
#worklist table.dataTable tbody tr{cursor:pointer}
#study_tbl td:first-child,#qtc_tbl td:first-child,#liver_tbl td:first-child{white-space:nowrap}
.tm-check{display:block;font-weight:600}.tm-rule{display:block;font-size:.8rem;color:var(--tm-muted);line-height:1.3}
table.dataTable tbody tr.selected .tm-rule{color:inherit}
.bslib-sidebar-layout>.sidebar hr{margin:.9rem 0 .6rem}.bslib-sidebar-layout>.sidebar h6{font-weight:700;margin-bottom:.4rem}
.dataTables_wrapper .dataTables_paginate{font-size:.85rem}
.sev{display:inline-block;font-weight:700;font-size:.78rem;letter-spacing:.02em;line-height:1.3;padding:.08rem .5rem;
 border-radius:999px;border:1px solid;white-space:nowrap;vertical-align:baseline}
.sev-RED{color:var(--tm-RED);background:var(--tm-RED-bg);border-color:var(--tm-RED-line)}
.sev-AMBER{color:var(--tm-AMBER);background:var(--tm-AMBER-bg);border-color:var(--tm-AMBER-line)}
.sev-watch{color:var(--tm-watch);background:var(--tm-watch-bg);border-color:var(--tm-watch-line)}
.sev-GREEN{color:var(--tm-GREEN);background:var(--tm-GREEN-bg);border-color:var(--tm-GREEN-line)}
.tm-whatif{display:inline-block;font-size:.72rem;font-weight:700;color:var(--tm-accent);border:1px dashed var(--tm-accent);border-radius:999px;padding:0 .45rem;margin-left:.3rem}
.tm-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(118px,1fr));gap:.5rem;margin:0 0 .9rem}
.tm-kpi{border:1px solid var(--tm-line);border-left:4px solid var(--tm-line);border-radius:.5rem;padding:.45rem .7rem .5rem;background:var(--tm-surface);min-width:0}
.tm-kpi .k{font-size:.78rem;font-weight:600;color:var(--tm-muted);line-height:1.25}
.tm-kpi .v{font-size:1.45rem;font-weight:700;line-height:1.35;min-height:1.95rem}
.tm-kpi .c{font-size:.74rem;color:var(--tm-muted);line-height:1.25}
.tm-kpi .v .sev{font-size:1.3rem;padding:0;border:0;background:none;letter-spacing:0}
.tm-kpi:has(.v .sev-RED),.tm-kpi.kpi-RED{border-left-color:var(--tm-RED)}
.tm-kpi:has(.v .sev-AMBER),.tm-kpi.kpi-AMBER{border-left-color:var(--tm-AMBER)}
.tm-kpi:has(.v .sev-watch),.tm-kpi.kpi-watch{border-left-color:var(--tm-watch)}
.tm-kpi:has(.v .sev-GREEN),.tm-kpi.kpi-GREEN{border-left-color:var(--tm-GREEN)}
.tm-kpi.kpi-RED .v{color:var(--tm-RED)}.tm-kpi.kpi-AMBER .v{color:var(--tm-AMBER)}.tm-kpi.kpi-watch .v{color:var(--tm-watch)}
.tm-start{background:var(--tm-surface);border:1px solid var(--tm-line);border-left:4px solid var(--tm-accent);border-radius:.5rem;margin:0 0 .8rem}
.tm-start>summary{cursor:pointer;padding:.55rem .9rem;line-height:1.5}
.tm-start>summary:focus-visible{outline:3px solid var(--tm-accent);outline-offset:2px;border-radius:.4rem}
.tm-start .t{font-weight:700;font-size:1rem;margin-right:.5rem}
.tm-start .s{color:var(--tm-muted);font-size:.88rem}
.tm-start .tog{float:right;font-size:.82rem;font-weight:600;color:var(--tm-accent);margin-left:.75rem}
.tm-start .tog:after{content:'Show'}.tm-start[open] .tog:after{content:'Hide'}
.tm-start-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:.2rem 1.5rem;padding:0 .95rem .65rem}
@media (min-width:1100px){.tm-start-grid{grid-template-columns:minmax(0,1fr) minmax(0,1.1fr) minmax(0,1fr)}}
.tm-start h3{font-size:.74rem;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:var(--tm-muted);margin:.35rem 0 .35rem}
.tm-start p,.tm-start li{font-size:.86rem;line-height:1.42}
.tm-start p{margin:0 0 .4rem}
.tm-start ol{margin:0;padding-left:1.15rem}.tm-start ol li{margin:0 0 .3rem}
.tm-legend{list-style:none;margin:0;padding:0}.tm-legend li{margin:0 0 .22rem;display:flex;gap:.45rem;align-items:baseline}
.tm-legend .sev{min-width:4.2rem;text-align:center}
.tm-hint{font-size:.88rem;color:var(--tm-muted);margin:.1rem 0 .5rem}
.tm-hint strong{color:var(--tm-text)}
.packet dl{margin:.4rem 0 0}.packet dt{font-weight:700;margin-top:.45rem;font-size:.78rem;text-transform:uppercase;letter-spacing:.04em;color:var(--tm-muted)}
.packet dd{margin:0}
.packet-head{font-weight:700;font-size:.98rem}
.packet .note{font-style:italic;margin:.5rem 0 0;padding:.4rem .6rem;border-left:3px solid var(--tm-line);color:var(--tm-muted)}
.foot{font-size:.85rem;color:var(--tm-muted)}
.tm-plot-note{font-size:.85rem;color:var(--tm-muted);margin:.25rem 0 .75rem}
.tm-soc{font-weight:700}.tm-pt{padding-left:1.25rem;display:inline-block}
.tm-footer{font-size:.8rem;color:var(--tm-muted);margin:1rem 0 .25rem}
#grid_tbl{overflow-x:auto;flex:0 0 auto!important;height:auto!important}
#grid_tbl td:nth-child(-n+2),#grid_tbl td:nth-child(16),#grid_tbl thead tr:last-child th{white-space:nowrap}
#grid_tbl td:nth-child(17),#grid_tbl td:nth-child(18){min-width:12rem}
#grid_tbl thead th[rowspan]{vertical-align:bottom}#grid_tbl th.tm-ref{min-width:8.5rem}
table.dataTable td.tm-ref,table.dataTable th.tm-ref{border-left:3px solid var(--tm-AMBER)!important;font-style:italic}
@media (max-width:575.98px){.tm-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.tm-kpi .v{font-size:1.25rem}}
"

# ---- small UI pieces ---------------------------------------------------------------------------
sev_span <- function(s) span(class = paste0("sev sev-", s), s)

# the same chip as HTML text, for DT columns and renderTable cells
sev_html <- function(s) sprintf('<span class="sev sev-%s">%s</span>', s, s)

tm_esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

kpi <- function(label, value, caption, level = NULL)
  div(class = paste(c("tm-kpi", if (length(level)) paste0("kpi-", level)), collapse = " "),
      div(class = "k", label), div(class = "v", value), div(class = "c", caption))

start_here_ui <- function(n_dosed, cohort_text) {
  tags$details(
    class = "tm-start", open = NA,
    tags$summary(span(class = "t", "Start here"),
                 span(class = "s", "what this console shows, what the colors mean, three things to try"),
                 span(class = "tog", `aria-hidden` = "true")),
    # on a phone the open card would fill the first screen: start it folded there (one tap opens it)
    tags$script(HTML("(function(){var d=document.currentScript.parentNode;if(window.innerWidth<576)d.removeAttribute('open');})();")),
    div(class = "tm-start-grid",
      div(tags$h3("What it shows"),
          p(sprintf(paste("Synthetic study CP-101, a first-in-human multiple ascending dose study, at its Cohort 4",
                          "(120 mg) data cut: %d dosed participants in %s."), n_dosed, cohort_text),
            "Each check flags a participant, a cohort or a study indicator; the flags roll up worst-of into the",
            "boxes below and the ranked worklist, and the tabs show the evidence. The console flags; the medical",
            "monitor and the Safety Review Committee decide.")),
      div(tags$h3("What the colors mean"),
          tags$ul(class = "tm-legend", lapply(TM_LEVELS, function(l) tags$li(sev_span(l), span(TM_LEVEL_TEXT[[l]])))),
          p(class = "mt-1 mb-0", "Worst-of: one RED makes its tier and the overall level RED.")),
      div(tags$h3("Try this"),
          tags$ol(
            tags$li(tags$strong("Click a Participant row"), " in the worklist: the sidebar shows that participant's packet."),
            tags$li("Open ", tags$strong("Liver (eDISH)"), " and click the point in the shaded box: CP101-014, a",
                    " potential Hy's Law case."),
            tags$li("Switch ", tags$strong("Lab grading"), " to v5.0 in the sidebar: CP101-013's neutrophil count",
                    " becomes grade 3 and AMBER goes from 7 to 8.")))))
}

# a data frame for renderTable(sanitize.text.function = identity): character columns escaped,
# except the columns listed in `html`, which already hold safe HTML
tm_table <- function(df, html = character()) {
  for (n in setdiff(names(df)[vapply(df, is.character, logical(1))], html)) df[[n]] <- tm_esc(df[[n]])
  names(df) <- tm_esc(names(df))
  df
}

# ---- plots (base graphics) ---------------------------------------------------------------------
.tm_par <- function(pal, mar) par(mar = mar, fg = pal$line, col.axis = pal$muted, col.lab = pal$fg,
                                  col.main = pal$fg, las = 1, mgp = c(2.7, .55, 0), tcl = -.25, cex.axis = .85,
                                  cex.lab = .92, family = "sans", xpd = FALSE)

# a one-row legend above the plotting region; items: named colors, pch 21 points or lines
.tm_legend_top <- function(labels, cols, pal, type = "point", pch = 21, border = pal$surface, rows = 1) {
  x0 <- grconvertX(0, "npc", "user"); y0 <- grconvertY(1, "npc", "user")
  op <- par(xpd = NA); on.exit(par(op))
  pt <- type == "point"
  legend(x0, y0, legend = labels, ncol = ceiling(length(labels) / rows), bty = "n", xjust = 0,
         yjust = 0, cex = .82, text.col = pal$fg, y.intersp = .9,
         pch = if (pt) pch else NA, pt.bg = if (pt) cols else NA, col = if (pt) border else cols,
         pt.cex = if (pt) 1.35 else 1, pt.lwd = 1.1, lwd = if (pt) NA else 2.2, lty = if (pt) 0 else 1,
         seg.len = 1.4, x.intersp = .6, text.width = NULL)
}

.tm_log_ticks <- function(lim) {
  t <- c(.05, .1, .2, .3, .5, 1, 2, 3, 5, 10, 20, 30, 50, 100)
  t[t >= lim[1] & t <= lim[2]]
}

# a phone-width device: shorter titles and labels, the eDISH legend on two rows
.tm_narrow <- function() dev.size("in")[1] < 5.6

# eDISH: peak ALT or AST against peak TBL, x ULN, log scales; `sel` is ringed
tm_plot_edish <- function(h, lim, pal, sel = NULL) {
  screen <- ifelse(h$hys, "Potential Hy's Law", ifelse(!is.na(h$at3x_day), "AT > 3x ULN: confirm", "No hepatic flag"))
  lv <- c("Potential Hy's Law" = "RED", "AT > 3x ULN: confirm" = "AMBER", "No hepatic flag" = "GREEN")
  narrow <- .tm_narrow()
  .tm_par(pal, c(4, if (narrow) 3.6 else 4.6, if (narrow) 4.6 else 3.6, 1))
  plot(NA, xlim = lim$x, ylim = lim$y, log = "xy", axes = FALSE, xaxs = "i", yaxs = "i",
       xlab = if (narrow) "Peak ALT or AST (x ULN)" else "Peak ALT or AST (x ULN, log scale)",
       ylab = if (narrow) "Peak TBL (x ULN)" else "Peak total bilirubin, TBL (x ULN, log scale)")
  usr <- 10^par("usr")
  rect(3, 2, usr[2], usr[4], col = adjustcolor(pal$sev[["RED"]], .09), border = NA)
  tx <- .tm_log_ticks(lim$x); ty <- .tm_log_ticks(lim$y)
  if (narrow) tx <- tx[tx %in% c(.1, .2, .5, 1, 2, 3, 5, 10, 20, 50, 100)]
  abline(v = tx, h = ty, col = adjustcolor(pal$line, .9), lwd = .7)
  abline(v = 3, h = 2, lty = 2, lwd = 1.3, col = pal$muted)
  axis(1, at = tx, labels = format(tx, drop0trailing = TRUE), col = NA, col.ticks = pal$line)
  axis(2, at = ty, labels = format(ty, drop0trailing = TRUE), col = NA, col.ticks = pal$line)
  box(col = pal$line)
  text(usr[2] / 1.04, usr[4] / 1.06, if (narrow) "Check timing" else "Check the timing", adj = c(1, 1),
       cex = if (narrow) .72 else .8, col = pal$sev[["RED"]], font = 2)
  if (!narrow) {
    text(usr[2] / 1.04, usr[3] * 1.08, "Lower right:\nAT >= 3x, TBL <= 2x", adj = c(1, 0), cex = .74, col = pal$muted)
    text(3 / 1.03, usr[3] * 1.08, "3x ULN", adj = c(1, 0), cex = .72, col = pal$muted)
  }
  text(usr[1] * 1.04, 2 * 1.05, "2x ULN", adj = c(0, 0), cex = .72, col = pal$muted)
  o <- order(match(screen, names(lv)), decreasing = TRUE)        # flagged points drawn last, on top
  points(h$peak_at[o], h$peak_tbl[o], pch = 21, cex = if (narrow) 1.45 else 1.75, lwd = 1.1, col = pal$surface,
         bg = pal$sev[lv[screen[o]]])
  if (length(sel) && sel %in% h$USUBJID) {
    i <- which(h$USUBJID == sel)
    points(h$peak_at[i], h$peak_tbl[i], pch = 21, cex = if (narrow) 2.5 else 2.9, lwd = 2.2, col = pal$accent, bg = NA)
  }
  # labels: the flagged participants and the ringed one (on a phone, only those flagged or ringed)
  lab <- if (narrow) which(screen != "No hepatic flag" | h$USUBJID %in% sel)
         else which(h$peak_at >= 2.5 | h$peak_tbl > 1.5 | h$USUBJID %in% sel)
  # label side: in the left half of the shaded box, to the right (off the 3x line); just under the
  # 2x line, away from it; elsewhere above the point, further out for the ringed one
  x <- h$peak_at[lab]; y <- h$peak_tbl[lab]
  pos <- ifelse(x >= 3 & y > 2 & x < sqrt(3 * usr[2]), 4, ifelse(y < 2 & y > 2 / 1.45, ifelse(x < 3, 2, 1), 3))
  ids <- if (narrow) sub("^CP101-", "", h$USUBJID[lab]) else h$USUBJID[lab]
  if (length(lab)) text(x, y, ids, pos = pos, offset = ifelse(h$USUBJID[lab] %in% sel, 1.25, .8),
                        cex = .78, col = pal$fg)
  .tm_legend_top(names(lv), pal$sev[lv], pal, rows = if (narrow) 2 else 1)
  title(main = if (narrow) "eDISH: peak liver tests" else "eDISH: each participant's peak liver tests", adj = 0,
        line = if (narrow) 3.2 else 2.2, cex.main = 1, font.main = 2)
  invisible(screen)
}

# one participant's liver tests by study day, x ULN
tm_plot_traj <- function(d, id, pal) {
  narrow <- .tm_narrow()
  .tm_par(pal, c(4, if (narrow) 3.4 else 4.2, 3.6, 1))
  yl <- c(0, max(3.4, 1.12 * max(d$xuln, na.rm = TRUE)))
  plot(NA, xlim = range(d$ADY), ylim = yl, axes = FALSE, yaxs = "i", xlab = "Study day", ylab = "x ULN")
  abline(h = pretty(yl), col = pal$line, lwd = .7)
  abline(h = c(2, 3), lty = 2, lwd = 1.2, col = pal$muted)
  usr <- par("usr")
  text(usr[1], 3, if (narrow) " 3x" else " 3x ULN (ALT, AST)", adj = c(0, -.4), cex = .72, col = pal$muted)
  text(usr[1], 2, if (narrow) " 2x" else " 2x ULN (TBL)", adj = c(0, -.4), cex = .72, col = pal$muted)
  axis(1, col = NA, col.ticks = pal$line); axis(2, at = pretty(yl), col = NA, col.ticks = pal$line)
  box(col = pal$line)
  tests <- levels(d$test)
  for (k in tests) {
    s <- d[d$test == k, ]; s <- s[order(s$ADY), ]
    if (nrow(s)) { lines(s$ADY, s$xuln, col = pal$lab[[k]], lwd = 2.1); points(s$ADY, s$xuln, pch = 19, cex = .8, col = pal$lab[[k]]) }
  }
  .tm_legend_top(tests, pal$lab[tests], pal, type = "line")
  title(main = sprintf(if (narrow) "%s: liver tests" else "%s: liver tests by study day", id), adj = 0, line = 2.2,
        cex.main = 1, font.main = 2)
}

# the dose ladder: one bar per cohort at its dose, colored by its level under the rule reference
tm_plot_ladder <- function(d, pal) {
  narrow <- .tm_narrow()
  .tm_par(pal, c(4.6, if (narrow) 3.6 else 4.4, 3.6, 1))
  dosed <- d$N > 0
  top <- max(d$DOSEMG) * 1.22
  mids <- barplot(d$DOSEMG, names.arg = rep("", nrow(d)), col = NA, border = NA, ylim = c(0, top), axes = FALSE,
                  space = .45, xlab = "", ylab = "Dose (mg)")
  abline(h = pretty(c(0, top)), col = pal$line, lwd = .7)
  half <- .5
  rect(mids - half, 0, mids + half, d$DOSEMG, col = ifelse(dosed, adjustcolor(pal$sev[d$sev], .85), NA),
       border = ifelse(dosed, NA, pal$muted), lty = ifelse(dosed, 1, 2), lwd = 1.3)
  axis(2, at = pretty(c(0, top)), col = NA, col.ticks = pal$line)
  mtext(sprintf("%s\n%g mg", d$COHORT, d$DOSEMG), side = 1, at = mids, line = 1.6, cex = .8, col = pal$fg)
  mtext("Cohort and dose", side = 1, line = 3.3, cex = .85, col = pal$fg)
  pend <- ifelse(d$PENDING > 0, sprintf(if (narrow) "\n+%d pending" else " (+%d pending)", d$PENDING), "")
  lab <- ifelse(!dosed, if (narrow) "planned" else "planned, not dosed",
                sprintf(if (narrow) "%d/%d%s" else "%d of %d DLTs%s", d$DLT, d$EVALUABLE, pend))
  text(mids, d$DOSEMG, lab, pos = 3, cex = .8, col = pal$fg, xpd = NA)
  shown <- unique(d$sev[dosed]); shown <- TM_LEVELS[TM_LEVELS %in% shown]
  .tm_legend_top(c(shown, if (narrow) "planned" else "planned, not dosed"), c(adjustcolor(pal$sev[shown], .85), NA), pal,
                 pch = 22, border = c(rep(NA, length(shown)), pal$muted))
  title(main = if (narrow) "DLTs by cohort (3+3 reference)" else "DLTs by cohort against the illustrative 3+3 rule",
        adj = 0, line = 2.2, cex.main = 1, font.main = 2)
  invisible(mids)
}
