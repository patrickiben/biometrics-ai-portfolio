# Client-neutral vaccine analyses, entirely in browser memory under Shinylive.
# The numerical core and export adapter are staged from their canonical sources.
suppressPackageStartupMessages({ library(shiny); library(bslib); library(DT); library(ggplot2); library(jsonlite) })
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")
asset_root <- if (file.exists("vaccine/browser.R")) "." else "../.."
source(file.path(asset_root, "vaccine/analysis.R"))
source(file.path(asset_root, "vaccine/browser.R"))
options(shiny.maxRequestSize = vaccine_browser_limits()$csv_bytes)
warm_up_graphics()
in_browser <- grepl("emscripten", R.version$os) || grepl("wasm", R.version$platform)
VAX_TRANSFER_LIMIT <- 50 * 1024^2

`%or%` <- function(x, fallback) if (is.null(x)) fallback else x
VAX_OUTPUTS <- c("Geometric titer / concentration summaries" = "immunogenicity", "Paired geometric mean fold rise" = "fold_rise",
  "Study-defined response rates" = "response", "Descriptive response over visits" = "titer_plot",
  "Solicited reactions by dose and symptom" = "reactogenicity", "Diary completeness and daily profiles" = "diary_profile")
VAX_FEEDS <- list(participants = c("USUBJID", "ARM", "IMMFL", "SAFEFL"),
  titers = c("USUBJID", "ASSAY", "ANTIGEN", "UNIT", "VISIT", "AVAL", "QUALIFIER", "LLOQ", "ULOQ"),
  doses = c("USUBJID", "DOSE"), diary = c("USUBJID", "DOSE", "DAY", "SYMPTOM", "GRADE"))
VAX_FEED_LABELS <- c(participants = "Participant populations and treatment arms", titers = "Assay results by analysis visit",
  doses = "Actual administered doses", diary = "Daily solicited reactions")
VAX_FEED_HINTS <- c(participants = "One row per participant. Map the prespecified immunogenicity and safety population flags; populations are not inferred from available results.",
  titers = "One selected record per participant, assay, antigen and analysis visit. Assign analysis visits before use. EXACT values are positive; BLQ, ALQ and MISSING values are blank with applicable limits supplied.",
  doses = "One row per participant and actually administered dose. Include recipients without diaries so their missing assessments remain visible.",
  diary = "One row per participant, dose, day and symptom. Grade 0 means assessed with no reaction. Blank grades and absent rows remain missing. A header-only diary is allowed.")
VAX_TEXT <- c("study_id", "study_title", "yes_value", "no_value", "assay", "antigen", "unit", "baseline_visit",
  "qualifier_exact", "qualifier_blq", "qualifier_alq", "qualifier_missing")
VAX_AREAS <- c("followup_visits", "dose_labels", "symptoms")
VAX_NUMBERS <- c("confidence", "response_threshold", "fold_threshold", "baseline_threshold", "day_start", "day_end", "max_grade")
VAX_SELECTS <- c("blq_policy", "alq_policy", "response_rule", "react_denominator")
VAX_CONFIRM <- c("visits_confirmed", "diary_confirmed", "review_confirmed")
VAX_FIELDS <- c(VAX_TEXT, VAX_AREAS, VAX_NUMBERS, VAX_SELECTS, VAX_CONFIRM, "outputs")
blank_settings <- vaccine_browser_defaults()
# These choices have scientific meaning and must be deliberately supplied.
for (key in VAX_SELECTS) blank_settings[[key]] <- ""
for (key in setdiff(VAX_NUMBERS, "confidence")) blank_settings[[key]] <- NA_real_
for (key in VAX_CONFIRM) blank_settings[[key]] <- FALSE
blank_settings$outputs <- character()
value <- function(id, fallback = "") blank_settings[[id]] %or% fallback
choice <- function(id, label, choices) selectInput(id, label, choices = c("Choose a study rule…" = "", choices), selected = "", selectize = FALSE)
heading <- function(title, description) tagList(h2(style = "font-size:1.3rem;margin:0 0 8px", title), p(class = "vax-hint", description))
next_buttons <- function(back = NULL, next_step = NULL) div(class = "vax-next",
  if (!is.null(back)) actionButton(paste0("back_", back), "Previous step") else span(),
  if (!is.null(next_step)) actionButton(paste0("next_", next_step), "Continue", class = "btn-primary"))
input_panel <- function(slot) div(class = "vax-input-slot", id = paste0("slot_", slot),
  h3(VAX_FEED_LABELS[[slot]]), p(class = "vax-hint", VAX_FEED_HINTS[[slot]]),
  uiOutput(paste0("upload_", slot)),
  div(class = "vax-actions", actionButton(paste0("template_", slot), "Download blank CSV template", class = "btn-sm"), actionButton(paste0("clear_", slot), "Remove this feed", class = "btn-sm")),
  uiOutput(paste0("input_status_", slot)), uiOutput(paste0("mapping_", slot)),
  tags$details(tags$summary("Preview the first 5 source records"), div(class = "vax-preview", tableOutput(paste0("preview_", slot)))))

ui <- page_fluid(theme = portfolio_theme(), class = "vax-page",
  app_status_ui("the guided setup form; no study data or analysis is loaded at startup"),
  tags$head(includeCSS("vaccine-ui.css"), includeScript("vaccine-ui.js")),
  div(class = "vax-top", div(class = "vax-brand", div(class = "vax-kicker", "Trial biostatistics toolkit"),
    h1("Vaccine immunogenicity & reactogenicity"),
    p(class = "vax-sub", "Configure descriptive analyses, review the inputs, and run R directly in this browser.")),
    div(class = "vax-actions", actionButton("load_example", "Load synthetic example"), actionButton("reset", "Reset all"), bp_theme_toggle())),
  div(class = "vax-memory", p(strong(if (in_browser) "Your data stay in this browser session. " else "This is a native R session. "),
    if (in_browser) "Files are read into browser memory and are not sent to an analysis server. Closing or reloading the app clears this session. Download results you want to keep. "
    else "This copy processes files in the R process serving the app. The published browser edition keeps analysis in your browser. Download results you want to keep. ",
    tags$a(href = "../../vaccine/index.html", target = "_blank", rel = "noopener", "Module guide"))),
  uiOutput("state_panel"),
  navset_tab(id = "workflow",
    nav_panel("1. Study", value = "study", div(class = "vax-setup",
      heading("Start with the study definitions", "No client or study is preselected. Use your approved analysis plan, or deliberately load the fictional example to explore."),
      card(card_header("Study and outputs"), card_body(
        div(class = "vax-grid", textInput("study_id", "Study identifier", value("study_id")), textInput("study_title", "Study / project title (optional)", value("study_title"))),
        checkboxGroupInput("outputs", "Outputs to compute", choices = VAX_OUTPUTS, selected = character()),
        actionButton("select_all_outputs", "Select all six outputs", class = "btn-sm"),
        div(class = "vax-grid", numericInput("confidence", "Two-sided confidence level", value("confidence", .95), min = .5, max = .999, step = .001),
          div(p(class = "vax-hint", "Intervals are descriptive and pointwise. This app does not test vaccine efficacy, establish protection thresholds or grant scientific approval."))),
        div(class = "vax-grid", textInput("yes_value", "Source population flag: included value", value("yes_value", "Y")),
          textInput("no_value", "Source population flag: excluded value", value("no_value", "N"))))), next_buttons(next_step = "inputs"))),
    nav_panel("2. Inputs", value = "inputs", div(class = "vax-setup",
      heading("Add CSV files and review the mappings", "Only feeds needed by selected outputs are required. Column names may differ: choose the corresponding source column for each analysis field."),
      p(class = "vax-hint", "Browser limits: 16 MiB and 200,000 records per CSV; at most 250,000 expected assay or diary assessments and 32 diary figures. The optional desktop toolkit supports larger expected grids, with separate upload limits of 16 MiB and 100,000 records per CSV. Keep all eligible participants and the full prespecified window."),
      uiOutput("input_requirements"), tagList(lapply(names(VAX_FEEDS), input_panel)), next_buttons(back = "study", next_step = "assay"))),
    nav_panel("3. Immunogenicity", value = "assay", div(class = "vax-setup",
      heading("Specify the assay, visits and response rule", "Required for immunogenicity outputs. Select one assay, antigen and reported unit per run. These fields remain yours to define."),
      card(card_header("Assay and analysis visits"), card_body(
        div(class = "vax-grid three", textInput("assay", "Assay value to analyze", ""), textInput("antigen", "Antigen value to analyze", ""), textInput("unit", "Reported assay unit", "")),
        div(class = "vax-grid", textInput("baseline_visit", "Baseline analysis-visit label", ""), textAreaInput("followup_visits", "Follow-up visits in order (one per line)", "", rows = 3)),
        p(class = "vax-hint", "The module uses supplied analysis-visit labels. It does not assign sample dates to visit windows."))),
      card(card_header("Assay limits and source qualifiers"), card_body(
        div(class = "vax-grid", choice("blq_policy", "Below-LLOQ analysis rule", c("Exclude from numerical analyses" = "exclude", "Substitute LLOQ / 2" = "half_lloq", "Substitute LLOQ" = "lloq")),
          choice("alq_policy", "Above-ULOQ analysis rule", c("Exclude from numerical analyses" = "exclude", "Substitute ULOQ" = "uloq"))),
        p(class = "vax-hint", "Limit substitution is a study assumption that can change summaries and response classification. There is no universally correct substitution rule."),
        div(class = "vax-grid", textInput("qualifier_exact", "Source qualifier: exact result", value("qualifier_exact", "EXACT")),
          textInput("qualifier_blq", "Source qualifier: below LLOQ", value("qualifier_blq", "BLQ")),
          textInput("qualifier_alq", "Source qualifier: above ULOQ", value("qualifier_alq", "ALQ")),
          textInput("qualifier_missing", "Source qualifier: missing result", value("qualifier_missing", "MISSING"))))),
      card(card_header("Study-defined response"), card_body(
        p(class = "vax-hint", "Only required when response rates are selected. Inclusive comparisons (≥) use your study thresholds; they do not imply protection."),
        choice("response_rule", "Response definition", c("Post-baseline value at or above a threshold" = "threshold", "Paired fold rise at or above a multiplier" = "fold_rise", "Baseline-dependent threshold / fold-rise rule" = "conditional")),
        div(class = "vax-grid three", numericInput("response_threshold", "Post-baseline threshold (assay units)", NA_real_, min = 0),
          numericInput("fold_threshold", "Required fold-rise multiplier", NA_real_, min = 1), numericInput("baseline_threshold", "Baseline split threshold (assay units)", NA_real_, min = 0)),
        p(class = "vax-hint", "For the conditional rule, baseline below the split uses the post-baseline threshold; baseline at or above the split uses paired fold rise. Unused thresholds may remain blank."))),
      next_buttons(back = "inputs", next_step = "diary"))),
    nav_panel("4. Reactions", value = "diary", div(class = "vax-setup",
      heading("Define the solicited-reaction window", "Required for reaction incidence and diary profiles. Actual doses and protocol-assigned grades come from the study; no clinical grading thresholds are inferred."),
      card(card_header("Doses, symptoms and diary assessments"), card_body(
        div(class = "vax-grid", textAreaInput("dose_labels", "Administered dose labels (one per line)", "", rows = 3), textAreaInput("symptoms", "Prespecified symptoms (one per line)", "", rows = 3)),
        div(class = "vax-grid three", numericInput("day_start", "First diary day, inclusive", NA_real_, min = -1, max = 60, step = 1),
          numericInput("day_end", "Last diary day, inclusive", NA_real_, min = -1, max = 60, step = 1), numericInput("max_grade", "Highest protocol-assigned grade", NA_real_, min = 1, max = 5, step = 1)),
        choice("react_denominator", "Reaction incidence denominator", c("Complete window for the symptom" = "complete", "At least one assessed day (observed reactions)" = "observed")),
        div(class = "vax-note", strong("Missing is different from no reaction. "),
          "Grade 0 is an observed absence. Blank grades and absent records remain missing. Complete-window incidence excludes partial diaries from that symptom's denominator; observed incidence can miss reactions on unobserved days. Both approaches retain missingness counts and listings."))),
      next_buttons(back = "assay", next_step = "review"))),
    nav_panel("5. Review & run", value = "review",
      heading("Review the choices before running", "Data validation checks structure and analysis eligibility. Study-specific scientific review and approval remain separate."),
      card(card_header("Current configuration"), card_body(uiOutput("configuration_summary"))),
      div(class = "vax-setup", checkboxInput("visits_confirmed", "I confirmed the analysis-visit assignments and prespecified population flags (immunogenicity outputs)", FALSE),
        checkboxInput("diary_confirmed", "I confirmed administered doses, day numbering, symptoms and protocol-assigned grades (reaction outputs)", FALSE),
        checkboxInput("review_confirmed", "I reviewed the settings and their study-specific interpretation", FALSE)),
      div(class = "vax-actions", uiOutput("validate_control", inline = TRUE), uiOutput("run_control", inline = TRUE)),
      div(style = "margin-top:16px", uiOutput("validation_messages"), div(class = "vax-preview", tabindex = "0", `aria-label` = "Validation audit table; scroll for all columns", tableOutput("validation_counts"))), next_buttons(back = "diary")),
    nav_panel("6. Results", value = "results", uiOutput("results_panel"))
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(data = setNames(vector("list", length(VAX_FEEDS)), names(VAX_FEEDS)), filenames = list(),
    mapping_epoch = 0L, revision = 0L, upload_errors = list(), pending_uploads = list(), validation = NULL, validated = NULL, result = NULL, result_revision = NULL,
    state = "empty", message = "Choose study outputs and add data, or load the synthetic example.", download_note = "", owned = character())
  upload_versions <- setNames(lapply(names(VAX_FEEDS), function(slot) reactiveVal(0L)), names(VAX_FEEDS))
  active_upload_id <- function(slot) paste0("file_", slot, "_", isolate(upload_versions[[slot]]()))
  rotate_upload <- function(slot) upload_versions[[slot]](isolate(upload_versions[[slot]]()) + 1L)
  completed_uploads <- new.env(parent = emptyenv())
  received_uploads <- new.env(parent = emptyenv())
  forget_upload <- function(id) if (exists(id, envir = received_uploads, inherits = FALSE)) rm(list = id, envir = received_uploads)
  epoch <- function() as.integer(isolate(input$form_epoch) %or% 0L)
  clear_result <- function() {
    old <- isolate(rv$result)
    rv$result <- NULL; rv$result_revision <- NULL; rv$download_note <- ""
    if (!is.null(old$directory) && old$directory %in% isolate(rv$owned)) unlink(old$directory, recursive = TRUE)
  }
  invalidate <- function(reset_review = TRUE, message = "Inputs or settings changed. Review and validate this configuration before running.") {
    clear_result(); rv$revision <- isolate(rv$revision) + 1L; rv$validation <- NULL; rv$validated <- NULL
    empty <- !any(!vapply(isolate(rv$data), is.null, TRUE)) && !nzchar(isolate(input$study_id) %or% "") && !length(isolate(input$outputs))
    rv$state <- if (length(isolate(rv$upload_errors))) "invalid" else if (length(isolate(rv$pending_uploads))) "uploading" else if (empty) "empty" else "changed"
    rv$message <- if (length(isolate(rv$upload_errors))) paste(unlist(isolate(rv$upload_errors)), collapse = "\n") else if (length(isolate(rv$pending_uploads))) "An input is still uploading. Wait for it to finish or Reset to cancel." else if (empty) "Choose study outputs and add data, or load the synthetic example." else message
    if (reset_review) for (id in VAX_CONFIRM) updateCheckboxInput(session, id, value = FALSE)
  }
  core_settings <- reactive({
    fields <- setdiff(VAX_FIELDS, VAX_CONFIRM)
    out <- setNames(lapply(fields, function(id) input[[id]] %or% blank_settings[[id]]), fields)
    out$outputs <- out$outputs %or% character(); out$columns <- list()
    for (slot in names(VAX_FEEDS)) {
      headers <- names(rv$data[[slot]])
      out$columns[[slot]] <- setNames(lapply(VAX_FEEDS[[slot]], function(column) {
        input[[paste0("map_", slot, "_", column)]] %or% if (column %in% headers) column else ""
      }), VAX_FEEDS[[slot]])
    }
    out
  })
  settings <- reactive(c(core_settings(), setNames(lapply(VAX_CONFIRM, function(id) input[[id]] %or% FALSE), VAX_CONFIRM)))
  observeEvent(core_settings(), invalidate(TRUE), ignoreInit = TRUE, priority = 100)
  observeEvent(lapply(VAX_CONFIRM, function(id) input[[id]]), invalidate(FALSE), ignoreInit = TRUE, priority = 100)
  observeEvent(input$form_epoch, invalidate(FALSE), ignoreInit = TRUE, priority = 150)
  observeEvent(input$select_all_outputs, updateCheckboxGroupInput(session, "outputs", selected = unname(VAX_OUTPUTS)))
  set_settings <- function(values) {
    complete <- utils::modifyList(blank_settings, values, keep.null = TRUE)
    for (id in VAX_TEXT) updateTextInput(session, id, value = complete[[id]] %or% "")
    for (id in VAX_AREAS) updateTextAreaInput(session, id, value = paste(unlist(complete[[id]] %or% ""), collapse = "\n"))
    for (id in VAX_NUMBERS) updateNumericInput(session, id, value = suppressWarnings(as.numeric(complete[[id]] %or% NA_real_)))
    for (id in VAX_SELECTS) updateSelectInput(session, id, selected = complete[[id]] %or% "")
    for (id in VAX_CONFIRM) updateCheckboxInput(session, id, value = FALSE)
    updateCheckboxGroupInput(session, "outputs", selected = unlist(complete$outputs %or% character(), use.names = FALSE))
  }
  observeEvent(input$load_example, {
    invalidate(TRUE, "Synthetic example loaded. Review its fictional choices and confirm the applicable definitions before running.")
    example <- tryCatch(vaccine_browser_example(asset_root), error = identity)
    if (inherits(example, "error")) { rv$state <- "error"; rv$message <- conditionMessage(example); return() }
    rv$pending_uploads <- list(); rv$upload_errors <- list(); rv$data <- example$data; rv$filenames <- setNames(as.list(paste0(names(VAX_FEEDS), ".csv (synthetic)")), names(VAX_FEEDS))
    for (slot in names(VAX_FEEDS)) rotate_upload(slot); rv$mapping_epoch <- isolate(rv$mapping_epoch) + 1L; set_settings(example$settings)
    nav_select("workflow", "review", session = session)
  })
  observeEvent(input$reset, {
    invalidate(TRUE); rv$pending_uploads <- list(); rv$upload_errors <- list(); rv$data <- setNames(vector("list", length(VAX_FEEDS)), names(VAX_FEEDS)); rv$filenames <- list()
    for (slot in names(VAX_FEEDS)) rotate_upload(slot); rv$mapping_epoch <- isolate(rv$mapping_epoch) + 1L; set_settings(blank_settings)
    rv$state <- "empty"; rv$message <- "Session data and results cleared. Choose a new study configuration."
    nav_select("workflow", "study", session = session)
  })
  for (step in c("study", "inputs", "assay", "diary", "review")) local({ target <- step
    observeEvent(input[[paste0("next_", target)]], nav_select("workflow", target, session = session))
    observeEvent(input[[paste0("back_", target)]], nav_select("workflow", target, session = session))
  })
  send_file <- function(file, filename = basename(file), export_epoch = epoch(), type = "application/octet-stream") {
    size <- file.info(file)$size
    if (is.na(size) || 4 * ceiling(size / 3) > VAX_TRANSFER_LIMIT) stop("This file exceeds the 50 MiB encoded browser-transfer limit.", call. = FALSE)
    bytes <- readBin(file, "raw", n = size)
    session$sendCustomMessage("vax-download", list(filename = filename, type = type, base64 = jsonlite::base64_enc(bytes), epoch = export_epoch))
  }
  for (slot_name in names(VAX_FEEDS)) local({ slot <- slot_name; last_mapping_epoch <- -1L
    output[[paste0("upload_", slot)]] <- renderUI({
      id <- paste0("file_", slot, "_", upload_versions[[slot]]())
      div(class = "vax-uploader", `data-slot` = slot, `data-upload-id` = id,
          `data-max-bytes` = vaccine_browser_limits()$csv_bytes,
          fileInput(id, "Choose UTF-8 CSV", accept = c(".csv", "text/csv"), buttonLabel = "Choose CSV", placeholder = "No uploaded file", width = "100%"))
    })
    outputOptions(output, paste0("upload_", slot), suspendWhenHidden = FALSE)
    output[[paste0("input_status_", slot)]] <- renderUI({
      data <- rv$data[[slot]]
      pending <- !is.null(rv$pending_uploads[[slot]])
      div(class = "vax-input-summary", `data-pending` = tolower(as.character(pending)),
        `data-loaded` = tolower(as.character(!is.null(data))), `data-upload-id` = paste0("file_", slot, "_", upload_versions[[slot]]()),
        if (pending) "Selected file is uploading; the prior feed was cleared." else if (is.null(data)) "No data loaded." else paste(rv$filenames[[slot]], "·", format(nrow(data), big.mark = ","), "rows ·", ncol(data), "source columns"))
    })
    outputOptions(output, paste0("input_status_", slot), suspendWhenHidden = FALSE)
    output[[paste0("mapping_", slot)]] <- renderUI({
      data <- rv$data[[slot]]; revision <- rv$mapping_epoch
      reset_mapping <- !identical(revision, last_mapping_epoch)
      last_mapping_epoch <<- revision
      if (is.null(data)) return(NULL)
      headers <- names(data)
      tagList(p(class = "vax-hint", "Map analysis fields to source columns. Empty AVAL or limit cells are allowed where appropriate; the GRADE column must be mapped even if all its values are missing."),
        div(class = "vax-map-grid", lapply(VAX_FEEDS[[slot]], function(column) {
          id <- paste0("map_", slot, "_", column); previous <- isolate(input[[id]])
          selected <- if (!reset_mapping && !is.null(previous) && previous %in% headers) previous else if (column %in% headers) column else ""
          selectInput(id, column, choices = c("Choose source column…" = "", setNames(headers, headers)), selected = selected, selectize = FALSE)
        })))
    })
    outputOptions(output, paste0("mapping_", slot), suspendWhenHidden = FALSE)
    output[[paste0("preview_", slot)]] <- renderTable({ req(rv$data[[slot]]); utils::head(rv$data[[slot]], 5L) }, striped = TRUE, bordered = TRUE, rownames = FALSE)
    observeEvent(input[[paste0("clear_", slot)]], {
      rv$data[[slot]] <- NULL; rv$filenames[[slot]] <- NULL; rv$pending_uploads[[slot]] <- NULL; rv$upload_errors[[slot]] <- NULL
      rotate_upload(slot); invalidate(TRUE)
    })
    observeEvent(input[[paste0("template_", slot)]], {
      tryCatch(send_file(file.path(asset_root, "vaccine/examples", paste0(slot, "_template.csv")), type = "text/csv"),
        error = function(e) showNotification(conditionMessage(e), type = "error"))
    })
  })
  # Clear an old feed at selection time, before Shiny starts transferring bytes.
  # Each control generation accepts at most one upload; reset/example rotate IDs.
  observeEvent(input$upload_started, {
    event <- input$upload_started
    if (!is.list(event) || length(event$slot) != 1L || !is.character(event$slot) || !event$slot %in% names(VAX_FEEDS) || !identical(event$id, active_upload_id(event$slot))) return()
    slot <- event$slot
    rv$data[[slot]] <- NULL; rv$filenames[[slot]] <- NULL; rv$upload_errors[[slot]] <- NULL
    if (!identical(as.integer(event$count), 1L) || length(event$size) != 1L || !is.numeric(event$size) || !is.finite(event$size) || event$size > vaccine_browser_limits()$csv_bytes || event$size < 0) {
      rv$pending_uploads[[slot]] <- NULL
      rv$upload_errors[[slot]] <- paste(VAX_FEED_LABELS[[slot]], "— choose one UTF-8 CSV of at most 16 MiB. The prior feed was cleared.")
      rotate_upload(slot)
    } else {
      rv$pending_uploads[[slot]] <- list(id = event$id, name = event$name, size = event$size)
    }
    invalidate(TRUE)
  }, priority = 300)
  observeEvent(input$upload_failed, {
    event <- input$upload_failed
    if (!is.list(event) || length(event$slot) != 1L || !is.character(event$slot) || !event$slot %in% names(VAX_FEEDS) || !identical(event$id, active_upload_id(event$slot))) return()
    slot <- event$slot
    rv$pending_uploads[[slot]] <- NULL
    rv$upload_errors[[slot]] <- paste(VAX_FEED_LABELS[[slot]], "— the file transfer did not complete. Choose the CSV again or Reset.")
    rotate_upload(slot); invalidate(TRUE)
  }, priority = 250)
  observeEvent(list(reactiveValuesToList(input), lapply(upload_versions, function(version) version())), {
    values <- reactiveValuesToList(input)
    ids <- unique(c(grep("^file_(participants|titers|doses|diary)_[0-9]+$", names(values), value = TRUE), ls(received_uploads)))
    for (id in ids) {
      upload <- if (exists(id, envir = received_uploads, inherits = FALSE)) get(id, envir = received_uploads) else values[[id]]
      if (exists(id, envir = completed_uploads, inherits = FALSE) || !is.data.frame(upload) || nrow(upload) != 1L || !"datapath" %in% names(upload)) next
      slot <- sub("^file_(.*)_[0-9]+$", "\\1", id)
      pending <- rv$pending_uploads[[slot]]
      if (!identical(id, active_upload_id(slot))) {
        assign(id, TRUE, envir = completed_uploads)
        forget_upload(id); unlink(upload$datapath[[1]]); next
      }
      # webR can deliver the completed file before the selection event. Keep a
      # current-generation completion until that event supplies matching metadata;
      # Reset/example rotate the generation and still discard an old completion.
      # A delayed initial NULL from the new file binding can also follow its
      # completed value, so retain the metadata until selection is reconciled.
      if (is.null(pending)) { assign(id, upload, envir = received_uploads); next }
      assign(id, TRUE, envir = completed_uploads)
      forget_upload(id)
      if (!identical(pending$id, id)) { unlink(upload$datapath[[1]]); next }
      if (!identical(as.character(upload$name[[1]]), as.character(pending$name)) || !isTRUE(as.numeric(upload$size[[1]]) == pending$size)) {
        unlink(upload$datapath[[1]]); rv$pending_uploads[[slot]] <- NULL
        rv$upload_errors[[slot]] <- paste(VAX_FEED_LABELS[[slot]], "— the completed transfer did not match the selected file. Choose it again.")
        rotate_upload(slot); invalidate(TRUE); next
      }
      data <- tryCatch(vaccine_browser_read_csv(upload$datapath[[1]]), error = identity, finally = unlink(upload$datapath[[1]]))
      rv$pending_uploads[[slot]] <- NULL; rotate_upload(slot)
      if (inherits(data, "error")) {
        rv$data[[slot]] <- NULL; rv$filenames[[slot]] <- NULL
        rv$upload_errors[[slot]] <- paste(VAX_FEED_LABELS[[slot]], "—", conditionMessage(data))
      } else {
        rv$upload_errors[[slot]] <- NULL; rv$data[[slot]] <- data; rv$filenames[[slot]] <- upload$name[[1]]
      }
      invalidate(TRUE, if (inherits(data, "error")) "Resolve the input error." else paste("Added", upload$name[[1]], "— review the suggested column mappings."))
    }
  }, ignoreInit = FALSE, priority = 200)
  required_slots <- reactive({
    selected <- settings()$outputs
    unique(c(if (length(selected)) "participants", if (any(selected %in% unname(VAX_OUTPUTS)[1:4])) "titers", if (any(selected %in% unname(VAX_OUTPUTS)[5:6])) c("doses", "diary")))
  })
  output$input_requirements <- renderUI({
    slots <- required_slots()
    div(class = "vax-note", if (!length(slots)) "Select outputs on the Study tab to see which feeds are required." else paste("Required for the selected outputs:", paste(VAX_FEED_LABELS[slots], collapse = "; "), "."))
  })
  output$state_panel <- renderUI({
    labels <- c(empty = "Ready for your study", uploading = "Input upload in progress", changed = "Configuration changed", invalid = "Resolve validation issues", ready = "Ready to run", running = "Computing analyses", succeeded = "Analysis completed", error = "Analysis did not complete")
    div(id = "analysis_state", class = "vax-state", `data-state` = rv$state, strong(labels[[rv$state]]), p(class = "vax-hint", rv$message),
      span(class = "vax-state-count", paste(sum(!vapply(rv$data, is.null, TRUE)), "of 4 feeds loaded")))
  })
  output$configuration_summary <- renderUI({
    cfg <- settings(); slots <- required_slots()
    labels <- names(VAX_OUTPUTS)[match(cfg$outputs, VAX_OUTPUTS)]
    entries <- list("Study" = paste(cfg$study_id, cfg$study_title), "Selected outputs" = paste(labels, collapse = "; "),
      "Confidence level" = as.character(cfg$confidence), "Population values" = paste("Included:", cfg$yes_value, "| Excluded:", cfg$no_value),
      "Required inputs" = paste(vapply(slots, function(slot) paste0(slot, ": ", if (is.null(rv$data[[slot]])) "missing" else paste(nrow(rv$data[[slot]]), "rows")), ""), collapse = "\n"))
    if ("titers" %in% slots) entries <- c(entries, list("Assay / antigen / unit" = paste(cfg$assay, cfg$antigen, cfg$unit, sep = " / "),
      "Analysis visits" = paste("Baseline:", cfg$baseline_visit, "\nFollow-up:", cfg$followup_visits), "Limit rules" = paste("BLQ:", cfg$blq_policy, "| ALQ:", cfg$alq_policy)))
    if ("response" %in% cfg$outputs) entries <- c(entries, list("Response rule" = paste(cfg$response_rule, "| post threshold:", cfg$response_threshold, "| fold:", cfg$fold_threshold, "| baseline split:", cfg$baseline_threshold)))
    if ("diary" %in% slots) entries <- c(entries, list("Doses / symptoms" = paste(cfg$dose_labels, cfg$symptoms, sep = "\n"),
      "Diary definition" = paste("Days", cfg$day_start, "through", cfg$day_end, "| maximum grade", cfg$max_grade, "| denominator", cfg$react_denominator)))
    tags$dl(class = "vax-review-dl", lapply(names(entries), function(name) tagList(tags$dt(name), tags$dd(if (nzchar(entries[[name]])) entries[[name]] else "Not configured"))))
  })
  current_snapshot <- function() list(settings = isolate(settings()), revision = isolate(rv$revision), epoch = epoch())
  is_validated <- reactive({ !length(rv$pending_uploads) && !length(rv$upload_errors) && !is.null(rv$validated) && identical(rv$validated, current_snapshot()) && isTRUE(rv$validation$ok) })
  output$validate_control <- renderUI({ rv$revision
    actionButton("validate_setup", "Validate this configuration", class = "btn-primary", disabled = if (length(rv$pending_uploads)) "disabled" else NULL)
  })
  output$run_control <- renderUI(actionButton("run_analysis", "Run selected analyses", class = "btn-primary", disabled = if (!isTRUE(is_validated())) "disabled" else NULL))
  observeEvent(input$validate_setup, {
    clear_result(); rv$validated <- NULL
    if (length(rv$pending_uploads)) { rv$state <- "uploading"; rv$message <- "Wait for the selected file to finish uploading or remove that feed to cancel."; return() }
    if (length(rv$upload_errors)) {
      rv$validation <- list(ok = FALSE, errors = data.frame(field = paste0("inputs.", names(rv$upload_errors)), message = unlist(rv$upload_errors, use.names = FALSE)))
      rv$state <- "invalid"; rv$message <- "Resolve failed uploads or remove unused feeds, then validate again."; return()
    }
    checked <- tryCatch(vaccine_browser_validate(isolate(rv$data), isolate(settings())), error = function(e) list(ok = FALSE, errors = data.frame(field = "configuration", message = conditionMessage(e))))
    rv$validation <- checked
    if (isTRUE(checked$ok)) { rv$validated <- current_snapshot(); rv$state <- "ready"; rv$message <- "Configuration validated. Run the selected analyses to create a new result set." }
    else { rv$state <- "invalid"; rv$message <- "Resolve the listed issues, then validate again." }
  })
  output$validation_messages <- renderUI({
    checked <- rv$validation
    if (is.null(checked)) return(div(class = "vax-note", "Confirm the applicable study definitions, then validate this configuration."))
    if (!isTRUE(checked$ok)) return(div(class = "vax-errors", strong("Please resolve these items"), tags$ul(lapply(seq_len(nrow(checked$errors)), function(i) tags$li(strong(paste0(checked$errors$field[[i]], ": ")), checked$errors$message[[i]])))))
    tagList(div(class = "vax-success", strong("Validation passed. "), "Input and configuration checks passed. Scientific approval remains separate."),
      if (length(checked$preview$warnings)) tags$ul(class = "vax-output-notes", lapply(checked$preview$warnings, tags$li)))
  })
  output$validation_counts <- renderTable({ checked <- rv$validation; req(isTRUE(checked$ok)); checked$preview$counts }, rownames = FALSE)
  observeEvent(input$run_analysis, {
    if (!isTRUE(isolate(is_validated()))) { rv$state <- "invalid"; rv$message <- "Validate the current configuration before running."; return() }
    snapshot <- current_snapshot(); data <- isolate(rv$data); cfg <- isolate(settings()); clear_result()
    rv$state <- "running"; rv$message <- "R is computing the selected outputs and preparing the downloadable review package."
    directory <- tempfile("vaccine-browser-results-"); dir.create(directory); rv$owned <- c(isolate(rv$owned), directory)
    computed <- tryCatch(withProgress(message = "Computing vaccine analyses", value = .1, {
      result <- vaccine_browser_run(data, cfg, directory, asset_root = asset_root); incProgress(.9); result
    }), error = identity)
    if (inherits(computed, "error")) {
      unlink(directory, recursive = TRUE); rv$state <- "error"; rv$message <- paste("No completed results were retained.", conditionMessage(computed)); rv$validated <- NULL; return()
    }
    if (!identical(snapshot, current_snapshot())) { unlink(directory, recursive = TRUE); invalidate(FALSE); return() }
    computed$directory <- directory; computed$epoch <- snapshot$epoch; rv$result <- computed; rv$result_revision <- isolate(rv$revision)
    rv$state <- "succeeded"; rv$message <- paste(length(computed$outputs), "outputs completed. Review the estimates, missingness, assumptions and warnings before study use.")
    session$sendCustomMessage("vax-results-ready", list(epoch = computed$epoch)); nav_select("workflow", "results", session = session)
  })
  current_result <- reactive({
    result <- rv$result
    if (is.null(result) || !identical(rv$result_revision, rv$revision) || !identical(result$epoch, as.integer(input$form_epoch %or% 0L))) return(NULL)
    result
  })
  output$results_panel <- renderUI({
    result <- current_result()
    if (is.null(result)) return(div(class = "vax-empty", h3("Results appear after a reviewed run"),
      "Complete the setup, validate the current inputs and run the selected analyses. Editing settings or replacing a file clears the prior results and download controls."))
    files <- result$files; choices <- setNames(names(result$outputs), names(VAX_OUTPUTS)[match(names(result$outputs), VAX_OUTPUTS)])
    div(id = "result_content", uiOutput("result_summary_panel"),
      card(card_header("Explore computed outputs"), card_body(
        div(class = "vax-grid", selectInput("result_output", "Analysis output", choices = choices, selected = names(result$outputs)[[1]], selectize = FALSE), uiOutput("component_control")),
        uiOutput("result_notes"), uiOutput("component_view"))),
      card(card_header("Download this result set"), card_body(
        p(class = "vax-hint", "Download and extract the complete ZIP, then open analysis_report.html to follow linked tables and figures. R generated these results; the configured native SAS program is an unexecuted reference. No scientific approval is implied."),
        div(class = "vax-downloads", actionButton("download_bundle", "Complete review package (.zip)", class = "btn-primary vax-export"),
          actionButton("download_report", "Report index (requires extracted ZIP)", class = "vax-export"), actionButton("download_profile", "Setup profile", class = "vax-export"), actionButton("download_sas", "SAS reference", class = "vax-export")),
        selectInput("download_choice", "Individual file (CSV, figure, report or reproducibility source)", choices = setNames(files, files), selectize = FALSE),
        actionButton("download_file", "Download selected file", class = "vax-export"),
        p(class = "vax-hint", "CSV values that could be interpreted as spreadsheet formulas are escaped. RDS files retain original values. The encoded browser-transfer limit is 50 MiB per file or complete ZIP payload; it does not change computed estimates."), textOutput("download_note"))))
  })
  output$result_summary_panel <- renderUI({
    result <- current_result(); req(result)
    div(id = "result_summary", class = "vax-success", `data-output-count` = length(result$outputs), `data-run-id` = basename(result$directory),
      strong(paste(length(result$outputs), "outputs completed for", result$config$study_id)),
      p("Computed results are ready for review. Scientific review and study approval remain separate."),
      if (length(result$warnings)) tags$ul(lapply(result$warnings, tags$li)))
  })
  selected_output <- reactive({ result <- current_result(); req(result); key <- input$result_output %or% names(result$outputs)[[1]]; req(key %in% names(result$outputs)); result$outputs[[key]] })
  output$component_control <- renderUI({
    result <- selected_output(); labels <- vapply(seq_along(result$components), function(i) paste(i, result$components[[i]]$label %or% result$components[[i]]$name %or% paste("Component", i), sep = ". "), "")
    selectInput("result_component", "Table or figure", choices = setNames(as.character(seq_along(labels)), labels), selected = "1", selectize = FALSE)
  })
  selected_component <- reactive({ result <- selected_output(); i <- suppressWarnings(as.integer(input$result_component %or% "1")); req(length(i) == 1L, !is.na(i), i >= 1L, i <= length(result$components)); result$components[[i]] })
  component_value <- function(component) component$value %or% component$object %or% component$data
  output$result_notes <- renderUI({ result <- selected_output(); tags$ul(class = "vax-output-notes", lapply(c(result$title$footnotes, result$warnings), tags$li)) })
  output$component_view <- renderUI({
    object <- component_value(selected_component())
    if (inherits(object, "ggplot")) plotOutput("result_plot", height = "560px")
    else if (is.data.frame(object)) DTOutput("result_table")
    else div(class = "vax-note", "This component is available in the downloaded report.")
  })
  output$result_table <- renderDT({ object <- component_value(selected_component()); req(is.data.frame(object)); datatable(object, rownames = FALSE, escape = TRUE, selection = "none", options = list(pageLength = 10L, lengthMenu = c(10L, 25L, 50L), scrollX = TRUE, autoWidth = FALSE)) }, server = FALSE)
  output$result_plot <- renderPlot(guard("the selected vaccine figure", {
    object <- component_value(selected_component()); req(inherits(object, "ggplot")); object + bp_ggplot_theme(if (identical(input$bp_theme, "light")) "light" else "dark")
  }), res = 96, alt = "Selected vaccine analysis figure. Exact estimates and denominators are available in the accompanying table and downloads.")
  output$download_note <- renderText(rv$download_note)
  export_action <- function(which) {
    result <- isolate(current_result())
    if (is.null(result)) { showNotification("Results changed. Review and run the current configuration before downloading.", type = "error"); return() }
    tryCatch({
      files <- result$files
      if (which == "bundle") {
        paths <- file.path(result$directory, files); sizes <- file.info(paths)$size; total <- sum(4 * ceiling(sizes / 3))
        if (!is.finite(total) || total > VAX_TRANSFER_LIMIT) stop("The complete package exceeds the 50 MiB encoded browser-transfer limit. The computed results are unchanged; download individual files below.", call. = FALSE)
        payload <- lapply(seq_along(files), function(i) list(name = files[[i]], base64 = jsonlite::base64_enc(readBin(paths[[i]], "raw", n = file.info(paths[[i]])$size))))
        session$sendCustomMessage("vax-download", list(filename = "vaccine-review-package.zip", files = payload, epoch = result$epoch))
      } else {
        file <- switch(which, report = "analysis_report.html", profile = "setup_profile.json", sas = "vaccine_analysis.sas", file = input$download_choice)
        if (length(file) != 1L || !file %in% files) stop("Choose an available file from the current result set.", call. = FALSE)
        send_file(file.path(result$directory, file), export_epoch = result$epoch)
      }
      rv$download_note <- "Preparing the requested browser download…"
    }, error = function(e) { rv$download_note <- conditionMessage(e); showNotification(conditionMessage(e), type = "error", duration = 10) })
  }
  for (kind in c("bundle", "report", "profile", "sas", "file")) local({ which <- kind
    observeEvent(input[[paste0("download_", which)]], export_action(which))
  })
  observeEvent(input$download_finished, rv$download_note <- paste("Downloaded", input$download_finished$filename))
  observeEvent(input$download_failed, { rv$download_note <- paste("Download failed:", input$download_failed); showNotification(rv$download_note, type = "error") })
  session$onSessionEnded(function() { for (directory in isolate(rv$owned)) unlink(directory, recursive = TRUE) })
}
shinyApp(ui, server)
