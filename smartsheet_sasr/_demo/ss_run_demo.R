# ss_run_demo.R — the worked nightly job, run for REAL against the local representative
# Smartsheet API. It sources the SHIPPED library (macro_library/ss_companion.R) and only
# overrides the base URL, so every function exercised here — ss_colmap, ss_get_rows,
# ss_upsert, ss_attach, ss_guard — is the exact code that ships. Ops-only; no PHI.
source("macro_library/ss_companion.R")                       # the real SHEETLINK library
SS_BASE <<- sprintf("http://127.0.0.1:%s/2.0", Sys.getenv("SS_MOCK_PORT", "9787"))
sheet <- Sys.getenv("CP101_TRACKER_ID", "5500")
allow <- c("TaskID", "Task", "Status", "PctDone", "Owner", "Due")   # the ops-only allowlist

cat("\n== read the sheet first: fresh column map + rows, keyed by the Task code ==\n")
cm <- ss_colmap(sheet)
cat("column map (title -> columnId):\n"); print(cm)
before <- ss_get_rows(sheet, cm)
print(as.data.frame(before)[, c("rowId", "TASKID", "STATUS", "PCTDONE", "DUE")])

cat("\n== compute tonight's operational status from the validated extract ==\n")
df <- tibble::tibble(
  TaskID  = c("CP101-ENR", "CP101-ADPC", "CP101-CUT", "CP101-TLF", "CP101-CSR"),
  Task    = c(NA,          NA,           NA,          NA,          "CSR shell - build"),
  Status  = c("At Risk",   "On Track",   "Watch",     "On Track",  "Planned"),
  PctDone = c(NA,          0.85,         NA,          0.10,        0.00),
  Owner   = c(NA,          NA,           NA,          NA,          "Biostat"),
  Due     = c("ongoing",   "15 Jun",     "19 Jun",    "26 Jun",    "10 Jul"))
print(as.data.frame(df))

cat("\n== push by key: idempotent upsert (ops-only allowlist enforced in code) ==\n")
ss_upsert(sheet = sheet, key = "TaskID", df = df, allow = allow)

cat("\n== attach last night's one-page status PDF to the data-cut row ==\n")
ss_attach(sheet = sheet, row = 1003, file = "_demo/CP101_status.pdf")

cat("\n== re-run the SAME job: matched by key, it converges and never duplicates ==\n")
ss_upsert(sheet = sheet, key = "TaskID", df = df, allow = allow)

cat("\n== try to push a non-allowlisted column: the guard blocks it (no PHI to cloud) ==\n")
bad <- tibble::tibble(TaskID = "CP101-ENR", ParticipantALT = 6.2)
tryCatch(ss_upsert(sheet = sheet, key = "TaskID", df = bad, allow = allow),
         error = function(e) cat(conditionMessage(e), "\n"))
