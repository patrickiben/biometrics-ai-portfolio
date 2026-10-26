# Presentation helpers shared by the TRIALMON Quarto pages (tables, labels, light/dark plots).
# The rules themselves live in ../trialmon_shiny/R/logic.R.

esc <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

sev_html <- function(s) sprintf('<span class="sev sev-%s">%s</span>', s, s)

kpi_html <- function(label, value) sprintf('<div class="tm-kpi"><div class="k">%s</div><div class="v">%s</div></div>', esc(label), value)

# df -> an HTML table. `num` names right-aligned columns; `raw` names columns already in HTML;
# `row_class` gives an optional class per row; `nowrap` names columns kept on one line (IDs).
html_table <- function(df, num = character(0), raw = character(0), row_class = NULL, caption = NULL,
                       nowrap = intersect(names(df), c("Participant", "Participant, cohort or indicator"))) {
  th <- vapply(names(df), function(n) sprintf('<th scope="col"%s>%s</th>', if (n %in% num) ' class="num"' else "", esc(n)), "")
  rows <- vapply(seq_len(nrow(df)), function(i) {
    td <- vapply(names(df), function(n) {
      v <- df[[n]][i]; v <- if (n %in% raw) as.character(v) else esc(v)
      cl <- c(if (n %in% num) "num", if (n %in% nowrap) "nw")
      sprintf('<td%s>%s</td>', if (length(cl)) sprintf(' class="%s"', paste(cl, collapse = " ")) else "", v)
    }, "")
    rc <- if (!is.null(row_class) && nzchar(row_class[i])) sprintf(' class="%s"', row_class[i]) else ""
    sprintf("<tr%s>%s</tr>", rc, paste(td, collapse = ""))
  }, "")
  cap <- if (is.null(caption)) "" else sprintf("<caption>%s</caption>", caption)
  sprintf('<div class="tm-wrap"><table class="tm-table">%s<thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>\n',
          cap, paste(th, collapse = ""), paste(rows, collapse = "\n"))
}

npct <- function(n, N) {
  N <- rep_len(N, length(n))
  ifelse(N > 0, sprintf("%d (%.0f%%)", n, 100 * n / N), "0")
}

# light and dark versions of every figure (Quarto shows the one that matches the reader's theme);
# text and grid colors are the site tokens --text and --line (light) / --line-2 (dark)
TM_LOOK <- list(
  light = list(fg = "#1F2A37", grid = "#D7DEE7", pal = c(GREEN = "#1D6B3A", watch = "#2F5F8A", AMBER = "#A86400", RED = "#B42318"),
               tests = c(ALT = "#B42318", AST = "#A86400", ALP = "#4F5B67", TBL = "#0757BF")),
  dark = list(fg = "#C9D3E1", grid = "#2E3A4D", pal = c(GREEN = "#8FD8A8", watch = "#9CC3EA", AMBER = "#F3C169", RED = "#FF9B8F"),
              tests = c(ALT = "#FF9B8F", AST = "#F3C169", ALP = "#A9B3BD", TBL = "#7DB5FF")))

tm_theme <- function(look, base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) + ggplot2::theme(
    text = ggplot2::element_text(colour = look$fg), axis.text = ggplot2::element_text(colour = look$fg),
    panel.grid = ggplot2::element_line(colour = look$grid), legend.position = "top",
    plot.background = ggplot2::element_rect(fill = "transparent", colour = NA),
    panel.background = ggplot2::element_rect(fill = "transparent", colour = NA))
}

both <- function(make) print(make(TM_LOOK[["dark"]]))   # the pages use the dark theme (darkly), so one rendering

edish_plot <- function(h, look) {
  h$screen <- factor(ifelse(h$hys, "Potential Hy's Law", ifelse(!is.na(h$at3x_day), "AT > 3x ULN: confirm", "No hepatic flag")),
                     levels = c("Potential Hy's Law", "AT > 3x ULN: confirm", "No hepatic flag"))
  cols <- setNames(look$pal[c("RED", "AMBER", "GREEN")], levels(h$screen))
  lab <- h[h$peak_at >= 2.5 | h$peak_tbl > 1.5, ]
  lim <- edish_limits(h)                       # widened when needed, so no participant falls off
  ggplot2::ggplot(h, ggplot2::aes(peak_at, peak_tbl, colour = screen)) +
    ggplot2::annotate("rect", xmin = 3, xmax = Inf, ymin = 2, ymax = Inf, alpha = .10, fill = look$pal[["RED"]]) +
    ggplot2::geom_vline(xintercept = 3, linetype = 2, colour = look$pal[["AMBER"]]) +
    ggplot2::geom_hline(yintercept = 2, linetype = 2, colour = look$pal[["AMBER"]]) +
    ggplot2::geom_point(size = 2.8) +
    ggplot2::geom_text(data = lab, ggplot2::aes(label = USUBJID), vjust = -1, size = 3.2, show.legend = FALSE) +
    ggplot2::annotate("text", x = .96 * lim$x[2], y = .93 * lim$y[2], label = "upper right: check timing", hjust = 1, size = 3.2, colour = look$pal[["RED"]]) +
    ggplot2::annotate("text", x = .96 * lim$x[2], y = 1.1 * lim$y[1], label = "lower right: AT >= 3x, TBL <= 2x", hjust = 1, size = 3.2, colour = look$pal[["AMBER"]]) +
    ggplot2::annotate("text", x = 1.05 * lim$x[1], y = .93 * lim$y[2], label = "upper left: TBL > 2x, AT < 3x", hjust = 0, size = 3.2, colour = look$fg) +
    ggplot2::scale_x_log10(limits = lim$x) + ggplot2::scale_y_log10(limits = lim$y) +
    ggplot2::scale_colour_manual(values = cols, drop = FALSE, name = NULL) +
    ggplot2::labs(x = "Peak post-baseline ALT or AST (x ULN, log scale)", y = "Peak total bilirubin (x ULN, log scale)") +
    tm_theme(look)
}

trajectory_plot <- function(d, look, title) {
  ggplot2::ggplot(d, ggplot2::aes(ADY, xuln, colour = test)) +
    ggplot2::geom_hline(yintercept = c(2, 3), linetype = 3, colour = look$pal[["AMBER"]]) +
    ggplot2::geom_line(linewidth = .8) + ggplot2::geom_point(size = 1.8) +
    ggplot2::scale_colour_manual(values = look$tests, name = NULL) +
    ggplot2::labs(x = "Study day", y = "x ULN", title = title) + tm_theme(look, 11)
}
