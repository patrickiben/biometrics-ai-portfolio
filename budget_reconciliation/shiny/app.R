# ===========================================================================
# app.R — Hours Budget Reconciliation ("Find Hours") Shiny app
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
source("R/logic.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

seed <- hours_load()

ui <- page_sidebar(
  title = "Find Hours — Hours Budget Reconciliation",
  theme = bs_theme(version = 5, bootswatch = "darkly", primary = "#5b8cff"),
  sidebar = sidebar(
    width = 300,
    div(class = "text-warning small fw-bold", "HOURS / EFFORT ONLY — no $, no headcount"),
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
    value_box("Contingency", textOutput("v_cont"), theme = "secondary"),
    value_box("Net findable", textOutput("v_find"), theme = "success")
  ),
  layout_columns(
    col_widths = c(7, 5),
    card(card_header("Project effort ledger (hours) — editable"),
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
                   " Move hours from tasks forecasting under plan (EAC < planned) — already yours."),
           tags$li(tags$b("Draw the contingency buffer."),
                   " The management reserve exists for this; a decision to record, not a silent move."),
           tags$li(tags$b("Defer / re-sequence lower-priority in-scope work,"),
                   " with the PM's agreement on new dates."),
           tags$li(tags$b("Escalate a change order"),
                   " for any residual shortfall — genuine added scope, not a silent over-run.")))
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

  metrics <- reactive(hours_metrics(rv$ledger, input$contingency %||% seed$contingency))
  fh <- reactive(find_hours(input$need %||% 0, rv$ledger, input$contingency %||% seed$contingency))

  output$v_planned <- renderText(sprintf("%d h", metrics()$planned))
  output$v_actual  <- renderText(sprintf("%d h", metrics()$actual))
  output$v_eac     <- renderText(sprintf("%d h", metrics()$eac))
  output$v_cont    <- renderText(sprintf("%d h", metrics()$contingency))
  output$v_find    <- renderText(sprintf("%d h", metrics()$findable))

  output$ledger <- renderDT({
    isolate({
      d <- rv$ledger
      names(d) <- c("Deliverable", "Planned", "Actual", "% done", "EAC", "Variance")
      datatable(d, rownames = FALSE, selection = "none",
                editable = list(target = "cell", disable = list(columns = c(0, 5))),
                options = list(dom = "t", paging = FALSE, ordering = FALSE,
                               scrollY = "300px", scrollCollapse = TRUE)) |>
        formatStyle("Variance", color = styleInterval(c(-0.5, 0.5),
                    c("#e8657a", "#94a1c0", "#43c47d")))
    })
  }, server = TRUE)

  proxy <- dataTableProxy("ledger")
  observeEvent(input$ledger_cell_edit, {
    info <- input$ledger_cell_edit
    j <- info$col + 1L                      # rownames=FALSE -> 0-based data cols
    num <- suppressWarnings(as.numeric(info$value))
    if (j %in% 2:5 && !is.na(num)) {
      rv$ledger[info$row, j] <- num
      rv$ledger$variance <- rv$ledger$planned - rv$ledger$eac
      d <- rv$ledger; names(d) <- c("Deliverable","Planned","Actual","% done","EAC","Variance")
      replaceData(proxy, d, resetPaging = FALSE, rownames = FALSE)
    }
  })

  output$verdict <- renderUI({
    f <- fh(); m <- f$metrics
    src <- tags$div(class = "mb-2",
      tags$div(class = "d-flex justify-content-between border-bottom pb-1",
               tags$b(sprintf("Need: %d h", f$need))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("1 · Under-run slack"), tags$span(class = "text-success", sprintf("−%d h", f$from_slack))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("2 · Contingency"), tags$span(class = "text-success", sprintf("−%d h", f$from_cont))),
      tags$div(class = "d-flex justify-content-between",
               tags$span("3 · Shortfall"),
               tags$span(class = if (f$shortfall > 0) "text-danger" else "text-success",
                         sprintf("%d h", f$shortfall))))
    if (f$absorbable) {
      box <- tags$div(class = "alert alert-success",
        tags$div(class = "h5", "Absorbable internally"),
        sprintf("Sourced %d h from under-run slack and %d h from contingency (%d h contingency left). Record the reallocation; no change order needed.",
                f$from_slack, f$from_cont, f$contingency_left))
    } else {
      box <- tags$div(class = "alert alert-danger",
        tags$div(class = "h5", sprintf("Change order needed: %d h", f$shortfall)),
        sprintf("Net headroom (%d h) covers %d h; the remaining %d h is genuine added scope. Defer lower-priority work or raise a change order — do not absorb it as a silent over-run.",
                m$findable, f$need - f$shortfall, f$shortfall))
    }
    tagList(src, box)
  })

  output$plot <- renderPlot({
    d <- rv$ledger
    dd <- rbind(
      data.frame(deliverable = d$deliverable, hours = d$planned, kind = "Planned"),
      data.frame(deliverable = d$deliverable, hours = d$eac,     kind = "Forecast (EAC)"))
    dd$deliverable <- factor(dd$deliverable, levels = rev(d$deliverable))
    ggplot(dd, aes(hours, deliverable, fill = kind)) +
      geom_col(position = "dodge", width = 0.7) +
      scale_fill_manual(values = c("Planned" = "#5b8cff", "Forecast (EAC)" = "#3fd0c9")) +
      labs(x = "Hours", y = NULL, fill = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "top",
            panel.grid.major.y = element_blank(),
            plot.background = element_rect(fill = "#222630", colour = NA),
            panel.background = element_rect(fill = "#222630", colour = NA),
            text = element_text(colour = "#e9edf7"),
            axis.text = element_text(colour = "#c5cee4"),
            panel.grid.major.x = element_line(colour = "#3a4157"))
  })

  output$dl_ledger <- downloadHandler(
    filename = function() "effort_ledger.csv",
    content = function(file) {
      d <- rv$ledger
      names(d) <- c("Deliverable","PlannedHours","ActualToDate","PctComplete","EAC","Variance")
      utils::write.csv(d, file, row.names = FALSE)
    })
  output$dl_co <- downloadHandler(
    filename = function() "change_order.md",
    content = function(file) writeLines(change_order_text(fh()), file))
}

shinyApp(ui, server)
