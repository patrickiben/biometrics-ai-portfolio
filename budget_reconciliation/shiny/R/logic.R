# ---------------------------------------------------------------------------
# logic.R — pure reconciliation logic for the "Find Hours" tool.
# HOURS / EFFORT ONLY. No dollars, rates, ROI, or headcount. Synthetic data.
#
# These are plain functions with no Shiny dependency, so the Shiny app, the
# Quarto documents, and the unit tests all call the SAME logic. Edit the math
# in one place and every surface updates.
# ---------------------------------------------------------------------------

DEFAULT_CONTINGENCY <- 40L

# Load the effort ledger from a CSV (the editable template) and split out the
# contingency reserve and the TOTAL summary row from the real deliverable rows.
hours_load <- function(path = NULL) {
  cand <- c(path,
            "../templates/project_hours_ledger.csv",
            "templates/project_hours_ledger.csv",
            "budget_reconciliation/templates/project_hours_ledger.csv")
  cand <- Filter(Negate(is.null), cand)
  p <- Find(file.exists, cand)
  if (is.null(p)) stop("Cannot find project_hours_ledger.csv (looked in: ",
                       paste(cand, collapse = ", "), ")")
  d <- utils::read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
  cont_row  <- grepl("^CONTINGENCY", d$Deliverable, ignore.case = TRUE)
  total_row <- grepl("^TOTAL",       d$Deliverable, ignore.case = TRUE)
  contingency <- if (any(cont_row)) as.integer(d$PlannedHours[cont_row][1]) else DEFAULT_CONTINGENCY
  ledger <- d[!cont_row & !total_row,
              c("Deliverable", "PlannedHours", "ActualToDate", "PctComplete", "EAC")]
  names(ledger) <- c("deliverable", "planned", "actual", "pct", "eac")
  ledger[c("planned", "actual", "pct", "eac")] <-
    lapply(ledger[c("planned", "actual", "pct", "eac")], as.numeric)
  rownames(ledger) <- NULL
  list(ledger = ledger, contingency = contingency)
}

# Portfolio-level roll-up. net_slack is the honest under-run across every task
# (planned minus the forecast cost to finish, floored at zero); findable adds
# the contingency reserve. This is the one number the whole tool is about.
hours_metrics <- function(ledger, contingency = DEFAULT_CONTINGENCY) {
  planned <- sum(ledger$planned); actual <- sum(ledger$actual); eac <- sum(ledger$eac)
  net_slack <- max(0, planned - eac)
  list(planned = planned, actual = actual, eac = eac,
       net_slack = net_slack, contingency = contingency,
       findable = net_slack + contingency)
}

# Test a new out-of-scope ask against the net headroom, sourcing hours in order:
# under-run slack first, then contingency, then whatever is left is a shortfall.
find_hours <- function(need, ledger, contingency = DEFAULT_CONTINGENCY) {
  need <- max(0, round(as.numeric(need)))
  m <- hours_metrics(ledger, contingency)
  from_slack <- min(need, m$net_slack)
  from_cont  <- min(need - from_slack, contingency)
  shortfall  <- need - from_slack - from_cont
  absorbable <- shortfall <= 0
  list(need = need, from_slack = from_slack, from_cont = from_cont,
       shortfall = shortfall, contingency_left = contingency - from_cont,
       absorbable = absorbable, metrics = m,
       verdict = if (absorbable) "Absorbable internally"
                 else sprintf("Change order needed: %d h", shortfall))
}

# Draft a change-order note (hours only) for a residual shortfall.
change_order_text <- function(fh, study = "CP-XXX", deliverable = "<out-of-scope deliverable>") {
  paste0(
    "# Change Order (effort, hours)\n\n",
    "Study: ", study, "\n",
    "Added deliverable: ", deliverable, "\n\n",
    "Estimated effort: ", fh$need, " h\n",
    "Absorbed internally: ", fh$need - fh$shortfall, " h ",
    "(", fh$from_slack, " h under-run slack + ", fh$from_cont, " h contingency)\n",
    "Additional scope requiring a change order: ", fh$shortfall, " h\n\n",
    "Justification: the residual ", fh$shortfall,
    " h is not covered by planned effort or the management reserve and represents ",
    "scope beyond the current SOW.\n\n",
    "Approvals: Lead Biostatistician ______  Project Manager ______  Sponsor ______\n\n",
    "Hours/effort only. Pricing is handled downstream by the PM / project finance.\n")
}
