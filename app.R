# ==============================================================================
# APLICACIÓN: app.R
# PROYECTO: Buscador y Catálogo Digital del Acervo Editorial del INE
# TECNOLOGÍAS: R Shiny + bslib (Bootstrap 5) + DT + DuckDB + Plotly
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
# FUNCIÓN AUXILIAR DE SANITIZACIÓN DE TEXTO
# ------------------------------------------------------------------------------
limpiar_cadena_corrupta <- function(txt) {
  if (is.null(txt) || is.na(txt)) return("")
  res <- as.character(txt)
  res <- gsub("[\\v\\r\\n\\t\\f\\p{C}]", " ", res, perl = TRUE)
  res <- gsub("(?i)\\s*ert\\{\\}\\s*", " ", res, perl = TRUE)
  return(trimws(gsub("\\s+", " ", res)))
}

# ------------------------------------------------------------------------------
# 1. CARGA DE DATOS DESDE DUCKDB Y LIMPIEZA INICIAL
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

# Normalizaciones defensivas de columnas
if (!"url_recurso" %in% colnames(datos_acervo)) {
  if ("url_descarga" %in% colnames(datos_acervo)) {
    datos_acervo$url_recurso <- datos_acervo$url_descarga
  } else if ("url" %in% colnames(datos_acervo)) {
    datos_acervo$url_recurso <- datos_acervo$url
  } else {
    datos_acervo$url_recurso <- "#"
  }
}

if (!"tipo_recurso" %in% colnames(datos_acervo)) {
  if ("formato" %in% colnames(datos_acervo)) {
    datos_acervo$tipo_recurso <- datos_acervo$formato
  } else {
    datos_acervo$tipo_recurso <- "PDF"
  }
}

# Aplicar sanitización a la base de datos cargada
cols_char <- names(datos_acervo)[sapply(datos_acervo, is.character)]
for (col in cols_char) {
  datos_acervo[[col]] <- sapply(datos_acervo[[col]], limpiar_cadena_corrupta, USE.NAMES = FALSE)
}

# Filtrar ficha genérica de la sección
datos_acervo <- datos_acervo %>%
  filter(!str_detect(str_to_lower(coalesce(url_recurso, "")), "cuadernos-divulgacion-manuales-guias/?$"))

if (!"id_obra" %in% colnames(datos_acervo)) {
  datos_acervo$id_obra <- seq_len(nrow(datos_acervo))
}

if (!"ruta_portada" %in% colnames(datos_acervo)) {
  datos_acervo$ruta_portada <- paste0("portadas/portada_", datos_acervo$id_obra, ".jpg")
}

opciones_coleccion <- c("Todas", sort(unique(na.omit(datos_acervo$coleccion[datos_acervo$coleccion != ""]))))
opciones_eje       <- c("Todos", sort(unique(na.omit(datos_acervo$eje_tematico[datos_acervo$eje_tematico != ""]))))
opciones_tipo      <- c("Todos", sort(unique(na.omit(datos_acervo$tipo_recurso[datos_acervo$tipo_recurso != ""]))))

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

      uiOutput("contenedor_vista_dinamica")
    )
  ),

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

  nav_panel(
    title = "Acerca del Proyecto",
    icon = icon("circle-info"),
    card(
      card_header("Caso de Estudio: Optimización del Acervo Editorial del INE"),
      p("Propuesta de catalogación del sello editorial del INE para mejorar la experiencia de usuario en la exploración de las publicaciones."),
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

  observeEvent(input$btn_limpiar, {
    updateTextInput(session, "txt_busqueda", value = "")
    updateSelectInput(session, "sel_coleccion", selected = "Todas")
    updateSelectInput(session, "sel_eje", selected = "Todos")
    updateCheckboxGroupInput(session, "chk_tipo", selected = setdiff(opciones_tipo, "Todos"))
  })

  output$val_total_recursos <- renderText({ nrow(datos_filtrados()) })
  output$val_total_colecciones <- renderText({ n_distinct(datos_filtrados()$coleccion) })
  output$val_total_formatos <- renderText({ n_distinct(datos_filtrados()$tipo_recurso) })

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

      # Sanitización al vuelo para evitar remanentes de ert{} o caracteres invisibles
      coleccion_limpia <- limpiar_cadena_corrupta(item$coleccion)
      eje_limpio       <- limpiar_cadena_corrupta(item$eje_tematico)
      titulo_limpio    <- limpiar_cadena_corrupta(item$titulo)

      badge_color <- if(str_detect(eje_limpio, "Paridad")) "bg-danger" else "bg-dark"

      kw_raw <- coalesce(item$palabras_clave, "INE, Cultura Democrática")
      tags_kw <- unlist(strsplit(kw_raw, ",\\s*"))

      sinopsis_txt <- ifelse(
        !is.na(item$sinopsis_real) & nchar(str_squish(item$sinopsis_real)) > 15 & !str_detect(item$sinopsis_real, "Publicado el:"),
        limpiar_cadena_corrupta(item$sinopsis_real),
        "Sinopsis no disponible para esta obra."
      )

      img_src <- sprintf("portadas/portada_%d.jpg", item$id_obra)

      tiene_resumen_3p <- "resumen_ejecutivo_3p" %in% colnames(item) &&
        !is.na(item$resumen_ejecutivo_3p) &&
        nchar(trimws(coalesce(item$resumen_ejecutivo_3p, ""))) > 50

      btn_resumen_3p <- if (tiene_resumen_3p) {
        actionButton(
          inputId = paste0("btn_resumen_", item$id_obra),
          label = " Resumen (IA)",
          icon = icon("brain"),
          class = "btn-outline-info btn-sm w-100 rounded-pill fw-bold mb-2"
        )
      } else {
        NULL
      }

      div(
        class = "col-12 col-sm-6 col-md-4 col-lg-3 mb-4",
        div(
          class = "card h-100 shadow-sm border-0 transition-all",
          style = "border-radius: 12px; overflow: hidden; background: #ffffff;",

          div(
            class = "d-flex align-items-center justify-content-center bg-light p-2 position-relative border-bottom",
            style = "height: 220px; overflow: hidden; background-color: #f8f9fa;",
            span(class = paste("badge position-absolute top-0 start-0 m-2 shadow-sm z-1", badge_color), item$tipo_recurso),
            tags$img(
              src = img_src,
              style = "max-height: 100%; max-width: 100%; object-fit: contain; border-radius: 4px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);",
              alt = titulo_limpio,
              onerror = "this.onerror=null; this.src='portadas/portada_generica.jpg';"
            )
          ),

          div(
            class = "card-body d-flex flex-column justify-content-between p-3",
            div(
              h6(class = "card-title fw-bold text-truncate-2 mb-1", style = "font-size: 0.88rem; line-height: 1.2;", titulo_limpio),
              p(class = "text-muted small mb-1 text-truncate", icon("bookmark"), " ", coleccion_limpia),
              p(class = "badge bg-light text-dark border mb-2", eje_limpio),

              div(
                class = "card-text small text-secondary mb-2",
                style = "font-size: 0.88rem; line-height: 1.35; color: #4a5568;",
                p(strong("Sinopsis: "), str_trunc(sinopsis_txt, 250))
              ),

              div(
                class = "mb-2",
                lapply(tags_kw, function(tag) {
                  span(class = "badge bg-secondary opacity-75 me-1 mb-1", style = "font-size: 0.65rem;", paste0("#", tag))
                })
              )
            ),

            div(
              class = "mt-2 pt-2 border-top text-center",
              btn_resumen_3p,
              a(
                href = item$url_recurso,
                target = "_blank",
                rel = "noopener noreferrer",
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

  # MODAL CON FORMATO DE PÁRRAFOS Y SALTO DE LÍNEA TRAS EL ENCABEZADO
  observe({
    df <- datos_filtrados()
    if (is.null(df) || nrow(df) == 0 || !"resumen_ejecutivo_3p" %in% colnames(df)) return()

    lapply(seq_len(nrow(df)), function(i) {
      item <- df[i, ]
      btn_id <- paste0("btn_resumen_", item$id_obra)

      observeEvent(input[[btn_id]], {
        resumen_raw <- coalesce(item$resumen_ejecutivo_3p, "Resumen no disponible.")

        # Limpieza de prefijos OBRA y ert{}
        resumen_limpio <- str_replace(resumen_raw, "(?i)^\\s*OBRA:\\s*.*?(\r?\n)+", "")
        resumen_limpio <- limpiar_cadena_corrupta(resumen_limpio)

        # Asegurar salto de línea tras el encabezado 'RESUMEN EJECUTIVO'
        resumen_limpio <- str_replace(resumen_limpio, "(?i)^RESUMEN EJECUTIVO\\s*", "RESUMEN EJECUTIVO\n\n")

        showModal(modalDialog(
          title = tagList(icon("brain"), " Resumen Ejecutivo (elaborado por IA)"),
          size = "l",
          easyClose = TRUE,
          footer = modalButton("Cerrar"),

          tags$div(
            style = "max-height: 70vh; overflow-y: auto; padding: 15px; background: #fafafa; border-radius: 8px;",
            tags$h5(limpiar_cadena_corrupta(item$titulo), style = "color: #1D3557; font-weight: 700; margin-bottom: 5px;"),
            tags$p(class = "text-muted small mb-3", paste("Colección:", limpiar_cadena_corrupta(item$coleccion), "| Eje:", limpiar_cadena_corrupta(item$eje_tematico))),
            hr(),
            tags$div(
              style = "white-space: pre-wrap; font-size: 0.95rem; line-height: 1.6; color: #334155;",
              resumen_limpio
            )
          )
        ))
      }, ignoreInit = TRUE)
    })
  })

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
