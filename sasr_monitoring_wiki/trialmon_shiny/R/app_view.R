# ---------------------------------------------------------------------------
# app_view.R: how the TRIALMON console looks, on SYNTHETIC data. The four review levels and the
# liver tests as site tones, the page CSS and its few lines of JavaScript, the level chips, the
# "Start here" card, small table helpers and the three plots. No screening rule lives here: those
# are in logic.R (the color legend is built from its WORKLIST_RULES).
#
# Needs portfolio_app.R first (bp_palette(), bp_tones and the CSS variables of bp_theme_head(): the
# site's tokens, generated from assets/theme/tokens.css) and logic.R before start_here_ui() is
# called. Uses shiny tags and base graphics only. No color is written here: each level names a
# site tone, and build_pages.py --check fails on a color literal.
#
# Why plain CSS over the precompiled Bootstrap theme, and base graphics: in the browser (webR),
# a custom bslib theme is compiled with Sass every time the app starts (about 0.6 s on a fast
# laptop, measured 2026-10-25) and loading ggplot2 takes about 0.65 s more, before any result
# shows. Bootstrap 5.3 reads its colors from CSS variables, so the site tokens restyle the
# precompiled theme at no cost, and the three plots draw in base graphics, which R has loaded
# already.
# ---------------------------------------------------------------------------

TM_LEVELS <- c("RED", "AMBER", "watch", "GREEN")     # worst first, as the worklist ranks them

# the site tone of each review level, and of each liver test in the plots
TM_TONE <- c(RED = "red", AMBER = "amber", watch = "blue", GREEN = "green")
TM_LAB_TONE <- c(ALT = "blue", AST = "violet", ALP = "neutral", TBL = "orange")

# the four review levels: fg for text, bg and line for the chips, from the tones (build_pages.py
# checks fg at 4.5:1 or better on the chip and on every page surface, in both themes). Delayed:
# Shiny sources R/ by itself before app.R runs, so this file can load before portfolio_app.R has
# defined bp_tones.
delayedAssign("TM_SEV", lapply(c(light = "light", dark = "dark"), function(m)
  lapply(TM_TONE, function(t) bp_tones[[m]][[t]][c("fg", "bg", "line")])))

# what each level asks of the reviewer (the Start here card); the rules that give each level
# come from WORKLIST_RULES in logic.R, so the legend lists every rule that can fire
TM_LEVEL_HEAD <- c(RED = "review now", AMBER = "confirm or look closer", watch = "the lowest flag",
                   GREEN = "no flag")
tm_level_text <- function(level) {
  rules <- unique(WORKLIST_RULES$phrase[WORKLIST_RULES$sev == level])
  switch(level,
    watch = sprintf("%s; it still counts in the roll-up.", paste(rules, collapse = ", ")),
    GREEN = "nothing above fired.",
    paste0(paste(rules, collapse = ", "), "."))
}

# colors for plots: the site tokens, the level fills and one fill per liver test
tm_palette <- function(dark = FALSE) {
  k <- bp_palette(if (isTRUE(dark)) "dark" else "light")
  fill <- function(tones) vapply(tones, function(t) k$tone[[t]][["fill"]], "")
  list(fg = k$text, muted = k$muted, line = k$line_2, surface = k$surface, accent = k$accent,
       sev = fill(TM_TONE), lab = fill(TM_LAB_TONE))
}

# ---- page CSS ---------------------------------------------------------------------------------
# The console's names for the site tokens (CSS variables from bp_theme_head()), then its own rules.
tm_css <- function() {
  sev <- paste(vapply(names(TM_TONE), function(l) sprintf("--tm-%s:var(--tone-%s-fg);--tm-%s-bg:var(--tone-%s-bg);--tm-%s-line:var(--tone-%s-line);",
                                                          l, TM_TONE[[l]], l, TM_TONE[[l]], l, TM_TONE[[l]]), ""), collapse = "")
  paste0(
    "html{--tm-bg:var(--bg);--tm-surface:var(--surface);--tm-surface2:var(--surface-2);--tm-text:var(--text);",
    "--tm-ink:var(--ink);--tm-muted:var(--muted);--tm-line:var(--line-2);--tm-accent:var(--accent);",
    "--tm-accent-text:var(--accent-ink);--tm-sans:var(--sans);--tm-mono:var(--mono);", sev, "}\n", TM_CSS_RULES)
}

TM_CSS_RULES <- "
.bslib-page-title{font-size:1.15rem;font-weight:700}
.tm-title{font-size:1rem;font-weight:400;line-height:1.5;margin:0}
.nav-tabs .nav-link{padding:.5rem .7rem;white-space:nowrap}
@media (max-width:1399.98px){.nav-tabs .nav-link{padding:.45rem .5rem;font-size:.92rem}}
@media (max-width:575.98px){.nav-tabs .nav-link{padding:.4rem .55rem;font-size:.9rem}}
.form-label,.control-label{font-weight:600;font-size:.9rem}
table.dataTable,.shiny-table{font-size:.9rem}
table.dataTable caption,.dataTables_wrapper caption,.tm-table caption{caption-side:bottom;font-size:.82rem;color:var(--tm-muted);padding:.4rem 0 0}
table.dataTable thead th,.shiny-table thead th{font-size:.8rem;font-weight:700;color:var(--tm-muted);vertical-align:bottom}
table.dataTable td.dt-right,table.dataTable th.dt-right,.tm-table .tm-num{text-align:right}
#worklist table.dataTable tbody tr{cursor:pointer}
#study_tbl td:first-child,#qtc_tbl td:first-child,#liver_tbl td:first-child,#worklist td:nth-child(2){white-space:nowrap}
.tm-check{display:block;font-weight:600}.tm-rule{display:block;font-size:.8rem;color:var(--tm-muted);line-height:1.3}
.bslib-sidebar-layout>.sidebar hr{margin:.9rem 0 .6rem}.bslib-sidebar-layout>.sidebar h6{font-weight:700;margin-bottom:.4rem}
.dataTables_wrapper .dataTables_paginate{font-size:.85rem}
.sev{display:inline-block;font-weight:700;font-size:.78rem;letter-spacing:.02em;line-height:1.3;padding:.08rem .5rem;
 border-radius:999px;border:1px solid;white-space:nowrap;vertical-align:baseline}
.sev-RED{color:var(--tm-RED);background:var(--tm-RED-bg);border-color:var(--tm-RED-line)}
.sev-AMBER{color:var(--tm-AMBER);background:var(--tm-AMBER-bg);border-color:var(--tm-AMBER-line)}
.sev-watch{color:var(--tm-watch);background:var(--tm-watch-bg);border-color:var(--tm-watch-line)}
.sev-GREEN{color:var(--tm-GREEN);background:var(--tm-GREEN-bg);border-color:var(--tm-GREEN-line)}
.tm-whatif{display:inline-block;font-size:.72rem;font-weight:700;color:var(--tm-accent-text);border:1px dashed var(--tm-accent);border-radius:999px;padding:0 .45rem;margin-left:.3rem}
.tm-kpis-wrap{container-type:inline-size;margin:0 0 .9rem}
.tm-kpis{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:.5rem}
.tm-kpi{grid-column:span 3}.tm-kpi.kpi-tier{grid-column:span 4}
@container (min-width:760px){.tm-kpis{grid-template-columns:repeat(7,minmax(0,1fr))}.tm-kpi,.tm-kpi.kpi-tier{grid-column:auto}}
@container (max-width:479.98px){.tm-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.tm-kpi,.tm-kpi.kpi-tier{grid-column:auto}
 .tm-kpi:first-child{grid-column:1/-1}.tm-kpi .v{font-size:1.25rem}}
.tm-kpi{border:1px solid var(--tm-line);border-left:4px solid var(--tm-line);border-radius:.5rem;padding:.45rem .65rem .5rem;background:var(--tm-surface);min-width:0}
.tm-kpi .k{font-size:.78rem;font-weight:600;color:var(--tm-muted);line-height:1.25}
.tm-kpi .k .nw{white-space:nowrap}
.tm-kpi .v{font-size:1.45rem;font-weight:700;line-height:1.35;min-height:1.95rem}
.tm-kpi .c{font-size:.74rem;color:var(--tm-muted);line-height:1.25}
.tm-kpi .v .sev{font-size:1.3rem;padding:0;border:0;background:none;letter-spacing:0}
.tm-kpi:has(.v .sev-RED),.tm-kpi.kpi-RED{border-left-color:var(--tm-RED)}
.tm-kpi:has(.v .sev-AMBER),.tm-kpi.kpi-AMBER{border-left-color:var(--tm-AMBER)}
.tm-kpi:has(.v .sev-watch),.tm-kpi.kpi-watch{border-left-color:var(--tm-watch)}
.tm-kpi:has(.v .sev-GREEN),.tm-kpi.kpi-GREEN{border-left-color:var(--tm-GREEN)}
.tm-kpi.kpi-RED .v{color:var(--tm-RED)}.tm-kpi.kpi-AMBER .v{color:var(--tm-AMBER)}.tm-kpi.kpi-watch .v{color:var(--tm-watch)}
.tm-start{background:var(--tm-surface);border:1px solid var(--tm-line);border-left:4px solid var(--tm-accent);border-radius:.5rem;margin:0 0 .8rem}
.tm-start>summary{display:flex;flex-wrap:wrap;align-items:baseline;column-gap:.5rem;list-style:none;cursor:pointer;padding:.55rem .9rem;line-height:1.5}
.tm-start>summary::-webkit-details-marker{display:none}
.tm-start>summary::before{content:'';flex:none;width:0;height:0;border-style:solid;border-width:.3rem 0 .3rem .48rem;
 border-color:transparent transparent transparent currentColor;align-self:center;transition:transform .15s}
.tm-start[open]>summary::before{transform:rotate(90deg)}
.tm-start>summary:focus-visible{outline:3px solid var(--tm-accent);outline-offset:2px;border-radius:.4rem}
.tm-start .t{font-weight:700;font-size:1rem;order:1}
.tm-start .s{color:var(--tm-muted);font-size:.88rem;order:2;flex:1 1 14rem;min-width:0}
.tm-start .tog{order:3;margin-left:auto;font-size:.82rem;font-weight:600;color:var(--tm-accent-text)}
.tm-start .tog:after{content:'Show'}.tm-start[open] .tog:after{content:'Hide'}
@media (max-width:575.98px){.tm-start .s{order:4;flex-basis:100%;font-size:.84rem;line-height:1.4}}
.tm-start-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:.2rem 1.3rem;padding:0 .95rem .55rem}
@media (min-width:1100px){.tm-start-grid{grid-template-columns:minmax(0,.74fr) minmax(0,1.3fr) minmax(0,1.04fr)}}
.tm-start h3{font:600 .72rem/1.3 var(--tm-mono);text-transform:uppercase;letter-spacing:.08em;color:var(--tm-muted);margin:.3rem 0 .3rem}
.tm-start p,.tm-start li{font-size:.83rem;line-height:1.38}
.tm-start p{margin:0 0 .35rem}
.tm-start ol{margin:0;padding-left:1.15rem}.tm-start ol li{margin:0 0 .25rem}
.tm-legend{list-style:none;margin:0;padding:0}.tm-legend li{margin:0 0 .2rem;display:flex;gap:.45rem;align-items:baseline}
.tm-legend .sev{min-width:4rem;text-align:center;flex:none}
.tm-legend .h{font-weight:600}
.tm-hint{font-size:.88rem;color:var(--tm-muted);margin:.1rem 0 .5rem}
.tm-hint strong{color:var(--tm-text)}
.tm-status{font-size:.88rem;color:var(--tm-muted);margin:.1rem 0 .5rem;line-height:1.45}
.tm-status strong{color:var(--tm-text)}
.tm-status strong,.tm-plot-note strong,.shiny-notification strong{white-space:nowrap}
.tm-status .btn-link{font-size:inherit;vertical-align:baseline;padding:0;border:0}
#shiny-notification-panel .shiny-notification{font-size:.9rem}
.shiny-notification-close{color:var(--tm-muted)}.shiny-notification-action a{font-weight:600}
.packet dl{margin:.4rem 0 0}.packet dt{font:600 .72rem/1.3 var(--tm-mono);margin-top:.5rem;text-transform:uppercase;letter-spacing:.08em;color:var(--tm-muted)}
.packet dd{margin:0}
.packet-head{font-weight:700;font-size:.98rem}
.packet .note{font-style:italic;margin:.5rem 0 0;padding:.4rem .6rem;border-left:3px solid var(--tm-line);color:var(--tm-muted)}
.foot{font-size:.85rem;color:var(--tm-muted)}
.tm-plot-note{font-size:.85rem;color:var(--tm-muted);margin:.25rem 0 .75rem}
.tm-plot-note strong{color:var(--tm-text)}
.tm-soc{font-weight:700}.tm-pt{padding-left:1.25rem;display:inline-block}
.tm-footer{font-size:.8rem;color:var(--tm-muted);margin:1rem 0 .25rem}
#grid_tbl{flex:0 0 auto!important;height:auto!important}
#grid_tbl td:nth-child(-n+2),#grid_tbl td:nth-child(16),#grid_tbl thead tr:last-child th{white-space:nowrap}
#grid_tbl td:nth-child(17),#grid_tbl td:nth-child(18){min-width:12rem}
#grid_tbl thead th[rowspan]{vertical-align:bottom}#grid_tbl th.tm-ref{min-width:8.5rem}
table.dataTable td.tm-ref,table.dataTable th.tm-ref{border-left:3px solid var(--tm-AMBER)!important;font-style:italic}
#ae_tbl td:not(:first-child),#ae_tbl th:not(:first-child),#qtc_cat td:not(:first-child),#shift td,#qtc_tbl td{white-space:nowrap}
#ae_tbl td:first-child{min-width:11rem}
.tm-xscroll{overflow-x:auto;max-width:100%}
.tm-xhint{display:none;font-size:.8rem;color:var(--tm-muted);margin:.15rem 0 .35rem}
.tm-xhint:before{content:'\\2194';margin-right:.35rem;color:var(--tm-accent-text);font-weight:700}
.tm-wide.tm-overflow .tm-xhint{display:block}
.tm-more-right{-webkit-mask-image:linear-gradient(90deg,black calc(100% - 3rem),rgba(0,0,0,.22));mask-image:linear-gradient(90deg,black calc(100% - 3rem),rgba(0,0,0,.22))}
.tm-more-left{-webkit-mask-image:linear-gradient(90deg,rgba(0,0,0,.22),black 3rem);mask-image:linear-gradient(90deg,rgba(0,0,0,.22),black 3rem)}
.tm-more-left.tm-more-right{-webkit-mask-image:linear-gradient(90deg,rgba(0,0,0,.22),black 3rem,black calc(100% - 3rem),rgba(0,0,0,.22));
 mask-image:linear-gradient(90deg,rgba(0,0,0,.22),black 3rem,black calc(100% - 3rem),rgba(0,0,0,.22))}
.tm-table{width:100%}.tm-table td,.tm-table th{vertical-align:top}
.tm-stack-only{display:none}
@media (max-width:575.98px){
 #worklist table.dataTable thead{display:none}
 #worklist table.dataTable,#worklist table.dataTable tbody{display:block;width:100%!important}
 #worklist table.dataTable tbody tr{display:grid;grid-template-columns:auto minmax(0,1fr) auto;
  grid-template-areas:'lvl id tier' 'scr scr scr' 'fnd fnd fnd';column-gap:.55rem;row-gap:.2rem;padding:.6rem .55rem;
  border-bottom:1px solid var(--tm-line)}
 #worklist table.dataTable tbody tr>td{display:block;padding:0!important;border:0!important;box-shadow:none!important;background:none!important;min-width:0}
 #worklist table.dataTable tbody tr.odd{background:rgba(var(--bs-emphasis-color-rgb),.035)}
 #worklist table.dataTable tbody tr.selected{background:rgb(var(--dt-row-selected));box-shadow:inset 3px 0 0 var(--tm-accent)}
 #worklist table.dataTable tbody tr.selected>td{color:var(--tm-ink)!important}
 #worklist table.dataTable tbody tr.selected .tm-rule{color:inherit}
 #worklist td:nth-child(1){grid-area:tier;color:var(--tm-muted);font-size:.78rem;align-self:center}
 #worklist tr.selected td:nth-child(1){color:inherit}
 #worklist td:nth-child(2){grid-area:id;font-weight:700;align-self:center}
 #worklist td:nth-child(3){grid-area:lvl;align-self:center}
 #worklist td:nth-child(4){grid-area:scr}
 #worklist td:nth-child(5){grid-area:fnd;font-size:.84rem}
 table.tm-stack thead{display:none}
 table.tm-stack,table.tm-stack tbody{display:block;width:100%}
 table.tm-stack tr{display:grid;grid-template-columns:repeat(var(--tm-stack-cols,3),minmax(0,1fr));gap:.35rem .7rem;padding:.6rem .45rem;border-bottom:1px solid var(--tm-line)}
 table.tm-stack tr:nth-child(odd){background:rgba(var(--bs-emphasis-color-rgb),.035)}
 table.tm-stack td{display:block;border:0;padding:0;box-shadow:none!important;background:none!important;text-align:left!important;min-width:0}
 table.tm-stack td::before{content:attr(data-label);display:block;font-size:.72rem;font-weight:600;color:var(--tm-muted);line-height:1.2;
  white-space:nowrap;overflow-wrap:normal}
 table.tm-stack td.tm-stack-head{grid-column:1/-1;font-weight:700;font-size:.95rem}
 table.tm-stack td.tm-stack-head::before{content:none}
 table.tm-stack td.tm-stack-wide{grid-column:1/-1}
 table.tm-stack td.tm-stack-hide{display:none}
 table.tm-stack .tm-stack-only{display:inline}
}
"

# ---- a few lines of JavaScript ----------------------------------------------------------------
# A wide table gets a fade on the side it continues and a "scroll sideways" line above it, but only
# while it is wider than its card (checked after every update, tab switch, resize and scroll).
TM_JS <- "
(function () {
  function mark() {
    document.querySelectorAll('.tm-wide').forEach(function (w) {
      var any = false;
      w.querySelectorAll('.dataTables_scrollBody, .tm-xscroll').forEach(function (s) {
        if (!s.offsetWidth) return;
        var over = s.scrollWidth > s.clientWidth + 2;
        var t = s.classList.contains('dataTables_scrollBody') ? (s.closest('.dataTables_scroll') || s) : s;
        t.classList.toggle('tm-more-right', over && s.scrollLeft + s.clientWidth < s.scrollWidth - 2);
        t.classList.toggle('tm-more-left', over && s.scrollLeft > 2);
        if (over) any = true;
      });
      w.classList.toggle('tm-overflow', any);
    });
  }
  var timer; function soon() { clearTimeout(timer); timer = setTimeout(mark, 120); }
  document.addEventListener('scroll', function (e) {
    var t = e.target; if (t && t.classList && (t.classList.contains('dataTables_scrollBody') || t.classList.contains('tm-xscroll'))) mark();
  }, true);
  window.addEventListener('resize', soon);
  document.addEventListener('DOMContentLoaded', function () {
    if (window.jQuery) jQuery(document).on('shiny:value shown.bs.tab draw.dt', soon);
    if (window.ResizeObserver) new ResizeObserver(soon).observe(document.body);
    soon();
  });
  window.tmShowPacket = function () {
    var p = document.querySelector('#packet .packet') || document.getElementById('pid');
    if (p) p.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
})();"

# the Start here card opens on a visitor's first visit (folded on a phone) and starts folded after
# that, unless they opened it last time; the choice is kept in this browser only (localStorage)
TM_START_JS <- paste0(
  "(function(){var d=document.currentScript.parentNode,k='trialmon-start-here',v=null;",
  "try{v=localStorage.getItem(k)}catch(e){}",
  "if(window.innerWidth<576||v==='closed'||v==='seen')d.removeAttribute('open');",
  "try{if(v===null)localStorage.setItem(k,'seen')}catch(e){}",
  "var u=false;d.querySelector('summary').addEventListener('click',function(){u=true;});",   # the visitor's own clicks only
  "d.addEventListener('toggle',function(){if(!u)return;u=false;try{localStorage.setItem(k,d.open?'open':'closed')}catch(e){}});})();")

# ---- small UI pieces ---------------------------------------------------------------------------
sev_span <- function(s) span(class = paste0("sev sev-", s), s)

# the same chip as HTML text, for DT columns and table cells
sev_html <- function(s) sprintf('<span class="sev sev-%s">%s</span>', s, s)

tm_esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

# one decimal, always shown ("4.0", not "4"); empty for a missing value
tm_f1 <- function(x) ifelse(is.na(x), "", sprintf("%.1f", x))

kpi <- function(label, value, caption, level = NULL, tier = FALSE)
  div(class = paste(c("tm-kpi", if (tier) "kpi-tier", if (length(level)) paste0("kpi-", level)), collapse = " "),
      div(class = "k", label), div(class = "v", value), div(class = "c", caption))

# a table wider than a phone: a "scroll sideways" line that shows only while it is wider than its card
tm_wide <- function(..., hint = TRUE)
  div(class = "tm-wide", if (hint) p(class = "tm-xhint", "Wider than the screen: scroll the table sideways for more columns."), ...)
tm_xscroll <- function(...) div(class = "tm-xscroll", ...)

# the "Try this" steps, the same four as on the launch page (apps/trialmon/launch.json)
TM_TRY <- list(
  HTML("<strong>Click CP101-004's row</strong> (the first AMBER) in the worklist: the sidebar packet switches to it."),
  HTML(paste("Open <strong>Liver (eDISH)</strong>: two points sit in the shaded box. Click CP101-014 (potential Hy's",
             "Law), then CP101-004 (TBL peaked 18 days before its ALT: not Hy's Law) and compare.")),
  HTML("Set <strong>Lab grading</strong> to v5.0: CP101-013's neutrophils become grade 3 and AMBER goes from 7 to 8."),
  HTML("On <strong>Study tier</strong>, set an indicator to RED: the study tier turns RED; Reset to the feed undoes it."))

start_here_ui <- function(n_dosed, cohort_text) {
  tags$details(
    class = "tm-start", open = NA,
    tags$summary(span(class = "t", "Start here"),
                 span(class = "s", sprintf("what this console shows, what the colors mean, %s things to try",
                                           c("one", "two", "three", "four", "five")[length(TM_TRY)])),
                 span(class = "tog", `aria-hidden` = "true")),
    tags$script(HTML(TM_START_JS)),
    div(class = "tm-start-grid",
      div(tags$h3("What it shows"),
          p(sprintf(paste("Synthetic first-in-human multiple ascending dose study CP-101 at its Cohort 4 (120 mg)",
                          "data cut: %d dosed participants in %s."), n_dosed, cohort_text),
            "Flags roll up worst-of into the boxes below and the ranked worklist; the tabs show the evidence.",
            "The console flags; the Safety Review Committee decides.")),
      div(tags$h3("What the colors mean"),
          tags$ul(class = "tm-legend", lapply(TM_LEVELS, function(l)
            tags$li(sev_span(l), span(span(class = "h", paste0(TM_LEVEL_HEAD[[l]], ":")), " ", tm_level_text(l))))),
          p(class = "mt-1 mb-0", "Worst-of: one RED makes its tier and the overall level RED.")),
      div(tags$h3("Try this"), tags$ol(lapply(TM_TRY, tags$li)))))
}

# an HTML table that turns into one small card per row on a phone (each cell labeled with its
# column name): `html` columns already hold safe HTML, `head` is the card's title cell, `wide`
# cells take a whole line, `hide` cells are left out of the card (their content is in the head),
# and `labels` gives a card label shorter than its column name
tm_stack_table <- function(df, html = character(), head = NULL, wide = character(), hide = character(),
                           cols = 3, caption = NULL, labels = character()) {
  num <- names(df)[vapply(df, is.numeric, logical(1))]
  cls <- function(n) paste(c(if (n %in% num) "tm-num", if (identical(n, head)) "tm-stack-head",
                             if (n %in% wide) "tm-stack-wide", if (n %in% hide) "tm-stack-hide"), collapse = " ")
  cell <- function(v, n) if (n %in% html) HTML(v) else if (is.na(v)) "" else format(v)
  tags$table(class = "table shiny-table table-striped table-hover spacing-s tm-table tm-stack",
             style = sprintf("--tm-stack-cols:%d", cols),
    if (length(caption)) tags$caption(caption),
    tags$thead(tags$tr(lapply(names(df), function(n) tags$th(class = if (n %in% num) "tm-num", n)))),
    tags$tbody(lapply(seq_len(nrow(df)), function(i) tags$tr(lapply(names(df), function(n)
      tags$td(`data-label` = if (n %in% names(labels)) labels[[n]] else n, class = cls(n), cell(df[[n]][[i]], n)))))))
}

# ---- plots (base graphics) ---------------------------------------------------------------------
# Every word a plot writes is placed in device inches by the helpers below, which pick the longest
# wording that fits the device (a phone, the eDISH column on a laptop, a wide screen) and record
# each text box. Each plot returns those boxes (attribute "boxes"), so the tests can check that no
# text leaves the device or covers another label.
.tm_par <- function(pal, mar) par(mar = mar, fg = pal$line, col.axis = pal$muted, col.lab = pal$fg,
                                  col.main = pal$fg, las = 1, mgp = c(2.7, .55, 0), tcl = -.25, cex.axis = .85,
                                  cex.lab = .92, family = "sans", xpd = FALSE)

.tm_recorder <- function() {
  b <- list()
  list(add = function(kind, label, x0, x1, y0, y1)
         b[[length(b) + 1]] <<- data.frame(kind = kind, label = label, x0 = x0, x1 = x1, y0 = y0, y1 = y1,
                                           stringsAsFactors = FALSE),
       get = function() if (length(b)) do.call(rbind, b)
                        else data.frame(kind = character(), label = character(), x0 = numeric(), x1 = numeric(),
                                        y0 = numeric(), y1 = numeric()))
}

# width and height of a label in inches (height with room for descenders)
.tm_wh <- function(label, cex, font = 1) {
  w <- strwidth(label, "inches", cex = cex, font = font)
  h <- strheight(label, "inches", cex = cex, font = font) + .28 * strheight("M", "inches", cex = cex, font = font)
  c(w, h)
}
.tm_lh <- function() par("csi") * par("mex")     # one margin line, in inches
.tm_plt <- function() c(grconvertX(0:1, "npc", "inches"), grconvertY(0:1, "npc", "inches"))   # x0 x1 y0 y1
.tm_fits <- function(label, cex, font, width) .tm_wh(label, cex, font)[1] <= width

# the first of the candidate wordings that fits the width (the last one if none does)
.tm_pick <- function(cands, cex, font, width) {
  for (s in cands) if (.tm_fits(s, cex, font, width)) return(s)
  cands[[length(cands)]]
}

# draw a label whose box has its left edge at x0 and its bottom at y0 (inches), and record the box;
# `halo` paints the plot background behind it, so a grid or reference line under it stays readable
.tm_put <- function(rec, kind, label, x0, y0, cex, col, font = 1, srt = 0, halo = NULL) {
  wh <- .tm_wh(label, cex, font)
  w <- if (srt == 90) wh[2] else wh[1]; h <- if (srt == 90) wh[1] else wh[2]
  op <- par(xpd = NA); on.exit(par(op))
  ux <- function(v) grconvertX(v, "inches", "user"); uy <- function(v) grconvertY(v, "inches", "user")
  if (length(halo)) rect(ux(x0 - .02), uy(y0), ux(x0 + w + .02), uy(y0 + h), col = adjustcolor(halo, .82), border = NA)
  text(ux(x0 + w / 2), uy(y0 + h / 2), label, adj = c(.5, .5), cex = cex, col = col, font = font, srt = srt)
  rec$add(kind, label, x0, x0 + w, y0, y0 + h)
  invisible(c(x0, x0 + w, y0, y0 + h))
}

# the title at the top left of the figure, above the legend
.tm_title <- function(rec, label, x0, cex = 1) {
  wh <- .tm_wh(label, cex, 2)
  .tm_put(rec, "title", label, x0, dev.size("in")[2] - .06 - wh[2], cex, par("col.main"), font = 2)
}

# legend items laid out left to right in rows that wrap at the device's right edge, as evenly as
# the width allows (two and two rather than three and one)
.tm_legend_rows <- function(labels, x0, x1, cex = .82, sym = .2) {
  w <- vapply(labels, function(l) sym + .07 + .tm_wh(l, cex)[1], 0) + .2
  row <- integer(length(w)); x <- x0; r <- 1
  for (i in seq_along(w)) { if (x > x0 && x + w[i] - .2 > x1) { r <- r + 1; x <- x0 }; row[i] <- r; x <- x + w[i] }
  if (max(row) > 1) {
    even <- ceiling(seq_along(w) / ceiling(length(w) / max(row)))
    if (max(even) == max(row) && all(tapply(w, even, sum) - .2 <= x1 - x0)) row <- even
  }
  list(row = row, w = w, n = max(row), h = .tm_wh("Ag", cex)[2] + .05)
}
.tm_legend_draw <- function(rec, labels, cols, lay, x0, top, pal, type = "point", border = NULL, cex = .82, sym = .2) {
  op <- par(xpd = NA); on.exit(par(op))
  x <- x0; r <- 1
  for (i in seq_along(labels)) {
    if (lay$row[i] != r) { r <- lay$row[i]; x <- x0 }
    yc <- top - (r - .5) * lay$h
    ux <- function(v) grconvertX(v, "inches", "user"); uy <- function(v) grconvertY(v, "inches", "user")
    if (type == "line") segments(ux(x), uy(yc), ux(x + sym), uy(yc), col = cols[i], lwd = 2.2)
    else if (type == "box") rect(ux(x + .02), uy(yc - .06), ux(x + sym - .02), uy(yc + .06), col = cols[i],
                                 border = if (length(border) && !is.na(border[i])) border[i] else NA, lty = if (is.na(cols[i])) 2 else 1)
    else points(ux(x + sym / 2), uy(yc), pch = 21, cex = 1.35, lwd = 1.1, col = pal$surface, bg = cols[i])
    wh <- .tm_wh(labels[i], cex)
    .tm_put(rec, "legend", labels[i], x + sym + .07, yc - wh[2] / 2, cex, pal$fg)
    x <- x + lay$w[i]
  }
}

# the top margin (lines) for a title and a legend of `rows` rows
.tm_top_mar <- function(rows, title_cex = 1, cex = .82) {
  inch <- .06 + .tm_wh("Ag", title_cex, 2)[2] + .08 + rows * (.tm_wh("Ag", cex)[2] + .05) + .1
  inch / .tm_lh()
}

.tm_log_ticks <- function(lim) {
  t <- c(.05, .1, .2, .3, .5, 1, 2, 3, 5, 10, 20, 30, 50, 100)
  t[t >= lim[1] & t <= lim[2]]
}

# overlap area of box a with each row of the boxes matrix b (columns x0 x1 y0 y1), inches^2
.tm_overlap <- function(a, b) {
  if (!length(b) || !nrow(b)) return(0)
  pmax(0, pmin(a[2], b[, 2]) - pmax(a[1], b[, 1])) * pmax(0, pmin(a[4], b[, 4]) - pmax(a[3], b[, 3]))
}

# place point labels where they cover no point, no other label and no annotation, inside the
# plotting region, and clearly nearer their own point than any other. Points `want` get a label: `need`
# ones always (at the least-bad place), the others only where one fits cleanly
.tm_place_labels <- function(rec, px, py, r, ids, want, need, obst, region, cex, col, lines = NULL, halo = NULL) {
  pts <- cbind(px - r, px + r, py - r, py + r)
  placed <- matrix(numeric(0), ncol = 4)
  idx <- which(want); idx <- idx[order(!need[idx])]
  for (i in idx) {
    wh <- .tm_wh(ids[i], cex); w <- wh[1]; h <- wh[2]; g <- .035; d <- r[i] + g; q <- r[i] * .72 + g
    cand <- rbind(c(px[i] + d, py[i] - h / 2), c(px[i] - d - w, py[i] - h / 2),            # right, left
                  c(px[i] - w / 2, py[i] + d), c(px[i] - w / 2, py[i] - d - h),            # above, below
                  c(px[i] + q, py[i] + q), c(px[i] + q, py[i] - q - h),                    # the diagonals
                  c(px[i] - q - w, py[i] + q), c(px[i] - q - w, py[i] - q - h),
                  c(px[i] + d, py[i] - h * .15), c(px[i] + d, py[i] - h * .85),            # right, raised or lowered
                  c(px[i] - d - w, py[i] - h * .15), c(px[i] - d - w, py[i] - h * .85),    # left, raised or lowered
                  c(px[i] - r[i], py[i] + d), c(px[i] + r[i] - w, py[i] + d),              # above, to one side
                  c(px[i] - r[i], py[i] - d - h), c(px[i] + r[i] - w, py[i] - d - h))      # below, to one side
    score <- vapply(seq_len(nrow(cand)), function(k) {
      bx <- c(cand[k, 1], cand[k, 1] + w, cand[k, 2], cand[k, 2] + h)
      out <- (max(0, region[1] - bx[1]) + max(0, bx[2] - region[2])) * h +
             (max(0, region[3] - bx[3]) + max(0, bx[4] - region[4])) * w
      hit <- sum(.tm_overlap(bx, pts[-i, , drop = FALSE])) + sum(.tm_overlap(bx, placed)) + sum(.tm_overlap(bx, obst)) + out
      # the gap from the label to each point's edge: the label must sit clearly nearer its own point
      gap <- sqrt(pmax(bx[1] - px, 0, px - bx[2])^2 + pmax(bx[3] - py, 0, py - bx[4])^2) - r
      near <- if (length(px) > 1 && min(gap[-i]) < gap[i] + .07) .5 else 0
      cross <- if (length(lines)) sum(bx[1] < lines$x & bx[2] > lines$x) + sum(bx[3] < lines$y & bx[4] > lines$y) else 0
      1000 * hit + near + .3 * cross + .001 * k
    }, 0)
    k <- which.min(score)
    if (!need[i] && score[k] >= .5) next
    placed <- rbind(placed, .tm_put(rec, "label", ids[i], cand[k, 1], cand[k, 2], cex, col, halo = halo))
  }
}

# eDISH: peak ALT or AST against peak TBL, x ULN, log scales; `sel` is ringed
tm_plot_edish <- function(h, lim, pal, sel = NULL) {
  rec <- .tm_recorder()
  screen <- ifelse(h$hys, "Potential Hy's Law", ifelse(!is.na(h$at3x_day), "AT > 3x ULN: confirm", "No hepatic flag"))
  lv <- c("Potential Hy's Law" = "RED", "AT > 3x ULN: confirm" = "AMBER", "No hepatic flag" = "GREEN")
  W <- dev.size("in")[1]
  narrow <- W < 4                                         # a phone: short IDs and a compact layout
  left <- if (narrow) 3.4 else 4.4
  x0 <- left * .tm_lh(); x1 <- W - .08
  leg_long <- names(lv); leg_short <- c("Hy's Law", "AT > 3x ULN", "No flag")
  lay <- .tm_legend_rows(leg_long, x0, x1)
  leg <- leg_long
  if (lay$n > 1) { lay2 <- .tm_legend_rows(leg_short, x0, x1); if (lay2$n < lay$n) { leg <- leg_short; lay <- lay2 } }
  title_txt <- .tm_pick(c("eDISH: each participant's peak liver tests", "eDISH: peak liver tests", "eDISH"), 1, 2, x1 - x0)
  .tm_par(pal, c(3.9, left, .tm_top_mar(lay$n), 1))
  plot(NA, xlim = lim$x, ylim = lim$y, log = "xy", axes = FALSE, xaxs = "i", yaxs = "i", xlab = "", ylab = "")
  usr <- 10^par("usr"); reg <- .tm_plt()
  rect(3, 2, usr[2], usr[4], col = adjustcolor(pal$sev[["RED"]], .09), border = NA)
  tx <- .tm_log_ticks(lim$x); ty <- .tm_log_ticks(lim$y)
  if (narrow) tx <- tx[tx %in% c(.1, .2, .5, 1, 2, 3, 5, 10, 20, 50, 100)]
  abline(v = tx, h = ty, col = adjustcolor(pal$line, .9), lwd = .7)
  abline(v = 3, h = 2, lty = 2, lwd = 1.3, col = pal$muted)
  axis(1, at = tx, labels = format(tx, drop0trailing = TRUE), col = NA, col.ticks = pal$line)
  axis(2, at = ty, labels = format(ty, drop0trailing = TRUE), col = NA, col.ticks = pal$line)
  box(col = pal$line)
  xl <- .tm_pick(c("Peak ALT or AST (x ULN, log scale)", "Peak ALT or AST (x ULN)"), .92, 1, reg[2] - reg[1])
  wh <- .tm_wh(xl, .92); .tm_put(rec, "axis", xl, (reg[1] + reg[2] - wh[1]) / 2, reg[3] - 2.55 * .tm_lh() - wh[2] / 2, .92, pal$fg)
  yl <- .tm_pick(c("Peak total bilirubin, TBL (x ULN, log scale)", "Peak TBL (x ULN, log scale)", "Peak TBL (x ULN)"),
                 .92, 1, reg[4] - reg[3])
  wh <- .tm_wh(yl, .92); .tm_put(rec, "axis", yl, reg[1] - (left - .75) * .tm_lh() - wh[2] / 2, (reg[3] + reg[4] - wh[1]) / 2, .92, pal$fg, srt = 90)
  # annotations, each only where it fits: the shaded box's prompt clear of the 3x line, the
  # lower-right quadrant's meaning, and the two reference-line labels
  x3 <- grconvertX(3, "user", "inches"); y2 <- grconvertY(2, "user", "inches")
  rec$add("ref", "3x ULN line", x3, x3, reg[3], reg[4])            # not text: lets the tests check the box prompt
  r_pt <- .375 * (if (narrow) 1.45 else 1.75) * par("ps") / 72
  pts <- cbind(grconvertX(h$peak_at, "user", "inches"), grconvertY(h$peak_tbl, "user", "inches"))
  ptbox <- cbind(pts[, 1] - r_pt, pts[, 1] + r_pt, pts[, 2] - r_pt, pts[, 2] + r_pt)
  ann <- matrix(numeric(0), ncol = 4)
  room <- reg[2] - .07 - (x3 + .07)
  for (s in list(list("Check the timing", .8), list("Check timing", .74), list("Check\ntiming", .72))) {
    wh <- .tm_wh(s[[1]], s[[2]], 2)
    if (wh[1] <= room || identical(s[[1]], "Check\ntiming")) {
      ann <- rbind(ann, .tm_put(rec, "note", s[[1]], reg[2] - .07 - wh[1], reg[4] - .06 - wh[2], s[[2]], pal$sev[["RED"]], font = 2))
      break
    }
  }
  try_note <- function(label, x0, y0, cex) {
    wh <- .tm_wh(label, cex); bx <- c(x0, x0 + wh[1], y0, y0 + wh[2])
    if (bx[1] < reg[1] + .03 || bx[2] > reg[2] - .03 || sum(.tm_overlap(bx, rbind(ptbox, ann))) > 0) return(invisible(NULL))
    ann <<- rbind(ann, .tm_put(rec, "note", label, x0, y0, cex, pal$muted))
  }
  lr <- "Lower right:\nAT >= 3x, TBL <= 2x"; wh <- .tm_wh(lr, .74)
  if (reg[2] - .07 - wh[1] > x3 + .07) try_note(lr, reg[2] - .07 - wh[1], reg[3] + .06, .74)
  wh <- .tm_wh("3x ULN", .72); try_note("3x ULN", x3 - .05 - wh[1], reg[3] + .06, .72)
  try_note("2x ULN", reg[1] + .05, y2 + .03, .72)
  o <- order(match(screen, names(lv)), decreasing = TRUE)        # flagged points drawn last, on top
  points(h$peak_at[o], h$peak_tbl[o], pch = 21, cex = if (narrow) 1.45 else 1.75, lwd = 1.1, col = pal$surface,
         bg = pal$sev[lv[screen[o]]])
  ring <- .375 * (if (narrow) 2.5 else 2.9) * par("ps") / 72
  is_sel <- h$USUBJID %in% sel
  if (any(is_sel)) points(h$peak_at[is_sel], h$peak_tbl[is_sel], pch = 21, cex = if (narrow) 2.5 else 2.9, lwd = 2.2,
                          col = pal$accent, bg = NA)
  # labels: every flagged participant and the ringed one; the others near the lines only where they fit
  need <- screen != "No hepatic flag" | is_sel
  want <- need | h$peak_at >= 2 | h$peak_tbl > 1.25
  ids <- if (narrow) sub("^CP101-", "", h$USUBJID) else h$USUBJID
  .tm_place_labels(rec, pts[, 1], pts[, 2], ifelse(is_sel, ring, r_pt), ids, want, need,
                   ann, reg + c(.02, -.02, .02, -.02), .78, pal$fg, lines = list(x = x3, y = y2), halo = pal$surface)
  .tm_title(rec, title_txt, x0)
  .tm_legend_draw(rec, leg, pal$sev[lv], lay, x0, rec$get()$y0[rec$get()$kind == "title"] - .08, pal)
  structure(screen, boxes = rec$get())
}

# one participant's liver tests by study day, x ULN
tm_plot_traj <- function(d, id, pal) {
  rec <- .tm_recorder()
  W <- dev.size("in")[1]; narrow <- W < 4
  left <- if (narrow) 3.2 else 4
  x0 <- left * .tm_lh(); x1 <- W - .08
  tests <- levels(d$test)
  lay <- .tm_legend_rows(tests, x0, x1, sym = .3)
  title_txt <- .tm_pick(c(sprintf("%s: liver tests by study day", id), sprintf("%s: liver tests", id), id), 1, 2, x1 - x0)
  .tm_par(pal, c(3.6, left, .tm_top_mar(lay$n), 1))
  yl <- c(0, max(3.4, 1.12 * max(d$xuln, na.rm = TRUE)))
  plot(NA, xlim = range(d$ADY), ylim = yl, axes = FALSE, yaxs = "i", xlab = "", ylab = "")
  reg <- .tm_plt()
  abline(h = pretty(yl), col = pal$line, lwd = .7)
  abline(h = c(2, 3), lty = 2, lwd = 1.2, col = pal$muted)
  for (ref in list(list(3, c("3x ULN (ALT, AST)", "3x")), list(2, c("2x ULN (TBL)", "2x")))) {
    lab <- if (narrow) ref[[2]][2] else ref[[2]][1]
    .tm_put(rec, "note", lab, reg[1] + .05, grconvertY(ref[[1]], "user", "inches") + .02, .72, pal$muted)
  }
  axis(1, col = NA, col.ticks = pal$line); axis(2, at = pretty(yl), col = NA, col.ticks = pal$line)
  box(col = pal$line)
  wh <- .tm_wh("Study day", .92); .tm_put(rec, "axis", "Study day", (reg[1] + reg[2] - wh[1]) / 2, reg[3] - 2.3 * .tm_lh() - wh[2] / 2, .92, pal$fg)
  wh <- .tm_wh("x ULN", .92); .tm_put(rec, "axis", "x ULN", reg[1] - (left - .8) * .tm_lh() - wh[2] / 2, (reg[3] + reg[4] - wh[1]) / 2, .92, pal$fg, srt = 90)
  for (k in tests) {
    s <- d[d$test == k, ]; s <- s[order(s$ADY), ]
    if (nrow(s)) { lines(s$ADY, s$xuln, col = pal$lab[[k]], lwd = 2.1); points(s$ADY, s$xuln, pch = 19, cex = .8, col = pal$lab[[k]]) }
  }
  .tm_title(rec, title_txt, x0)
  .tm_legend_draw(rec, tests, pal$lab[tests], lay, x0, rec$get()$y0[rec$get()$kind == "title"] - .08, pal, type = "line", sym = .3)
  invisible(structure(tests, boxes = rec$get()))
}

# the dose ladder: one bar per cohort at its dose, colored by its level under the rule reference
tm_plot_ladder <- function(d, pal) {
  rec <- .tm_recorder()
  WH <- dev.size("in"); W <- WH[1]; narrow <- W < 4
  left <- if (narrow) 3.6 else 4.4; bottom <- 4.6
  x0 <- left * .tm_lh(); x1 <- W - .08
  dosed <- d$N > 0; n <- nrow(d)
  shown <- TM_LEVELS[TM_LEVELS %in% unique(d$sev[dosed])]
  leg <- c(shown, "planned, not dosed")
  lay <- .tm_legend_rows(leg, x0, x1)
  if (lay$n > 1) { leg[length(leg)] <- "planned"; lay <- .tm_legend_rows(leg, x0, x1) }
  title_txt <- .tm_pick(c("DLTs by cohort against the illustrative 3+3 rule", "DLTs by cohort (3+3 rule reference)",
                          "DLTs by cohort"), 1, 2, x1 - x0)
  topmar <- .tm_top_mar(lay$n)
  # geometry before plotting: bar i spans [.45 + 1.45 (i - 1), + 1] in x; the slot is the room each
  # bar has for its labels, and the y range leaves room above every bar for its label
  mids <- .95 + 1.45 * (seq_len(n) - 1); xlim <- c(0, 1.45 * n + .45)
  reg_w <- W - (left + 1) * .tm_lh(); reg_h <- WH[2] - (bottom + topmar) * .tm_lh()
  slot <- 1.2 * reg_w / diff(xlim)                 # the bar and most of the gaps beside it
  labs <- vapply(seq_len(n), function(i) {
    p <- d$PENDING[i]
    cands <- if (!dosed[i]) c("planned, not dosed", "planned\nnot dosed", "planned")
      else if (p > 0) c(sprintf("%d of %d DLTs (+%d pending)", d$DLT[i], d$EVALUABLE[i], p),
                        sprintf("%d of %d DLTs\n+%d pending", d$DLT[i], d$EVALUABLE[i], p),
                        sprintf("%d/%d\n+%d pending", d$DLT[i], d$EVALUABLE[i], p),
                        sprintf("%d/%d\n+%d\npending", d$DLT[i], d$EVALUABLE[i], p))
      else c(sprintf("%d of %d DLTs", d$DLT[i], d$EVALUABLE[i]), sprintf("%d/%d", d$DLT[i], d$EVALUABLE[i]))
    .tm_pick(cands, .8, 1, slot)
  }, "")
  lab_h <- vapply(labs, function(l) .tm_wh(l, .8)[2], 0)
  top <- max(max(d$DOSEMG) * 1.12, d$DOSEMG * reg_h / pmax(reg_h - .1 - lab_h, .2 * reg_h))
  .tm_par(pal, c(bottom, left, topmar, 1))
  plot.new(); plot.window(xlim = xlim, ylim = c(0, top), xaxs = "i", yaxs = "i")
  reg <- .tm_plt()
  abline(h = pretty(c(0, top)), col = pal$line, lwd = .7)
  rect(mids - .5, 0, mids + .5, d$DOSEMG, col = ifelse(dosed, adjustcolor(pal$sev[d$sev], .85), NA),
       border = ifelse(dosed, NA, pal$muted), lty = ifelse(dosed, 1, 2), lwd = 1.3)
  axis(2, at = pretty(c(0, top)), col = NA, col.ticks = pal$line)
  box(col = pal$line, bty = "l")
  mx <- grconvertX(mids, "user", "inches")
  with_mg <- all(vapply(sprintf("%g mg", d$DOSEMG), .tm_fits, logical(1), cex = .8, font = 1, width = slot))
  xlab <- if (with_mg) sprintf("%s\n%g mg", d$COHORT, d$DOSEMG) else sprintf("%s\n%g", d$COHORT, d$DOSEMG)
  for (i in seq_len(n)) {
    wh <- .tm_wh(xlab[i], .8)
    .tm_put(rec, "xlab", xlab[i], mx[i] - wh[1] / 2, reg[3] - .08 - wh[2], .8, pal$fg)
  }
  at <- if (with_mg) "Cohort and dose" else "Cohort and dose (mg)"
  wh <- .tm_wh(at, .85)
  .tm_put(rec, "axis", at, (reg[1] + reg[2] - wh[1]) / 2, reg[3] - .14 - .tm_wh("C1\n10", .8)[2] - wh[2], .85, pal$fg)
  wh <- .tm_wh("Dose (mg)", .92)
  .tm_put(rec, "axis", "Dose (mg)", reg[1] - (left - .75) * .tm_lh() - wh[2] / 2, (reg[3] + reg[4] - wh[1]) / 2, .92, pal$fg, srt = 90)
  for (i in seq_len(n)) {
    wh <- .tm_wh(labs[i], .8)
    .tm_put(rec, "bar", labs[i], mx[i] - wh[1] / 2, grconvertY(d$DOSEMG[i], "user", "inches") + .04, .8, pal$fg)
  }
  .tm_title(rec, title_txt, x0)
  .tm_legend_draw(rec, leg, c(adjustcolor(pal$sev[shown], .85), NA), lay, x0,
                  rec$get()$y0[rec$get()$kind == "title"] - .08, pal, type = "box", border = c(rep(NA, length(shown)), pal$muted))
  invisible(structure(mids, boxes = rec$get()))
}
