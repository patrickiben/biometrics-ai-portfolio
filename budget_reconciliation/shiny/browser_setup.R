BW_TEMPLATES <- list("project_hours_ledger.csv" = list(data = hours_export(seed$ledger, seed$contingency), required = TRUE))
bw_hours_validate <- function(frames, settings = NULL) {
  d <- frames[["project_hours_ledger.csv"]]
  bw_need(bw_nonblank(d$Deliverable) && !anyDuplicated(d$Deliverable), "Deliverable names must be nonblank and unique.")
  reserve <- grepl("^CONTINGENCY", d$Deliverable, ignore.case = TRUE)
  total <- grepl("^TOTAL", d$Deliverable, ignore.case = TRUE)
  bw_need(sum(reserve) <= 1L, "Only one contingency row is allowed.")
  contingency <- if (any(reserve)) d$PlannedHours[reserve][[1]] else 0
  ledger <- d[!reserve & !total, c("Deliverable", "PlannedHours", "ActualToDate", "PctComplete", "EAC"), drop = FALSE]
  names(ledger) <- c("deliverable", "planned", "actual", "pct", "eac")
  hours_validate(ledger, contingency)
  if (!is.null(settings$need)) hours_scalar(settings$need, "Requested hours")
  list(ledger = ledger, contingency = contingency)
}
