# ===========================================================================
# app.R: IRT / RTSM UAT execution and sign-off tracker (Shiny)
#
# A runnable, editable version of the UAT tracker. Select a test and record its result, close a
# defect once its test passes a retest, add a draft test for an untraced requirement, and watch the
# KPIs and the go-live sign-off gate recompute. Operations data only, synthetic, no participant data.
#
# Run:  shiny::runApp("uat_irt/shiny")     (from the package root)
#
# The gate and KPI logic lives in R/logic.R (shared with the Quarto docs and the unit tests); the
# seed data is ../templates/*.csv (edit it to reuse for a study). The app folder carries a copy in
# templates/ so it also runs in the browser under Shinylive, which exports only this folder;
# tests/test-logic.R fails if the two copies differ. Nothing heavy runs at startup: three small
# CSVs are read and every panel is computed from them in well under a second.
#
# First load: every panel has content. RAND-04 (a failing critical test with an open critical
# defect) is selected, so the Selected test card shows something to act on; each empty state
# says why it is empty and what to do. Colors come from the portfolio site's tokens (site.css),
# in light and dark; input_dark_mode() follows the visitor's system setting.
# ===========================================================================
suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(ggplot2)
})
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")  # status, error cards, theme
warm_up_graphics()   # in the browser, load the plot fonts while the launch page still shows its status
source("R/logic.R")

seed <- uat_load()   # ../templates in local R; the bundled templates/ in the browser

DEFAULT_TEST <- "RAND-04"   # selected on first load: failing, critical, with an open critical defect
# Status comes right after ID, so a phone shows the two that matter without scrolling sideways
TEST_COLS    <- c("TestID", "Status", "TestTitle", "Priority", "Area", "RequirementID", "LinkedDefect")
TEST_NAMES   <- c("ID", "Status", "Title", "Priority", "Area", "Requirement", "Defect")
DEFECT_COLS  <- c("DefectID", "Severity", "Status", "FoundInTest", "Description")
PAGE_LEN     <- 10

# bar colors for the area plot; the same hues as the status pills below (light and dark)
STATUS_FILL <- list(
  light = c(Pass = "#2E8B57", Fail = "#C8402F", Blocked = "#D07A1F", `In Progress` = "#3D7FD9", `Not Run` = "#97A3AF"),
  dark  = c(Pass = "#5DBB84", Fail = "#F07A6A", Blocked = "#E9A55A", `In Progress` = "#7DB5FF", `Not Run` = "#76828E"))

n_of <- function(n, one, many = paste0(one, "s")) sprintf("%d %s", n, if (n == 1) one else many)
and_list <- function(x) {
  if (length(x) <= 1) return(paste(x, collapse = ""))
  paste(paste(x[-length(x)], collapse = ", "), "and", x[length(x)])
}
gate_text <- function(g) {
  if (g$go) return("The gate is READY for sign-off.")
  left <- c(if (g$crit_fail) paste(n_of(g$crit_fail, "critical test"), "not passing"),
            if (g$open_cm) n_of(g$open_cm, "open critical or major defect"),
            if (g$unretested) paste(n_of(g$unretested, "closed defect"), "whose test has not passed a retest"),
            if (g$untracked) paste(n_of(g$untracked, "failing test"), "with no open defect"),
            if (g$trace_gap) paste(n_of(g$trace_gap, "requirement"), "without a test"),
            if (g$not_run) paste(n_of(g$not_run, "test"), "not run yet"))
  paste0("The gate is still blocked: ", and_list(left), ".")
}
pill <- function(x) span(class = paste0("uat-pill s-", gsub("[^a-z]", "", tolower(x))), x)
nw   <- function(x) span(class = "uat-nw", x)   # an ID that never breaks at its hyphen
and_ids <- function(ids, last = " and ") {      # and_list() as tags, each ID kept on one line
  n <- length(ids)
  tagList(lapply(seq_len(n), function(k) tagList(nw(ids[k]), if (k < n - 1) ", " else if (k == n - 1) last)))
}

# ---- styles: the site tokens for status colors, a calm header, readable tables -----------------
UAT_CSS <- "
:root{--uat-pass-fg:#1D5E35;--uat-pass-bg:#E3F2E8;--uat-pass-line:#9CCBAD;--uat-pass-fill:#2E8B57;
 --uat-fail-fg:#A1261B;--uat-fail-bg:#FDECEA;--uat-fail-line:#E5A39B;--uat-fail-fill:#C8402F;
 --uat-blocked-fg:#8A3A10;--uat-blocked-bg:#FBEBDF;--uat-blocked-line:#E3B796;--uat-blocked-fill:#D07A1F;
 --uat-progress-fg:#0B4F9C;--uat-progress-bg:#E5EEFA;--uat-progress-line:#A7C3E8;--uat-progress-fill:#3D7FD9;
 --uat-notrun-fg:#4F5B67;--uat-notrun-bg:#EEF1F4;--uat-notrun-line:#D5DBE1;--uat-notrun-fill:#97A3AF;
 --uat-accent:#0757BF;--uat-accent-soft:#E7EFFA;--uat-muted:#4F5B67;--uat-line:#D5DBE1}
[data-bs-theme=dark]{--uat-pass-fg:#93DBAE;--uat-pass-bg:#17301F;--uat-pass-line:#2F6B45;--uat-pass-fill:#5DBB84;
 --uat-fail-fg:#FFB4A9;--uat-fail-bg:#3A1D1A;--uat-fail-line:#7A3A33;--uat-fail-fill:#F07A6A;
 --uat-blocked-fg:#F5B48A;--uat-blocked-bg:#3A2416;--uat-blocked-line:#7A4B2C;--uat-blocked-fill:#E9A55A;
 --uat-progress-fg:#A9CCFF;--uat-progress-bg:#1A2B40;--uat-progress-line:#36557D;--uat-progress-fill:#7DB5FF;
 --uat-notrun-fg:#A9B3BD;--uat-notrun-bg:#212A34;--uat-notrun-line:#323C47;--uat-notrun-fill:#76828E;
 --uat-accent:#7DB5FF;--uat-accent-soft:#1E2B3B;--uat-muted:#A9B3BD;--uat-line:#323C47}
.uat-page{max-width:1640px;padding:14px 18px 28px}
.uat-page .card{margin-bottom:0}
.uat-page .card-header{font-weight:600;display:flex;flex-wrap:wrap;align-items:baseline;gap:2px 12px}
.uat-hint{font-weight:400;font-size:.85rem;color:var(--uat-muted);margin-left:auto}
.uat-page .card-footer{font-size:.85rem;color:var(--uat-muted);background:transparent}
.uat-top{display:flex;flex-wrap:wrap;align-items:center;gap:8px 16px;margin:0 0 12px}
.uat-brand{display:flex;flex-wrap:wrap;align-items:center;gap:4px 10px;margin-right:auto}
.uat-title{font-size:1.3rem;font-weight:700;margin:0;line-height:1.25}
.uat-badge{display:inline-block;font-size:.75rem;font-weight:600;padding:.15rem .55rem;border-radius:999px;
 color:var(--uat-blocked-fg);background:var(--uat-blocked-bg);border:1px solid var(--uat-blocked-line)}
.uat-sub{font-size:.85rem;color:var(--uat-muted)}
.uat-actions{display:flex;flex-wrap:wrap;align-items:center;gap:8px}
.uat-changes{font-size:.85rem;color:var(--uat-muted);margin-right:4px}
.uat-guide{margin-bottom:14px}
.uat-guide .accordion-button{font-weight:600;padding:.65rem 1rem}
.uat-guide .accordion-body{padding:.2rem 1rem .8rem}
.uat-guide .bslib-grid{margin-bottom:0;row-gap:.4rem}
.uat-guide h3{font-size:.95rem;font-weight:700;margin:.4rem 0 .35rem}
.uat-guide p,.uat-guide li{font-size:.9rem;line-height:1.45;margin-bottom:0}
.uat-guide ol{padding-left:1.2em;margin:0}
.uat-guide li{margin-bottom:.2rem}
.uat-legend{display:grid;grid-template-columns:auto 1fr;gap:5px 10px;align-items:baseline;font-size:.88rem;margin:0}
.uat-legend dt{font-weight:600;white-space:nowrap}
.uat-legend dd{margin:0;display:flex;flex-wrap:wrap;align-items:center;gap:3px 4px}
.uat-legend .uat-pill{font-size:.76rem;padding:.02rem .45rem}
.uat-pill{display:inline-block;padding:.08rem .5rem;border-radius:999px;font-size:.8rem;font-weight:600;line-height:1.45;
 white-space:nowrap;border:1px solid var(--uat-notrun-line);color:var(--uat-notrun-fg);background:var(--uat-notrun-bg)}
.s-pass,.s-closed{color:var(--uat-pass-fg);background:var(--uat-pass-bg);border-color:var(--uat-pass-line)}
.s-fail,.s-critical{color:var(--uat-fail-fg);background:var(--uat-fail-bg);border-color:var(--uat-fail-line)}
.s-blocked,.s-open,.s-major{color:var(--uat-blocked-fg);background:var(--uat-blocked-bg);border-color:var(--uat-blocked-line)}
.s-inprogress{color:var(--uat-progress-fg);background:var(--uat-progress-bg);border-color:var(--uat-progress-line)}
.uat-kpis{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px;margin-bottom:14px}
.uat-kpis>.bslib-value-box{margin-bottom:0;border-top:4px solid var(--uat-tone,var(--uat-line))}
.uat-kpis .card-body{padding:0}
.uat-kpis .value-box-area{padding:.6rem .95rem .7rem;gap:0;justify-content:flex-start}
.uat-kpis .value-box-title{font-size:.9rem;font-weight:600;margin-bottom:.1rem}
.uat-kpis .value-box-value{font-size:2rem;font-weight:700;line-height:1.15;margin-bottom:.15rem;color:var(--uat-tone-fg,inherit)}
.uat-kpi-note{font-size:.85rem;color:var(--uat-muted);line-height:1.35}
.tone-total{--uat-tone:var(--uat-accent)}
.tone-pass{--uat-tone:var(--uat-pass-fill);--uat-tone-fg:var(--uat-pass-fg)}
.tone-fail{--uat-tone:var(--uat-fail-fill);--uat-tone-fg:var(--uat-fail-fg)}
.tone-def{--uat-tone:var(--uat-blocked-fill);--uat-tone-fg:var(--uat-blocked-fg)}
.tone-cov{--uat-tone:var(--uat-progress-fill);--uat-tone-fg:var(--uat-progress-fg)}
@media (max-width:1100px){.uat-kpis{grid-template-columns:repeat(3,minmax(0,1fr))}}
@media (max-width:600px){.uat-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.uat-kpis>:last-child{grid-column:span 2}
 .uat-page{padding:10px 10px 24px}.uat-hint{margin-left:0}}
.uat-row{margin-bottom:14px}
.uat-stack{display:flex;flex-direction:column;gap:14px}
/* one column (below bslib's lg breakpoint): the gate first, then the test scripts, the selected
   test right below them, then the plot */
@media (max-width:991.98px){.uat-row>.bslib-grid-item,.uat-row>.bslib-grid-item>.uat-stack{display:contents}
 .uat-row .uat-stack>.card{grid-column:1/-1}
 .uat-c-gate{order:1}.uat-c-tests{order:2}.uat-c-sel{order:3}.uat-c-plot{order:4}}
.uat-page table.dataTable{--dt-row-selected:231,239,250;--dt-row-selected-text:24,33,43;--dt-row-selected-link:7,87,191}
[data-bs-theme=dark] .uat-page table.dataTable{--dt-row-selected:30,43,59;--dt-row-selected-text:230,234,238;--dt-row-selected-link:125,181,255}
.uat-page table.dataTable>tbody>tr.selected>td:first-child{box-shadow:inset 4px 0 0 var(--uat-accent),inset 0 0 0 9999px rgb(var(--dt-row-selected))}
.uat-page table.dataTable>tbody>tr{cursor:pointer}
.uat-page #defects table.dataTable>tbody>tr{cursor:default}
.uat-page table.dataTable{--bs-table-bg:transparent;--bs-table-hover-bg:var(--uat-accent-soft);--bs-table-hover-color:var(--bs-body-color)}
.uat-page table.dataTable thead th{border-bottom:1px solid var(--uat-line)}
.uat-page table.dataTable td,.uat-page table.dataTable th{font-size:.9rem;vertical-align:middle}
.uat-page table.dataTable td.uat-id{font-weight:600;white-space:nowrap}
.uat-page table.dataTable .dt-nowrap{white-space:nowrap}
.uat-page table.dataTable .uat-title-col{min-width:10rem}
.uat-page #defects table.dataTable td:last-child{min-width:14rem}
.uat-page div.dataTables_wrapper div.dataTables_filter{float:none;text-align:left;margin:0}
.uat-page div.dataTables_wrapper div.dataTables_filter label{display:block;width:100%}
.uat-page div.dataTables_wrapper div.dataTables_filter input{margin:0;width:min(24rem,100%);display:block}
.uat-dt-top{margin-bottom:.5rem}
.uat-dt-foot{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:6px 12px;margin-top:.5rem}
.uat-page div.dataTables_wrapper div.dataTables_info{font-size:.85rem;color:var(--uat-muted);padding:0}
.uat-page div.dataTables_wrapper div.dataTables_paginate{margin:0}
.uat-page div.dataTables_wrapper div.dataTables_paginate ul.pagination{margin:0}
.uat-page td.dataTables_empty{color:var(--uat-muted);font-style:normal;padding:1rem}
.uat-link{background:none;border:0;padding:0;font:inherit;color:var(--uat-accent);text-decoration:underline;text-underline-offset:2px;cursor:pointer}
.uat-verdict{border-radius:.5rem;padding:.65rem .85rem;margin-bottom:.7rem;border:1px solid}
.uat-verdict.go{color:var(--uat-pass-fg);background:var(--uat-pass-bg);border-color:var(--uat-pass-line)}
.uat-verdict.no{color:var(--uat-fail-fg);background:var(--uat-fail-bg);border-color:var(--uat-fail-line)}
.uat-verdict-title{font-size:1.15rem;font-weight:700;display:block}
.uat-verdict-detail{font-size:.88rem;display:block}
.uat-crit{display:flex;gap:.6rem;align-items:flex-start;padding:.45rem 0;border-top:1px solid var(--uat-line)}
.uat-crit:first-of-type{border-top:0}
.uat-mark-ok,.uat-mark-no{flex:0 0 1.35rem;height:1.35rem;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;
 font-size:.8rem;font-weight:700;margin-top:.1rem}
.uat-mark-ok{color:var(--uat-pass-fg);background:var(--uat-pass-bg);border:1px solid var(--uat-pass-line)}
.uat-mark-no{color:var(--uat-fail-fg);background:var(--uat-fail-bg);border:1px solid var(--uat-fail-line)}
.uat-crit-title{font-weight:600;font-size:.93rem;line-height:1.35}
.uat-crit-detail{font-size:.86rem;color:var(--uat-muted);line-height:1.4}
.uat-chips{display:flex;flex-wrap:wrap;gap:4px;margin-top:.3rem}
.uat-chip{font-size:.8rem;font-weight:600;padding:.12rem .5rem;border-radius:999px;cursor:pointer;
 color:var(--uat-accent);background:var(--uat-accent-soft);border:1px solid var(--uat-line)}
.uat-chip:hover,.uat-chip:focus-visible{border-color:var(--uat-accent)}
.uat-fine{font-size:.82rem;color:var(--uat-muted);margin:.6rem 0 0;line-height:1.4}
.uat-detail-head{display:flex;flex-wrap:wrap;align-items:center;gap:6px 8px;margin-bottom:.15rem}
.uat-detail-id{font-weight:700;font-size:1.05rem}
.uat-detail-title{font-weight:600;line-height:1.35;margin-bottom:.15rem}
.uat-detail-meta{font-size:.85rem;color:var(--uat-muted);margin-bottom:.5rem}
.uat-detail dl{display:grid;grid-template-columns:auto 1fr;gap:3px 10px;font-size:.88rem;margin:0 0 .6rem}
.uat-detail dt{font-weight:600}
.uat-detail dd{margin:0}
.uat-callout{font-size:.86rem;padding:.4rem .6rem;border-radius:.4rem;margin:0 0 .6rem;color:var(--uat-fail-fg);
 background:var(--uat-fail-bg);border:1px solid var(--uat-fail-line)}
.uat-callout.ok{color:var(--uat-pass-fg);background:var(--uat-pass-bg);border-color:var(--uat-pass-line)}
.uat-label{font-size:.85rem;font-weight:600;margin:.2rem 0 .3rem;display:block}
.uat-mark{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:.7rem}
.uat-mark .btn{font-size:.82rem;padding:.2rem .55rem}
.uat-mark .btn.active{font-weight:700}
.uat-defect{border:1px solid var(--uat-line);border-radius:.45rem;padding:.5rem .65rem;font-size:.88rem}
.uat-defect-head{display:flex;flex-wrap:wrap;gap:4px 6px;align-items:center;margin-bottom:.25rem}
.uat-defect .btn{margin-top:.45rem}
.uat-defect .uat-callout{margin:.45rem 0 0}
.uat-stack-sm{display:flex;flex-direction:column;gap:8px}
.uat-btn{color:var(--bs-body-color);background:var(--bs-tertiary-bg);border:1px solid var(--uat-line)}
.uat-btn:hover,.uat-btn:focus-visible{color:var(--bs-body-color);background:var(--bs-tertiary-bg);border-color:var(--uat-accent)}
.uat-btn-accent{color:var(--uat-accent);border-color:var(--uat-accent)}
.uat-btn-accent:hover{color:var(--uat-accent)}
#shiny-notification-panel .shiny-notification{font-size:.9rem;line-height:1.45;opacity:1;color:var(--bs-body-color);
 background:var(--bs-body-bg);border:1px solid var(--uat-line);border-left:4px solid var(--uat-accent);border-radius:.5rem;
 box-shadow:0 6px 22px rgba(0,0,0,.16)}
#shiny-notification-panel .shiny-notification-warning{border-left-color:var(--uat-blocked-fill)}
#shiny-notification-panel,#shiny-notification-panel .shiny-notification{pointer-events:none}
#shiny-notification-panel .shiny-notification-close{pointer-events:auto}
/* phones: span the screen with an 8px margin; the doubled ID matches bslib's own rule (450px wide) */
@media (max-width:600px){#shiny-notification-panel#shiny-notification-panel{left:8px;right:8px;bottom:8px;width:auto;max-width:none;padding:0}
 #shiny-notification-panel .shiny-notification{font-size:.82rem;padding:.45rem 1.6rem .45rem .7rem;margin-top:6px}}
.uat-nw{white-space:nowrap}
.uat-page table.dataTable .uat-area-col{min-width:7.5rem}
/* the defect Status cell opens its editor on a double-click anywhere in it: DataTables ignores a
   double-click whose target is not the cell itself, so the pill inside lets the pointer through */
.uat-page #defects td.uat-edit{cursor:text}
.uat-page #defects td.uat-edit .uat-pill{pointer-events:none}
.uat-page #tests tbody tr:focus-visible{outline:2px solid var(--uat-accent);outline-offset:-2px}
.uat-swipe{display:none;font-size:.82rem;color:var(--uat-muted);margin:0 0 .45rem}
.uat-defect-note{font-size:.84rem;color:var(--uat-muted);margin-top:.35rem;line-height:1.4}
@media (max-width:600px){.uat-swipe{display:block}.uat-wide{display:none}.uat-changes{flex-basis:100%}}
"

# ---- browser side: the CSV download, and buttons that carry the test or defect they act on ------
UAT_JS <- "
Shiny.addCustomMessageHandler('uat-download', function(m) {
  var url = URL.createObjectURL(new Blob([m.content], {type: m.type}));
  var a = document.createElement('a');
  a.href = url; a.download = m.filename; document.body.appendChild(a); a.click();
  setTimeout(function () { URL.revokeObjectURL(url); a.remove(); }, 1000);
});
$(document).on('click', '[data-uat-test][data-uat-status]', function (e) {
  e.preventDefault();
  Shiny.setInputValue('test_set', {id: this.getAttribute('data-uat-test'), status: this.getAttribute('data-uat-status')}, {priority: 'event'});
});
$(document).on('click', '[data-uat-defect][data-uat-to]', function (e) {
  e.preventDefault();
  Shiny.setInputValue('defect_set', {id: this.getAttribute('data-uat-defect'), to: this.getAttribute('data-uat-to')}, {priority: 'event'});
});
$(document).on('click', '[data-uat-cover]', function (e) {
  e.preventDefault();
  Shiny.setInputValue('cover_gap', this.getAttribute('data-uat-cover'), {priority: 'event'});
});
// DT saves a cell edit when the box loses focus; let Enter save it too
$(document).on('keydown', '#defects td input', function (e) {
  if (e.key === 'Enter') { e.preventDefault(); this.blur(); }
});
$(document).on('click', '[data-uat-jump]', function (e) {
  e.preventDefault(); e.stopPropagation();
  Shiny.setInputValue('jump', this.getAttribute('data-uat-jump'), {priority: 'event'});
  var c = document.getElementById('uat-selected');
  if (c) { var r = c.getBoundingClientRect(); if (r.top < 0 || r.top > window.innerHeight - 80) c.scrollIntoView({behavior: 'smooth', block: 'start'}); }
});
// keyboard: Tab reaches each test row; Enter or Space opens it, as a click does (DataTables
// selects a row on mousedown)
$(document).on('keydown', '#tests tbody tr[tabindex]', function (e) {
  if (e.key !== 'Enter' && e.key !== ' ') return;
  e.preventDefault();
  if (!$(this).hasClass('selected')) $(this).trigger('mousedown');
});
// one column: a row opens the Selected test card just below the table; bring it into view
$(document).on('mousedown', '#tests tbody tr', function () {
  if (!window.matchMedia || !window.matchMedia('(max-width: 991.98px)').matches) return;
  setTimeout(function () {
    var c = document.getElementById('uat-selected');
    if (c && c.getBoundingClientRect().top > window.innerHeight - 120) c.scrollIntoView({behavior: 'smooth', block: 'start'});
  }, 350);
});
// phones: start with the Start here guide closed, so the KPIs and the gate are near the top
$(function () {
  if (!window.matchMedia || !window.matchMedia('(max-width: 600px)').matches) return;
  var c = document.querySelector('#guide .accordion-collapse.show');
  if (!c) return;
  c.classList.remove('show');
  var b = document.querySelector('#guide .accordion-button');
  if (b) { b.classList.add('collapsed'); b.setAttribute('aria-expanded', 'false'); }
});
"

# DT cell renderers: show status and severity as colored pills and test IDs as links; the data
# (which the search and the edits use) stays plain text
PILL_JS <- JS("function (data, type) {
  if (type !== 'display') return data;
  var s = String(data == null ? '' : data);
  var e = s.replace(/[&<>\"']/g, function (c) { return {'&': '&amp;', '<': '&lt;', '>': '&gt;', '\"': '&quot;', \"'\": '&#39;'}[c]; });
  return '<span class=\"uat-pill s-' + s.toLowerCase().replace(/[^a-z]/g, '') + '\">' + e + '</span>';
}")
JUMP_JS <- JS("function (data, type) {
  if (type !== 'display' || !data) return data;
  var s = String(data).replace(/[^A-Za-z0-9_-]/g, '');
  return '<button type=\"button\" class=\"uat-link\" data-uat-jump=\"' + s + '\" title=\"Open ' + s + ' in the Selected test card\">' + s + '</button>';
}")

# DataTables' own scripts normally arrive with the first table's value. When two tables arrive in
# the same update, Shiny starts loading the scripts for the first and lets the second skip them
# without waiting, so under Shinylive (where scripts load more slowly) the second table can start
# before DataTables exists ("$table.DataTable is not a function") and stay empty. Shipping the
# same dependency (same name and version) with the page removes that race.
DT_PRELOAD <- htmltools::attachDependencies(
  tags$span(hidden = NA), DT::datatable(data.frame(x = 1), style = "bootstrap5")$dependencies)

ui <- page_fluid(
  title = "IRT/RTSM UAT tracker (synthetic data)",
  theme = portfolio_theme(),
  class = "uat-page",
  tags$head(tags$style(HTML(UAT_CSS)), tags$script(HTML(UAT_JS))),
  DT_PRELOAD,
  app_status_ui("the KPIs, the test-script table, the sign-off gate, the selected test, the area plot and the defect log"),

  div(class = "uat-top",
      div(class = "uat-brand",
          h1(class = "uat-title", "IRT / RTSM UAT tracker"),
          span(class = "uat-badge", "Synthetic data"),
          span(class = "uat-sub", "Operations data only, no participant data")),
      div(class = "uat-actions",
          span(class = "uat-changes", textOutput("changes", inline = TRUE)),
          # on phones the labels shorten (the .uat-wide words hide) so the three controls share a row
          actionButton("dl_tests", tagList("Download", span(class = "uat-wide", " results"), " (CSV)"),
                       icon = icon("download"), class = "btn-sm uat-btn", title = "Download the test results as a CSV file"),
          actionButton("reset", tagList("Reset", span(class = "uat-wide", " to seed")),
                       icon = icon("rotate-left"), class = "btn-sm uat-btn", title = "Reset to the seed data"),
          input_dark_mode(id = "mode"))),

  accordion(
    id = "guide", open = "start", class = "uat-guide",
    accordion_panel(
      "Start here: what this shows and what to try", value = "start", icon = icon("circle-info"),
      layout_columns(
        col_widths = breakpoints(sm = 12, lg = c(4, 4, 4)), fill = FALSE,
        div(h3("What this shows"),
            p("User acceptance testing (UAT) of an interactive response technology (IRT) system, the software that",
              "randomizes participants and manages trial supply: 29 test scripts traced to 30 requirements, 4 defects,",
              "and a go-live gate that says whether the build is ready for a named person to sign off.",
              "All of it is invented.")),
        div(h3("How to read the colors"),
            tags$dl(class = "uat-legend",
                    tags$dt("Tests"), tags$dd(lapply(STATUSES, pill)),
                    tags$dt("Defects"), tags$dd(pill("Open"), pill("Closed"), span(class = "uat-sub", "severity"),
                                                pill("Critical"), pill("Major"), pill("Minor")),
                    tags$dt("Gate"), tags$dd(span(class = "uat-mark-ok", "\u2713"), "met",
                                             span(class = "uat-mark-no", "\u2715"), "blocking"),
                    tags$dt("Table"), tags$dd("The highlighted row is the selected test."))),
        div(h3("Try this"),
            tags$ol(
              tags$li("RAND-04 failed and its critical defect DEF-01 is open. In the", tags$b("Selected test"),
                      "card, record the retest as Pass, then close DEF-01. A defect closes only after its",
                      "test passes."),
              tags$li("Work down the gate: each ID opens that test. Retest SUP-03 before closing DEF-03, run",
                      "the five tests not run yet, then add a draft test for URS-SUP-005 and run it too.",
                      "With every blocker cleared, the gate turns READY."),
              tags$li("Download the results as a CSV, or Reset to seed.")))))),

  div(class = "uat-kpis",
      value_box("Test scripts", textOutput("v_total", inline = TRUE),
                div(class = "uat-kpi-note", textOutput("v_total_note", inline = TRUE)), class = "tone-total"),
      value_box("Passed", textOutput("v_pass", inline = TRUE),
                div(class = "uat-kpi-note", textOutput("v_pass_note", inline = TRUE)), class = "tone-pass"),
      value_box("Failed", textOutput("v_fail", inline = TRUE),
                div(class = "uat-kpi-note", uiOutput("v_fail_note", inline = TRUE)), class = "tone-fail"),
      value_box("Open defects", textOutput("v_def", inline = TRUE),
                div(class = "uat-kpi-note", textOutput("v_def_note", inline = TRUE)), class = "tone-def"),
      value_box("Requirements traced", textOutput("v_cov", inline = TRUE),
                div(class = "uat-kpi-note", textOutput("v_cov_note", inline = TRUE)), class = "tone-cov")),

  layout_columns(
    col_widths = breakpoints(sm = 12, lg = c(8, 4)), fill = FALSE, class = "uat-row",
    div(class = "uat-stack",
        card(class = "uat-c-tests", fill = FALSE,
             card_header("Test scripts", span(class = "uat-hint", "Click a row (or Tab to it and press Enter) to open it")),
             p(class = "uat-swipe", "Swipe the table sideways for the title, priority, area and requirement."),
             DTOutput("tests", fill = FALSE)),
        card(class = "uat-c-plot", fill = FALSE,
             card_header("Execution by test area", span(class = "uat-hint", "Redraws when you record a result")),
             plotOutput("plot", height = "auto"),
             card_footer("One bar per test area, colored by test status; the label counts the passing scripts."))),
    div(class = "uat-stack",
        card(class = "uat-c-gate", fill = FALSE,
             card_header("Go-live sign-off gate", span(class = "uat-hint", "Click an ID to open it")),
             uiOutput("gate")),
        card(id = "uat-selected", class = "uat-c-sel", fill = FALSE, card_header("Selected test"), uiOutput("detail")))),

  card(class = "uat-row", fill = FALSE,
       card_header("Defect log", span(class = "uat-hint", "Double-click a Status cell to edit it")),
       DTOutput("defects", fill = FALSE),
       card_footer("Type Open or Closed, then press Enter or click elsewhere; or use the button in the Selected test card.",
                   "A defect closes only after the test it was found in passes a retest. Open critical and major",
                   "defects block the gate; a test ID opens that test."))
)

server <- function(input, output, session) {
  rv <- reactiveValues(tests = seed$tests, defects = seed$defects, trace = seed$trace)
  tproxy <- dataTableProxy("tests")
  dproxy <- dataTableProxy("defects")

  gate     <- reactive(uat_gate(rv$tests, rv$defects, rv$trace))
  summ     <- reactive(uat_summary(rv$tests, rv$defects, rv$trace))
  blockers <- reactive(uat_blockers(rv$tests, rv$defects, rv$trace))
  dark     <- reactive(identical(input$mode, "dark"))

  # the selected test: the table's selection once the table is drawn; before that (and in the
  # headless tests) the default, so the Selected test card never starts empty
  selected <- reactive({
    s <- input$tests_rows_selected
    if (length(s)) return(as.integer(s[1]))
    if (is.null(input$tests_rows_all)) return(match(DEFAULT_TEST, rv$tests$TestID))
    NA_integer_
  })

  # a short confirmation of what changed and where the gate stands; it lets clicks through (CSS)
  note <- function(msg, type = "message") showNotification(msg, type = type, duration = 5, id = "uat-note")
  show_tests   <- function() replaceData(tproxy, rv$tests[, TEST_COLS], resetPaging = FALSE, rownames = FALSE, clearSelection = "none")
  show_defects <- function() replaceData(dproxy, rv$defects[, DEFECT_COLS], resetPaging = FALSE, rownames = FALSE, clearSelection = "none")

  # Select a test and page the table to it, so the highlighted row and the Selected test card
  # always agree. The page comes from the table's row list (input$tests_rows_all: data rows in the
  # current order and search). That list is out of date right after rows are added or removed,
  # and lacks a row that a search hides (the search is then cleared, with a note), so in those
  # cases the table is paged once it reports a row list that holds the row (two updates at most).
  pending_row <- reactiveVal(NULL)
  page_to <- function(i) {
    pos <- match(i, isolate(input$tests_rows_all))
    if (is.na(pos)) return(FALSE)
    selectPage(tproxy, (pos - 1) %/% PAGE_LEN + 1)
    TRUE
  }
  clear_search <- function(why) {
    q <- isolate(input$tests_search)
    if (!length(q) || !nzchar(q)) return(FALSE)
    updateSearch(tproxy, keywords = list(global = "", columns = NULL))
    showNotification(sprintf("Cleared the search \u201c%s\u201d %s.", q, why), duration = 5, id = "uat-search")
    TRUE
  }
  select_test <- function(id, rows_changed = FALSE) {
    i <- match(id, rv$tests$TestID)
    if (is.na(i)) return(invisible(FALSE))
    selectRows(tproxy, i)
    if (rows_changed) clear_search(paste("to show", id))   # the new row list must hold the row
    wait <- rows_changed || (!page_to(i) && clear_search(paste("to show", id)))
    pending_row(if (wait) list(row = i, left = 2L) else NULL)
    invisible(TRUE)
  }
  observeEvent(input$tests_rows_all, {
    p <- pending_row()
    if (is.null(p)) return()
    pending_row(if (!page_to(p$row) && p$left > 1L) list(row = p$row, left = p$left - 1L) else NULL)
  }, ignoreInit = TRUE)

  set_test <- function(id, status) {
    i <- match(id, rv$tests$TestID)
    if (is.na(i) || !status %in% STATUSES || identical(rv$tests$Status[i], status)) return(invisible(FALSE))
    old <- rv$tests$Status[i]
    rv$tests$Status[i] <- status
    show_tests()
    # what the new result means for the test's defects, then where the gate stands
    b <- blockers()
    r <- which(rv$defects$FoundInTest == id & rv$defects$Status == "Open")
    nxt <- if (status == "Pass" && length(r)) sprintf("It passed its retest, so %s can now be closed.", and_list(rv$defects$DefectID[r]))
      else if (id %in% b$unretested$FoundInTest)
        sprintf("%s is closed, so its fix no longer counts as retested.", and_list(b$unretested$DefectID[b$unretested$FoundInTest == id]))
      else if (id %in% b$untracked$TestID) "A failing test needs an open defect, and none is logged for it."
    note(paste(c(sprintf("%s: %s to %s.", id, old, status), nxt, gate_text(gate())), collapse = " "))
    invisible(TRUE)
  }
  set_defect <- function(id, to) {
    r <- match(id, rv$defects$DefectID)
    if (is.na(r)) return(invisible(FALSE))
    if (identical(to, "Closed") && !identical(rv$defects$Status[r], "Closed")) {
      cc <- uat_can_close(rv$tests, rv$defects, id)
      if (!cc$ok) {
        show_defects()   # puts back the display after a typed edit
        note(sprintf("%s stays Open: a defect closes only after the test it was found in passes a retest, and %s is %s. Mark %s Pass first.",
                     id, cc$test, if (is.na(cc$status)) "not in the test table" else cc$status, cc$test), type = "warning")
        return(invisible(FALSE))
      }
    }
    if (!identical(rv$defects$Status[r], to)) {
      rv$defects$Status[r] <- to
      note(sprintf("%s is now %s. %s", id, to, gate_text(gate())))
    }
    show_defects()   # also puts back the display after an edit that changed nothing
    invisible(TRUE)
  }

  observeEvent(input$reset, {
    rows_changed <- nrow(rv$tests) != nrow(seed$tests)
    rv$tests <- seed$tests; rv$defects <- seed$defects; rv$trace <- seed$trace
    show_tests(); show_defects(); select_test(DEFAULT_TEST, rows_changed = rows_changed)
    note(sprintf("Back to the seed data: %s and %s. %s", n_of(nrow(seed$tests), "test script"),
                 n_of(nrow(seed$defects), "defect"), gate_text(gate())))
  })

  # ---- header and KPIs ----
  output$changes <- renderText({
    n <- uat_changes(rv$tests, rv$defects, seed)
    if (n == 0) "Seed data, no changes yet" else paste(n_of(n, "change"), "since the seed")
  })
  output$v_total <- renderText(as.character(summ()$total))
  output$v_pass  <- renderText(as.character(summ()$pass))
  output$v_fail  <- renderText(as.character(summ()$fail))
  output$v_def   <- renderText(as.character(summ()$open_def))
  output$v_cov   <- renderText(sprintf("%d%%", summ()$cov))
  output$v_total_note <- renderText({
    s <- summ(); left <- s$total - s$pass
    if (left == 0) "All passing" else paste(left, "not passing yet")
  })
  output$v_pass_note <- renderText({
    s <- summ(); run <- s$pass + s$fail
    if (run == 0) "None executed yet" else sprintf("%d%% of the %d executed", s$pass_rate, run)
  })
  output$v_fail_note <- renderUI({   # the IDs never break at their hyphen
    ids <- rv$tests$TestID[rv$tests$Status == "Fail"]
    if (!length(ids)) return("None failing")
    if (length(ids) > 3) return(tagList(and_ids(ids[1:3], last = ", "), sprintf(" and %d more", length(ids) - 3)))
    and_ids(ids)
  })
  output$v_def_note <- renderText({
    n <- gate()$open_cm
    if (summ()$open_def == 0) "All closed" else if (n == 0) "Minor only: fix or waive" else paste(n, "critical or major")
  })
  output$v_cov_note <- renderText({
    s <- summ()
    if (s$traced == s$n_urs && s$req_run == s$n_urs) sprintf("All %d have a test, all tested", s$n_urs)
    else sprintf("%d of %d have a test; %d tested", s$traced, s$n_urs, s$req_run)
  })

  # ---- test-script table (select a row) ----
  output$tests <- renderDT(guard("the test-script table", {
    isolate({
      d <- rv$tests[, TEST_COLS]
      datatable(
        d, rownames = FALSE, class = "table table-hover table-sm",
        selection = list(mode = "single", selected = match(DEFAULT_TEST, d$TestID), target = "row"),
        colnames = TEST_NAMES,
        options = list(
          pageLength = PAGE_LEN, dom = "<'uat-dt-top'f>t<'uat-dt-foot'ip>", scrollX = TRUE, autoWidth = FALSE,
          # each row is a Tab stop; Enter or Space opens it (UAT_JS). One statement per line, with
          # the closing brace on its own line: formatStyle() below inserts its code before that line
          rowCallback = JS("function (row, data) {",
                           "  $(row).attr({tabindex: 0, title: 'Open ' + data[0] + ' in the Selected test card'});",
                           "}"),
          language = list(
            search = "", searchPlaceholder = "Search tests (ID, status, title, area)",
            zeroRecords = "No test script matches this search. Clear the search box to see all of them.",
            emptyTable = "No test scripts are loaded. Reset to seed to load the 29 seed scripts.",
            info = "Test scripts _START_ to _END_ of _TOTAL_", infoEmpty = "No test scripts",
            infoFiltered = "(searched in _MAX_)"),
          columnDefs = list(   # ID, Status, Title, Priority, Area, Requirement, Defect
            list(targets = 0, className = "uat-id"),
            list(targets = 1, render = PILL_JS, className = "dt-nowrap"),
            list(targets = 2, className = "uat-title-col"),
            list(targets = 4, className = "uat-area-col"),
            list(targets = c(3, 5, 6), className = "dt-nowrap")))) |>
        formatStyle("Priority", fontWeight = styleEqual("Critical", "700"))
    })
  }), server = TRUE)

  # ---- selected test: detail, status buttons, its defect ----
  output$detail <- renderUI(guard("the selected test", {
    i <- selected()
    if (is.na(i) || i > nrow(rv$tests))
      return(empty_state(paste("No test is selected. Click a row in the Test scripts table, or an ID in the gate,",
                               "to see its steps, record its result and close its defect.")))
    t <- rv$tests[i, ]
    b <- blockers()
    # one callout: what this test still needs for the gate (or that it meets it)
    callout <- if (t$Priority == "Critical" && t$Status == "Pass")
      div(class = "uat-callout ok", "Critical test, passing: it meets the gate's first criterion.")
    else if (t$Priority == "Critical")
      div(class = "uat-callout", "Critical test, not passing: the gate stays blocked until it passes.")
    else if (!t$Status %in% RUN_STATUSES)
      div(class = "uat-callout", sprintf("%s: the gate stays blocked until every test has been run (Pass or Fail).",
                                         if (t$Status == "Not Run") "Not run yet" else t$Status))
    else if (t$TestID %in% b$untracked$TestID)
      div(class = "uat-callout", paste("Failing, with no open defect logged: a failure needs one before go-live.",
                                       "This demo cannot raise new defects, so retest it and record Pass to clear the block."))
    # the defects found in this test (or linked to it), each with what can be done with it now
    linked <- if (is.na(t$LinkedDefect)) "" else t$LinkedDefect
    rows <- which(rv$defects$FoundInTest == t$TestID | rv$defects$DefectID == linked)
    defect_box <- function(r) {
      d <- rv$defects[r, ]
      st <- defect_test_status(rv$tests, d)
      if (d$Status == "Open") {
        cc <- uat_can_close(rv$tests, rv$defects, d$DefectID)
        action <- tags$button(type = "button", class = "btn btn-sm btn-primary", disabled = if (!cc$ok) NA,
                              `data-uat-defect` = d$DefectID, `data-uat-to` = "Closed", sprintf("Close %s", d$DefectID))
        why <- if (!cc$ok) div(class = "uat-defect-note",
                              if (identical(cc$test, t$TestID)) sprintf("Close it once %s passes its retest: record the result above.", cc$test)
                              else sprintf("Close it once %s, the test it was found in, passes its retest.", cc$test))
      } else {
        action <- tags$button(type = "button", class = "btn btn-sm uat-btn",
                              `data-uat-defect` = d$DefectID, `data-uat-to` = "Open", sprintf("Reopen %s", d$DefectID))
        why <- if (d$DefectID %in% b$unretested$DefectID)
          div(class = "uat-callout", sprintf("Closed, but %s is %s, so the fix no longer counts as retested and the gate is blocked. Retest %s, or reopen %s.",
                                             d$FoundInTest, if (is.na(st)) "not in the test table" else st, d$FoundInTest, d$DefectID))
      }
      div(class = "uat-defect",
          div(class = "uat-defect-head", tags$b(d$DefectID), pill(d$Severity), pill(d$Status)),
          div(d$Description),
          why, action)
    }
    defects <- if (length(rows)) div(class = "uat-stack-sm", lapply(rows, defect_box))
      else if (nzchar(linked)) div(class = "uat-sub", sprintf("Linked defect %s is not in the defect log.", linked))
      else div(class = "uat-sub", "No defect is logged for this test.")
    div(class = "uat-detail",
        div(class = "uat-detail-head", span(class = "uat-detail-id", t$TestID), pill(t$Status)),
        div(class = "uat-detail-title", t$TestTitle),
        div(class = "uat-detail-meta", sprintf("%s · %s · %s priority", t$Area, t$RequirementID, t$Priority)),
        callout,
        tags$dl(tags$dt("Steps"), tags$dd(t$Steps), tags$dt("Expected"), tags$dd(t$ExpectedResult)),
        span(class = "uat-label", id = "uat-mark-label", sprintf("Record the result of %s", t$TestID)),
        div(class = "uat-mark", role = "group", `aria-labelledby` = "uat-mark-label",
            lapply(STATUSES, function(s) {
              on <- identical(s, t$Status)
              tags$button(type = "button", class = paste("btn btn-sm", if (on) "btn-primary active" else "uat-btn"),
                          `aria-pressed` = if (on) "true" else "false",
                          `data-uat-test` = t$TestID, `data-uat-status` = s, s)
            })),
        span(class = "uat-label", if (length(rows) > 1) "Defects" else "Defect"),
        defects)
  }))
  observeEvent(input$test_set, set_test(input$test_set$id, input$test_set$status))
  observeEvent(input$defect_set, set_defect(input$defect_set$id, input$defect_set$to))
  observeEvent(input$jump, {
    if (!select_test(input$jump)) note(sprintf("%s is not in the test-script table.", input$jump), type = "warning")
  })

  # ---- defect log (edit Status) ----
  output$defects <- renderDT(guard("the defect log", {
    isolate({
      d <- rv$defects[, DEFECT_COLS]
      datatable(
        d, rownames = FALSE, selection = "none", class = "table table-sm",
        editable = list(target = "cell", disable = list(columns = c(0, 1, 3, 4))),
        colnames = c("ID", "Severity", "Status", "Found in", "Description"),
        options = list(
          dom = "t", paging = FALSE, ordering = FALSE, scrollX = TRUE,
          language = list(emptyTable = "No defects are logged. Reset to seed to load the 4 seed defects."),
          columnDefs = list(
            list(targets = 0, className = "uat-id"),
            list(targets = 1, render = PILL_JS, className = "dt-nowrap"),
            list(targets = 2, render = PILL_JS, className = "dt-nowrap uat-edit"),   # the editable one
            list(targets = 3, render = JUMP_JS, className = "dt-nowrap"))))
    })
  }), server = TRUE)
  observeEvent(input$defects_cell_edit, {
    info <- input$defects_cell_edit
    if (info$col + 1L != 3L) return()   # only the Status column is editable
    id <- rv$defects$DefectID[info$row]
    to <- uat_defect_status(info$value)
    if (is.na(to)) {
      show_defects()
      note(sprintf("%s: type Open or Closed. It stays %s.", id, rv$defects$Status[info$row]), type = "warning")
    } else set_defect(id, to)
  })

  # ---- gate ----
  output$gate <- renderUI(guard("the sign-off gate", {
    g <- gate(); b <- blockers()
    n_block <- (!g$tests_ok) + (!g$defects_ok) + (!g$trace_ok)
    minor <- g$minor_open
    chip <- function(id, label) tags$button(type = "button", class = "uat-chip", `data-uat-jump` = id,
                                            title = sprintf("Open %s in the Selected test card", id), label)
    chips <- function(lead, items) if (length(items)) tagList(div(class = "uat-crit-detail", lead), div(class = "uat-chips", items))
    crit <- function(ok, title, met, ...)
      div(class = "uat-crit",
          span(class = if (ok) "uat-mark-ok" else "uat-mark-no", role = "img",
               `aria-label` = if (ok) "met" else "blocking", if (ok) "✓" else "✕"),
          div(div(class = "uat-crit-title", title), if (ok) div(class = "uat-crit-detail", met), ...))
    status_of <- function(x) ifelse(is.na(x), "missing", x)
    div(
      div(class = paste("uat-verdict", if (g$go) "go" else "no"),
          span(class = "uat-verdict-title", g$verdict),
          span(class = "uat-verdict-detail",
               if (g$go) paste0("All three criteria are met. The evidence is ready for a named person to review and sign",
                                if (length(minor)) sprintf(", who must also fix or waive the open minor %s %s with a rationale.",
                                                           if (length(minor) == 1) "defect" else "defects", and_list(minor)) else ".")
               else sprintf("%d of 3 criteria %s blocking. Fix the items below.", n_block, if (n_block == 1) "is" else "are"))),
      crit(g$tests_ok, "Every critical test passes", "All critical tests pass.",
           chips(paste(n_of(g$crit_fail, "critical test"), "not passing:"),
                 Map(function(id, st) chip(id, sprintf("%s (%s)", id, st)), b$tests$TestID, b$tests$Status))),
      crit(g$defects_ok, "No open critical or major defect, and every fix retested",
           paste0("None open, and each closed defect's test passes",
                  if (length(minor)) sprintf(". Open but minor, so not blocking: %s.", and_list(minor)) else "."),
           chips(paste(n_of(g$open_cm, "open defect"), "(the ID opens the test it was found in):"),
                 Map(function(id, sev, test) chip(test, sprintf("%s (%s, %s)", id, sev, test)),
                     b$defects$DefectID, b$defects$Severity, b$defects$FoundInTest)),
           chips(paste(n_of(g$unretested, "defect"), "closed before its test passed a retest:"),
                 Map(function(id, test, st) chip(test, sprintf("%s (%s is %s)", id, test, status_of(st))),
                     b$unretested$DefectID, b$unretested$FoundInTest, b$unretested$TestStatus)),
           chips(paste(n_of(g$untracked, "failing test"), "with no open defect logged:"),
                 lapply(b$untracked$TestID, function(id) chip(id, sprintf("%s (Fail)", id))))),
      crit(g$trace_ok, "Every requirement has a test, and every test has been run",
           sprintf("All %d requirements are traced to a test, and all %d tests have been run.", nrow(rv$trace), nrow(rv$tests)),
           chips(paste(n_of(g$trace_gap, "requirement"), "without a test:"),
                 Map(function(req, desc)
                   tags$button(type = "button", class = "btn btn-sm uat-btn uat-btn-accent", `data-uat-cover` = req,
                               title = desc, sprintf("Add a draft test for %s", req)),
                   b$gaps$RequirementID, b$gaps$RequirementDescription)),
           chips(paste(n_of(g$not_run, "test"), "not run yet:"),
                 Map(function(id, st) chip(id, sprintf("%s (%s)", id, st)), b$not_run$TestID, b$not_run$Status))),
      p(class = "uat-fine", "A named tester or biostatistician signs UAT off. The gate packages the evidence; it does not grant approval."))
  }))
  observeEvent(input$cover_gap, {
    res <- uat_cover_gap(rv$tests, rv$trace, input$cover_gap)
    if (is.na(res$test_id)) return()
    rv$tests <- res$tests; rv$trace <- res$trace
    show_tests(); select_test(res$test_id, rows_changed = TRUE)
    note(sprintf("Added draft test %s (Not Run) for %s: write its steps, then run it. %s",
                 res$test_id, input$cover_gap, gate_text(gate())))
  })

  # ---- area plot ----
  output$plot <- renderPlot(guard("the execution-by-area plot", {
    t <- rv$tests
    explain_empty(nrow(t) > 0, "No test scripts are loaded, so there is nothing to plot. Reset to seed to load them.")
    pal <- STATUS_FILL[[if (dark()) "dark" else "light"]]
    col <- portfolio_colors(dark())
    areas <- unique(t$Area)
    df <- uat_area_counts(t)
    df$Area <- factor(as.character(df$Area), levels = rev(areas))
    a <- factor(t$Area, levels = rev(areas))
    lab <- data.frame(Area = factor(levels(a), levels = levels(a)),
                      n = as.integer(table(a)), pass = as.integer(tapply(t$Status == "Pass", a, sum)))
    narrow <- isTRUE(session$clientData$output_plot_width < 560)   # phones: shorter labels, wrapped areas
    lab$text <- if (narrow) sprintf("%d/%d", lab$pass, lab$n) else sprintf("%d of %d passed", lab$pass, lab$n)
    wrap <- function(x) vapply(x, function(z) paste(strwrap(z, if (narrow) 16 else 40), collapse = "\n"), "")
    ggplot(df, aes(Freq, Area, fill = Status)) +
      geom_col(width = 0.68, colour = col$surface, linewidth = 0.5, show.legend = TRUE) +
      geom_text(data = lab, aes(x = n, y = Area, label = text), inherit.aes = FALSE,
                hjust = 0, nudge_x = 0.12, size = if (narrow) 3.2 else 3.6, colour = col$muted) +
      scale_fill_manual(values = pal, limits = STATUSES, drop = FALSE, name = NULL) +
      scale_y_discrete(labels = wrap) +
      guides(fill = guide_legend(nrow = if (narrow) 2 else 1)) +
      scale_x_continuous(breaks = function(l) seq(0, max(1, floor(l[2])), by = if (l[2] > 12) 2 else 1),
                         expand = expansion(mult = c(0, 0.42))) +
      labs(x = "Test scripts", y = NULL) +
      theme_minimal(base_size = if (narrow) 11 else 13) +
      theme(legend.position = "top", legend.justification = "left", legend.location = "plot",
            legend.margin = margin(0, 0, 0, 0),
            legend.text = element_text(colour = col$text, size = if (narrow) 9.5 else 11),
            plot.background = element_rect(fill = col$surface, colour = NA),
            panel.background = element_rect(fill = col$surface, colour = NA),
            text = element_text(colour = col$text),
            axis.text = element_text(colour = col$muted),
            axis.text.y = element_text(colour = col$text, size = if (narrow) 9.5 else 11.5, lineheight = 0.9),
            axis.title.x = element_text(colour = col$muted, size = 11, margin = margin(t = 6)),
            panel.grid.major.y = element_blank(),
            panel.grid.major.x = element_line(colour = col$line, linewidth = 0.4),
            panel.grid.minor = element_blank(),
            plot.margin = margin(4, 8, 4, 4))
  }), res = 96, height = function() if (isTRUE(session$clientData$output_plot_width < 560)) 450 else 330,
  alt = reactive({
    s <- summ()
    sprintf("Bar chart of test status by test area: %d of %d test scripts passed, %d failed.", s$pass, s$total, s$fail)
  }))

  # client-side download: R builds the CSV text and the browser saves it, so the button also
  # works under Shinylive (a downloadHandler request there can miss the service worker)
  dl_payload <- reactiveVal(NULL)
  observeEvent(input$dl_tests, {
    con <- textConnection(NULL, "w", local = TRUE)
    utils::write.csv(rv$tests, con, row.names = FALSE)
    csv <- textConnectionValue(con); close(con)
    p <- list(filename = "SYNTHETIC_uat_test_results.csv", type = "text/csv",
              content = paste0(paste(csv, collapse = "\n"), "\n"))
    dl_payload(p)
    session$sendCustomMessage("uat-download", p)
    note(sprintf("Saved SYNTHETIC_uat_test_results.csv: %s with their current status.", n_of(nrow(rv$tests), "test script")))
  })
}

shinyApp(ui, server)
