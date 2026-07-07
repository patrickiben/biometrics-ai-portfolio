# ===========================================================================
# app.R - Study Knowledge Graph (Shiny + visNetwork).
#
# The CP-101 study knowledge base as an interactive, force-directed graph of
# linked notes. Filter by note type, click a node to see its detail and its
# neighbours, and read the graph metrics (degree, brokers, clusters). No PHI.
#
# Run:  shiny::runApp("knowledge_vault/shiny")
# Data: data/nodes.csv + edges.csv + types.csv (swap in your own vault).
# ===========================================================================
library(shiny); library(bslib); library(visNetwork)
source("R/logic.R")
kg <- kg_load("data")
V  <- kg_vis(kg)

ui <- page_sidebar(
  title = "Study Knowledge Graph",
  theme = bs_theme(version = 5, bootswatch = "darkly", primary = "#5b8cff"),
  sidebar = sidebar(
    width = 320,
    div(class = "small text-muted",
        "The CP-101 study knowledge base as a linked-note graph. Filter by type, ",
        "click a node for its detail and neighbours. Synthetic, no PHI."),
    checkboxGroupInput("types", "Show note types",
      choices = setNames(kg$types$type, kg$types$label), selected = kg$types$type),
    selectInput("focus", "Focus a note", choices = c("(none)" = "", setNames(kg$nodes$id, kg$nodes$title))),
    hr(),
    uiOutput("detail")
  ),
  layout_columns(
    col_widths = c(3,3,3,3),
    value_box("Notes", textOutput("k_nodes"), theme = "secondary"),
    value_box("Links", textOutput("k_edges"), theme = "secondary"),
    value_box("Clusters", textOutput("k_clusters"), theme = "info"),
    value_box("Hub links (CP-101)", textOutput("k_hub"), theme = "warning")
  ),
  card(card_header("Knowledge graph (drag to explore · click a note)"),
       visNetworkOutput("net", height = "560px"))
)

server <- function(input, output, session) {
  st <- kg_stats(kg)
  output$k_nodes    <- renderText(as.character(st$n_nodes))
  output$k_edges    <- renderText(as.character(st$n_edges))
  output$k_clusters <- renderText(as.character(st$n_clusters))
  output$k_hub      <- renderText(as.character(st$hub_degree))

  sub <- reactive({
    keep <- V$nodes$group %in% input$types
    ns <- V$nodes[keep, ]
    es <- V$edges[V$edges$from %in% ns$id & V$edges$to %in% ns$id, ]
    list(nodes = ns, edges = es)
  })

  output$net <- renderVisNetwork({
    s <- sub()
    legend <- data.frame(label = kg$types$label, color = kg$types$color,
                         shape = "dot", stringsAsFactors = FALSE)
    visNetwork(s$nodes, s$edges, background = "#141925") |>
      visNodes(font = list(color = "#e9edf7", size = 16), borderWidth = 1) |>
      visEdges(color = list(color = "#2A3242", highlight = "#5b8cff"), smooth = FALSE) |>
      visOptions(highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE)) |>
      visPhysics(solver = "forceAtlas2Based",
                 forceAtlas2Based = list(gravitationalConstant = -55), stabilization = TRUE) |>
      visLegend(useGroups = FALSE, addNodes = legend, width = 0.18, position = "left", ncol = 1) |>
      visEvents(selectNode = "function(n){ Shiny.setInputValue('kg_sel', n.nodes[0], {priority:'event'}); }")
  })

  observeEvent(input$focus, {
    if (nzchar(input$focus)) visNetworkProxy("net") |> visFocus(id = input$focus, scale = 1.2) |>
      visSelectNodes(id = input$focus)
  })
  selected <- reactiveVal("hub")
  observeEvent(input$kg_sel, selected(input$kg_sel))
  observeEvent(input$focus, if (nzchar(input$focus)) selected(input$focus))

  output$detail <- renderUI({
    id <- selected(); n <- kg$nodes[kg$nodes$id == id, ]
    if (!nrow(n)) return(div(class = "small text-muted", "Click a note in the graph."))
    nb <- kg_neighbors(kg, id)
    col <- setNames(kg$types$color, kg$types$type)[n$type]
    tagList(
      div(class = "fw-bold", n$title),
      div(class = "small", tags$span(style = sprintf("color:%s;font-weight:700", col), n$type),
          " · ", n$status, " · ", n$owner),
      div(class = "small text-muted my-1", n$summary),
      div(class = "small", tags$b(sprintf("Links to %d notes: ", nrow(nb))),
          paste(nb$title, collapse = ", "))
    )
  })
}

shinyApp(ui, server)
