# ---------------------------------------------------------------------------
# portfolio_app.R: shared status, error and theme helpers for the portfolio's Shiny apps
# (TRIALMON, the UAT tracker and the Study Lifecycle Monitor). Synthetic data only.
#
# One copy lives in apps/_shared/. The Pages build (.github/pages/build_site.R) copies it next to
# each app's app.R before the Shinylive export, so the browser and local R run the same file.
# In app.R:
#
#   source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")
#   warm_up_graphics()       # right after library(): see below
#   ui <- page_sidebar(..., app_status_ui("the KPIs, the test table and the gate"), ...)
#   output$plot <- renderPlot(guard("the area plot", { ... }))
#   output$tbl  <- renderDT({ d <- f(); explain_empty(nrow(d) > 0, "No tests match. Clear the filters."); ... })
#
# app_status_ui(computing)  A startup card that says what R is computing and counts the panels
#     filled so far; Shiny's busy indicators (spinners and a pulse) for every later update; a
#     message if the first results take more than 45 s or the connection to R is lost; and error
#     cards, so a panel that fails says what failed, shows the message and says it is a bug
#     instead of going blank.
# guard(what, expr)  Wraps a render expression so an error names the computation that failed.
#     req() and validate() pass through unchanged. A ggplot is drawn after guard() returns, so an
#     error while drawing it still gets the error card, without the name.
# explain_empty(ok, message)  validate(need()) with a message, shown as a neutral note, so an
#     output is never silently empty. empty_state(message) is the same note for renderUI().
# warm_up_graphics()  Draws one throwaway plot while the app starts. In the browser, webR
#     downloads the graphics library and fonts the first time anything is plotted; doing it here
#     moves that download into the launch page's "starting R" step, where a failure is reported,
#     instead of leaving every plot empty after the layout is drawn. Does nothing in local R.
# portfolio_theme(), portfolio_colors(dark)  The site's color tokens (site.css), light and dark,
#     as a bslib theme and as R values for plots. Pair the theme with bslib::input_dark_mode(),
#     which follows the visitor's system setting.
# ---------------------------------------------------------------------------

PORTFOLIO_TOKENS <- list(
  light = c(bg = "#F6F7F8", surface = "#FFFFFF", surface2 = "#EEF1F4", text = "#18212B",
            muted = "#4F5B67", line = "#D5DBE1", accent = "#0757BF"),
  dark  = c(bg = "#12171D", surface = "#1A2129", surface2 = "#212A34", text = "#E6EAEE",
            muted = "#A9B3BD", line = "#323C47", accent = "#7DB5FF"))
PORTFOLIO_SANS <- paste('-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue",',
                        "Arial, sans-serif")
PORTFOLIO_MONO <- 'ui-monospace, "SF Mono", Menlo, Consolas, monospace'

portfolio_colors <- function(dark = FALSE) as.list(PORTFOLIO_TOKENS[[if (isTRUE(dark)) "dark" else "light"]])

portfolio_theme <- function(...) {
  L <- PORTFOLIO_TOKENS$light; D <- PORTFOLIO_TOKENS$dark
  theme <- bslib::bs_theme(
    version = 5, primary = L[["accent"]], base_font = PORTFOLIO_SANS, code_font = PORTFOLIO_MONO,
    "body-bg" = L[["bg"]], "body-color" = L[["text"]], "border-color" = L[["line"]],
    "body-secondary-color" = L[["muted"]], "body-tertiary-bg" = L[["surface2"]],
    "body-bg-dark" = D[["bg"]], "body-color-dark" = D[["text"]], "border-color-dark" = D[["line"]],
    "body-secondary-color-dark" = D[["muted"]], "body-tertiary-bg-dark" = D[["surface2"]],
    "link-color-dark" = D[["accent"]], ...)
  bslib::bs_add_rules(theme, sprintf(paste(
    ".card, .bslib-card { --bs-card-bg: %s; }",
    "[data-bs-theme=dark] .card, [data-bs-theme=dark] .bslib-card { --bs-card-bg: %s; }",
    "[data-bs-theme=dark] { --bs-primary: %s; --bs-primary-rgb: 125, 181, 255; }"),
    L[["surface"]], D[["surface"]], D[["accent"]]))
}

guard <- function(what, expr) {
  tryCatch(expr, error = function(e) {
    if (inherits(e, "shiny.silent.error")) stop(e)     # req(), validate() and cancelOutput: unchanged
    stop(shiny::safeError(sprintf("While computing %s: %s", what, conditionMessage(e))))
  })
}

explain_empty <- function(ok, message) shiny::validate(shiny::need(isTRUE(ok), message))

empty_state <- function(message) htmltools::div(class = "pf-empty", role = "note", message)

warm_up_graphics <- function(force = FALSE) {
  in_browser <- grepl("emscripten", R.version$os) || grepl("wasm", R.version$platform)
  if (!force && !in_browser) return(invisible(FALSE))
  f <- tempfile(fileext = ".png")
  on.exit(unlink(f))
  ok <- tryCatch({
    shiny::plotPNG(function() {
      graphics::par(mar = c(0, 0, 0, 0))
      graphics::plot.new()
      graphics::text(0.5, 0.65, "warm-up", font = 1)
      graphics::text(0.5, 0.35, "warm-up", font = 2)
    }, filename = f, width = 160, height = 120)
    TRUE
  }, error = function(e) {
    message("warm_up_graphics: ", conditionMessage(e))
    FALSE
  })
  invisible(ok)
}

PORTFOLIO_STATUS_CSS <- "
.pf-startup{position:fixed;inset:0;z-index:2000;display:flex;align-items:flex-start;justify-content:center;
 padding:14vh 16px 16px;background:rgba(127,127,127,.18);
 background:color-mix(in srgb,var(--bs-body-bg,#fff) 64%,transparent);pointer-events:none;transition:opacity .25s,visibility .25s}
.pf-startup.pf-hidden{opacity:0;visibility:hidden}
.pf-startup-card{pointer-events:auto;max-width:32rem;display:flex;gap:.85rem;align-items:flex-start;
 background:var(--bs-body-bg,#fff);color:var(--bs-body-color,#18212b);border:1px solid var(--bs-border-color,#d5dbe1);
 border-radius:.6rem;padding:.95rem 1.15rem;box-shadow:0 8px 28px rgba(0,0,0,.14);line-height:1.45}
.pf-spinner{flex:0 0 1.15rem;height:1.15rem;margin-top:.15rem;border-radius:50%;border:2px solid var(--bs-border-color,#d5dbe1);
 border-top-color:var(--bs-primary,#0757bf);animation:pf-spin .8s linear infinite}
.pf-problem .pf-spinner{animation:none;border-color:var(--bs-danger,#b42318)}
@keyframes pf-spin{to{transform:rotate(360deg)}}
.pf-startup-title{display:block;font-weight:700}
.pf-startup-detail,.pf-startup-count{display:block;font-size:.9rem;color:var(--bs-secondary-color,#4f5b67)}
.pf-startup-count:empty{display:none}
.pf-reload{margin-top:.6rem}
.shiny-output-error:not(.shiny-output-error-validation){display:block;color:var(--bs-danger-text-emphasis,#8a1c12);
 background:var(--bs-danger-bg-subtle,#fdecea);border:1px solid var(--bs-danger-border-subtle,#e5a39b);border-radius:.5rem;
 padding:.7rem .9rem;font-size:.9rem;line-height:1.45;white-space:pre-wrap;overflow:auto;text-align:left}
span.shiny-output-error:not(.shiny-output-error-validation){display:inline-block;font-size:.8rem;line-height:1.3;padding:.3rem .5rem}
span.shiny-output-error:not(.shiny-output-error-validation)::before,span.shiny-output-error[data-pf-what]:not(.shiny-output-error-validation)::before{content:'Could not compute';margin-bottom:.1rem}
span.shiny-output-error:not(.shiny-output-error-validation)::after{content:'This is a bug in the app.';margin-top:.15rem}
.shiny-output-error:not(.shiny-output-error-validation)::before{content:'This panel could not be computed';display:block;font-weight:700;margin-bottom:.25rem}
.shiny-output-error[data-pf-what]:not(.shiny-output-error-validation)::before{content:'Could not compute: ' attr(data-pf-what)}
.shiny-output-error:not(.shiny-output-error-validation)::after{content:'This is a bug in the app, not something you did. The other panels still work; reloading the page may help.';
 display:block;margin-top:.4rem;font-size:.85em;opacity:.85}
.shiny-output-error-validation,.pf-empty{display:block;color:var(--bs-secondary-color,#4f5b67);background:var(--bs-tertiary-bg,#eef1f4);
 border:1px dashed var(--bs-border-color,#d5dbe1);border-radius:.5rem;padding:.6rem .85rem;font-size:.9rem;line-height:1.45;white-space:normal;text-align:left}
span.shiny-output-error-validation{display:inline-block;font-size:.8rem;padding:.3rem .5rem}
.shiny-output-error-validation::before{content:none}
@media (prefers-reduced-motion:reduce){.pf-spinner{animation:none}.pf-startup{transition:none}}
"

PORTFOLIO_STATUS_JS <- "
(function () {
  if (window.portfolioApp) return;
  var S = window.portfolioApp = { state: 'connecting', connected: false, ready: false, t0: Date.now() };
  var WATCHDOG_MS = 45000;
  function card() { return document.getElementById('pf-startup'); }
  function put(sel, txt) { var c = card(), e = c && c.querySelector(sel); if (e) e.textContent = txt; }
  function shown(e) {
    var x = getComputedStyle(e).display === 'contents' ? e.parentElement : e;
    return !!(x && (x.offsetWidth || x.offsetHeight || x.getClientRects().length));
  }
  function filled(e) {
    if (e.classList.contains('recalculating')) return false;
    if (e.classList.contains('shiny-output-error')) return true;
    if (e.classList.contains('shiny-plot-output') || e.classList.contains('shiny-image-output')) {
      var i = e.querySelector('img'); return !!(i && i.getAttribute('src'));
    }
    return (e.textContent || '').trim().length > 0 || !!e.querySelector('img,svg,canvas,table');
  }
  function count() {
    var outs = [].slice.call(document.querySelectorAll('.shiny-bound-output')).filter(shown);
    return { n: outs.length, done: outs.filter(filled).length,
             busy: outs.filter(function (e) { return e.classList.contains('recalculating'); }).length };
  }
  function label(el) {
    var vb = el.closest('.bslib-value-box, .value-box'), t = vb && vb.querySelector('.value-box-title');
    if (t && t.textContent.trim()) return t.textContent.trim();
    var c = el.closest('.card'), h = c && c.querySelector(':scope > .card-header');
    if (h && !h.querySelector('.nav') && h.textContent.trim()) return h.textContent.trim();
    var p = el.closest('.tab-pane'), v = p && p.getAttribute('data-value');
    if (v) return v + (el.id ? ', output ' + el.id : '');
    return el.id ? 'output ' + el.id : 'this panel';
  }
  function finish() {
    if (S.ready) return;
    S.ready = true; S.state = 'ready'; S.tReady = Date.now();
    clearInterval(S.tick); clearTimeout(S.watch);
    var c = card(); if (c) { c.classList.add('pf-hidden'); c.classList.remove('pf-problem'); }
    document.documentElement.setAttribute('data-pf-state', 'ready');
  }
  function problem(title, detail) {
    S.state = 'problem';
    var c = card(); if (!c) return;
    c.classList.remove('pf-hidden'); c.classList.add('pf-problem');
    put('.pf-startup-title', title); put('.pf-startup-detail', detail); put('.pf-startup-count', '');
    var b = c.querySelector('.pf-reload'); if (b) b.hidden = false;
    document.documentElement.setAttribute('data-pf-state', 'problem');
  }
  function check() {
    var k = count();
    if (!S.ready) put('.pf-startup-count', k.n ? k.done + ' of ' + k.n + ' panels ready' : '');
    if (S.connected && S.idle && !S.ready && k.busy === 0) finish();
  }
  document.addEventListener('click', function (ev) {
    if (ev.target && ev.target.classList && ev.target.classList.contains('pf-reload')) {
      try { window.top.location.reload(); } catch (e) { window.location.reload(); }
    }
  });
  $(document).on('shiny:connected', function () {
    S.connected = true; S.state = 'computing'; S.tConnected = Date.now();
    put('.pf-startup-title', 'Computing the first results');
    S.watch = setTimeout(function () {
      if (!S.ready) problem('Still computing after 45 seconds',
        'R may have stopped, usually because a file failed to download. Reload the page to start again.');
    }, WATCHDOG_MS);
  });
  $(document).on('shiny:busy', function () { S.idle = false; });
  $(document).on('shiny:idle', function () { S.idle = true; setTimeout(check, 0); });
  $(document).on('shiny:value', function () { if (!S.ready) setTimeout(check, 0); });
  $(document).on('shiny:disconnected', function () {
    problem('The connection to R was lost',
      'The app stopped responding. Reload the page to start it again; changes made in this visit are not kept.');
  });
  $(document).on('shiny:error', function (ev) {
    var e = ev.error || {}, types = [].concat(e.type || []);
    if (!e.message || types.indexOf('validation') >= 0 || !ev.target || !ev.target.setAttribute) return;
    ev.target.setAttribute('data-pf-what', label(ev.target));
  });
  S.tick = setInterval(check, 500);
})();
"

app_status_ui <- function(computing) {
  htmltools::tagList(
    shiny::useBusyIndicators(spinners = TRUE, pulse = TRUE),
    htmltools::tags$head(htmltools::tags$style(htmltools::HTML(PORTFOLIO_STATUS_CSS)),
                         htmltools::tags$script(htmltools::HTML(PORTFOLIO_STATUS_JS))),
    htmltools::div(
      id = "pf-startup", class = "pf-startup", role = "status", `aria-live` = "polite",
      htmltools::div(
        class = "pf-startup-card",
        htmltools::span(class = "pf-spinner", `aria-hidden` = "true"),
        htmltools::div(
          htmltools::span(class = "pf-startup-title", "Connecting to R"),
          htmltools::span(class = "pf-startup-detail", sprintf("R is computing %s.", computing)),
          htmltools::span(class = "pf-startup-count"),
          htmltools::tags$button(type = "button", class = "btn btn-sm btn-primary pf-reload", hidden = NA,
                                 "Reload the page")))))
}
