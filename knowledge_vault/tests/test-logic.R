#!/usr/bin/env Rscript
# Unit tests for the Study Knowledge Graph logic. Needs igraph.
# Run:  Rscript knowledge_vault/tests/test-logic.R

lp <- Find(file.exists, c("../shiny/R/logic.R", "knowledge_vault/shiny/R/logic.R", "shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp)); source(lp)
dir <- Find(function(d) file.exists(file.path(d, "nodes.csv")),
            c("../shiny/data", "knowledge_vault/shiny/data", "shiny/data"))
kg <- kg_load(dir)
s  <- kg_stats(kg)
v  <- kg_vis(kg)

stopifnot(
  "28 notes"                 = s$n_nodes == 28,
  "59 links"                 = s$n_edges == 59,
  "hub is most-connected"    = s$hub_id == "hub",
  "no orphan notes"          = s$orphans == 0,
  "every vis node has colour"= all(!is.na(v$nodes$color)),
  "no India/NA in owners"    = !any(grepl("India|\\(NA\\)", kg$nodes$owner)),
  "SAP links to 7 notes"     = nrow(kg_neighbors(kg, "sap")) == 7
)

cat("Knowledge-graph logic: all tests passed\n")
