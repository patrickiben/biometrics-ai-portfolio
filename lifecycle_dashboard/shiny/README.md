# Study Lifecycle Monitor - Shiny app

A runnable operational study-lifecycle console for a synthetic portfolio of eight early-phase
studies. Each study is scored from 0 to 100 on four operational dimensions (timeline, data, TLF
production, resourcing), and the overall score is their weighted blend. The scoring is
transparent: pick a study, nudge its open queries or double programming with the what-if
sliders, and watch its score, the counts and the signals move. No PHI, no participant-level
data. Synthetic, deterministic.

## What you see

- **Start here** (top, collapsible): what the console shows, what each color means, and three
  things to try.
- **KPIs**: active studies by phase, studies at risk and on watch (named), portfolio open
  queries, average deliverables done, and the next DB lock (study and date).
- **Portfolio risk heatmap**: one row per study, its four dimension scores and the outlined
  overall score with its status. Click a row to open that study. On a phone the column headers
  shorten (Time, Data, TLF, Res.) so the whole table, the Overall column included, fits the screen.
- **Early-warning signals**: the rule-based signals, red first. Click a study to open it.
- **The selected study**: its status, the score breakdown (each dimension, its weight, its
  contribution and the inputs that drive it; the Timeline line gives the points behind its score),
  the milestone track against the snapshot date (each milestone's date on the right), the TLF
  production funnel, the deliverables register and the 8-week open-query trend, with a note on
  the study's database lock.
- **Study inputs behind the scores**: the inputs of every study in one table; a what-if value
  shows in purple. A table wider than its card (on a phone) fades at the edge and says it scrolls
  sideways.

Colors: red at risk (above 66), amber watch (34 to 66), green on track (33 or less), purple a
what-if. The header says the data are synthetic and gives the snapshot date (21 Jun 2026). The
sidebar says whether a what-if is in effect, and Reset to data undoes every what-if. On a phone
the study picker and the sliders sit behind the arrow button at the top left.

## Run it

```r
install.packages(c("shiny", "bslib", "ggplot2"))   # once
shiny::runApp("lifecycle_dashboard/shiny")
```

It also runs in the browser with Shinylive (webR): the site's Pages workflow exports this folder,
data included, to `apps/lifecycle_dashboard/`. `app.R` sources the shared status and error helpers, [`apps/_shared/portfolio_app.R`](../../apps/_shared/portfolio_app.R)
(from the repository in local R; the Pages build copies the file next to `app.R` for the browser), and
the site opens the app behind a launch page that reports each step of starting R
([how it works](../../apps/_shared/README.md)). The app shows the shared startup card until its
first results arrive, names a panel that fails, and explains every empty panel (for example a
study with no milestone rows) instead of leaving it blank.

### In the browser

Every panel except the two charts is plain HTML, so the panels follow light and dark without
being redrawn, and only the milestone track and the query trend use ggplot2. The site's tokens
(`assets/theme/tokens.css`, through `bp_theme_head()` in the shared helper) are applied as CSS
variables on the precompiled Bootstrap theme, and the RAG levels, milestone statuses and what-if
marks are site tones: a custom bslib theme would compile Bootstrap's Sass in the visitor's
browser, which measured 0.9 s of every start. The app follows the site's light or dark choice
(input `bp_theme`). The app needs no DT.

Measured on 2026-10-25 with a full local export (as the Pages workflow builds it), served under
`/biometrics-ai-portfolio/` and opened in headless Chrome 155 at 1440x900 with a fresh profile:
R started 0.3 s after the page opened, the layout appeared at 6.7 s, and all 23 outputs had
content at 7.7 s on a first visit (three runs, 7.69 to 7.71 s) and 7.1 to 7.5 s after a reload,
all in one flush, with no output or console errors. Dark mode: 7.9 s, and 7.7 s after a reload.
The deploy smoke test passes (ready at 7.7 s, reload 7.3 s). Before this version, the same build
was ready at 9.0 s. After the review fixes (24 outputs, with the trend note): ready at 7.9 to
8.2 s at 1280, 1366, 1440 and 390 px wide, light and dark; the launch page's status line now
counts the panels as they arrive, so it never says "0 of 24 panels filled" while the app already
shows them (it did for about 0.5 s before). Inside the app, a study switch takes about 0.8 s, a what-if about 0.9 s,
Reset 0.6 s and the light or dark switch 0.7 s. After the move to the site's tokens
(2026-10-25), two runs of the deploy smoke test read 7.7 to 7.9 s to ready and 7.1 s after a reload,
and eight more first visits at 1280 and 390 px, light and dark, 7.3 to 7.9 s. Of R's own start in the browser,
`library(bslib)` takes 2.0 s and `library(ggplot2)` 0.7 s; the app's own computation is under 1 s.

A click on a study selects it in the picker at once, in the browser. Right after a study switch
the sliders still show the previous study's values until R's update arrives, so a slider moved
in that moment is ignored rather than written into the new study.

Tabbing onto a what-if slider leaves its value alone. ion.rangeSlider answers its track taking
focus with a simulated click beside the handle, which moved the value one step, so a keyboard
visitor passing through the sidebar made a what-if nobody asked for (and again after Reset).
`app.R` replaces that focus handler on the slider's shared prototype, so the sliders that
`updateSliderInput()` rebuilds keep the fix; focus still prepares the arrow keys, which move one
step from the data value. The focused track carries the slider role, its label and its value for
assistive technology, and the handle shows a focus ring. The deploy smoke test checks all of this
([`apps/lifecycle_dashboard/launch.json`](../../apps/lifecycle_dashboard/launch.json)).

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny app (a `bslib` layout + the reactive graph). |
| `R/logic.R` | The **pure scoring** - the four operational dimensions (Timeline, Data, TLF, Resource), their weights, the overall blend, the RAG rule, the KPIs, the signal rules, the snapshot date and the words behind each score, as plain functions. The Quarto docs and the unit tests call the same functions. |
| `R/gen_data.R` | The deterministic synthetic-portfolio generator. |
| `data/*.csv` | The portfolio (`studies`, `milestones`, `deliverables`, `query_trend`). |
| `../tests/test-logic.R` | Unit tests (run with `Rscript`): the scoring, the published KPIs, the consistency of the data, the generator's determinism and the what-ifs the guidance promises. |
| `../tests/test-server.R` | The server driven headless with `shiny::testServer()`: every panel has content on first load, opening the app leaves the data as loaded, a what-if moves the score and is shown everywhere, reset restores it, the empty states explain themselves, and the app still starts on data without CP-108. |

The scoring is deliberately transparent:

```
overall = 0.30*Timeline + 0.28*Data + 0.27*TLF + 0.15*Resource      (each 0..100)
RAG:  > 66 red   ·   34-66 amber   ·   <= 33 green
```

The synthetic data are internally consistent, so no panel contradicts another. The phases follow
the database lock: in Startup and Conduct the lock is months ahead; DB Lock is the phase in which
the lock is prepared (the last participant is out and the lock is 8 and 16 days ahead for CP-105
and CP-106); Reporting comes after it. A locked database has no open queries and is fully cleaned
and source-verified, and its query trend is 0 from the lock week on. Final TLFs exist only after
the lock: before it, the programmed and QC'd TLFs are dry runs and the Reporting deliverables have
not started. Each study's query trend ends on its open-query count, the TLFs milestone is done only
when every planned TLF is finalized and the CSR only after the TLFs, the deliverables register
fills in phase order (Analysis follows TLF programming, Reporting follows finalization), and
`days_to_dbl` is the DB lock milestone's date minus the snapshot date. `test-logic.R` checks each
of these.

The scoring follows the lock too. Before it, the Timeline's deadline is the lock and the TLF score
counts the TLFs QC'd as dry runs; after it, the deadline is the next report due (TLFs, then CSR)
and the TLF score counts the finalized TLFs, so a study that locked on time carries no lock
pressure. The "Query backlog rising" signal reads the snapshot week from the study's open queries,
so a what-if moves it like every other score, count and signal.

## Make it your own

`R/gen_data.R` writes the four CSVs so you can see the shape. On a real study you
replace them with a **read-only CTMS / EDC export** carrying the same columns
(`studies.csv`: id, phase, days_to_dbl, open_queries, clean_pct, sdv_pct, the TLF
counts, dbl_prog_pct, discrep; plus `milestones.csv`, `deliverables.csv`,
`query_trend.csv`). Nothing here writes back to a source system. The console opens
on CP-108, the planted at-risk study, or on the first study by id when your data
have no CP-108. To change what "risk" means, edit `score_study()` and `SCORE_WEIGHTS` in
`R/logic.R`; nothing else changes.

## Other formats

The [visual guide](../quarto/lifecycle-guide.html), the shareable
[dashboard](../quarto/lifecycle-dashboard.html), and the
[run-and-build page](../quarto/lifecycle-build.html) are all built from this same
`R/logic.R` and these CSVs. After a change to the data or the scoring, re-render them
(`quarto render` in `../quarto/`): `test-logic.R` fails when their KPI boxes or the snapshot's
ranked table no longer match the committed CSVs.

*A screening lens for operational health, never a reported clinical number.*
