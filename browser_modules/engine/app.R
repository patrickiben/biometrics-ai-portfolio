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
})
shinyApp(fluidPage('Browser runtime assets'), function(input, output, session) {})
