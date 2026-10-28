#!/usr/bin/env Rscript
# Synthetic operational example. Base R only; Python 3.10+ must be on PATH.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Run this example with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
module_dir <- dirname(dirname(script_file))
output_dir <- if (length(args)) args[[1L]] else file.path(module_dir, "out")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, mustWork = TRUE)
python <- Sys.which("python3")
if (!nzchar(python)) python <- Sys.which("python")
if (!nzchar(python)) stop("Install Python 3.10+ and put it on PATH.")

rows <- data.frame(
  task_id = c("DEMO-ADAM", "DEMO-TLF", "DEMO-QC", "007"),
  title = c("ADaM specification review", "TLF shell approval", "Independent QC plan", "Transfer readiness check"),
  status = c("In progress", "Blocked", "Done", "At risk"),
  owner = c("Programming", "Biostatistics", "QC lead", "Data management"),
  due = c("2026-11-06", "2026-11-09", "2026-10-27", "2026-11-02"),
  progress = c(70L, 40L, 100L, 25L),
  notes = rep("Synthetic example from the base-R bridge.", 4),
  stringsAsFactors = FALSE
)
csv_path <- file.path(output_dir, "r-status.csv")
write.csv(rows, csv_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
run_tracker <- function(...) {
  command_args <- c(file.path(module_dir, "tracker.py"), "--db", file.path(output_dir, "tracker.sqlite"), ...)
  status <- system2(python, args = vapply(command_args, shQuote, character(1)))
  if (status != 0L) stop("Tracker command failed; exit status ", status)
}
run_tracker("upsert", "--csv", csv_path, "--actor", "R-demo")
run_tracker("export", "--html", file.path(output_dir, "tracker.html"))
cat("Open ", file.path(output_dir, "tracker.html"), " in a browser.\n", sep = "")
