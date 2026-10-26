# ---------------------------------------------------------------------------
# logic.R - pure graph logic for the Study Knowledge Graph (CP-101 KB).
# The vault is a set of linked notes; this computes the graph metrics the app,
# the Quarto page, and the tests all share. No PHI. Synthetic study.
# ---------------------------------------------------------------------------
suppressWarnings(suppressMessages(library(igraph)))

kg_load <- function(dir = NULL) {
  cand <- c(dir, "data", "../data", "shiny/data", "knowledge_vault/shiny/data")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "nodes.csv")), cand)
  if (is.null(base)) stop("Cannot find nodes.csv")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE)
  list(nodes = rd("nodes.csv"), edges = rd("edges.csv"), types = rd("types.csv"))
}

kg_igraph <- function(kg) {
  g <- igraph::graph_from_data_frame(kg$edges[, c("from", "to")],
         directed = FALSE, vertices = kg$nodes["id"])
  igraph::simplify(g)
}

# Attach degree + betweenness to the node frame (drives node size / importance).
kg_metrics <- function(kg) {
  g <- kg_igraph(kg)
  n <- kg$nodes
  deg <- igraph::degree(g)[n$id]
  btw <- round(igraph::betweenness(g, normalized = TRUE)[n$id] * 100)
  n$degree <- as.integer(deg)
  n$betweenness <- as.integer(btw)
  n
}

kg_neighbors <- function(kg, id) {
  e <- kg$edges
  ids <- unique(c(e$to[e$from == id], e$from[e$to == id]))
  kg$nodes[kg$nodes$id %in% ids, c("id", "title", "type")]
}

kg_stats <- function(kg) {
  n <- kg_metrics(kg)
  hub <- n[order(-n$degree), ][1, ]
  broker <- n[order(-n$betweenness), ][1, ]
  list(n_nodes = nrow(n), n_edges = nrow(kg$edges),
       n_clusters = length(unique(n$cluster)), n_types = length(unique(n$type)),
       hub_id = hub$id, hub_title = hub$title, hub_degree = hub$degree,
       broker_id = broker$id, broker_title = broker$title,
       by_type = as.data.frame(table(type = n$type)),
       orphans = sum(n$degree == 0))
}

# Nodes/edges shaped for visNetwork (id/label/group/value/color/title + from/to).
kg_vis <- function(kg) {
  n <- kg_metrics(kg)
  col <- setNames(kg$types$color, kg$types$type)
  nodes <- data.frame(
    id = n$id, label = n$title, group = n$type,
    value = pmax(4, n$degree), color = unname(col[n$type]),
    title = sprintf("<b>%s</b><br>%s · %s<br>owner: %s<br>%s",
             n$title, n$type, n$status, n$owner, n$summary),
    stringsAsFactors = FALSE)
  edges <- data.frame(from = kg$edges$from, to = kg$edges$to, stringsAsFactors = FALSE)
  list(nodes = nodes, edges = edges, legend = kg$types)
}
