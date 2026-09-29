# ==============================================================================
# APLICACIÓN: app.R
# PROYECTO: Buscador y Catálogo Digital del Acervo Editorial del INE
# TECNOLOGÍAS: R Shiny + bslib (Bootstrap 5) + DT + DuckDB + Plotly ($0 USD)
# ==============================================================================

library(shiny)
library(bslib)
library(DT)
library(duckdb)
library(dplyr)
library(stringr)
library(plotly)

# REGISTRO DE RUTA DE RECURSOS ESTÁTICOS PARA IMÁGENES DE PORTADAS
if (dir.exists("www/portadas")) {
  addResourcePath(prefix = "portadas", directoryPath = "www/portadas")
}

# ------------------------------------------------------------------------------
# 1. CARGA DE DATOS DESDE DUCKDB
# ------------------------------------------------------------------------------
conectar_db <- function() {
  con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb", read_only = TRUE)
  return(con)
}

con <- conectar_db()
if ("acervo_enriquecido" %in% dbListTables(con)) {
  datos_acervo <- dbReadTable(con, "acervo_enriquecido")
} else {
  datos_acervo <- dbReadTable(con, "acervo_editorial") %>%
    mutate(
      eje_tematico = "Cultura Democrática y Ciudadanía",
      poblacion_objetivo = "Público General",
      sinopsis_real = descripcion,
      palabras_clave = "INE, Cultura Democrática",
      ruta_portada = "portadas/portada_generica.jpg"
    )
}
dbDisconnect(con, shutdown = TRUE)

# Asegurar identificador y columna de portadas
if (!"id_obra" %in% colnames(datos_acervo)) {
  datos_acervo$id_obra <- seq_len(nrow(datos_acervo))
}
if (!"ruta_portada" %in% colnames(datos_acervo)) {
  datos_acervo$ruta_portada <- paste0("portadas/portada_", datos_acervo$id_obra, ".jpg")
}

opciones_coleccion <- c("Todas", sort(unique(datos_acervo$coleccion)))
opciones_eje       <- c("Todos", sort(unique(datos_acervo$eje_tematico)))
opciones_tipo      <- c("Todos", sort(unique(datos_acervo$tipo_recurso)))

# ------------------------------------------------------------------------------
# 2. INTERFAZ DE USUARIO (UI)
# ------------------------------------------------------------------------------
ui <- page_navbar(
  title = "📚 Acervo Editorial INE",
  theme = bs_theme(
    version = 5,
    bootswatch = "zephyr",
    primary = "#1D3557",
    secondary = "#D81B60",
    `enable-shadows` = TRUE
  ),

  # PESTAÑA PRINCIPAL: LIBRERÍA / CATÁLOGO
  nav_panel(
    title = "Catálogo de Libros",
    icon = icon("book-open-reader"),

    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        title = "Filtros del Catálogo",

        textInput(
          inputId = "txt_busqueda",
          label = "Buscar obra, tema o palabras clave:",
          placeholder = "Ej. voto, paridad, fake news, infancias..."
        ),

        selectInput(
          inputId = "sel_coleccion",
          label = "Colección Editorial:",
          choices = opciones_coleccion,
          selected = "Todas"
        ),

        selectInput(
          inputId = "sel_eje",
          label = "Eje Temático:",
          choices = opciones_eje,
          selected = "Todos"
        ),

        checkboxGroupInput(
          inputId = "chk_tipo",
          label = "Formato de Recurso:",
          choices = setdiff(opciones_tipo, "Todos"),
          selected = setdiff(opciones_tipo, "Todos")
        ),

        hr(),
        radioButtons(
          inputId = "tipo_vista",
          label = "Modo de Visualización:",
          choices = c("Galería de Libros 📚" = "galeria", "Vista de Tabla 📊" = "tabla"),
          selected = "galeria"
        ),

        actionButton("btn_limpiar", "Restablecer Filtros", icon = icon("rotate-left"), class = "btn-outline-dark btn-sm w-100 mt-2")
      ),

      # Indicadores Superiores (Value Boxes)
      layout_columns(
        fill = FALSE,
        value_box(
          title = "Títulos Disponibles",
          value = textOutput("val_total_recursos"),
          showcase = icon("book"),
          theme = "primary"
        ),
        value_box(
          title = "Colecciones",
          value = textOutput("val_total_colecciones"),
          showcase = icon("tags"),
          theme = "dark"
        ),
        value_box(
          title = "Formatos",
          value = textOutput("val_total_formatos"),
          showcase = icon("file-pdf"),
          theme = "secondary"
        )
      ),

      # VISTA DINÁMICA (GALERÍA O TABLA)
      uiOutput("contenedor_vista_dinamica")
    )
  ),

  # PESTAÑA: MÉTRICAS Y DASHBOARD
  nav_panel(
    title = "Análisis del Acervo",
    icon = icon("chart-pie"),
    layout_columns(
      card(
        card_header("Distribución de Obras por Eje Temático"),
        plotlyOutput("grafico_ejes")
      ),
      card(
        card_header("Participación por Colección Editorial"),
        plotlyOutput("grafico_colecciones")
      )
    )
  ),

  # PESTAÑA: CASO DE ESTUDIO
  nav_panel(
    title = "Acerca del Proyecto",
    icon = icon("circle-info"),
    card(
      card_header("Caso de Estudio: Optimización del Acervo Editorial del INE"),
      p("Buscador e-commerce e interfaz analítica desarrollada de forma independiente para explorar las publicaciones institucionales del INE."),
      tags$ul(
        tags$li(strong("Stack Tecnológico:"), " R, R Shiny, DuckDB, bslib, DT, rvest, plotly."),
        tags$li(strong("Ingeniería de Datos:"), " Web scraping multisección con rotación de User-Agents y etiquetado NLP."),
        tags$li(strong("Costo de Infraestructura:"), " $0 USD.")
      )
    )
  )
)

# ------------------------------------------------------------------------------
# 3. LÓGICA DEL SERVIDOR (SERVER)
# ------------------------------------------------------------------------------
server <- function(input, output, session) {

  # Filtrado Reactivo por Búsqueda Multidimensional
  datos_filtrados <- reactive({
    df <- datos_acervo

    if (nzchar(input$txt_busqueda)) {
      patron <- tolower(input$txt_busqueda)
      df <- df %>%
        filter(
          str_detect(tolower(coalesce(titulo, "")), patron) |
            str_detect(tolower(coalesce(descripcion, "")), patron) |
            str_detect(tolower(coalesce(sinopsis_real, "")), patron) |
            str_detect(tolower(coalesce(palabras_clave, "")), patron)
        )
    }

    if (input$sel_coleccion != "Todas") {
      df <- df %>% filter(coleccion == input$sel_coleccion)
    }

    if (input$sel_eje != "Todos") {
      df <- df %>% filter(eje_tematico == input$sel_eje)
    }

    if (length(input$chk_tipo) > 0) {
      df <- df %>% filter(tipo_recurso %in% input$chk_tipo)
    } else {
      df <- df[0, ]
    }

    return(df)
  })

  # Restablecer Filtros
  observeEvent(input$btn_limpiar, {
    updateTextInput(session, "txt_busqueda", value = "")
    updateSelectInput(session, "sel_coleccion", selected = "Todas")
    updateSelectInput(session, "sel_eje", selected = "Todos")
    updateCheckboxGroupInput(session, "chk_tipo", selected = setdiff(opciones_tipo, "Todos"))
  })

  # Indicadores Numéricos
  output$val_total_recursos <- renderText({ nrow(datos_filtrados()) })
  output$val_total_colecciones <- renderText({ n_distinct(datos_filtrados()$coleccion) })
  output$val_total_formatos <- renderText({ n_distinct(datos_filtrados()$tipo_recurso) })

  # Renderizado de Vista Dinámica
  output$contenedor_vista_dinamica <- renderUI({
    if (input$tipo_vista == "galeria") {
      uiOutput("galeria_libros")
    } else {
      card(
        card_header("Catálogo Tabular de Publicaciones"),
        DTOutput("tabla_acervo")
      )
    }
  })

  # GENERADOR DE GALERÍA CON PORTADAS Y SINOPSIS GARANTIZADAS
  output$galeria_libros <- renderUI({
    df <- datos_filtrados()

    if (is.null(df) || nrow(df) == 0) {
      return(
        div(
          class = "text-center p-5 my-4 bg-light rounded-3 border",
          icon("book-open", class = "fa-3x text-muted mb-3"),
          h5(class = "text-secondary", "No se encontraron obras que coincidan con tu búsqueda."),
          p(class = "text-muted small", "Intenta cambiar las palabras clave o restablecer los filtros de la izquierda.")
        )
      )
    }

    limite <- min(nrow(df), 48)

    tarjetas <- lapply(seq_len(limite), function(i_idx) {
      item <- df[i_idx, ]

      eje_txt <- coalesce(item$eje_tematico, "General")
      badge_color <- if(str_detect(eje_txt, "Paridad")) "bg-danger" else "bg-dark"

      kw_raw <- coalesce(item$palabras_clave, "INE, Cultura Democrática")
      tags_kw <- unlist(strsplit(kw_raw, ",\\s*"))

      # Respaldo para la Sinopsis
      sinopsis_txt <- coalesce(item$sinopsis_real, item$sinopsis, item$descripcion, "Publicación oficial del Instituto Nacional Electoral.")

      # Ruta de la imagen local en www/portadas/
      img_src <- sprintf("portadas/portada_%d.jpg", item$id_obra)

      div(
        class = "col-12 col-sm-6 col-md-4 col-lg-3 mb-4",
        div(
          class = "card h-100 shadow-sm border-0 transition-all",
          style = "border-radius: 12px; overflow: hidden; background: #ffffff;",

          # PORTADA VISUAL DEL LIBRO
          div(
            class = "d-flex align-items-center justify-content-center bg-light p-2 position-relative border-bottom",
            style = "height: 220px; overflow: hidden; background-color: #f8f9fa;",
            span(class = paste("badge position-absolute top-0 start-0 m-2 shadow-sm z-1", badge_color), item$tipo_recurso),
            tags$img(
              src = img_src,
              style = "max-height: 100%; max-width: 100%; object-fit: contain; border-radius: 4px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);",
              alt = item$titulo,
              onerror = "this.onerror=null; this.src='portadas/portada_generica.jpg';"
            )
          ),

          # DETALLES Y SINOPSIS DE LA OBRA
          div(
            class = "card-body d-flex flex-column justify-content-between p-3",
            div(
              h6(class = "card-title fw-bold text-truncate-2 mb-1", style = "font-size: 0.88rem; line-height: 1.2;", item$titulo),
              p(class = "text-muted small mb-1 text-truncate", icon("bookmark"), " ", item$coleccion),
              p(class = "badge bg-light text-dark border mb-2", eje_txt),

              # SINOPSIS VISIBLE DE LA OBRA
              div(
                class = "card-text small text-secondary mb-2",
                style = "font-size: 0.8rem; line-height: 1.35; color: #4a5568;",
                p(strong("Sinopsis: "), str_trunc(sinopsis_txt, 140))
              ),

              # TAGS DE PALABRAS CLAVE
              div(
                class = "mb-2",
                lapply(tags_kw, function(tag) {
                  span(class = "badge bg-secondary opacity-75 me-1 mb-1", style = "font-size: 0.65rem;", paste0("#", tag))
                })
              )
            ),

            # BOTÓN DE ENLACE DIRECTO
            div(
              class = "mt-2 pt-2 border-top text-center",
              a(
                href = item$url_recurso,
                target = "_blank",
                class = "btn btn-sm btn-outline-dark w-100 rounded-pill fw-bold",
                icon("book-open"), " Leer / Descargar"
              )
            )
          )
        )
      )
    })

    div(class = "row", tarjetas)
  })

  # Tabla Interactiva Alternativa (DT)
  output$tabla_acervo <- renderDT({
    df_tabla <- datos_filtrados() %>%
      mutate(
        Enlace = paste0("<a href='", url_recurso, "' target='_blank' class='btn btn-sm btn-dark rounded-pill'><i class='fa-solid fa-download'></i> Leer</a>")
      ) %>%
      select(`Colección` = coleccion, `Título` = titulo, `Eje Temático` = eje_tematico, `Tipo` = tipo_recurso, `Acción` = Enlace)

    datatable(
      df_tabla, escape = FALSE, selection = "none",
      options = list(pageLength = 10, language = list(url = "//cdn.datatables.net/plug-ins/1.10.11/i18n/Spanish.json"))
    )
  })

  # Gráficos de Análisis (Plotly)
  output$grafico_ejes <- renderPlotly({
    df_chart <- datos_filtrados() %>% count(eje_tematico)
    plot_ly(df_chart, x = ~n, y = ~reorder(eje_tematico, n), type = "bar", orientation = "h", marker = list(color = "#1D3557"))
  })

  output$grafico_colecciones <- renderPlotly({
    df_chart <- datos_filtrados() %>% count(coleccion)
    plot_ly(df_chart, labels = ~coleccion, values = ~n, type = "pie")
  })
}

# ------------------------------------------------------------------------------
# 4. EJECUCIÓN DE LA APLICACIÓN
# ------------------------------------------------------------------------------
shinyApp(ui = ui, server = server)
