# ===========================================================================
# app.R — IRT / RTSM UAT Execution & Sign-off Tracker (Shiny)
#
# A runnable, editable version of the UAT tracker. Select a test and mark it
# Pass/Fail/Blocked, close a defect, and watch the KPIs and the go-live sign-off
# gate recompute live. Operations-only, synthetic, no PHI.
#
# Run:  shiny::runApp("uat_irt/shiny")     (from the package root)
#
# The gate + KPI logic lives in R/logic.R (shared with the Quarto docs + unit
# tests); the seed data is ../templates/*.csv (edit it to reuse for a study).
# ===========================================================================
library(shiny)
library(bslib)
library(DT)
library(ggplot2)
source("R/logic.R")

seed <- uat_load()

ui <- page_sidebar(
  title = "IRT / RTSM UAT Tracker",
  theme = bs_theme(version = 5, bootswatch = "darkly", primary = "#5b8cff"),
  sidebar = sidebar(
    width = 330,
    div(class = "small text-muted", "Operations-only, synthetic, no PHI. ",
        "Select a test row to see its detail and mark it; close a defect to watch the gate move."),
    hr(),
    uiOutput("detail"),
    hr(),
    downloadButton("dl_tests", "Download test results (CSV)", class = "btn-sm"),
    actionButton("reset", "Reset to seed", class = "btn-sm btn-outline-warning")
  ),
  layout_columns(
    col_widths = c(2, 2, 2, 3, 3),
    value_box("Test scripts", textOutput("v_total"), theme = "secondary"),
    value_box("Passed",  textOutput("v_pass"), theme = "success"),
    value_box("Failed",  textOutput("v_fail"), theme = "danger"),
    value_box("Open defects", textOutput("v_def"), theme = "warning"),
    value_box("Requirements traced", textOutput("v_cov"), theme = "info")
  ),
  layout_columns(
    col_widths = c(8, 4),
    card(card_header("Test scripts — click a row to select"),
         DTOutput("tests")),
    card(card_header("Go-live sign-off gate"),
         uiOutput("gate"))
  ),
  layout_columns(
    col_widths = c(7, 5),
    card(card_header("Execution by test area"), plotOutput("plot", height = "300px")),
    card(card_header("Defect log — edit Status (Open / Closed)"), DTOutput("defects"))
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(tests = seed$tests, defects = seed$defects, trace = seed$trace)

  observeEvent(input$reset, {
    rv$tests <- seed$tests; rv$defects <- seed$defects; rv$trace <- seed$trace
  })

  gate <- reactive(uat_gate(rv$tests, rv$defects, rv$trace))
  summ <- reactive(uat_summary(rv$tests, rv$defects, rv$trace))

  output$v_total <- renderText(as.character(summ()$total))
  output$v_pass  <- renderText(as.character(summ()$pass))
  output$v_fail  <- renderText(as.character(summ()$fail))
  output$v_def   <- renderText(as.character(summ()$open_def))
  output$v_cov   <- renderText(sprintf("%d%%", summ()$cov))

  # ---- tests table (select a row) ----
  output$tests <- renderDT({
    isolate({
      d <- rv$tests[, c("TestID","Area","RequirementID","TestTitle","Priority","Status","LinkedDefect")]
      datatable(d, rownames = FALSE, selection = "single", filter = "top",
                colnames = c("ID","Area","Requirement","Title","Priority","Status","Defect"),
                options = list(pageLength = 10, dom = "tip", scrollX = TRUE)) |>
        formatStyle("Status", fontWeight = "bold",
          color = styleEqual(c("Pass","Fail","Blocked","In Progress","Not Run"),
                             c("#43c47d","#e8657a","#e0a64c","#94a1c0","#94a1c0")))
    })
  }, server = TRUE)
  tproxy <- dataTableProxy("tests")
  refresh_tests <- function() {
    d <- rv$tests[, c("TestID","Area","RequirementID","TestTitle","Priority","Status","LinkedDefect")]
    replaceData(tproxy, d, resetPaging = FALSE, rownames = FALSE)
  }

  # ---- selected-test detail + status setter ----
  output$detail <- renderUI({
    sel <- input$tests_rows_selected
    if (is.null(sel) || length(sel) == 0)
      return(div(class = "small text-muted", "No test selected."))
    t <- rv$tests[sel, ]
    tagList(
      div(class = "fw-bold", sprintf("%s — %s", t$TestID, t$TestTitle)),
      div(class = "small text-muted mb-1", sprintf("%s · %s · %s", t$Area, t$RequirementID, t$Priority)),
      div(class = "small mb-1", tags$b("Steps: "), t$Steps),
      div(class = "small mb-2", tags$b("Expected: "), t$ExpectedResult),
      radioButtons("set_status", "Mark this test:", choices = STATUSES,
                   selected = t$Status, inline = TRUE)
    )
  })
  observeEvent(input$set_status, {
    sel <- input$tests_rows_selected
    if (!is.null(sel) && length(sel) == 1 && rv$tests$Status[sel] != input$set_status) {
      rv$tests$Status[sel] <- input$set_status
      refresh_tests()
    }
  })

  # ---- defect log (edit Status) ----
  output$defects <- renderDT({
    isolate({
      d <- rv$defects[, c("DefectID","Severity","Status","FoundInTest","Description")]
      datatable(d, rownames = FALSE, selection = "none",
                editable = list(target = "cell", disable = list(columns = c(0,1,3,4))),
                colnames = c("ID","Severity","Status","Test","Description"),
                options = list(dom = "t", paging = FALSE)) |>
        formatStyle("Status", fontWeight = "bold",
          color = styleEqual(c("Open","Closed"), c("#e8657a","#43c47d")))
    })
  }, server = TRUE)
  dproxy <- dataTableProxy("defects")
  observeEvent(input$defects_cell_edit, {
    info <- input$defects_cell_edit
    val <- trimws(info$value)
    if (info$col + 1L == 3L && val %in% c("Open","Closed")) {   # Status column
      rv$defects$Status[info$row] <- val
      d <- rv$defects[, c("DefectID","Severity","Status","FoundInTest","Description")]
      replaceData(dproxy, d, resetPaging = FALSE, rownames = FALSE)
    }
  })

  # ---- gate ----
  output$gate <- renderUI({
    g <- gate()
    crit_cls <- if (g$go) "alert alert-success" else "alert alert-danger"
    chk <- function(ok, txt) div(class = "small",
      tags$span(class = if (ok) "text-success" else "text-danger",
                if (ok) "✔ " else "✘ "), txt)
    div(
      div(class = crit_cls, div(class = "h5 mb-0", g$verdict)),
      chk(g$crit_fail == 0, sprintf("%d critical test(s) not yet passing", g$crit_fail)),
      chk(g$open_cm == 0,  sprintf("%d open critical/major defect(s)", g$open_cm)),
      chk(g$trace_gap == 0, sprintf("%d requirement(s) without a test", g$trace_gap)),
      div(class = "small text-muted mt-2",
          "A named tester/biostatistician signs UAT off. The gate packages the evidence; it does not grant approval.")
    )
  })

  # ---- area plot ----
  output$plot <- renderPlot({
    df <- uat_area_counts(rv$tests)
    ggplot(df, aes(Freq, Area, fill = Status)) +
      geom_col(width = 0.7) +
      scale_fill_manual(values = c("Pass" = "#43c47d", "Fail" = "#e8657a",
        "Blocked" = "#e0a64c", "In Progress" = "#5b8cff", "Not Run" = "#6b7794"),
        drop = FALSE) +
      labs(x = "Tests", y = NULL, fill = NULL) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top",
            plot.background = element_rect(fill = "#222630", colour = NA),
            panel.background = element_rect(fill = "#222630", colour = NA),
            text = element_text(colour = "#e9edf7"),
            axis.text = element_text(colour = "#c5cee4"),
            panel.grid.major = element_line(colour = "#3a4157"),
            panel.grid.minor = element_blank())
  })

  output$dl_tests <- downloadHandler(
    filename = function() "uat_test_results.csv",
    content = function(file) utils::write.csv(rv$tests, file, row.names = FALSE))
}

shinyApp(ui, server)
