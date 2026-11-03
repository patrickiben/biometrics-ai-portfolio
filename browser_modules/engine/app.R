# Build-only dependency declaration for the direct browser R workspace.
suppressPackageStartupMessages({
  library(shiny)
library(bslib)
library(DT); library(jsonlite); library(dplyr); library(tidyr)
  library(stringr); library(purrr); library(tibble); library(rtables)
  library(ggplot2)
library(ggrepel)
library(patchwork); library(emmeans); library(lme4); library(lmerTest)
  library(broom); library(broom.mixed); library(testthat)
  # The canonical sandbox sources slm_client.R, which probes these optional
  # namespaces before browser methods disable the external model clients.
  # Stage their full dependency closure so the probes never fetch a CDN package.
  library(reticulate); library(digest); library(httr2)
})
shinyApp(fluidPage('Browser runtime assets'), function(input, output, session) {})
