# Native comparison oracle for an actual browser-generated methods ZIP.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
root <- normalizePath(args[1]); browser <- normalizePath(args[2]); output <- args[3]
source(file.path(root, 'browser_modules/methods/methods.R'))
config <- jsonlite::read_json(file.path(browser, 'configuration.json'), simplifyVector = TRUE)
result <- methods_run(config, root, output)
files <- list.files(browser, pattern = '\\.csv$', recursive = TRUE)
files <- setdiff(files, c('file_inventory.csv', 'software_versions.csv'))
rows <- cells <- 0L
diagnostics <- list()
max_relative_difference <- 0
for (file in files) {
  actual <- read.csv(file.path(browser, file), stringsAsFactors = FALSE)
  expected <- read.csv(file.path(result$directory, file), stringsAsFactors = FALSE)
  stopifnot(identical(names(actual), names(expected)), nrow(actual) == nrow(expected))
  for (key in names(actual)) {
    a <- actual[[key]]; b <- expected[[key]]
    stopifnot(identical(is.na(a), is.na(b)))
    if (is.numeric(a) && is.numeric(b)) {
      stopifnot(identical(is.infinite(a), is.infinite(b)), identical(a[is.infinite(a)], b[is.infinite(b)]))
      keep <- is.finite(a)
      relative <- abs(a[keep] - b[keep]) / pmax(1, abs(b[keep]))
      exceptions <- integer()
      if (config$kind == 'study' && file %in% c('study/05_qc/qc_ledger.csv', 'tables/table-05.csv') && key == 'max_abs_diff') {
        # GLM versus REML optimizer diagnostics can differ across native/Wasm math
        # libraries. This explicitly bounded exception applies only to the existing
        # within-CV check; its published 1e-6 tolerance and pass/fail rules stay fixed.
        exceptions <- which(keep)[which(relative > 1e-8)]
        if (length(exceptions)) {
          i <- exceptions
          stopifnot(all(actual$id[i] == 'Q3'), all(actual$variable[i] == 'cv_within'), all(actual$tolerance[i] == 1e-6), identical(actual$tolerance[i], expected$tolerance[i]), all(actual$status[i] == 'pass'), all(actual$mismatches[i] == 0), all(a[i] >= 0), all(b[i] >= 0), all(a[i] <= actual$tolerance[i]), all(b[i] <= expected$tolerance[i]))
          for (i in exceptions) diagnostics[[length(diagnostics) + 1L]] <- list(file = file, row = i, item = actual$item[i], variable = actual$variable[i], browser = a[i], native = b[i], canonical_tolerance = actual$tolerance[i])
        }
      }
      usual <- keep & !seq_along(a) %in% exceptions
      relative <- abs(a[usual] - b[usual]) / pmax(1, abs(b[usual]))
      if (length(relative)) max_relative_difference <- max(max_relative_difference, relative)
      if (any(relative > 1e-8)) stop(file, ': numerical mismatch in ', key, call. = FALSE)
    } else stopifnot(identical(as.character(a), as.character(b)))
  }
  rows <- rows + nrow(actual); cells <- cells + nrow(actual) * ncol(actual)
}
if (config$kind == 'sandbox') {
  for (file in list.files(file.path(root, 'sim_lifecycle/out'), pattern = '\\.csv$', full.names = FALSE))
    stopifnot(identical(unname(tools::md5sum(file.path(root, 'sim_lifecycle/out', file))), unname(tools::md5sum(file.path(browser, 'sim_lifecycle/out', file)))))
}
if (config$kind == 'study') {
  checks <- read.csv(file.path(browser, 'study/05_qc/qc_ledger.csv'))
  stopifnot(nrow(checks) == 40L, all(checks$status == 'pass'))
}
cat(jsonlite::toJSON(list(kind = config$kind, passed = TRUE, csv_files = length(files), rows = rows, cells = cells, max_relative_difference = max_relative_difference, qc_ledger_diagnostics = diagnostics, tolerance = '1e-8 * max(1, abs(native)); exact missingness and nonnumeric fields'), auto_unbox = TRUE, digits = 16), '\n')
