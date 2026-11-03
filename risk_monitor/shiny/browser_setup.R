BW_TEMPLATES <- list("signals.csv" = list(data = as.data.frame(seed), required = TRUE))
bw_risk_validate <- function(frames, settings = NULL) {
  s <- frames[["signals.csv"]]; risk_validate(s, require_both = TRUE)
  s$level <- factor(s$level, levels = c("green", "amber", "red")); s
}
