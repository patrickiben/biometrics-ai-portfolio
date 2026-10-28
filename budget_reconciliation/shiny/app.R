# ===========================================================================
# app.R: Hours Budget Reconciliation ("Find Hours") Shiny app
#
# A runnable, editable version of the find-hours worksheet. Edit the effort
# ledger, type an out-of-scope ask, and watch net-findable and the
# absorbable-vs-change-order verdict recompute live. HOURS ONLY, synthetic.
#
# Run:  shiny::runApp("budget_reconciliation/shiny")   (from the package root)
#   or: setwd("budget_reconciliation/shiny"); shiny::runApp()
#
# The math lives in R/logic.R (shared with the Quarto docs + unit tests);
# the seed data is ../templates/project_hours_ledger.csv (edit it to reuse).
# ===========================================================================
library(shiny)
library(bslib)
library(DT)
library(ggplot2)
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")
source("R/logic.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

seed <- hours_load()

ui <- page_sidebar(
  title = div(class = "d-flex flex-wrap align-items-center gap-3", "Find Hours: Hours Budget Reconciliation", bp_theme_toggle()),
  theme = bp_theme(),
  bp_theme_head(),
  tags$style(HTML(".bslib-page-sidebar>.navbar{background:var(--surface);border-bottom:1px solid var(--line-2)}
    .bslib-sidebar-layout{--_sidebar-bg:var(--surface);--bslib-sidebar-bg:var(--surface)}
    html .bslib-value-box{background:var(--surface)!important;color:var(--ink)!important;border:1px solid var(--line-2)}
    .value-box-title{color:var(--muted)}.value-box-value{color:var(--accent)}")),
  sidebar = sidebar(
    width = 300,
    div(class = "text-warning small fw-bold", "HOURS / EFFORT ONLY, no $, no headcount"),
    numericInput("need", "Out-of-scope ask (hours)", value = 45, min = 0, step = 5),
    div(class = "d-flex flex-wrap gap-1 mb-2",
        actionButton("q20",  "20h",  class = "btn-sm btn-outline-secondary"),
        actionButton("q45",  "45h",  class = "btn-sm btn-outline-secondary"),
        actionButton("q90",  "90h",  class = "btn-sm btn-outline-secondary"),
        actionButton("q150", "150h", class = "btn-sm btn-outline-secondary")),
    numericInput("contingency", "Contingency reserve (hours)",
                 value = seed$contingency, min = 0, step = 5),
    hr(),
    actionButton("reset", "Reset ledger", class = "btn-sm btn-outline-warning"),
    downloadButton("dl_ledger", "Download ledger (CSV)", class = "btn-sm"),
    downloadButton("dl_co", "Download change order", class = "btn-sm"),
    hr(),
    div(class = "small text-muted",
        "Edit any blue-editable cell in the ledger (Planned, Actual, % done, EAC). ",
        "This app connects to no real budget or timesheet.")
  ),
  layout_columns(
    col_widths = c(2, 2, 3, 2, 3),
    value_box("Planned", textOutput("v_planned"), theme = "secondary"),
    value_box("Spent",   textOutput("v_actual"),  theme = "secondary"),
    value_box("Forecast (EAC)", textOutput("v_eac"), theme = "info"),
    value_box("Reserve remaining", textOutput("v_cont"), theme = "secondary"),
    value_box("Net headroom", textOutput("v_find"), theme = "info")
  ),
  layout_columns(
    col_widths = c(7, 5),
    card(card_header("Project effort ledger (hours): editable"),
         DTOutput("ledger")),
    card(card_header("Find hours for the new ask"),
         uiOutput("verdict"))
  ),
  layout_columns(
    col_widths = c(7, 5),
    card(card_header("Planned vs forecast (EAC) by deliverable"),
         plotOutput("plot", height = "320px")),
    card(card_header("The find-hours decision tree"),
         tags$ol(class = "small",
           tags$li(tags$b("Reallocate under-run slack."),
                   " Move hours from tasks forecasting under plan (EAC < planned): already yours."),
           tags$li(tags$b("Draw the contingency buffer."),
                   " Existing forecast overruns consume reserve first. Record any further use for the new ask."),
           tags$li(tags$b("Defer / re-sequence lower-priority in-scope work,"),
                   " with the PM's agreement on new dates."),
           tags$li(tags$b("Escalate a change order"),
                   " for any residual shortfall: genuine added scope, not a silent over-run.")))
  )
)

server <- function(input, output, session) {

  withVar <- function(l) { l$variance <- l$planned - l$eac; l }
  rv <- reactiveValues(ledger = withVar(seed$ledger))

  # quick-pick buttons
  observeEvent(input$q20,  updateNumericInput(session, "need", value = 20))
  observeEvent(input$q45,  updateNumericInput(session, "need", value = 45))
  observeEvent(input$q90,  updateNumericInput(session, "need", value = 90))
  observeEvent(input$q150, updateNumericInput(session, "need", value = 150))
  observeEvent(input$reset, rv$ledger <- withVar(seed$ledger))

  metrics <- reactive(tryCatch(hours_metrics(rv$ledger, input$contingency %||% seed$contingency),
    error = function(e) validate(need(FALSE, conditionMessage(e)))))
  fh <- reactive(tryCatch(find_hours(input$need %||% 0, rv$ledger, input$contingency %||% seed$contingency),
    error = function(e) validate(need(FALSE, conditionMessage(e)))))

  output$v_planned <- renderText(hours_sprintf("%d h", metrics()$planned))
  output$v_actual  <- renderText(hours_sprintf("%d h", metrics()$actual))
  output$v_eac     <- renderText(hours_sprintf("%d h", metrics()$eac))
  output$v_cont    <- renderText(hours_sprintf("%d h", metrics()$remaining_contingency))
  output$v_find    <- renderText(hours_sprintf("%d h", metrics()$findable))

  output$ledger <- renderDT({
    isolate({
      d <- rv$ledger
      names(d) <- c("Deliverable", "Planned", "Actual", "% done", "EAC", "Variance")
      datatable(d, rownames = FALSE, selection = "none",
                editable = list(target = "cell", disable = list(columns = c(0, 5))),
                options = list(dom = "t", paging = FALSE, ordering = FALSE,
                               scrollY = "300px", scrollCollapse = TRUE)) |>
        formatStyle("Variance", color = styleInterval(c(-0.5, 0.5),
                    c("var(--red)", "var(--muted)", "var(--green)")))
    })
  }, server = TRUE)

  proxy <- dataTableProxy("ledger")
  observeEvent(input$ledger_cell_edit, {
    info <- input$ledger_cell_edit
    # Treat browser messages as untrusted, including editable table indices.
    if (!is.list(info) || !is.numeric(info$col) || length(info$col) != 1 ||
        !is.finite(info$col) || !info$col %in% 1:4 || !is.numeric(info$row) ||
        length(info$row) != 1 || !is.finite(info$row) || info$row != as.integer(info$row) ||
        info$row < 1 || info$row > nrow(rv$ledger) || length(info$value) != 1) return()
    j <- info$col + 1L                      # rownames=FALSE -> 0-based data cols
    num <- suppressWarnings(as.numeric(info$value))
    candidate <- rv$ledger
    candidate[info$row, j] <- num
    error <- tryCatch({ hours_validate(candidate, seed$contingency); NULL }, error = conditionMessage)
    if (is.null(error)) {
      rv$ledger <- withVar(candidate)
    } else showNotification(error, type = "error", duration = 8)
    d <- rv$ledger; names(d) <- c("Deliverable","Planned","Actual","% done","EAC","Variance")
    replaceData(proxy, d, resetPaging = FALSE, rownames = FALSE)
  })

  output$verdict <- renderUI({
    f <- fh(); m <- f$metrics
    src <- tags$div(class = "mb-2",
      tags$div(class = "d-flex justify-content-between border-bottom pb-1",
               tags$b(hours_sprintf("Need: %d h", f$need))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("1 · Under-run slack"), tags$span(class = "text-success", hours_sprintf("−%d h", f$from_slack))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("2 · Contingency"), tags$span(class = "text-success", hours_sprintf("−%d h", f$from_cont))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("3 · Added scope unfunded"), tags$span(hours_sprintf("%d h", f$request_shortfall))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("Existing forecast deficit"), tags$span(hours_sprintf("%d h", f$baseline_deficit))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("Total gap"),
               tags$span(class = if (f$shortfall > 0) "text-danger" else "text-success",
                         hours_sprintf("%d h", f$shortfall))))
    if (f$absorbable) {
      box <- tags$div(class = "alert alert-success",
        tags$div(class = "h5", "Absorbable internally"),
        hours_sprintf("Sourced %d h from under-run slack and %d h from contingency (%d h contingency left). Record the reallocation; no change order needed.",
                f$from_slack, f$from_cont, f$contingency_left))
    } else {
      box <- tags$div(class = "alert alert-danger",
        tags$div(class = "h5", f$verdict),
        hours_sprintf("Net headroom is %d h. The new ask uses %d h internally and leaves %d h unfunded; the existing forecast deficit is %d h. Review reallocation, re-sequencing, or a change order. Existing overruns need a separate decision and do not establish added scope.",
                m$findable, f$from_slack + f$from_cont, f$request_shortfall, f$baseline_deficit))
    }
    tagList(src, box)
  })

  output$plot <- renderPlot({
    k <- bp_palette(input$bp_theme)
    d <- rv$ledger
    dd <- rbind(
      data.frame(deliverable = d$deliverable, hours = d$planned, kind = "Planned"),
      data.frame(deliverable = d$deliverable, hours = d$eac,     kind = "Forecast (EAC)"))
    dd$deliverable <- factor(dd$deliverable, levels = rev(d$deliverable))
    ggplot(dd, aes(hours, deliverable, fill = kind)) +
      geom_col(position = "dodge", width = 0.7) +
      scale_fill_manual(values = c("Planned" = k$blue, "Forecast (EAC)" = k$accent)) +
      labs(x = "Hours", y = NULL, fill = NULL) +
      bp_ggplot_theme(k$mode, base_size = 12) +
      theme(legend.position = "top",
            panel.grid.major.y = element_blank())
  })

  output$dl_ledger <- downloadHandler(
    filename = function() "effort_ledger.csv",
    content = function(file) {
      d <- hours_export(rv$ledger, input$contingency %||% seed$contingency)
      utils::write.csv(d, file, row.names = FALSE)
    })
  output$dl_co <- downloadHandler(
    filename = function() "change_order.md",
    content = function(file) writeLines(change_order_text(fh()), file))
}

shinyApp(ui, server)
