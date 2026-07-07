# Build the UAT tracker yourself (R Shiny)

You do not have to accept a black-box GUI. This app is about 150 lines of R, and
the pattern is worth owning because you can reuse it for almost any
"table + rules + live status" tool. Here is how it is built, piece by piece.

The one principle: **separate the logic from the UI.** The rules (the go-live
gate, the KPIs) live in plain functions in `R/logic.R`. The app, the Quarto
guide, and the unit tests all call those same functions. You can change what the
gate *means* without touching the app, and change how it *looks* without
touching the rules.

---

## Step 1 — write the logic as plain functions

No Shiny yet. Just functions that take data frames and return numbers. This is
`R/logic.R`:

```r
# READY only when every Critical test passes, zero open Critical/Major
# defects, and traceability is complete.
uat_gate <- function(tests, defects, trace) {
  crit_fail <- sum(tests$Priority == "Critical" & tests$Status != "Pass")
  open_cm   <- sum(defects$Status == "Open" & defects$Severity %in% c("Critical","Major"))
  trace_gap <- sum(trace$Covered != "Y")
  go <- crit_fail == 0 && open_cm == 0 && trace_gap == 0
  list(crit_fail = crit_fail, open_cm = open_cm, trace_gap = trace_gap,
       go = go, verdict = if (go) "READY for sign-off" else "NOT ready - blocked")
}
```

`uat_summary()` does the same for the KPIs. Because these are pure functions,
you can test them in the console before writing a single line of UI.

## Step 2 — test the logic first

```r
source("R/logic.R")
d <- uat_load("../templates")
uat_gate(d$tests, d$defects, d$trace)$verdict   # "NOT ready - blocked"
```

If the rule is right here, it is right everywhere, because everything calls it.

## Step 3 — the app skeleton

An `app.R` is three things: a `ui`, a `server`, and `shinyApp(ui, server)`.

```r
library(shiny); library(bslib); library(DT); library(ggplot2)
source("R/logic.R")
seed <- uat_load()

ui <- page_sidebar(
  title = "IRT / RTSM UAT Tracker",
  theme = bs_theme(version = 5, bootswatch = "darkly"),
  sidebar = sidebar( ... ),
  # value boxes, table, gate, plot ...
)

server <- function(input, output, session) { ... }

shinyApp(ui, server)
```

`bslib::page_sidebar` gives you a modern sidebar layout for free;
`layout_columns()` and `card()` arrange the panels.

## Step 4 — hold the editable state in `reactiveValues`

The data changes as the user works, so it lives in `reactiveValues`. Every
output reads from it, so every output updates when it changes.

```r
server <- function(input, output, session) {
  rv <- reactiveValues(tests = seed$tests, defects = seed$defects, trace = seed$trace)

  gate <- reactive(uat_gate(rv$tests, rv$defects, rv$trace))   # recomputes on any change
  summ <- reactive(uat_summary(rv$tests, rv$defects, rv$trace))
```

`gate` and `summ` are **reactive expressions**: Shiny re-runs them automatically
whenever `rv$tests` (or defects/trace) changes. This is the whole trick.

## Step 5 — value boxes that read the reactive

```r
  output$v_pass <- renderText(as.character(summ()$pass))
```

In the UI: `value_box("Passed", textOutput("v_pass"), theme = "success")`.

## Step 6 — a selectable table and a status setter

Show the tests in a `DT` table with single-row selection. When a row is
selected, show its detail and a set of radio buttons to mark it:

```r
  output$tests <- renderDT(
    datatable(rv$tests[, cols], selection = "single", filter = "top"),
    server = TRUE)

  output$detail <- renderUI({
    sel <- input$tests_rows_selected
    if (length(sel) == 0) return("No test selected.")
    t <- rv$tests[sel, ]
    radioButtons("set_status", "Mark this test:", STATUSES, selected = t$Status, inline = TRUE)
  })

  observeEvent(input$set_status, {                 # user picked a new status
    sel <- input$tests_rows_selected
    if (length(sel) == 1 && rv$tests$Status[sel] != input$set_status) {
      rv$tests$Status[sel] <- input$set_status     # mutate the state ...
    }                                              # ... and everything recomputes
  })
```

That last write to `rv$tests$Status` is what makes the gate flip. You do not
call the gate yourself; changing `rv` triggers the reactive that does.

## Step 7 — the gate output

```r
  output$gate <- renderUI({
    g <- gate()
    div(class = if (g$go) "alert alert-success" else "alert alert-danger", g$verdict)
    # ... plus the three tick/cross criteria
  })
```

## Step 8 — a plot and a download

`renderPlot({ ggplot(uat_area_counts(rv$tests), ...) })` for the by-area bar, and
a `downloadHandler` that writes `rv$tests` to CSV so results round-trip to Excel
and the eTMF.

---

## Run it, and verify it without a browser

```r
shiny::runApp("uat_irt/shiny")
```

You can even test the reactivity headless, which is how this app was checked:

```r
shiny::testServer("uat_irt/shiny", {
  session$setInputs(tests_rows_selected = which(rv$tests$TestID == "RAND-04"),
                    set_status = "Pass")
  gate()$crit_fail            # dropped by one
})
```

## Make it yours

- **Change the rule:** edit `uat_gate()` in `R/logic.R` (for example, allow a Minor-defect waiver). Nothing else changes.
- **Change the data:** edit `../templates/*.csv`.
- **Add a column:** add it to the CSV and to the `datatable()` column list.
- **Add a panel:** another `card()` in the UI and a `render*` in the server.

The same skeleton (logic core → `reactiveValues` → reactive rules → outputs)
builds the find-hours app too. See `budget_reconciliation/BUILD_IT.md`.
