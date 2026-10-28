# ---------------------------------------------------------------------------
# logic.R: pure reconciliation logic for the "Find Hours" tool.
# HOURS / EFFORT ONLY. No dollars, rates, ROI, or headcount. Synthetic data.
#
# These are plain functions with no Shiny dependency, so the Shiny app, the
# Quarto documents, and the unit tests all call the SAME logic. Edit the math
# in one place and every surface updates.
# ---------------------------------------------------------------------------

DEFAULT_CONTINGENCY <- 40L

hours_scalar <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1 || !is.finite(x) || x < 0)
    stop(name, " must be one finite, nonnegative number.")
  x
}

hours_validate <- function(ledger, contingency = DEFAULT_CONTINGENCY) {
  fields <- c("deliverable", "planned", "actual", "pct", "eac")
  if (!is.data.frame(ledger) || !nrow(ledger) || anyDuplicated(names(ledger)) || !all(fields %in% names(ledger)))
    stop("The ledger requires nonempty rows and the documented columns.")
  if (anyNA(ledger$deliverable) || any(!nzchar(trimws(ledger$deliverable))) || anyDuplicated(ledger$deliverable))
    stop("Deliverable names must be nonblank and unique.")
  for (name in c("planned", "actual", "pct", "eac"))
    if (!is.numeric(ledger[[name]]) || any(!is.finite(ledger[[name]])) || any(ledger[[name]] < 0))
      stop("Ledger values must be finite, nonnegative numbers: ", name)
  if (any(ledger$pct > 100)) stop("Percent complete must be between 0 and 100.")
  if (any(ledger$eac < ledger$actual)) stop("Forecast (EAC) cannot be below hours already spent; update the forecast first.")
  hours_scalar(contingency, "Contingency")
  invisible(TRUE)
}

# Fractional-hour inputs are valid. Integer-only sprintf('%d') used to fail
# after a user typed 1.5, and rounding the ask could understate the shortfall.
hours_sprintf <- function(template, ...) {
  values <- lapply(list(...), function(x) if (is.numeric(x))
    format(x, trim = TRUE, scientific = FALSE, digits = 12) else x)
  do.call(sprintf, c(list(gsub("%d", "%s", template, fixed = TRUE)), values))
}

# Load the effort ledger from a CSV (the editable template) and split out the
# contingency reserve and the TOTAL summary row from the real deliverable rows.
hours_load <- function(path = NULL) {
  if (!is.null(path) && (!is.character(path) || length(path) != 1 || is.na(path) || !nzchar(path)))
    stop("Supply one explicit input path, or omit it to use the bundled example.")
  cand <- if (!is.null(path)) path else c(
            "../templates/project_hours_ledger.csv",
            "templates/project_hours_ledger.csv",
            "budget_reconciliation/templates/project_hours_ledger.csv")
  cand <- Filter(Negate(is.null), cand)
  p <- Find(file.exists, cand)
  if (is.null(p)) stop("Cannot find project_hours_ledger.csv (looked in: ",
                       paste(cand, collapse = ", "), ")")
  d <- utils::read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("Deliverable", "PlannedHours", "ActualToDate", "PctComplete", "EAC")
  if (anyDuplicated(names(d)) || !all(required %in% names(d)) || anyNA(d$Deliverable))
    stop("The CSV requires the documented ledger columns and nonmissing deliverable names.")
  cont_row  <- grepl("^CONTINGENCY", d$Deliverable, ignore.case = TRUE)
  total_row <- grepl("^TOTAL",       d$Deliverable, ignore.case = TRUE)
  if (sum(cont_row) > 1) stop("Only one CONTINGENCY row is allowed.")
  # A replacement CSV without an explicit reserve must not invent 40 hours.
  contingency <- if (any(cont_row)) as.numeric(d$PlannedHours[cont_row][1]) else 0
  ledger <- d[!cont_row & !total_row,
              c("Deliverable", "PlannedHours", "ActualToDate", "PctComplete", "EAC")]
  names(ledger) <- c("deliverable", "planned", "actual", "pct", "eac")
  ledger[c("planned", "actual", "pct", "eac")] <-
    lapply(ledger[c("planned", "actual", "pct", "eac")], as.numeric)
  rownames(ledger) <- NULL
  hours_validate(ledger, contingency)
  list(ledger = ledger, contingency = contingency)
}

# Export the editable ledger and its reserve together so a downloaded CSV can
# be loaded again without silently losing the current contingency setting.
hours_export <- function(ledger, contingency = DEFAULT_CONTINGENCY) {
  hours_validate(ledger, contingency)
  d <- ledger[c("deliverable", "planned", "actual", "pct", "eac")]
  d$variance <- d$planned - d$eac
  names(d) <- c("Deliverable", "PlannedHours", "ActualToDate", "PctComplete", "EAC", "Variance")
  rbind(d, data.frame(Deliverable = "CONTINGENCY", PlannedHours = contingency,
                     ActualToDate = 0, PctComplete = 0, EAC = 0, Variance = 0))
}

# Portfolio-level roll-up. Existing forecast overruns consume reserve first.
# Signed headroom preserves an existing deficit instead of inventing capacity.
hours_metrics <- function(ledger, contingency = DEFAULT_CONTINGENCY) {
  hours_validate(ledger, contingency)
  planned <- sum(ledger$planned); actual <- sum(ledger$actual); eac <- sum(ledger$eac)
  if (any(!is.finite(c(planned, actual, eac)))) stop("Ledger totals exceed the supported numeric range.")
  net_slack <- max(0, planned - eac)
  baseline_overrun <- max(0, eac - planned)
  reserve_used <- min(contingency, baseline_overrun)
  remaining_contingency <- contingency - reserve_used
  findable <- (planned - eac) + contingency
  if (!is.finite(findable)) stop("Available hours exceed the supported numeric range.")
  list(planned = planned, actual = actual, eac = eac,
       net_slack = net_slack, contingency = contingency,
       reserve_used = reserve_used, remaining_contingency = remaining_contingency,
       baseline_deficit = max(0, -findable), findable = findable)
}

# Test a new out-of-scope ask against the net headroom, sourcing hours in order:
# under-run slack first, then contingency, then whatever is left is a shortfall.
find_hours <- function(need, ledger, contingency = DEFAULT_CONTINGENCY) {
  need <- hours_scalar(need, "Requested hours")
  m <- hours_metrics(ledger, contingency)
  from_slack <- min(need, m$net_slack)
  from_cont  <- min(need - from_slack, m$remaining_contingency)
  request_shortfall <- need - from_slack - from_cont
  shortfall <- request_shortfall + m$baseline_deficit
  if (!is.finite(shortfall)) stop("Total shortfall exceeds the supported numeric range.")
  absorbable <- shortfall <= 0
  list(need = need, from_slack = from_slack, from_cont = from_cont,
       shortfall = shortfall, request_shortfall = request_shortfall,
       baseline_deficit = m$baseline_deficit,
       contingency_left = m$remaining_contingency - from_cont,
       absorbable = absorbable, metrics = m,
       verdict = if (absorbable) "Absorbable internally"
                 else if (m$baseline_deficit > 0) hours_sprintf("Total funding gap: %d h", shortfall)
                 else hours_sprintf("Change order needed: %d h", shortfall))
}

# Draft a change-order note (hours only) for a residual shortfall.
change_order_text <- function(fh, study = "CP-XXX", deliverable = "<out-of-scope deliverable>") {
  paste0(
    "# Change Order (effort, hours)\n\n",
    "Study: ", study, "\n",
    "Added deliverable: ", deliverable, "\n\n",
    "Estimated effort: ", fh$need, " h\n",
    "Absorbed internally: ", fh$from_slack + fh$from_cont, " h ",
    "(", fh$from_slack, " h under-run slack + ", fh$from_cont, " h contingency)\n",
    "Additional scope not funded: ", fh$request_shortfall, " h\n",
    "Existing forecast deficit after reserve: ", fh$baseline_deficit, " h\n",
    "Total gap requiring a funding decision: ", fh$shortfall, " h\n\n",
    "Justification: review the added scope and any existing forecast deficit separately. ",
    "An overrun on existing work is not evidence of additional scope. ",
    "Agree reallocation, re-sequencing, or a change order with the PM and sponsor.\n\n",
    "Approvals: Lead Biostatistician ______  Project Manager ______  Sponsor ______\n\n",
    "Hours/effort only. Pricing is handled downstream by the PM / project finance.\n")
}
