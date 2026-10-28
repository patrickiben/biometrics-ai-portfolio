# Launcher-only synthetic runs use the existing deterministic drafting fallback.
# Preserve every computation and validator; prevent optional model clients from
# loading or contacting a service when the user chose to rebuild a sample.
source <- function(file, local = FALSE, ...) {
  result <- base::source(file, local = local, ...)
  if (is.character(file) && length(file) == 1L && basename(file) == "slm_client.R") {
    target <- if (is.environment(local)) local else if (isTRUE(local)) parent.frame() else .GlobalEnv
    assign(".has_httr2", FALSE, envir = target)
    assign(".has_reticulate", FALSE, envir = target)
  }
  invisible(result)
}
