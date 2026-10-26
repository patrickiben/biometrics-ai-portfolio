# Study Knowledge Graph - Shiny app

The CP-101 study knowledge base as an interactive, force-directed graph of linked
notes. Filter by note type, click a node to see its detail and neighbours, and read
the graph metrics (degree, brokers, clusters). Synthetic study, no PHI.

## Run it

```r
install.packages(c("shiny", "bslib", "visNetwork", "igraph"))   # once
shiny::runApp("knowledge_vault/shiny")
```

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny app (a `visNetwork` graph + value boxes + a node-detail panel). |
| `R/logic.R` | The **pure graph logic** - builds the `igraph`, computes degree / betweenness / clusters (`kg_metrics`, `kg_stats`), finds a node's neighbours, and shapes nodes/edges for `visNetwork` (`kg_vis`). The Quarto page and unit tests call the same functions. |
| `data/nodes.csv` | The notes (id, title, type, status, owner, cluster, summary). |
| `data/edges.csv` | The links (from, to). |
| `data/types.csv` | The type legend (type, label, colour). |
| `../tests/test-logic.R` | Unit tests (run with `Rscript`). |

## Make it your own

The three CSVs *are* the vault. Add a note as a row in `nodes.csv`, wire it up with
rows in `edges.csv`, and it appears in the graph, sized by how many notes link to
it. Add a category by adding a row to `types.csv`. Nothing is hard-coded; the layout,
degree sizing, and neighbour lookups all come from the data via `igraph`.

## Other formats

The [visual guide](../quarto/kg-guide.html) explains the structure, the shareable
[interactive graph](../quarto/kg-graph.html) embeds the same graph with no server,
and the [run-and-build page](../quarto/kg-build.html) shows how it is made - all from
this `R/logic.R`.

*Synthetic study knowledge base. No PHI, no participant-level data.*
