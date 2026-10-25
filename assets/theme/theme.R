# assets/theme/theme.R: shared look for the portfolio's Shiny apps (bslib >= 0.6, Bootstrap 5.3).
# Generated from assets/theme/tokens.css by build_pages.py; edit the tokens, not this file.
# Adopt: copy into the app folder (Shinylive apps cannot read files outside it), source("theme.R"),
# then page_sidebar(theme = bp_theme(), bp_theme_head(), ...). No Shiny app uses it yet; the Quarto
# guides and snapshots source it for figure ink (bp_ggplot_theme, one rendering per theme).
bp_tokens <- list(
  dark = c(bg = "#0b0f15", surface = "#111721", surface_2 = "#161e2a", line = "#222c3b", line_2 = "#2e3a4d", ink = "#e8eef6", text = "#c9d3e1", muted = "#98a5b8", accent = "#3ad7c8", accent_ink = "#8ff0e6", blue = "#7aa4ff", green = "#4fd394", amber = "#f0b450", red = "#ff7a7a"),
  light = c(bg = "#f4f6f9", surface = "#ffffff", surface_2 = "#eef2f6", line = "#d7dee7", line_2 = "#c3ccd8", ink = "#121a24", text = "#1f2a37", muted = "#4d5a69", accent = "#0b7268", accent_ink = "#075b53", blue = "#0757bf", green = "#1d6b3c", amber = "#8a5300", red = "#b42318"))

bp_theme <- function() {
  l <- bp_tokens$light; d <- bp_tokens$dark
  bslib::bs_theme(
    version = 5,
    bg = l[["bg"]], fg = l[["text"]],
    primary = l[["accent"]], secondary = l[["muted"]], success = l[["green"]],
    info = l[["blue"]], warning = l[["amber"]], danger = l[["red"]],
    base_font = bslib::font_collection("-apple-system", "BlinkMacSystemFont", "Segoe UI",
                                       "Roboto", "Helvetica Neue", "Arial", "sans-serif"),
    code_font = bslib::font_collection("ui-monospace", "SF Mono", "Cascadia Mono", "Menlo",
                                       "Consolas", "monospace"),
    "border-radius" = "0.375rem", "border-radius-lg" = "0.75rem", "border-color" = l[["line"]],
    # Bootstrap 5.3 dark color mode
    "body-bg-dark" = d[["bg"]], "body-color-dark" = d[["text"]],
    "body-emphasis-color-dark" = d[["ink"]], "body-secondary-color-dark" = d[["muted"]],
    "body-secondary-bg-dark" = d[["surface"]], "body-tertiary-bg-dark" = d[["surface_2"]],
    "border-color-dark" = d[["line"]], "link-color-dark" = d[["accent"]],
    "link-hover-color-dark" = d[["accent_ink"]], "code-color-dark" = d[["accent_ink"]]
  )
}

# Same precedence as the site: a saved choice, then the system setting, then dark.
bp_theme_head <- function() {
  htmltools::tags$script(htmltools::HTML(paste0(
    "(function(){var t;try{t=localStorage.getItem('bp-theme')}catch(e){}",
    "if(t!=='light'&&t!=='dark'){t=(window.matchMedia&&matchMedia('(prefers-color-scheme: light)').matches)?'light':'dark'}",
    "document.documentElement.setAttribute('data-bs-theme',t)})();")))
}

# Neutral chart ink for ggplot2; series colors stay with each app.
bp_ggplot_theme <- function(mode = c("dark", "light"), base_size = 12) {
  k <- bp_tokens[[match.arg(mode)]]
  ggplot2::theme_minimal(base_size = base_size) + ggplot2::theme(
    plot.background = ggplot2::element_rect(fill = k[["surface"]], color = NA),
    panel.grid = ggplot2::element_line(color = k[["line"]]),
    text = ggplot2::element_text(color = k[["text"]]),
    axis.text = ggplot2::element_text(color = k[["muted"]]))
}
