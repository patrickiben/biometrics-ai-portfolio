# Launcher-only synthetic runs use the existing deterministic drafting fallback.
# Preserve every computation and validator; prevent optional model clients from
# loading or contacting a service when the user chose to rebuild a sample.
source <- function(file, local = FALSE, ...) {
  # Resolve TRUE in the original caller, before base::source enters this wrapper's frame.
  target <- if (isTRUE(local)) parent.frame() else local
  result <- base::source(file, local = target, ...)
  if (is.character(file) && length(file) == 1L && basename(file) == "slm_client.R") {
    target <- if (is.environment(target)) target else .GlobalEnv
    assign(".has_httr2", FALSE, envir = target)
    assign(".has_reticulate", FALSE, envir = target)
  }
  invisible(result)
}
