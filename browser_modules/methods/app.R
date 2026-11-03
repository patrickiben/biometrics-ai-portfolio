suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(ggplot2)
  library(jsonlite)
})
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")
asset_root <- if (file.exists("browser_modules/methods/methods.R")) normalizePath(".") else normalizePath("../..")
source(file.path(asset_root, "browser_modules/methods/methods.R"))
warm_up_graphics()
METHOD_LIMIT <- 50 * 1024^2
METHOD_FIELDS <- c("method", "n", "seed", "true_gmr", "within_cv", "replicates", "half_life", "theta", "washouts", "disposition", "configurations", "scenarios", "sign_vectors", "bootstrap", "controls")
method_choices <- setNames(names(METHOD_LABELS), unname(METHOD_LABELS))
select_plain <- function(id, label, choices, selected = NULL, multiple = FALSE) selectInput(id, label, choices, selected = selected, multiple = multiple, selectize = FALSE)
ui <- fluidPage(
  theme = bp_theme(), tags$head(tags$style(HTML(paste(readLines("methods-ui.css"), collapse = "\n"))), tags$script(HTML(paste(readLines("methods-ui.js"), collapse = "\n")))), app_status_ui("the selected synthetic-method workspace"),
  div(
    class = "method-page", div(class = "method-top", div(p(class = "method-kicker", "TRIAL BIOSTATISTICS TOOLKIT"), h1("Methods workspace"), p("Run the toolkit’s canonical R simulations and worked study in this browser.")), div(bp_theme_toggle(), actionButton("reset", "Reset workspace"))),
    div(class = "method-note", strong("Synthetic methods and worked examples. "), "These modules explore operating characteristics and reproduce a fixed educational study. They do not silently turn into a client analysis. No installation or account is needed. Download results before reloading; this session is not saved. Reload the page to stop a long run; unsaved results are lost."),
    div(class = "method-config", select_plain("method", "Choose a method module", c("Choose a module…" = "", method_choices), ""), uiOutput("setup")),
    uiOutput("run_control"), uiOutput("state"), uiOutput("results")
  )
)
server <- function(input, output, session) {
  rv <- reactiveValues(result = NULL, state = "empty", message = "Choose a method, inspect the settings, and confirm before running.", owned = character())
  epoch <- function() as.integer(isolate(input$form_epoch) %or% 0L)
  invalidate <- function() {
    if (!is.null(rv$result)) unlink(rv$result$directory, recursive = TRUE)
    rv$result <- NULL
    rv$state <- "changed"
    rv$message <- "Settings changed. Review and run again to create current results."
  }
  cfg <- reactive({
    kind <- input$method %or% ""
    if (!nzchar(kind)) {
      return(list(kind = "", confirmed = FALSE))
    }
    x <- methods_defaults(kind)
    for (k in intersect(names(x), METHOD_FIELDS)) if (k != "kind" && !is.null(input[[k]])) x[[k]] <- input[[k]]
    for (k in intersect(c("theta", "washouts"), names(x))) {
      value <- input[[k]]
      x[[k]] <- if (is.null(value) || !nzchar(trimws(value))) numeric() else suppressWarnings(as.numeric(strsplit(trimws(value), "[,;[:space:]]+")[[1]]))
    }
    x$confirmed <- isTRUE(input$confirmed)
    x
  })
  previous <- NULL
  observe({
    x <- cfg()
    x$confirmed <- NULL
    if (!identical(x, previous)) {
      previous <<- x
      if (!nzchar(x$kind)) {
        return()
      }
      invalidate()
    }
  })
  observeEvent(input$form_epoch,
    {
      invalidate()
    },
    ignoreInit = TRUE
  )
  observeEvent(input$method_request, {
    if (input$method_request %in% names(METHOD_LABELS)) updateSelectInput(session, "method", selected = input$method_request)
  })
  observeEvent(input$reset, {
    invalidate()
    rv$state <- "empty"
    rv$message <- "Workspace cleared. Choose a method to begin."
    updateSelectInput(session, "method", selected = "")
  })
  output$setup <- renderUI({
    kind <- input$method
    req(kind %in% names(METHOD_LABELS))
    d <- methods_defaults(kind)
    controls <- switch(kind,
      sandbox = tagList(p("A seeded synthetic 2×2 crossover generates eight ADaM-shaped domains and runs the existing PK, NCA, bioequivalence and safety computations. The complete workflow includes the original N=400 calibration diagnostic and can take several minutes depending on your device. The number-grounded text uses the documented deterministic fallback, not a language model."), div(class = "method-grid", numericInput("n", "Participants (even count)", d$n, min = 12, max = 300, step = 2), numericInput("seed", "Simulation seed", d$seed, min = 0, max = 2147483500, step = 1), numericInput("true_gmr", "Simulated true Test/Reference ratio", d$true_gmr, min = .5, max = 2, step = .01), numericInput("within_cv", "Within-participant CV (fraction)", d$within_cv, min = .01, max = .8, step = .01))),
      carryover = tagList(p("Explore residual carryover, exclusions and subtraction sensitivities using the canonical six-arm simulation. Every requested cell is retained with Monte Carlo standard errors. The separate ADaM demonstration remains the fixed 48-hour-washout example."), div(class = "method-grid", numericInput("n", "Participants per simulated study (even)", d$n, min = 12, max = 300, step = 2), numericInput("seed", "Master seed", d$seed, min = 0, max = 2147483500, step = 1), numericInput("replicates", "Replicates per scenario", d$replicates, min = 20, max = 2000, step = 20), numericInput("half_life", "Median half-life (hours)", d$half_life, min = 1, max = 240), textInput("theta", "True Test/Reference ratios (comma separated)", paste(d$theta, collapse = ", ")), textInput("washouts", "Washout / median half-life values", paste(d$washouts, collapse = ", "))), checkboxGroupInput("disposition", "Disposition model", c("Monoexponential" = "mono", "Biexponential sensitivity" = "biexp"), selected = d$disposition), checkboxGroupInput("configurations", "Sampling / assay configurations", c("Base" = "base", "Assay error and quantification limit" = "assay", "Extended sampling" = "extended"), selected = d$configurations), p(class = "method-small", "The published full grid uses 2,000 replicates, both disposition models and all configurations. The browser also permits that grid at the canonical participant count. Larger simulations take longer; lower replicate counts give less precise Monte Carlo estimates.")),
      cqtc = {
        catalog <- methods_cqtc_catalog(asset_root)
        tagList(p("Select canonical scenarios for the placebo-adjusted area test, sign-flip and model diagnostics. Scenario seeds preserve their original index even when a subset is selected. These are exploratory operating characteristics, not a treatment decision."), div(class = "method-grid", numericInput("seed", "Master seed", d$seed, min = 0, max = 2147483500, step = 1), numericInput("replicates", "Replicates per scenario", d$replicates, min = 20, max = 1000, step = 20), numericInput("sign_vectors", "Monte Carlo sign vectors (when not exact)", d$sign_vectors, min = 99, max = 9999, step = 100), numericInput("bootstrap", "Parametric bootstrap draws", d$bootstrap, min = 99, max = 999, step = 100)), select_plain("scenarios", "Scenarios (choose one or more)", setNames(catalog$id, catalog$label), d$scenarios, TRUE), actionButton("cqtc_full", "Select the full published grid"), checkboxInput("controls", "Include noise-free controls and the fixed worked checks", TRUE), p(class = "method-small", "The full published grid uses 1,000 replicates, 9,999 sign vectors and 999 bootstrap draws. It can take several minutes. Exact intervals are retained when a Monte Carlo rate is 0 or 1."))
      },
      study = tagList(p("Reproduce the fixed SIMBE01 educational study: design, SAP, SDTM-like/ADaM data, NCA and bioequivalence analysis, same-author QC, and number-checked CSR text. The original canonical R stages execute here; HTML presentation replaces Quarto. Study assumptions and authored SAP/CSR remain fixed, so this is a reproduction exercise."), p("Fixed design: 40 simulated healthy adults; a two-period TR/RT crossover; 100 mg single doses separated by 14 days; seed 2026. The authored SAP defines populations, BLQ handling, exclusions and bioequivalence models. Review the generated SAP and QC ledger alongside the results."), p("The complete download includes the executed stage sources, CSV/RDS results, XPT, metadata/specification, RTF tables, figures, stage pages, QC ledger, configuration and actual package versions. Browser package versions may differ from the native lockfile."))
    )
    tagList(h2(METHOD_LABELS[[kind]]), controls, checkboxInput("confirmed", "I reviewed these synthetic-method assumptions and understand that execution is not scientific or regulatory approval.", FALSE))
  })
  observeEvent(input$cqtc_full, {
    catalog <- methods_cqtc_catalog(asset_root)
    updateSelectInput(session, "scenarios", selected = catalog$id)
    updateNumericInput(session, "replicates", value = 1000)
    updateNumericInput(session, "sign_vectors", value = 9999)
    updateNumericInput(session, "bootstrap", value = 999)
    updateCheckboxInput(session, "controls", value = TRUE)
  })
  output$run_control <- renderUI({
    input$form_epoch
    actionButton("run", "Run selected R workflow", class = "btn-primary", disabled = !isTRUE(input$confirmed) || !input$method %in% names(METHOD_LABELS))
  })
  outputOptions(output, "run_control", suspendWhenHidden = FALSE)
  output$state <- renderUI(div(id = "method_state", class = paste("method-state", rv$state), `data-state` = rv$state, strong(switch(rv$state,
    empty = "Ready for setup",
    changed = "Review current settings",
    running = "R is computing",
    succeeded = "Workflow completed",
    error = "Resolve the reported issue"
  )), p(rv$message)))
  observeEvent(input$run, {
    invalidate()
    snapshot <- isolate(cfg())
    run_epoch <- epoch()
    checked <- tryCatch(methods_validate(snapshot, asset_root), error = identity)
    if (inherits(checked, "error")) {
      rv$state <- "error"
      rv$message <- conditionMessage(checked)
      return()
    }
    rv$state <- "running"
    rv$message <- "R is executing the selected workflow and preparing the complete review files. Large grids can take several minutes."
    directory <- tempfile("methods-results-")
    rv$owned <- c(rv$owned, directory)
    result <- tryCatch(withProgress(message = "Executing canonical R method", value = 0, {
      methods_run(checked, asset_root, directory, function(value, detail) setProgress(value = value, detail = detail))
    }), error = identity)
    if (inherits(result, "error")) {
      rv$state <- "error"
      rv$message <- gsub(asset_root, "<reviewed source>", conditionMessage(result), fixed = TRUE)
      return()
    }
    if (!identical(snapshot, isolate(cfg())) || run_epoch != epoch()) {
      unlink(directory, recursive = TRUE)
      invalidate()
      return()
    }
    result$epoch <- run_epoch
    rv$result <- result
    rv$state <- "succeeded"
    rv$message <- paste("Completed", length(result$files), "downloadable files. Review warnings and method limitations before reuse.")
    session$sendCustomMessage("method-ready", list(epoch = run_epoch))
  })
  current <- reactive({
    x <- rv$result
    if (is.null(x) || !identical(x$config, isolate(cfg())) || x$epoch != as.integer(input$form_epoch %or% 0L)) {
      return(NULL)
    }
    x
  })
  output$results <- renderUI({
    x <- current()
    if (is.null(x)) {
      return(div(class = "method-note", "Current results appear after a successful run. Changing a setting clears the previous result set."))
    }
    div(id = "method_result", `data-run-id` = basename(x$directory), `data-module` = x$config$kind, h2("Review and download"), if (length(x$warnings)) tags$details(tags$summary(paste(length(x$warnings), "retained warnings")), tags$ul(lapply(x$warnings, tags$li))), div(class = "method-grid", select_plain("table_choice", "Computed table", setNames(seq_along(x$tables), names(x$tables)), 1), if (length(x$plots)) select_plain("plot_choice", "Figure", setNames(seq_along(x$plots), names(x$plots)), 1)), p(class = "method-small", "The on-screen table previews up to 1,000 rows. Complete CSV/RDS files and paginated HTML reports are retained in the download."), DTOutput("table"), if (length(x$plots)) div(class = "method-figure", plotOutput("figure", height = if (x$config$kind == "cqtc") "1400px" else "580px")), div(class = "method-actions", actionButton("download_all", "Complete review package (.zip)", class = "btn-primary method-export"), actionButton("download_report", "Report index (needs extracted ZIP)", class = "method-export")), select_plain("file_choice", "Individual file", setNames(x$files, x$files)), actionButton("download_one", "Download selected file", class = "method-export"), p(class = "method-small", "Download and extract the ZIP, then open report.html. This preserves every source, result, warning and version. The browser transfer limit is 50 MiB of encoded data; oversized bundles can be downloaded as individual files."), textOutput("download_status"))
  })
  output$table <- renderDT(
    {
      x <- current()
      req(x)
      i <- as.integer(input$table_choice %or% 1)
      req(i %in% seq_along(x$tables))
      datatable(head(x$tables[[i]], 1000), rownames = FALSE, escape = TRUE, class = "compact stripe nowrap", options = list(pageLength = 10, scrollX = TRUE))
    },
    server = FALSE
  )
  output$figure <- renderPlot(
    {
      x <- current()
      req(x, length(x$plots))
      i <- as.integer(input$plot_choice %or% 1)
      req(i %in% seq_along(x$plots))
      x$plots[[i]] + bp_ggplot_theme(if (identical(input$bp_theme, "light")) "light" else "dark")
    },
    res = 100,
    alt = "Selected synthetic-method figure; exact estimates and uncertainty are in the complete result tables."
  )
  download_status <- reactiveVal("")
  output$download_status <- renderText(download_status())
  send <- function(which) {
    x <- isolate(current())
    if (is.null(x)) {
      return()
    }
    tryCatch(
      {
        files <- if (which == "all") x$files else if (which == "report") "report.html" else input$file_choice
        if (!length(files) || any(!files %in% x$files)) stop("Select a current result file.")
        paths <- file.path(x$directory, files)
        sizes <- file.info(paths)$size
        if (anyNA(sizes) || sum(4 * ceiling(sizes / 3)) > METHOD_LIMIT) stop("This download exceeds the 50 MiB encoded transfer limit. Use individual-file downloads; computed results are unchanged.")
        parts <- lapply(seq_along(files), function(i) list(name = files[i], base64 = jsonlite::base64_enc(readBin(paths[i], "raw", n = sizes[i]))))
        payload <- list(epoch = x$epoch, filename = if (which == "all") paste0("methods-", x$config$kind, ".zip") else basename(files[1]))
        if (which == "all") {
          payload$files <- parts
        } else {
          payload$base64 <- parts[[1]]$base64
          payload$type <- "application/octet-stream"
        }
        session$sendCustomMessage("method-download", payload)
        download_status("Download prepared from the current run.")
      },
      error = function(e) download_status(conditionMessage(e))
    )
  }
  observeEvent(input$download_all, send("all"))
  observeEvent(input$download_report, send("report"))
  observeEvent(input$download_one, send("one"))
  observeEvent(input$download_failed, download_status(input$download_failed))
  session$onSessionEnded(function() {
    for (path in isolate(rv$owned)) unlink(path, recursive = TRUE)
  })
}
`%or%` <- function(a, b) if (is.null(a) || !length(a)) b else a
shinyApp(ui, server)
