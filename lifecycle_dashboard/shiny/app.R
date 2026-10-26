# ===========================================================================
# app.R - Study Lifecycle Monitor (Shiny)
#
# A runnable, editable operational study-lifecycle console for a synthetic portfolio of eight
# studies: KPIs, a portfolio risk heatmap, ranked early-warning signals, and the selected study's
# score breakdown, milestone track, TLF funnel, deliverables register and open-query trend. The
# scoring is transparent: a what-if on one study's open queries or double programming moves its
# risk where you can see it. No PHI, no participant-level data. Synthetic, deterministic.
#
# Run:  shiny::runApp("lifecycle_dashboard/shiny")
# Data: data/*.csv (regenerate with Rscript R/gen_data.R, or swap in a CTMS export).
# Runs in the browser under Shinylive too: the data sit in data/ inside this folder, and every
# panel except the two charts is plain HTML, so the first results arrive quickly and follow the
# light or dark setting without redrawing.
# ===========================================================================
suppressPackageStartupMessages({ library(shiny); library(bslib); library(ggplot2) })
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")  # status, error cards, theme
warm_up_graphics()   # in the browser, load the plot fonts while the launch page still shows its status
source("R/logic.R")
if (!file.exists("data/studies.csv")) { source("R/gen_data.R"); gen_portfolio("data") }
seed <- lifecycle_load("data")
# the study selected when the app opens: CP-108 (the planted at-risk study), or the first study
# when the data have no CP-108, for example a CTMS export
OPEN_ID <- if ("CP-108" %in% seed$studies$id) "CP-108" else sort(seed$studies$id)[1]
S0 <- seed$studies[seed$studies$id == OPEN_ID, ][1, ]
AS_OF <- lifecycle_as_of(seed)

MS_ORDER <- c("Protocol", "SAP", "FPFV", "LPLV", "DBL", "TLFs", "CSR")
STATUS_LABEL <- c(done = "Done", wip = "In progress", risk = "Overdue", todo = "Planned")
STATUS_SHAPE <- c(done = 16, wip = 18, risk = 17, todo = 1)
# the site tone of each milestone status, and of the selected study's line in the query trend
STATUS_TONE <- c(done = "green", wip = "blue", risk = "red", todo = "neutral")
STUDY_TONE <- "violet"
tone_fill <- function(tones, mode) vapply(tones, function(t) bp_tones[[mode]][[t]][["fill"]], "")
RAG_WORD <- c(red = "At risk", amber = "Watch", green = "On track")
SEV_WORD <- c(red = "Red", amber = "Amber")

day_fmt  <- function(x) sub("^0", "", format(as.Date(x), "%d %b %Y"))
lock_fmt <- function(days) if (is.na(days)) "-" else if (days > 0) sprintf("in %d d", days) else
  if (days == 0) "today" else sprintf("%d d ago", -days)
# the picker shows the id and the design (the phase is in the heatmap), so the label fits the sidebar
study_label <- function(s) sprintf("%s \u00b7 %s", s$id, sub(" study$", "", s$name))
DIM_SHORT <- c(Timeline = "Time", Data = "Data", TLF = "TLF", Resource = "Res.")   # heatmap headers on a phone
STUDY_CHOICES <- local({
  s <- seed$studies[order(seed$studies$id), ]
  stats::setNames(s$id, vapply(seq_len(nrow(s)), function(j) study_label(s[j, ]), ""))
})
chip <- function(tone, text, ...) tags$span(class = paste("lc-chip", tone), text, ...)

# ---- styles: the site's tokens (CSS variables from bp_theme_head() in portfolio_app.R, generated
# from assets/theme/tokens.css) on the precompiled Bootstrap 5 theme, plus this app's RAG levels as
# site tones. A custom bslib theme would compile Bootstrap's Sass when the page is served, which in
# the browser (webR) adds about 0.9 s to every start; this needs no compiling at all.
LC_CSS <- "
html{--lc-surface:var(--surface);--lc-soft:var(--accent-soft);--lc-tile-text:var(--ink);
 --lc-red-fg:var(--tone-red-fg);--lc-red-bg:var(--tone-red-bg);--lc-red-line:var(--tone-red-line);--lc-red-tile:var(--tone-red-tile);--lc-red-fill:var(--tone-red-fill);
 --lc-amb-fg:var(--tone-amber-fg);--lc-amb-bg:var(--tone-amber-bg);--lc-amb-line:var(--tone-amber-line);--lc-amb-tile:var(--tone-amber-tile);--lc-amb-fill:var(--tone-amber-fill);
 --lc-grn-fg:var(--tone-green-fg);--lc-grn-bg:var(--tone-green-bg);--lc-grn-line:var(--tone-green-line);--lc-grn-tile:var(--tone-green-tile);--lc-grn-fill:var(--tone-green-fill);
 --lc-what:var(--tone-violet-fg);--lc-what-line:var(--tone-violet-line);--lc-what-bg:var(--tone-violet-bg)}
body{font-size:.95rem}
.bslib-page-sidebar>.navbar{border-bottom:1px solid var(--bs-border-color);background:var(--lc-surface)}
.bslib-sidebar-layout{--_sidebar-bg:var(--lc-surface);--bslib-sidebar-bg:var(--lc-surface)}
.lc-title{display:flex;flex-wrap:wrap;align-items:center;gap:.35rem .75rem;width:100%}
.lc-title h1{font-size:1.15rem;font-weight:700;margin:0}
.lc-asof{color:var(--bs-secondary-color);font-size:.85rem}
.lc-mode{margin-left:auto}
.lc-chip{display:inline-block;font-size:.75rem;font-weight:700;line-height:1.3;padding:.1rem .5rem;border-radius:999px;
 border:1px solid;white-space:nowrap;vertical-align:.08em}
.lc-chip.red{color:var(--lc-red-fg);background:var(--lc-red-bg);border-color:var(--lc-red-line)}
.lc-chip.amber{color:var(--lc-amb-fg);background:var(--lc-amb-bg);border-color:var(--lc-amb-line)}
.lc-chip.green{color:var(--lc-grn-fg);background:var(--lc-grn-bg);border-color:var(--lc-grn-line)}
.lc-chip.whatif{color:var(--lc-what);background:var(--lc-what-bg);border-color:var(--lc-what-line)}
.card-header{font-weight:600}
.lc-sub{display:block;font-weight:400;font-size:.82rem;color:var(--bs-secondary-color)}
.lc-start .accordion-button{font-weight:700;padding:.65rem 1rem}
.lc-start .accordion-body{padding:.3rem 1rem .5rem;font-size:.9rem}
.lc-start .bslib-grid{margin-bottom:0}
.lc-start h2{font-size:.8rem;text-transform:uppercase;letter-spacing:.04em;color:var(--bs-secondary-color);margin:.35rem 0 .3rem}
.lc-start p,.lc-start ul,.lc-start ol{margin:0 0 .3rem}
.lc-start ul{list-style:none;padding:0}.lc-start li{margin:0 0 .25rem}.lc-start ol{padding-left:1.2rem}
.lc-key li{display:flex;gap:.45rem;align-items:baseline}
.lc-phone-only{display:none;font-weight:600}@media (max-width:575.98px){.lc-phone-only{display:block}}.lc-key .lc-chip{flex:0 0 4.4rem;text-align:center}
.bslib-sidebar-layout>.sidebar>.sidebar-content{gap:.55rem}
#study{font-size:.85rem}
.lc-kpi .value-box-title{font-size:.85rem;font-weight:600;margin-bottom:.1rem;color:var(--bs-secondary-color)}
.lc-kpi .value-box-value{font-size:1.9rem;font-weight:700;line-height:1.15;margin-bottom:.1rem}
.bslib-value-box.lc-kpi>.card-body{padding:0}
.bslib-value-box.lc-kpi .value-box-area{padding:.7rem 1rem .75rem;justify-content:flex-start}
.lc-kpi .lc-kpi-sub{font-size:.8rem;color:var(--bs-secondary-color);margin:0;line-height:1.3}
.lc-kpi{border-left:4px solid var(--bs-border-color)!important}
.lc-kpi.tone-red{border-left-color:var(--lc-red-line)!important}.lc-kpi.tone-red .value-box-value{color:var(--lc-red-fg)}
.lc-kpi.tone-amber{border-left-color:var(--lc-amb-line)!important}.lc-kpi.tone-amber .value-box-value{color:var(--lc-amb-fg)}
.lc-kpi.tone-accent{border-left-color:var(--bs-primary)!important}
.lc-heat{width:100%;border-collapse:separate;border-spacing:3px;font-variant-numeric:tabular-nums}
.lc-heat th,.lc-heat td{padding:.22rem .45rem;font-size:.88rem;line-height:1.25}
.lc-heat thead th{font-size:.8rem;color:var(--bs-secondary-color);font-weight:600;text-align:center}
.lc-heat thead th:first-child{text-align:left}
.lc-heat tbody tr{cursor:pointer}
.lc-heat tbody th{font-weight:600;white-space:nowrap;border-radius:6px}
.lc-heat .lc-phase{display:block;font-weight:400;font-size:.75rem;color:var(--bs-secondary-color)}
.lc-heat td{text-align:center;font-weight:700;border-radius:6px;color:var(--lc-tile-text);min-width:3.2rem}
.lc-heat td.red{background:var(--lc-red-tile)}.lc-heat td.amber{background:var(--lc-amb-tile)}.lc-heat td.green{background:var(--lc-grn-tile)}
.lc-heat td.lc-overall{box-shadow:inset 0 0 0 2px color-mix(in srgb,var(--bs-body-color) 70%,transparent)}
.lc-heat .lc-word{display:block;font-size:.7rem;font-weight:600}
.lc-heat tr.is-selected th{background:var(--lc-soft);box-shadow:inset 3px 0 0 var(--bs-primary)}
.lc-heat tbody tr:hover th{background:var(--bs-tertiary-bg)}
.lc-heat tr.is-selected:hover th{background:var(--lc-soft)}
.lc-pick{all:unset;cursor:pointer;color:var(--bs-link-color);text-decoration:underline;text-underline-offset:2px}
.lc-pick:focus-visible{outline:2px solid var(--bs-primary);outline-offset:2px;border-radius:2px}
.lc-legend{display:flex;flex-wrap:wrap;gap:.3rem .9rem;font-size:.8rem;color:var(--bs-secondary-color);margin-top:.4rem}
.lc-swatch{display:inline-block;width:.85rem;height:.85rem;border-radius:3px;vertical-align:-.12em;margin-right:.3rem}
.lc-swatch.red{background:var(--lc-red-tile)}.lc-swatch.amber{background:var(--lc-amb-tile)}.lc-swatch.green{background:var(--lc-grn-tile)}
.lc-signals{list-style:none;margin:0;padding:0;max-height:24rem;overflow:auto}
.lc-signals li{display:flex;gap:.6rem;align-items:flex-start;padding:.45rem .25rem;border-bottom:1px solid var(--bs-border-color)}
.lc-signals li:last-child{border-bottom:0}
.lc-signals li.is-selected{background:var(--lc-soft);border-radius:6px}
.lc-signals .lc-chip{flex:0 0 3.6rem;text-align:center;margin-top:.1rem}
.lc-sig-title{font-size:.9rem}.lc-sig-msg{font-size:.82rem;color:var(--bs-secondary-color)}
.lc-bars{display:grid;grid-template-columns:auto 1fr auto;gap:.35rem .6rem;align-items:center;font-size:.88rem;font-variant-numeric:tabular-nums}
.lc-bar{height:.8rem;background:var(--bs-tertiary-bg);border-radius:999px;overflow:hidden;min-width:3rem}
.lc-bar>span{display:block;height:100%;background:var(--bs-primary);border-radius:999px}
.lc-bar>span.red{background:var(--lc-red-fill)}.lc-bar>span.amber{background:var(--lc-amb-fill)}.lc-bar>span.green{background:var(--lc-grn-fill)}
.lc-num{text-align:right;white-space:nowrap}
.lc-why{grid-column:1/-1;font-size:.78rem;color:var(--bs-secondary-color);margin:-.2rem 0 .25rem}
.lc-total{display:flex;flex-wrap:wrap;align-items:baseline;gap:.3rem .6rem;margin-top:.5rem;padding-top:.5rem;border-top:1px solid var(--bs-border-color)}
.lc-total b{font-size:1.25rem}
.lc-h3{font-size:.8rem;text-transform:uppercase;letter-spacing:.04em;color:var(--bs-secondary-color);font-weight:600;margin:0 0 .5rem}
.lc-note{font-size:.78rem;color:var(--bs-secondary-color);margin:.5rem 0 0}
.lc-table{--bs-table-bg:transparent;--bs-table-color:var(--bs-body-color);font-size:.85rem;font-variant-numeric:tabular-nums;margin:0}
.lc-table th{font-size:.8rem;color:var(--bs-secondary-color);font-weight:600;white-space:nowrap}
.lc-table tbody th{color:inherit}.lc-table td{white-space:nowrap}
.lc-table td,.lc-table th{padding:.35rem .42rem;vertical-align:middle}
.lc-table td.n{text-align:right}
.lc-table tr.is-selected td,.lc-table tr.is-selected th{background:var(--lc-soft)}
.lc-table td.is-whatif{color:var(--lc-what);font-weight:700}
.lc-heat .lc-short{display:none}
@media (max-width:575.98px){
 .lc-heat{border-spacing:2px}
 .lc-heat th,.lc-heat td{padding:.2rem .22rem;font-size:.82rem}
 .lc-heat td{min-width:2.1rem}
 .lc-heat thead th{font-size:.72rem}
 .lc-heat .lc-long{display:none}.lc-heat .lc-short{display:inline}
 .lc-heat abbr{text-decoration:none}
 .lc-heat .lc-word{font-size:.64rem}
 .lc-heat tbody th .lc-chip{display:block;width:max-content;margin:.15rem 0 0!important}
}
.lc-scroll{overflow-x:auto}
.lc-scroll:focus-visible{outline:2px solid var(--bs-primary);outline-offset:2px}
.lc-scroll-box{position:relative}
.lc-scroll-box::after{content:'';position:absolute;top:0;right:0;bottom:0;width:2rem;pointer-events:none;opacity:0;
 transition:opacity .15s;background:linear-gradient(to right,transparent,var(--lc-surface) 80%)}
.lc-scroll-wrap.is-clipped:not(.at-end) .lc-scroll-box::after{opacity:1}
.lc-scroll-hint{display:none;font-size:.78rem;color:var(--bs-secondary-color);margin:.35rem 0 0}
.lc-scroll-wrap.is-clipped .lc-scroll-hint{display:block}
.lc-side-head{font-weight:700;font-size:.9rem;margin:.25rem 0 .2rem}
.lc-whatif{font-size:.83rem;line-height:1.4;border-radius:6px;padding:.45rem .6rem;border:1px dashed var(--bs-border-color);color:var(--bs-secondary-color)}
.lc-whatif.on{border:1px solid var(--lc-what-line);color:var(--bs-body-color);background:var(--lc-what-bg)}
.lc-whatif ul{margin:.2rem 0 0;padding-left:1.1rem}
.bslib-sidebar-layout>.sidebar .shiny-input-container{margin-bottom:.6rem}
.shiny-plot-output img{max-width:100%}

"

# A click on a study selects it in the sidebar's picker right away, in the browser, so R hears of
# the new study before any later slider move (a round trip through R could let a quick slider move
# land on the previous study). input$pick is the fallback when the picker is missing.
LC_JS <- "
$(document).on('click', '[data-study]', function (ev) {
  ev.preventDefault(); ev.stopPropagation();
  var id = this.getAttribute('data-study'), sel = document.getElementById('study');
  if (sel && [].some.call(sel.options, function (o) { return o.value === id; })) {
    if (sel.value !== id) $(sel).val(id).trigger('change');
  } else Shiny.setInputValue('pick', id, { priority: 'event' });
});
// A table wider than its card scrolls sideways: say so, with a fade at the clipped edge and a
// line under the table, and make the scroll area reachable from the keyboard.
function lcClip() {
  [].forEach.call(document.querySelectorAll('.lc-scroll-wrap'), function (w) {
    var s = w.querySelector('.lc-scroll'); if (!s) return;
    var clipped = s.scrollWidth > s.clientWidth + 1;
    w.classList.toggle('is-clipped', clipped);
    w.classList.toggle('at-end', !clipped || s.scrollLeft + s.clientWidth >= s.scrollWidth - 1);
    if (clipped) s.setAttribute('tabindex', '0'); else s.removeAttribute('tabindex');
  });
}
$(document).on('shiny:value', function () { setTimeout(lcClip, 0); }).on('shiny:idle', lcClip);
$(window).on('resize load', lcClip);
document.addEventListener('scroll', function (e) {
  if (e.target.classList && e.target.classList.contains('lc-scroll')) lcClip();
}, true);
$(function () {
  if (!window.ResizeObserver) return;
  var ro = new ResizeObserver(function () { lcClip(); });
  [].forEach.call(document.querySelectorAll('.lc-scroll'), function (s) { ro.observe(s); });
});
// The what-if sliders and the keyboard. ion.rangeSlider answers its track taking focus with a
// simulated click beside the handle, which moved the value one step: tabbing past a slider made a
// what-if nobody asked for. Focus now only prepares the slider for the arrow keys (what that click
// also set up), on the shared prototype, so the sliders that updateSliderInput() rebuilds keep it.
$(document).on('shiny:bound', '.js-range-slider', function () {
  var s = $(this).data('ionRangeSlider'), P = s && Object.getPrototypeOf(s);
  if (!P || P.lcQuietFocus) return;
  P.lcQuietFocus = true;
  P.pointerFocus = function () {
    if (this.target) return;
    var single = this.options.type === 'single';
    this.current_plugin = this.plugin_count;
    this.target = single ? 'single' : 'from';
    this.coords.p_gap = 0;
    this.coords.p_pointer = single ? this.coords.p_single_fake : this.coords.p_from_fake;
  };
  $('.js-range-slider').each(function () {
    var t = $(this).data('ionRangeSlider'); if (!t || !t.$cache.line) return;
    t.$cache.line.off('focus.irs_' + t.plugin_count).on('focus.irs_' + t.plugin_count, t.pointerFocus.bind(t));
  });
});
// The track is the slider's tab stop: give it the role, name and value a screen reader announces.
// Set on every change, because each updateSliderInput() rebuilds the track (Shiny then fires change).
function lcSliderAria(inp) {
  var s = $(inp).data('ionRangeSlider'), l = inp.parentNode && inp.parentNode.querySelector('.irs-line');
  if (!s || !l) return;
  l.setAttribute('role', 'slider');
  l.setAttribute('aria-labelledby', inp.id + '-label');
  l.setAttribute('aria-valuemin', s.result.min);
  l.setAttribute('aria-valuemax', s.result.max);
  l.setAttribute('aria-valuenow', s.result.from);
  l.setAttribute('aria-valuetext', s.result.from + (s.options.postfix || ''));
  inp.setAttribute('aria-hidden', 'true');   // the read-only copy would be read twice
}
$(document).on('change', 'input.js-range-slider', function () { lcSliderAria(this); })
  .on('shiny:sessioninitialized shiny:bound', function () {
    $('input.js-range-slider').each(function () { lcSliderAria(this); });
  });
"
# a table that scrolls sideways when it is wider than its card, with a visible cue when it does
scroll_wrap <- function(label, ...) div(
  class = "lc-scroll-wrap",
  div(class = "lc-scroll-box", div(class = "lc-scroll", role = "region", `aria-label` = label, ...)),
  p(class = "lc-scroll-hint", "Scroll the table sideways to see every column →"))

kpi_box <- function(title, id, tone = "") value_box(
  title = title, value = textOutput(id, inline = TRUE),
  tags$p(class = "lc-kpi-sub", textOutput(paste0(id, "_sub"), inline = TRUE)),
  class = paste("lc-kpi", tone), fill = FALSE)

start_here <- accordion(
  class = "lc-start mb-3", open = "start",
  accordion_panel(
    "Start here: what this console shows and how to read it", value = "start",
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(4, 4, 4)), gap = "1.25rem",
      div(tags$h2("What it shows"),
          p("Operational health of eight synthetic early-phase studies, from protocol to clinical study report.",
            "Each study gets four risk scores from 0 to 100 (higher is riskier), blended into an overall score.",
            "Click any study to open its detail below the heatmap.")),
      div(tags$h2("How to read the colors"),
          tags$ul(class = "lc-key",
            tags$li(chip("red", "Red"), "at risk, above 66"),
            tags$li(chip("amber", "Amber"), "watch, 34 to 66"),
            tags$li(chip("green", "Green"), "on track, 33 or less"),
            tags$li(chip("whatif", "What-if"), "a value you changed; the data files stay as loaded"))),
      div(tags$h2("Try this"),
          tags$ol(
            tags$li("Click CP-107: its TLFs and CSR are overdue with 44% of TLFs final."),
            tags$li("Pick CP-103 and drag Open queries to 120: it turns amber, On watch goes to 4 and its backlog signal turns red."),
            tags$li("For CP-108, raise Double-programmed % to 80: At risk drops to 0. Reset to data undoes it.")),
          p(class = "lc-phone-only", "On a narrow screen, the arrow button at the top left opens the study picker and the what-if sliders.")))))

ui <- page_sidebar(
  title = div(class = "lc-title",
              tags$h1("Study Lifecycle Monitor"),
              span(class = "bp-chip synthetic", "Synthetic data"),
              span(class = "lc-asof", if (is.na(AS_OF)) "Snapshot date not in the data" else paste("Snapshot", day_fmt(AS_OF))),
              div(class = "lc-mode", bp_theme_toggle())),
  window_title = "Study Lifecycle Monitor",
  theme = bp_theme(),   # precompiled; the site's tokens come from bp_theme_head() (in app_status_ui())
  lang = "en",
  fillable = FALSE,
  sidebar = sidebar(
    width = 300, id = "controls",   # wide enough for the longest study label in the picker
    # on a phone the controls sit behind the toggle at the top left, so the guidance comes first
    open = list(desktop = "open", mobile = "closed"),
    selectInput("study", "Selected study", choices = STUDY_CHOICES, selected = OPEN_ID, selectize = FALSE),
    div(class = "lc-side-head", "What-if on the selected study"),
    p(class = "small text-body-secondary mb-2",
      "Change an input and every score, count and signal recomputes at once."),
    sliderInput("openq", sprintf("Open queries (data: %d)", S0$open_queries),
                min = 0, max = max(150, S0$open_queries), value = S0$open_queries),
    sliderInput("dblprog", sprintf("Double-programmed %% (data: %d)", S0$dbl_prog_pct),
                min = 0, max = 100, value = S0$dbl_prog_pct, post = "%"),
    uiOutput("whatif_state"),
    actionButton("reset", "Reset to data", class = "btn-sm btn-outline-primary w-100 mt-2"),
    tags$hr(),
    div(class = "lc-side-head", "How the score works"),
    p(class = "small mb-1", "Overall = 30% Timeline + 28% Data + 27% TLF + 15% Resource."),
    p(class = "small text-body-secondary mb-0",
      "Each dimension is 0 to 100 and comes from the study's own inputs, listed in the table at the bottom.",
      "Screening for operational health, never a reported clinical number.")
  ),
  app_status_ui("the risk scores, the heatmap, the ranked signals and the selected study's detail"),
  tags$head(tags$style(HTML(LC_CSS)), tags$script(HTML(LC_JS))),
  start_here,
  layout_columns(
    col_widths = breakpoints(sm = c(6, 6, 6, 6, 6, 6), lg = c(4, 4, 4, 4, 4, 4)), class = "mb-3",
    kpi_box("Active studies", "k_n"),
    kpi_box("At risk", "k_risk", "tone-red"),
    kpi_box("On watch", "k_watch", "tone-amber"),
    kpi_box("Open queries", "k_q", "tone-accent"),
    kpi_box("Deliverables done", "k_del"),
    kpi_box("Next DB lock", "k_dbl")
  ),
  layout_columns(
    col_widths = breakpoints(sm = 12, lg = c(7, 5)), class = "mb-3",
    card(card_header(div("Portfolio risk heatmap",
                         span(class = "lc-sub", "Scores 0 to 100, higher is riskier. Click a row to open that study."))),
         card_body(scroll_wrap("Risk heatmap", uiOutput("heat")),
                   div(class = "lc-legend",
                       span(span(class = "lc-swatch green"), "0 to 33 on track"),
                       span(span(class = "lc-swatch amber"), "34 to 66 watch"),
                       span(span(class = "lc-swatch red"), "67 to 100 at risk"),
                       span("Overall = the outlined column")))),
    card(card_header(div("Early-warning signals", span(class = "lc-sub", textOutput("signals_hdr", inline = TRUE)))),
         card_body(uiOutput("signals")))
  ),
  card(
    class = "mb-3",
    card_header(uiOutput("detail_hdr")),
    card_body(
      fillable = FALSE,
      layout_columns(
        col_widths = breakpoints(sm = 12, md = c(6, 6, 12), xl = c(4, 4, 4)), gap = "1.5rem",
        div(div(class = "lc-h3", "Score breakdown"), uiOutput("breakdown")),
        div(div(class = "lc-h3", "Milestone track"),
            plotOutput("milestones", height = "280px", fill = FALSE),
            p(class = "lc-note", "FPFV first participant's first visit, LPLV last participant's last visit,",
              "DBL database lock, TLFs tables, listings and figures, CSR clinical study report.",
              "The dashed line is the snapshot date; each milestone's date is on the right.")),
        div(div(class = "lc-h3", "TLF production funnel"), uiOutput("funnel"),
            div(class = "lc-h3 mt-3", "Deliverables register"), uiOutput("deliv"))
      ),
      div(class = "lc-h3 mt-3", "Open-query trend, last 8 weeks"),
      plotOutput("trend", height = "230px", fill = FALSE),
      uiOutput("trend_note"))),
  card(card_header(div("Study inputs behind the scores",
                       span(class = "lc-sub", "One row per study, as loaded; a what-if value shows in purple. Click a study to select it."))),
       card_body(scroll_wrap("Study inputs table", uiOutput("inputs"))))
)

plot_theme <- function(dark) {
  pc <- portfolio_colors(dark)
  bp_ggplot_theme(if (isTRUE(dark)) "dark" else "light", base_size = 13) + theme(
    plot.background = element_rect(fill = "transparent", colour = NA),
    panel.background = element_rect(fill = "transparent", colour = NA),
    axis.text = element_text(colour = pc$muted, size = 11.5),
    panel.grid = element_line(colour = pc$line, linewidth = 0.4), panel.grid.minor = element_blank(),
    legend.position = "bottom", legend.title = element_blank(), legend.text = element_text(colour = pc$text, size = 11),
    legend.key = element_rect(fill = "transparent", colour = NA), legend.background = element_rect(fill = "transparent", colour = NA),
    plot.margin = margin(4, 8, 4, 4))
}

server <- function(input, output, session) {
  rv <- reactiveValues(studies = seed$studies)
  dark <- reactive(identical(input$bp_theme, "dark"))
  sel <- reactive({ req(input$study); input$study })

  # Keep the what-if sliders in sync with the selected study. The sliders open on the selected
  # study's values and the what-if observer ignores its first run, so opening the app never writes
  # slider defaults into a study. After a study switch (or Reset) the sliders still show the old
  # values until the browser applies the update R sends, so R remembers the values it asked for
  # (`asked`) and ignores slider events until the browser reports them: a quick slider move in that
  # moment can never write one study's values into another. A request expires after 3 s, so the
  # sliders can never stay locked.
  asked <- new.env()
  move_sliders <- function(s, max_q = NULL) {
    now <- list(openq = input$openq, dblprog = input$dblprog)
    want <- list(openq = s$open_queries, dblprog = s$dbl_prog_pct)
    for (k in names(want)) asked[[k]] <- if (length(now[[k]]) == 1 && !identical(as.integer(round(now[[k]])), as.integer(want[[k]])))
      list(value = as.integer(want[[k]]), at = Sys.time())
    s0 <- seed$studies[seed$studies$id == s$id, ]
    updateSliderInput(session, "openq", value = want$openq, max = max_q,
                      label = sprintf("Open queries (data: %d)", s0$open_queries))
    updateSliderInput(session, "dblprog", value = want$dblprog,
                      label = sprintf("Double-programmed %% (data: %d)", s0$dbl_prog_pct))
  }
  observeEvent(input$study, {
    s <- rv$studies[rv$studies$id == input$study, ]
    if (nrow(s) == 1) move_sliders(s, max_q = max(150, s$open_queries))
  })
  # Whole numbers, as in the data: writing the value a study already has leaves rv$studies
  # identical, so switching studies recomputes nothing.
  observeEvent(list(input$openq, input$dblprog), {
    i <- which(rv$studies$id == input$study)
    if (length(i) != 1 || length(input$openq) != 1 || length(input$dblprog) != 1) return()
    got <- list(openq = as.integer(round(input$openq)), dblprog = as.integer(round(input$dblprog)))
    for (k in names(got)) {
      a <- asked[[k]]
      if (is.null(a)) next
      if (identical(got[[k]], a$value) || difftime(Sys.time(), a$at, units = "secs") > 3) asked[[k]] <- NULL
      else return()   # the browser has not applied R's update yet: a stale value, not a what-if
    }
    x <- rv$studies
    x$open_queries[i] <- got$openq
    x$dbl_prog_pct[i] <- got$dblprog
    rv$studies <- x
  }, ignoreInit = TRUE)
  observeEvent(input$reset, {
    rv$studies <- seed$studies
    s <- seed$studies[seed$studies$id == input$study, ]
    if (nrow(s) == 1) move_sliders(s)
  })
  observeEvent(input$pick, {
    if (input$pick %in% seed$studies$id) updateSelectInput(session, "study", selected = input$pick)
  })

  data_now <- reactive(list(studies = rv$studies, milestones = seed$milestones,
                            deliverables = seed$deliverables, query_trend = seed$query_trend))
  st  <- reactive(score_portfolio(data_now()))
  kpi <- reactive(lifecycle_kpis(st(), data_now()))
  sg  <- reactive(lifecycle_signals(st(), data_now()))
  # the studies and fields a what-if has changed: list(id = c("open_queries", ...))
  edits <- reactive({
    now <- rv$studies; was <- seed$studies[match(now$id, seed$studies$id), ]
    out <- lapply(seq_len(nrow(now)), function(j)
      c("open_queries", "dbl_prog_pct")[c(now$open_queries[j] != was$open_queries[j],
                                          now$dbl_prog_pct[j] != was$dbl_prog_pct[j])])
    names(out) <- now$id
    Filter(length, out)
  })
  cur <- reactive({ s <- st()[st()$id == sel(), ]; req(nrow(s) == 1); s })
  whatif_note <- function() if (length(edits())) " (with what-if)" else ""

  # ---- KPIs ----
  output$k_n     <- renderText(guard("the study count", as.character(kpi()$n)))
  output$k_n_sub <- renderText(guard("the phase mix", {
    ph <- table(factor(st()$phase, levels = c("Startup", "Conduct", "DB Lock", "Reporting")))
    paste(sprintf("%d %s", as.integer(ph), names(ph))[ph > 0], collapse = " \u00b7 ")
  }))
  output$k_risk     <- renderText(guard("the at-risk count", as.character(kpi()$at_risk)))
  output$k_risk_sub <- renderText({
    ids <- st()$id[st()$rag == "red"]
    paste0(if (length(ids)) paste(ids, collapse = ", ") else "No study above 66", whatif_note())
  })
  output$k_watch     <- renderText(guard("the watch count", as.character(kpi()$watch)))
  output$k_watch_sub <- renderText({
    ids <- st()$id[st()$rag == "amber"]
    paste0(if (length(ids)) paste(ids, collapse = ", ") else "No study between 34 and 66", whatif_note())
  })
  output$k_q     <- renderText(guard("the open-query total", as.character(kpi()$open_q)))
  output$k_q_sub <- renderText(paste0("Across all studies, snapshot week", whatif_note()))
  output$k_del     <- renderText(guard("the deliverables average", sprintf("%d%%", kpi()$avg_del)))
  output$k_del_sub <- renderText(sprintf("Average of the %d study registers", kpi()$n))
  output$k_dbl     <- renderText(if (is.na(kpi()$next_dbl_days)) "None" else sprintf("%d days", kpi()$next_dbl_days))
  output$k_dbl_sub <- renderText({
    k <- kpi()
    if (is.na(k$next_dbl_id)) "Every study has locked its database" else {
      d <- seed$milestones$date[seed$milestones$study_id == k$next_dbl_id & seed$milestones$milestone == "DBL"]
      paste0(k$next_dbl_id, if (length(d)) paste(" on", day_fmt(d[1])) else "")
    }
  })

  # ---- heatmap (an HTML table: crisp, clickable, follows light and dark) ----
  output$heat <- renderUI(guard("the risk heatmap", {
    x <- st(); ed <- edits()
    explain_empty(nrow(x) > 0, "No studies in studies.csv, so there is nothing to score. Add a row per study.")
    tags$table(
      class = "lc-heat", `aria-label` = "Risk scores by study and dimension",
      tags$thead(tags$tr(tags$th(scope = "col", "Study"),
                         lapply(SCORE_DIMS, function(dm) tags$th(
                           scope = "col", span(class = "lc-long", dm),
                           span(class = "lc-short", tags$abbr(title = dm, DIM_SHORT[[dm]])))),
                         tags$th(scope = "col", "Overall"))),
      tags$tbody(lapply(seq_len(nrow(x)), function(j) {
        s <- x[j, ]
        tags$tr(
          class = if (s$id == sel()) "is-selected", `data-study` = s$id,
          tags$th(scope = "row",
                  tags$button(type = "button", class = "lc-pick", `data-study` = s$id,
                              `aria-pressed` = if (s$id == sel()) "true" else "false", s$id),
                  if (s$id %in% names(ed)) chip("whatif", "What-if", class = "ms-1"),
                  span(class = "lc-phase", s$phase)),
          lapply(SCORE_DIMS, function(dm) tags$td(class = rag_of(s[[dm]]), s[[dm]])),
          tags$td(class = paste("lc-overall", s$rag), s$overall, span(class = "lc-word", RAG_WORD[[s$rag]])))
      })))
  }))

  # ---- signals ----
  output$signals_hdr <- renderText({
    x <- sg()
    if (!nrow(x)) "None above the thresholds" else
      sprintf("%d signals: %d red, %d amber. Red first; click a study to open it.",
              nrow(x), sum(x$sev == "red"), sum(x$sev == "amber"))
  })
  output$signals <- renderUI(guard("the early-warning signals", {
    x <- sg()
    if (!nrow(x)) return(empty_state(paste(
      "No early-warning signals: every study is below the signal thresholds.",
      "Raise a study's open queries or lower its double programming with the what-if to see one appear.")))
    tags$ol(class = "lc-signals", lapply(seq_len(nrow(x)), function(j) {
      r <- x[j, ]
      tags$li(class = if (r$who == sel()) "is-selected",
              chip(r$sev, SEV_WORD[[r$sev]]),
              div(div(class = "lc-sig-title",
                      tags$button(type = "button", class = "lc-pick", `data-study` = r$who, r$who), " ", r$title),
                  div(class = "lc-sig-msg", r$msg)))
    }))
  }))

  # ---- the selected study ----
  output$detail_hdr <- renderUI(guard("the study header", {
    s <- cur()
    div(class = "d-flex flex-wrap align-items-center gap-2",
        span(sprintf("%s \u00b7 %s \u00b7 %s \u00b7 owner %s", s$id, s$name, s$phase, s$owner)),
        chip(s$rag, sprintf("Overall %d \u00b7 %s", s$overall, RAG_WORD[[s$rag]])),
        if (s$id %in% names(edits())) chip("whatif", "What-if applied"))
  }))
  output$breakdown <- renderUI(guard("the score breakdown", {
    s <- cur(); why <- score_drivers(s, s$overdue)
    contrib <- vapply(SCORE_DIMS, function(dm) SCORE_WEIGHTS[[dm]] * s[[dm]], numeric(1))
    tagList(
      div(class = "lc-bars", lapply(SCORE_DIMS, function(dm) tagList(
        span(sprintf("%s \u00d7 %d%%", dm, round(100 * SCORE_WEIGHTS[[dm]]))),
        div(class = "lc-bar", role = "img", `aria-label` = sprintf("%s score %d of 100", dm, s[[dm]]),
            span(class = rag_of(s[[dm]]), style = sprintf("width:%d%%", max(2, s[[dm]])))),
        span(class = "lc-num", sprintf("%d \u2192 %.1f", s[[dm]], contrib[[dm]])),
        div(class = "lc-why", why[[dm]])))),
      div(class = "lc-total",
          span("Overall"), tags$b(s$overall), chip(s$rag, RAG_WORD[[s$rag]]),
          span(class = "lc-sub", sprintf("= %s, rounded", paste(sprintf("%.1f", contrib), collapse = " + ")))))
  }))
  output$milestones <- renderPlot({
    m <- seed$milestones[seed$milestones$study_id == sel(), ]
    explain_empty(nrow(m) > 0, sprintf("No milestones for %s in milestones.csv. Add its rows to see the track.", sel()))
    guard("the milestone track", {
      d <- dark(); pc <- portfolio_colors(d)
      m$milestone <- factor(m$milestone, levels = rev(MS_ORDER))
      m$date <- as.Date(m$date)
      m$status <- factor(m$status, levels = names(STATUS_LABEL))
      # each milestone's date sits on the right-hand axis, in line with its row, so no date label
      # can run into the snapshot line or past the edge of a narrow plot
      day <- stats::setNames(sub("^0", "", format(m$date, "%d %b")), as.character(m$milestone))
      p <- ggplot(m, aes(date, milestone))
      if (!is.na(AS_OF)) p <- p + geom_vline(xintercept = AS_OF, linetype = "dashed", colour = pc$muted, linewidth = 0.5)
      p + geom_point(aes(colour = status, shape = status), size = 3.8, stroke = 1.2, show.legend = TRUE) +
        scale_colour_manual(values = tone_fill(STATUS_TONE, if (d) "dark" else "light"), labels = STATUS_LABEL, drop = FALSE) +
        scale_shape_manual(values = STATUS_SHAPE, labels = STATUS_LABEL, drop = FALSE) +
        scale_y_discrete(sec.axis = dup_axis(labels = function(b) unname(day[names(b) %||% as.character(b)]))) +
        scale_x_date(date_labels = "%b %Y", expand = expansion(mult = c(0.06, 0.06)),
                     guide = guide_axis(check.overlap = TRUE)) +
        labs(x = NULL, y = NULL) + plot_theme(d) +
        theme(panel.grid.major.y = element_blank(), axis.text.y.left = element_text(colour = pc$text, size = 12),
              axis.text.y.right = element_text(colour = pc$muted, size = 11.5, hjust = 0)) +
        guides(colour = guide_legend(nrow = 2, byrow = TRUE), shape = guide_legend(nrow = 2, byrow = TRUE))
    })
  }, bg = "transparent", alt = reactive(sprintf("Milestone track for %s", sel())))

  output$funnel <- renderUI(guard("the TLF funnel", {
    s <- cur()
    explain_empty(isTRUE(s$tlf_planned > 0), sprintf("%s has no TLFs planned yet, so there is no production funnel.", s$id))
    n <- c(Planned = s$tlf_planned, Programmed = s$tlf_programmed, `QC'd` = s$tlf_qcd, Finalized = s$tlf_finalized)
    tagList(
      div(class = "lc-bars", lapply(names(n), function(k) tagList(
        span(k),
        div(class = "lc-bar", role = "img", `aria-label` = sprintf("%s: %d of %d", k, n[[k]], n[[1]]),
            span(style = sprintf("width:%.0f%%", max(1, 100 * n[[k]] / n[[1]])))),
        span(class = "lc-num", if (k == "Planned") sprintf("%d", n[[k]]) else sprintf("%d (%d%%)", n[[k]], round(100 * n[[k]] / n[[1]])))))),
      p(class = "lc-note", if (isTRUE(s$locked))
        "The database is locked, so the TLFs are run on the final data; Finalized counts the signed-off ones."
        else sprintf("Final TLFs come after the database lock (%s); until then the programmed and QC'd TLFs are dry runs, and the TLF score counts the QC'd ones.",
                     sub("^DB lock ", "", lock_words(s$days_to_dbl)))))
  }))
  output$deliv <- renderUI(guard("the deliverables register", {
    x <- seed$deliverables[seed$deliverables$study_id == sel(), ]
    explain_empty(nrow(x) > 0, sprintf("No deliverables register rows for %s in deliverables.csv.", sel()))
    tagList(
      div(class = "lc-bars", lapply(seq_len(nrow(x)), function(j) tagList(
        span(x$phase[j]),
        div(class = "lc-bar", role = "img", `aria-label` = sprintf("%s: %d of %d done", x$phase[j], x$done[j], x$total[j]),
            span(class = "green", style = sprintf("width:%.0f%%", max(1, 100 * x$done[j] / x$total[j])))),
        span(class = "lc-num", sprintf("%d of %d", x$done[j], x$total[j]))))),
      p(class = "lc-note", sprintf("%d%% of %d deliverables done. Analysis follows TLF programming and Reporting follows finalization%s.",
                                   deliverables_pct(data_now(), sel()), sum(x$total),
                                   if (isTRUE(cur()$locked)) "" else ", so it starts after the database lock")))
  }))

  output$trend <- renderPlot({
    qt <- seed$query_trend
    explain_empty(nrow(qt) > 0, "No rows in query_trend.csv, so there is no trend to draw.")
    guard("the open-query trend", {
      d <- dark(); pc <- portfolio_colors(d)
      wk <- sort(unique(qt$week)); last <- max(wk)
      when <- if (is.na(AS_OF)) NULL else AS_OF - 7 * (last - wk)
      tot <- aggregate(open_queries ~ week, qt, sum)
      one <- qt[qt$study_id == sel(), c("week", "open_queries")]
      lines <- rbind(data.frame(series = "Portfolio", tot), if (nrow(one)) data.frame(series = sel(), one))
      lines$series <- factor(lines$series, levels = c("Portfolio", sel()))
      cols <- stats::setNames(c(pc$accent, tone_fill(STUDY_TONE, if (d) "dark" else "light")), c("Portfolio", sel()))
      ends <- lines[lines$week == last, ]
      # a what-if changes this week's open queries: show where the last point would move
      now <- rv$studies
      wi <- rbind(data.frame(series = "Portfolio", week = last, open_queries = sum(now$open_queries)),
                  data.frame(series = sel(), week = last, open_queries = now$open_queries[now$id == sel()]))
      wi$series <- factor(wi$series, levels = levels(lines$series))
      wi <- wi[wi$series %in% ends$series, ]
      wi <- wi[wi$open_queries != ends$open_queries[match(wi$series, ends$series)], ]
      ends$label <- sprintf("%s %d", ends$series, ends$open_queries)
      wi$label <- sprintf("what-if %d", wi$open_queries)
      # The end labels sit right of the last week when the plot has room for them, with the right
      # margin sized to the longest label; on a narrow plot (a phone) the legend carries the same
      # words instead, so no label is ever cut at the edge.
      width <- session$clientData$output_trend_width
      narrow <- length(width) == 1 && is.numeric(width) && width < 560
      p <- ggplot(lines, aes(week, open_queries, colour = series)) +
        geom_line(linewidth = 1.1) + geom_point(size = 2.2)
      if (nrow(wi)) p <- p + geom_point(data = wi, shape = 21, size = 3.4, stroke = 1.3, fill = NA, show.legend = FALSE)
      if (narrow) {
        key <- stats::setNames(ends$label, as.character(ends$series))
        for (j in seq_len(nrow(wi))) key[[as.character(wi$series[j])]] <- paste0(key[[as.character(wi$series[j])]], ", ", wi$label[j])
        right <- 0.07   # room for the last week's date under the axis
        p <- p + scale_colour_manual(values = cols, labels = key) + guides(colour = guide_legend(ncol = 1))
      } else {
        # keep each what-if label clear of the end labels: when an end label is close, put the
        # what-if label on the same side of it as the what-if circle
        gap <- 0.09 * max(c(lines$open_queries, wi$open_queries, 1))
        wi$label_y <- vapply(wi$open_queries, function(v) {
          near <- ends$open_queries[abs(ends$open_queries - v) < gap]
          if (!length(near)) v else if (v >= mean(near)) max(near) + gap else max(0, min(near) - gap) }, numeric(1))
        p <- p + geom_text(data = ends, aes(label = label), hjust = -0.12, size = 4, show.legend = FALSE)
        if (nrow(wi)) p <- p + geom_text(data = wi, aes(y = label_y, label = label), hjust = -0.3, size = 3.6, show.legend = FALSE)
        # about 6.3 px a character at size 4 and 5.7 at 3.6, plus the offset; the plot area is the
        # output's width less the y axis
        need <- max(nchar(ends$label) * 6.3 * 1.12, if (nrow(wi)) nchar(wi$label) * 5.7 * 1.3 else 0) + 8
        panel <- if (length(width) == 1 && is.numeric(width)) max(300, width - 70) else 760
        right <- need / max(panel - need, 1)
        p <- p + scale_colour_manual(values = cols)
      }
      p + scale_x_continuous(breaks = wk, labels = if (is.null(when)) wk else sub("^0", "", format(when, "%d %b")),
                             expand = expansion(mult = c(0.02, right)), guide = guide_axis(check.overlap = TRUE)) +
        # a little room under 0, so a study at 0 open queries shows its line and its whole label
        scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0.06, 0.12))) +
        labs(x = if (is.null(when)) "Week" else "Week ending", y = "Open queries") +
        plot_theme(d) + theme(legend.position = if (narrow) "bottom" else "none", panel.grid.major.x = element_blank())
    })
  }, bg = "transparent", alt = reactive(sprintf("Open-query trend for the portfolio and %s over 8 weeks", sel())))

  output$trend_note <- renderUI(guard("the trend note", {
    s <- cur()
    dbl <- seed$milestones$date[seed$milestones$study_id == s$id & seed$milestones$milestone == "DBL"]
    lock <- if (length(dbl)) as.Date(dbl[1]) else as.Date(NA)
    first <- if (is.na(AS_OF)) as.Date(NA) else AS_OF - 7 * (max(seed$query_trend$week, 1) - 1)
    why <- if (is.na(lock)) NULL
      else if (isTRUE(s$locked) && !is.na(first) && lock <= first)
        sprintf("%s locked its database on %s, before these weeks, so it has no open queries.", s$id, day_fmt(lock))
      else if (isTRUE(s$locked))
        sprintf("%s locked its database on %s; from that week on it has no open queries.", s$id, day_fmt(lock))
      else if (s$days_to_dbl > 0)
        sprintf("%s locks its database on %s, %d days after the snapshot, once its open queries are closed.",
                s$id, day_fmt(lock), s$days_to_dbl)
      else sprintf("%s's database lock was due on %s and is not done.", s$id, day_fmt(lock))
    p(class = "lc-note", "The portfolio total and the selected study. The last week is the snapshot week;",
      "a what-if on open queries shows as an open circle there.", why)
  }))

  # ---- the inputs table ----
  output$inputs <- renderUI(guard("the study inputs", {
    x <- rv$studies[order(rv$studies$id), ]; sc <- st(); ed <- edits()
    pct <- function(v) sprintf("%d%%", round(100 * v))
    # the owner is in the selected study's header; this table lists what the scores are made of
    head <- list("Study", "Phase", "DB lock", span(title = "Open queries", "Queries"), "Clean", "SDV",
                 tags$abbr(title = "QC'd dry runs before the lock, finalized TLFs after it", "TLFs"),
                 tags$abbr(title = "Double-programmed", "Dbl prog."), tags$abbr(title = "Open discrepancies", "Discrep."),
                 span(title = "Milestones overdue", "Overdue"), "Overall")
    tags$table(
      class = "table table-sm lc-table",
      tags$thead(tags$tr(lapply(head, function(h) tags$th(scope = "col", h)))),
      tags$tbody(lapply(seq_len(nrow(x)), function(j) {
        s <- x[j, ]; o <- sc[sc$id == s$id, ]; e <- ed[[s$id]] %||% character()
        tags$tr(class = if (s$id == sel()) "is-selected",
                tags$th(scope = "row", tags$button(type = "button", class = "lc-pick", `data-study` = s$id, s$id)),
                tags$td(s$phase), tags$td(lock_fmt(s$days_to_dbl)),
                tags$td(class = paste("n", if ("open_queries" %in% e) "is-whatif"), s$open_queries),
                tags$td(class = "n", pct(s$clean_pct)), tags$td(class = "n", pct(s$sdv_pct)),
                tags$td(class = "n", if (isTRUE(o$locked)) sprintf("%d/%d final", s$tlf_finalized, s$tlf_planned)
                                     else sprintf("%d/%d QC'd", s$tlf_qcd, s$tlf_planned)),
                tags$td(class = paste("n", if ("dbl_prog_pct" %in% e) "is-whatif"), sprintf("%d%%", s$dbl_prog_pct)),
                tags$td(class = "n", s$discrep), tags$td(class = "n", o$overdue),
                tags$td(chip(o$rag, sprintf("%d %s", o$overall, RAG_WORD[[o$rag]]))))
      })))
  }))

  output$whatif_state <- renderUI({
    ed <- edits()
    if (!length(ed)) return(div(class = "lc-whatif", "No what-if: every panel shows the data as loaded."))
    was <- seed$studies; now <- rv$studies
    items <- unlist(lapply(names(ed), function(id) {
      a <- was[was$id == id, ]; b <- now[now$id == id, ]
      c(if ("open_queries" %in% ed[[id]]) sprintf("%s open queries %d \u2192 %d", id, a$open_queries, b$open_queries),
        if ("dbl_prog_pct" %in% ed[[id]]) sprintf("%s double-programmed %d%% \u2192 %d%%", id, a$dbl_prog_pct, b$dbl_prog_pct))
    }))
    div(class = "lc-whatif on", tags$b("What-if in effect"), tags$ul(lapply(items, tags$li)))
  })
}

shinyApp(ui, server)
