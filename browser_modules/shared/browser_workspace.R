# Browser-only data intake and portable state for the operational Shiny apps.
# Algorithms remain in each app's canonical R/logic.R. All callbacks are session-local.
`%bw_or%` <- function(x, y) if (is.null(x)) y else x
BW_FILE_LIMIT <- 16 * 1024^2
BW_TOTAL_LIMIT <- 32 * 1024^2
BW_WORKSPACE_LIMIT <- 96 * 1024^2
BW_EXPORT_LIMIT <- 128 * 1024^2
BW_ROW_LIMIT <- 100000L
bw_csv <- function(x) { con <- textConnection("value", "w", local = TRUE); utils::write.csv(x, con, row.names = FALSE, na = ""); close(con); paste(value, collapse = "\n") }
bw_csv_safe <- function(x) {
  for (name in names(x)) if (is.character(x[[name]]) || is.factor(x[[name]])) {
    value <- as.character(x[[name]]); unsafe <- !is.na(value) & grepl("^[[:space:]]*[=+@-]", value)
    value[unsafe] <- paste0("'", value[unsafe]); x[[name]] <- value
  }
  bw_csv(x)
}
bw_empty <- function(x) x[FALSE, , drop = FALSE]
bw_types <- function(x) vapply(x, function(v) if (is.logical(v)) "logical" else if (is.numeric(v)) "numeric" else "character", "")
bw_parse <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || nchar(text, type = "bytes") > BW_FILE_LIMIT) stop("Each CSV must contain text and be at most 16 MiB.")
  con <- textConnection(text); on.exit(close(con), add = TRUE)
  field_counts <- utils::count.fields(con, sep = ",", quote = '"', comment.char = "", blank.lines.skip = TRUE)
  field_counts <- field_counts[!is.na(field_counts)]
  if (!length(field_counts) || any(field_counts != field_counts[[1]])) stop("Every CSV record must have the same number of fields as its header; no column or row was silently shifted.")
  result <- withCallingHandlers(utils::read.csv(text = text, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character", na.strings = NULL, nrows = BW_ROW_LIMIT + 1L), warning = function(w) {
      if (!grepl("incomplete final line", conditionMessage(w), fixed = TRUE)) stop(conditionMessage(w), call. = FALSE)
      invokeRestart("muffleWarning")
    })
  if (nrow(result) > BW_ROW_LIMIT) stop("Each CSV may contain at most 100,000 rows; no records were truncated.")
  if (!ncol(result) || any(!nzchar(names(result))) || anyDuplicated(names(result))) stop("CSV column names must be nonblank and unique.")
  result
}
bw_convert <- function(x, template, mapping) {
  fields <- names(template)
  if (length(mapping) != length(fields) || any(!nzchar(mapping)) || any(!mapping %in% names(x)) || anyDuplicated(mapping))
    stop("Choose a distinct source column for every required field.")
  out <- x[mapping]; names(out) <- fields
  types <- bw_types(template)
  for (field in fields) {
    value <- trimws(as.character(out[[field]]))
    missing <- is.na(value) | value %in% c("", "NA")
    if (types[[field]] == "numeric") {
      converted <- suppressWarnings(as.numeric(value))
      if (any(!missing & !is.finite(converted))) stop("Column ", field, " contains a nonnumeric or nonfinite value.")
      converted[missing] <- NA_real_; out[[field]] <- converted
    } else if (types[[field]] == "logical") {
      if (any(!missing & !toupper(value) %in% c("TRUE", "FALSE"))) stop("Column ", field, " requires TRUE or FALSE.")
      out[[field]] <- ifelse(missing, NA, toupper(value) == "TRUE")
    }
  }
  out
}
bw_source <- function(file) {
  path <- if (file.exists(file)) file else file.path("../../browser_modules/shared", file)
  if (!file.exists(path)) stop("Missing browser workspace asset: ", file)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
bw_ui <- function(ui, title, files, note = NULL, setup_controls = NULL) {
  panel <- shiny::div(id = "bw_workspace", class = "bw-workspace",
    shiny::div(class = "bw-toolbar", shiny::tags$strong(title), shiny::uiOutput("bw_status", inline = TRUE),
      shiny::tags$button(id = "bw_change", type = "button", class = "btn btn-sm btn-outline-secondary", "Study data"),
      shiny::tags$button(id = "bw_export", type = "button", class = "btn btn-sm btn-outline-primary", disabled = TRUE, "Save complete workspace"),
      shiny::tags$button(id = "bw_reset", type = "button", class = "btn btn-sm btn-outline-secondary", "Clear workspace")),
    shiny::tags$details(id = "bw_setup", open = TRUE,
      shiny::tags$summary("Load your study files or a fictional example"),
      shiny::p("Browser releases process files in browser memory. Closing or reloading clears the session; save the workspace to retain your inputs, edits and computed outputs. Native R sessions use their local R server."),
      if (!is.null(note)) shiny::div(class = "bw-note", note),
      shiny::p("Choose CSVs and map their columns below, or restore a previously saved workspace JSON. No code editing is needed. Each CSV is limited to 16 MiB and 100,000 rows; CSV selections are limited to 32 MiB combined. A saved workspace JSON may be up to 96 MiB."),
      shiny::tags$label(`for` = "bw_files", "Select study CSVs or a saved workspace JSON"),
      shiny::tags$input(id = "bw_files", type = "file", multiple = TRUE, accept = ".csv,.json", `data-bw-file` = "true", class = "form-control"),
      shiny::div(class = "bw-buttons",
        shiny::tags$button(id = "bw_templates", type = "button", class = "btn btn-outline-secondary", "Download blank CSV templates"),
        shiny::tags$button(id = "bw_example", type = "button", class = "btn btn-outline-primary", "Load fictional example")),
      setup_controls, shiny::uiOutput("bw_mapping"), shiny::uiOutput("bw_message")))
  # Keep the existing page/sidebar layout intact; add one sibling in its body.
  query <- htmltools::tagQuery(ui)$filter("body")
  wrapped <- if (length(query$selectedTags())) query$addAttrs(`data-bw-state` = "empty")$prepend(panel)$allTags() else shiny::tags$body(`data-bw-state` = "empty", panel, ui)
  htmltools::tagList(wrapped,
    shiny::tags$head(shiny::tags$style(shiny::HTML(bw_source("browser_workspace.css"))),
      shiny::tags$script(shiny::HTML(bw_source("browser_workspace.js")))))
}
bw_server <- function(input, output, session, module, templates, example, validate, apply, clear, export, sources = c("R/logic.R", "browser_setup.R", "browser_workspace.R"), settings = function() NULL, example_settings = NULL) {
  rv <- shiny::reactiveValues(generation = 0, state = "empty", message = "No study data loaded.", pending = NULL,
    restored = NULL, active = FALSE, origin = NULL, source_names = NULL)
  send_state <- function() session$sendCustomMessage("bw-state", list(state = shiny::isolate(rv$state), active = shiny::isolate(rv$active), generation = shiny::isolate(rv$generation)))
  invalidate <- function(state = "empty", message = "No study data loaded.") {
    rv$active <- FALSE; rv$state <- state; rv$message <- message; rv$pending <- NULL; rv$restored <- NULL; rv$origin <- NULL
    clear(); send_state()
  }
  active <- shiny::reactive(isTRUE(rv$active))
  output$bw_status <- shiny::renderUI(shiny::tags$span(class = "bw-status", `data-active` = tolower(as.character(rv$active)),
    `data-generation` = rv$generation, if (rv$active) paste("Loaded:", rv$origin) else rv$message))
  output$bw_message <- shiny::renderUI(shiny::div(class = if (rv$state == "error") "bw-error" else "bw-message", rv$message))
  output$bw_mapping <- shiny::renderUI({
    pending <- rv$pending
    if (is.null(pending)) return(NULL)
    generation <- rv$generation
    choices <- c("Choose a source file" = "", stats::setNames(names(pending), names(pending)), "Empty table (optional feed only)" = ".empty")
    controls <- lapply(seq_along(templates), function(i) {
      file <- names(templates)[[i]]; spec <- templates[[i]]; key <- paste0("bw_file_", generation, "_", i)
      selected <- input[[key]]
      if (is.null(selected)) selected <- if (file %in% names(pending)) file else if (length(templates) == 1L && length(pending) == 1L) names(pending)[[1]] else if (!isTRUE(spec$required)) ".empty" else ""
      columns <- if (selected %in% names(pending)) names(pending[[selected]]) else character()
      maps <- lapply(seq_along(spec$data), function(j) {
        field <- names(spec$data)[[j]]; id <- paste0("bw_map_", generation, "_", i, "_", j)
        value <- shiny::isolate(input[[id]])
        if (is.null(value) || !value %in% columns) value <- if (field %in% columns) field else ""
        shiny::selectInput(id, paste0(field, " (", bw_types(spec$data)[[field]], ")"), choices = c("Choose column" = "", columns), selected = value, selectize = FALSE)
      })
      shiny::div(class = "bw-feed", shiny::tags$h3(paste(file, if (isTRUE(spec$required)) "(required)" else "(optional)")),
        shiny::selectInput(key, "Source file", choices = choices, selected = selected, selectize = FALSE),
        if (selected != ".empty") shiny::div(class = "bw-map-grid", maps))
    })
    shiny::tagList(controls, shiny::checkboxInput(paste0("bw_confirm_", generation),
      "I reviewed the input mapping, units and method settings for this study. Automated checks do not provide scientific approval.", FALSE),
      shiny::tags$button(id = "bw_apply", type = "button", class = "btn btn-primary", "Validate and open workspace"))
  })
  for (name in c("bw_status", "bw_message", "bw_mapping")) shiny::outputOptions(output, name, suspendWhenHidden = FALSE)
  activate <- function(frames, settings = NULL, origin) {
    checked <- validate(frames, settings)
    apply(checked, settings)
    rv$active <- TRUE; rv$state <- "ready"; rv$origin <- origin; rv$message <- "Input checks passed. Review method settings before study use; save a complete workspace before closing."
    rv$pending <- NULL; rv$restored <- NULL; send_state()
  }
  try_action <- function(fn) tryCatch(fn(), error = function(e) { rv$state <- if (isTRUE(rv$active)) "ready" else "error"; rv$message <- conditionMessage(e); send_state() })
  parse_payload <- function(payload) {
    generation <- payload$generation
    if (!is.numeric(generation) || length(generation) != 1L || !is.finite(generation) || generation < rv$generation) return()
    if (generation > rv$generation) { rv$generation <- generation; invalidate("loading", "Reading selected files.") }
    if (!is.null(payload$error)) stop(as.character(payload$error))
    files <- payload$files
    if (!is.list(files) || !length(files) || length(files) > 30L) stop("Select between one and 30 files.")
    filenames <- vapply(files, function(f) as.character(f$name), "")
    if (any(!nzchar(filenames)) || anyDuplicated(filenames)) stop("Selected filenames must be nonblank and unique.")
    json_request <- length(files) == 1L && grepl("\\.json$", filenames, ignore.case = TRUE)
    if (sum(vapply(files, function(f) nchar(f$text, type = "bytes"), 0)) > (if (json_request) BW_WORKSPACE_LIMIT else BW_TOTAL_LIMIT)) stop("The selection exceeds its size limit: CSVs 32 MiB combined; saved workspace JSON 96 MiB.")
    rv$restored <- NULL
    if (json_request) {
      saved <- jsonlite::fromJSON(files[[1]]$text, simplifyVector = FALSE)
      if (!identical(saved$schema, 1L) && !identical(saved$schema, 1)) stop("Unsupported workspace format.")
      if (!identical(saved$module, module) || !is.list(saved$inputs) || !setequal(names(saved$inputs), names(templates))) stop("This workspace belongs to a different module or has an incomplete input set.")
      if (sum(vapply(saved$inputs, function(text) nchar(text, type = "bytes"), 0)) > BW_TOTAL_LIMIT) stop("Saved CSV inputs exceed 32 MiB combined.")
      rv$restored <- saved$settings
      rv$pending <- lapply(saved$inputs, bw_parse)
    } else {
      if (any(!grepl("\\.csv$", filenames, ignore.case = TRUE))) stop("Choose CSV files, or one saved workspace JSON.")
      rv$pending <- stats::setNames(lapply(files, function(f) bw_parse(f$text)), filenames)
    }
    rv$state <- "mapping"; rv$message <- "Map the selected files and columns, review the confirmation, then open the workspace."; send_state()
  }
  shiny::observeEvent(input$bw_begin, {
    event <- input$bw_begin
    if (is.numeric(event$generation) && length(event$generation) == 1L && is.finite(event$generation) && event$generation > rv$generation) {
      rv$generation <- event$generation; invalidate("loading", "Reading selected files. Previous study data and exports are cleared.")
    }
  }, priority = 300, ignoreInit = TRUE)
  shiny::observeEvent(input$bw_payload, try_action(function() parse_payload(input$bw_payload)), priority = 200, ignoreInit = TRUE)
  download <- function(files, name) {
    bytes <- sum(vapply(files, function(x) nchar(x, type = "bytes"), 0))
    if (!is.finite(bytes) || bytes > BW_EXPORT_LIMIT) stop("The complete export exceeds the 128 MiB browser limit. Reduce the study scope only when scientifically appropriate; no estimates were changed.")
    session$sendCustomMessage("bw-download", list(generation = rv$generation, filename = name,
      files = lapply(seq_along(files), function(i) list(name = names(files)[[i]], content = files[[i]]))))
  }
  snapshot <- function() {
    shiny::req(active())
    value <- export()
    if (!is.list(value$inputs) || !setequal(names(value$inputs), names(templates))) stop("The workspace export omitted a required input table.")
    value
  }
  shiny::observeEvent(input$bw_action, {
    event <- input$bw_action
    if (!is.numeric(event$generation) || length(event$generation) != 1L || !is.finite(event$generation) || event$generation < rv$generation) return()
    if (event$action %in% c("reset", "example") && event$generation > rv$generation) { rv$generation <- event$generation; invalidate() }
    try_action(function() {
      if (event$action == "reset") { invalidate(); return() }
      if (event$action == "example") { activate(example(), example_settings, "Fictional example"); return() }
      if (event$action == "templates") {
        files <- lapply(templates, function(spec) bw_csv(bw_empty(spec$data))); names(files) <- names(templates)
        files[["README.txt"]] <- "Blank study CSV templates. Fill these headers or map your source columns in the browser. Do not treat example thresholds as study approval."
        download(files, paste0(module, "-blank-templates.zip")); return()
      }
      if (event$generation != rv$generation) return()
      if (event$action == "apply") {
        if (is.null(rv$pending)) stop("Choose study files first.")
        if (!isTRUE(input[[paste0("bw_confirm_", rv$generation)]])) stop("Review and confirm the input mapping and study assumptions first.")
        frames <- lapply(seq_along(templates), function(i) {
          spec <- templates[[i]]; selected <- input[[paste0("bw_file_", rv$generation, "_", i)]]
          if (identical(selected, ".empty")) { if (isTRUE(spec$required)) stop("A required feed cannot be omitted: ", names(templates)[[i]]); return(bw_empty(spec$data)) }
          if (is.null(selected) || !selected %in% names(rv$pending)) stop("Choose the source file for ", names(templates)[[i]])
          mapping <- vapply(seq_along(spec$data), function(j) input[[paste0("bw_map_", rv$generation, "_", i, "_", j)]] %bw_or% "", "")
          bw_convert(rv$pending[[selected]], spec$data, mapping)
        }); names(frames) <- names(templates)
        activate(frames, if (is.null(rv$restored)) settings() else rv$restored, "Your study inputs"); return()
      }
      if (event$action == "export") {
        shiny::req(active()); value <- snapshot(); inputs <- lapply(value$inputs, bw_csv)
        saved <- list(schema = 1L, module = module, inputs = inputs, settings = value$settings %bw_or% list())
        files <- stats::setNames(inputs, paste0("inputs/", names(inputs)))
        files[[paste0(module, "-workspace.json")]] <- as.character(jsonlite::toJSON(saved, auto_unbox = TRUE, null = "null", na = "null", digits = 16, pretty = TRUE))
        for (key in names(value$outputs)) files[[paste0("outputs/", key, ".csv")]] <- bw_csv_safe(value$outputs[[key]])
        files[["review_notes.txt"]] <- paste(c(value$notes, "Automated computations do not provide scientific or operational approval.", "Input CSVs retain the entered values. Treat imported text as data, including spreadsheet formula-like text."), collapse = "\n")
        files[["software_versions.txt"]] <- paste(capture.output(utils::sessionInfo()), collapse = "\n")
        for (path in sources) if (file.exists(path)) files[[paste0("source/", basename(path))]] <- paste(readLines(path, warn = FALSE), collapse = "\n")
        download(files, paste0(module, "-workspace.zip"))
      }
    })
  }, priority = 100, ignoreInit = TRUE)
  list(active = active, state = rv, snapshot = snapshot, invalidate = invalidate, file = function(content, filename, type = "text/plain") {
    shiny::req(active()); if (nchar(content, type = "bytes") > BW_TOTAL_LIMIT) stop("The selected export exceeds 32 MiB.")
    session$sendCustomMessage("bw-file", list(generation = rv$generation, filename = filename, content = content, type = type))
  })
}

bw_need <- function(ok, message) { if (!isTRUE(ok)) stop(message, call. = FALSE); invisible(TRUE) }
bw_nonblank <- function(x) !anyNA(x) && all(nzchar(trimws(as.character(x))))
bw_key <- function(frame, columns, name, allow_empty = FALSE) {
  bw_need(is.data.frame(frame) && (allow_empty || nrow(frame) > 0), paste(name, "requires nonempty rows."))
  bw_need(all(columns %in% names(frame)), paste(name, "is missing its key columns."))
  bw_need(all(vapply(frame[columns], bw_nonblank, TRUE)), paste(name, "identifiers must not be missing or blank."))
  bw_need(!anyDuplicated(frame[columns]), paste(name, "contains duplicate keys."))
}
bw_scalar_table <- function(x) {
  values <- x[vapply(x, function(v) is.atomic(v) && length(v) == 1L, TRUE)]
  as.data.frame(values, stringsAsFactors = FALSE, check.names = FALSE)
}
bw_binding <- function(name, value, env) makeActiveBinding(name, local({ f <- value; function(x) { if (!missing(x)) stop("Read-only dataset binding."); f() } }), env)
