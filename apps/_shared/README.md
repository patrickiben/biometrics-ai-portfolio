# Shared parts of the in-browser apps

TRIALMON, the UAT tracker and the Study Lifecycle Monitor run in the visitor's browser with
Shinylive (webR). A first visit downloads about 55 MB and takes 10 to 20 seconds, so a visitor
must always be able to tell what the app is doing. Three shared pieces make sure of that:

| File | What it is |
|---|---|
| [`launch_template/index.html`](launch_template/index.html) | The page for every app, used as the Shinylive export template. The Pages build fills it from `apps/<name>/launch.json`. |
| [`launch.js`](launch.js), [`launch.css`](launch.css) | Start R in the page and report each step; the page style, from the `site.css` tokens (light and dark). |
| [`portfolio_app.R`](portfolio_app.R) | The R pattern every app uses: a startup card, readable error cards, explained empty states, a graphics warm-up and the site theme. |
| `../<name>/launch.json` | One per app: the launch page text and the smoke test's list of outputs to check, for example [`../trialmon/launch.json`](../trialmon/launch.json). |
| [`../../.github/pages/smoke/smoke.mjs`](../../.github/pages/smoke/smoke.mjs) | The deploy smoke test, run by the Pages workflow before anything is deployed. |

The build ([`../../.github/pages/build_site.R`](../../.github/pages/build_site.R)) stages each
app's folder with `portfolio_app.R` next to `app.R`, exports it with this template, and checks the
result. Synthetic data only.

## The launch page

The page text shows at once, before any R loads: the title, what the app shows, a "Try this" list,
an optional screenshot (`"screenshot"` in `launch.json`, a file in `apps/<name>/`), the synthetic
data note, and the expected first-load size and time. Below it, the live app area has a status line
with the elapsed time, and a step list that each real signal ticks off:

1. This page and its instructions.
2. The service worker is registered and controls the page (it lets R serve the app inside the
   page). The app starts only once it does, so the R download is not fetched twice.
3. R and the app's packages: `shinylive.js` loads, R's startup banner arrives from the webR
   worker (R itself has downloaded and started), then the viewer gives the app frame its address
   (the packages have loaded and `app.R` has run).
4. The app's page, served by R: the frame's `load` event.
5. The first results: inside the same-origin frame, `shiny:connected`, `shiny:busy` and
   `shiny:idle`, and the outputs themselves ("3 of 12 panels filled").

After that the status line says Ready, or Working while R recomputes. It reports instead of going
blank when: the browser has no service worker or the registration fails; the page is not under the
service worker's control, or the viewer throws "ServiceWorker controller was not found" (the page
reloads once; a second failure within two minutes shows the problem instead of looping); a file R
needs does not download (it says which, from webR's messages or a check of the main files);
`app.R` stops with an R error (it shows R's message); the connection to R is lost; nothing is ready
after 60 seconds of visible time (it says which step it is on and why that step usually stalls);
or one update keeps R busy for 45 seconds. Each problem has a Reload button, links to the guide and
the read-only snapshot, and technical details for a bug report. `window.launchStatus` and
`data-state` on `#app` expose the same state to tests.

## The R pattern (`portfolio_app.R`)

```r
suppressPackageStartupMessages({ library(shiny); library(bslib); library(DT); library(ggplot2) })
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")
warm_up_graphics()   # before the UI: in the browser, loads the plot fonts while the launch page reports

ui <- page_sidebar(..., app_status_ui("the KPIs, the test table and the gate"), ...)

server <- function(input, output, session) {
  output$plot <- renderPlot(guard("the area plot", { ... }))
  output$tbl <- renderDT({
    d <- filtered()
    explain_empty(nrow(d) > 0, "No tests match these filters. Clear a filter to see all 29.")
    datatable(d)
  })
}
```

- `app_status_ui(computing)` shows a startup card that names what R is computing and counts the
  panels as they fill, turns on Shiny's busy indicators for every later update, says so when the
  first results take more than 45 seconds or the connection to R is lost, and styles errors: a
  panel that fails shows "Could not compute:" with the panel's name, R's message and "This is a bug in
  the app".
- `guard(what, expr)` adds what was being computed to an error's message. `req()` and `validate()`
  pass through.
- `explain_empty(ok, message)` and `empty_state(message)`: an output a visitor can see is never
  silently empty. Use them instead of a bare `req()`, which leaves the panel blank.
- `warm_up_graphics()` draws one throwaway plot in the browser only. webR downloads the graphics
  library and fonts the first time anything is plotted; without the warm-up that happened after
  the layout was drawn, so a failed download left every plot empty with no message.
- `portfolio_theme()` and `portfolio_colors(dark)` carry the site's color tokens into bslib and
  into plots; pair the theme with `input_dark_mode()`, which follows the system setting.

## `launch.json`

`source` (the app folder), `title`, `summary` (one paragraph), `try` (three to five steps),
`screenshot` (`null`, or `src`, `alt`, `width`, `height`, `caption`), `links` (label and `href`
relative to `apps/<name>/`), `first_load` (`download_mb`, `first_s`, `revisit_s`), and `smoke`:
`timeout_s`, `outputs` (ids that must have content on first load), `expect` (exact text for some
of them), `fit` (optional: a CSS selector and a window width at which that element must fit its box
without sideways scrolling, for example a table at phone width) and `tabs` (a tab label and the
outputs it must fill once clicked).

## The smoke test

```sh
npm ci --prefix .github/pages/smoke
Rscript .github/pages/build_site.R ../portfolio-site
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  node .github/pages/smoke/smoke.mjs ../portfolio-site --shots ../smoke-shots
```

It serves the build under `/biometrics-ai-portfolio/` as Pages does, opens each launch page with a
fresh browser profile and fails unless the page text paints within 3 seconds, the app reaches
Ready within `timeout_s`, every listed output has content and no panel shows an error, each element
listed in `fit` fits its box at its window width, each listed tab fills in, and a reload reaches
Ready again. `--fault 'REGEX=404'` (or `drop`, `hang`) with
`--expect-problem KIND` checks an error state instead, for example
`--fault 'shinylive-sw\.js$=404' --expect-problem sw-failed`.

Checked locally on 2026-10-25 (macOS, headless Chrome 155, served from the same machine): all
three apps passed, ready 7.7 to 8.9 s after opening on a first visit and 7.2 to 8.6 s on a reload,
page text painted in under 60 ms. With the network throttled to 6 Mbps, the app was ready after
about 100 s; the 60-second notice appeared, named the step it was on, and cleared by itself. The error states were checked the same way: a service worker script that answers 404, a
font, font cache, graphics library, `R.wasm` or webR worker that does not download, a missing
`app.json` or `shinylive.js`, an `app.R` that stops, failing outputs, an endless computation, a
hard reload and a repeated viewer error. Safari and Firefox were not checked.
