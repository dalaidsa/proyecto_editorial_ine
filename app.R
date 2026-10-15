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

# 1. Mapeo estático con la ruta física absoluta de la carpeta de portadas
dir_portadas_abs <- file.path(getwd(), "www", "portadas")
if (!dir.exists(dir_portadas_abs)) {
  dir.create(dir_portadas_abs, recursive = TRUE)
}
addResourcePath(prefix = "portadas", directoryPath = dir_portadas_abs)

# ------------------------------------------------------------------------------
# FUNCIONES AUXILIARES DE SANITIZACIÓN Y FORMATEO
# ------------------------------------------------------------------------------
limpiar_cadena_corrupta <- function(txt) {
  if (is.null(txt) || is.na(txt)) return("")
  res <- as.character(txt)
  res <- gsub("[\\v\\r\\n\\t\\f\\p{C}]", " ", res, perl = TRUE)
  res <- gsub("(?i)\\s*ert\\{\\}\\s*", " ", res, perl = TRUE)
  return(trimws(gsub("\\s+", " ", res)))
}

asegurar_url_absoluta <- function(u) {
  if (is.null(u) || is.na(u) || !nzchar(trimws(u)) || u == "#") {
    return("https://www.ine.mx/cuadernos-divulgacion-conferencias-magistrales/")
  }
  u <- trimws(u)
  if (!str_detect(u, "(?i)^https?://")) {
    if (str_starts(u, "(?i)www\\.")) {
      u <- paste0("https://", u)
    } else if (str_starts(u, "/")) {
      u <- paste0("https://www.ine.mx", u)
    } else {
      u <- paste0("https://", u)
    }
  }
  return(u)
}

formatear_markdown_resumen <- function(txt) {
  if (is.null(txt) || is.na(txt) || nchar(trimws(txt)) == 0) return("Resumen no disponible.")

  res <- as.character(txt)
  res <- gsub("(?i)ert\\{\\}", "", res, perl = TRUE)
  res <- gsub("(?i)^\\s*OBRA:\\s*.*?(\r?\n)+", "", res, perl = TRUE)
  res <- gsub("\\*\\*", "", res)
  res <- gsub("__", "", res)
  res <- gsub("(?i)<\\/?(b|strong)[^>]*>", "", res, perl = TRUE)
  res <- gsub("\r\n", "\n", res)

  patron_secciones <- "(?i)(?<=\\s|\\.|^|:)\\s*(#+\\s*)?(I|II|III|IV|V|VI)[\\.\\:-]\\s*"
  res <- gsub(patron_secciones, "\n\n### \\2. ", res, perl = TRUE)

  res <- gsub("(?i)^\\s*(#+\\s*)?RESUMEN EJECUTIVO\\s*", "### RESUMEN EJECUTIVO\n\n", res, perl = TRUE)
  if (!str_detect(res, "(?i)^###\\s*RESUMEN EJECUTIVO")) {
    res <- paste0("### RESUMEN EJECUTIVO\n\n", res)
  }

  res <- gsub("(?<!\n)\n(?!\n)", "\n\n", res, perl = TRUE)
  res <- gsub("\n{3,}", "\n\n", res)
  return(trimws(res))
}

formatear_indice_vista <- function(txt) {
  if (is.null(txt) || is.na(txt) || nchar(trimws(txt)) < 5) {
    return("Índice temático no disponible para esta obra.")
  }

  res <- as.character(txt)
  res <- gsub("(?i)^\\s*(#+\\s*)?(ÍNDICE GENERAL|INDICE GENERAL|CONTENIDO|TABLA DE CONTENIDOS)\\s*[\r\n]*", "", res, perl = TRUE)
  res <- gsub("(?i)\n\\s*(#+\\s*)?(ÍNDICE GENERAL|INDICE GENERAL|CONTENIDO|TABLA DE CONTENIDOS)\\s*[\r\n]*", "\n", res, perl = TRUE)

  lineas <- unlist(strsplit(res, "\n"))
  lineas <- trimws(lineas)
  lineas <- lineas[nzchar(lineas)]

  lineas_procesadas <- sapply(lineas, function(l) {
    l <- gsub("^[*\\-\\•\\>\\#]+\\s*", "", l)
    l <- gsub("\\*\\*", "", l)

    if (str_detect(l, "\\d+$")) {
      l <- gsub("\\s*\\.{2,}\\s*(\\d+)$", " ... \\1 ...", l, perl = TRUE)
      l <- gsub("(?<=[^\\.\\s])\\s+(\\d+)$", " ... \\1 ...", l, perl = TRUE)
    } else if (str_detect(l, "\\d+\\s*\\.{0,2}$")) {
      l <- gsub("(\\d+)\\s*\\.{0,2}$", "\\1 ...", l, perl = TRUE)
    }

    return(l)
  }, USE.NAMES = FALSE)

  return(paste(lineas_procesadas, collapse = "\n"))
}

# ------------------------------------------------------------------------------
# 1. CARGA DE DATOS DESDE DUCKDB
# ------------------------------------------------------------------------------
conectar_db <- function() {
  con <- dbConnect(duckdb::duckdb(), dbdir = file.path(getwd(), "data", "acervo_ine.duckdb"), read_only = TRUE)
  return(con)
}

con <- conectar_db()
if ("acervo_enriquecido" %in% dbListTables(con)) {
  datos_acervo <- dbReadTable(con, "acervo_enriquecido")
} else {
  datos_acervo <- dbReadTable(con, "acervo_editorial")
}
dbDisconnect(con, shutdown = TRUE)

if (!"id_obra" %in% colnames(datos_acervo)) {
  datos_acervo$id_obra <- seq_len(nrow(datos_acervo))
}

# Asignación estricta de la ruta individual por id_obra
datos_acervo$ruta_portada <- sprintf("portadas/portada_%d.jpg", datos_acervo$id_obra)

opciones_coleccion <- c("Todas", sort(unique(na.omit(datos_acervo$coleccion[datos_acervo$coleccion != ""]))))
opciones_eje        <- c("Todos", sort(unique(na.omit(datos_acervo$eje_tematico[datos_acervo$eje_tematico != ""]))))
opciones_tipo       <- c("Todos", sort(unique(na.omit(datos_acervo$tipo_recurso[datos_acervo$tipo_recurso != ""]))))

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

  header = tags$head(
    tags$style(HTML("
      .resumen-markdown-body,
      .resumen-markdown-body * {
        font-family: 'Arial', sans-serif !important;
        font-size: 1.02rem !important;
        line-height: 1.85 !important;
        color: #2c3e50 !important;
        font-weight: 400 !important;
      }

      .resumen-markdown-body h3,
      .resumen-markdown-body h3 * {
        font-family: 'Arial', sans-serif !important;
        color: #1D3557 !important;
        font-weight: 700 !important;
        font-size: 1.25rem !important;
        margin-top: 2rem !important;
        margin-bottom: 1rem !important;
        border-bottom: 2px solid #e2e8f0 !important;
        padding-bottom: 0.4rem !important;
        display: block !important;
      }

      .resumen-markdown-body p {
        margin-bottom: 1.4rem !important;
        text-align: justify !important;
        display: block !important;
      }

      .indice-body,
      .indice-body * {
        font-family: 'Arial', sans-serif !important;
        font-size: 0.95rem !important;
        line-height: 1.5 !important;
        color: #1e293b !important;
        font-style: italic !important;
      }
    "))
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
          placeholder = "Ej. No. 1, Bobbio, paridad, voto..."
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
    title = "Cuentacuentos y Talleres",
    icon = icon("masks-theater"),
    div(
      class = "container-fluid py-3",
      div(
        class = "p-4 mb-4 rounded-3 border shadow-sm text-center",
        style = "background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);",
        h3(class = "fw-bold", style = "color: #1D3557;", "🎬 Cuentacuentos y Talleres del INE"),
        p(class = "text-muted mb-0", "Colección audiovisual completa con cuentacuentos, relatos y talleres recreativos.")
      ),
      uiOutput("galeria_cuentacuentos")
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
        tags$li(strong("Costo de Infraestructura:"), " Creado con software de código abierto (open source) | Licencia Pública General de GNU (GPL)")
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

    limite <- min(nrow(df), 60)

    tarjetas <- lapply(seq_len(limite), function(i_idx) {
      item <- df[i_idx, ]

      coleccion_limpia <- limpiar_cadena_corrupta(item$coleccion)
      eje_limpio        <- limpiar_cadena_corrupta(item$eje_tematico)
      titulo_limpio    <- limpiar_cadena_corrupta(item$titulo)

      url_recurso_final <- asegurar_url_absoluta(item$url_recurso)

      es_video <- str_detect(str_to_lower(coalesce(item$tipo_recurso, "")), "video|audiovisual") ||
        str_detect(str_to_lower(coalesce(url_recurso_final, "")), "youtube|vimeo")

      lbl_formato <- if (es_video) "Video / Material Audiovisual" else coalesce(item$tipo_recurso, "Libro PDF")
      badge_color <- if (es_video) "bg-danger" else "bg-dark"
      icon_btn    <- if (es_video) "video" else "book-open"
      lbl_btn     <- if (es_video) " Ver Video" else " Leer / Descargar"

      kw_raw  <- coalesce(item$palabras_clave, "Cultura Democrática")
      tags_kw <- unlist(strsplit(kw_raw, ",\\s*"))

      sinopsis_txt <- ifelse(
        !is.na(item$sinopsis_real) & nchar(str_squish(item$sinopsis_real)) > 15 & !str_detect(item$sinopsis_real, "Publicado el:"),
        limpiar_cadena_corrupta(item$sinopsis_real),
        "Sinopsis no disponible para esta obra."
      )

      # RUTA DIRECTA Y OBLIGATORIA A LA PORTADA 1:1 DE CADA OBRA CON PARÁMETRO CACHE-BUSTER
      img_src <- sprintf("portadas/portada_%d.jpg?v=%d", item$id_obra, item$id_obra)

      tiene_resumen_3p <- "resumen_ejecutivo_3p" %in% colnames(item) &&
        !is.na(item$resumen_ejecutivo_3p) &&
        nchar(trimws(coalesce(item$resumen_ejecutivo_3p, ""))) > 50

      btn_resumen_3p <- if (tiene_resumen_3p && !es_video) {
        actionButton(
          inputId = paste0("btn_resumen_", item$id_obra),
          label = " Resumen e Índice (IA)",
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
            span(class = paste("badge position-absolute top-0 start-0 m-2 shadow-sm z-1", badge_color), lbl_formato),
            tags$img(
              src = img_src,
              style = "max-height: 100%; max-width: 100%; object-fit: contain; border-radius: 4px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);",
              alt = titulo_limpio
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
                href = url_recurso_final,
                target = "_blank",
                rel = "noopener noreferrer",
                class = "btn btn-sm btn-outline-dark w-100 rounded-pill fw-bold",
                icon(icon_btn), lbl_btn
              )
            )
          )
        )
      )
    })

    div(class = "row", tarjetas)
  })

  # Renderizado de Galería Cuentacuentos
  output$galeria_cuentacuentos <- renderUI({
    videos_completos <- tibble::tribble(
      ~titulo, ~categoria, ~url_recurso, ~yt_id, ~descripcion,
      "Escuchar a las niñas y los niños en tiempos de coronavirus con Pepe Gordon", "Cápsula de Divulgación", "https://www.youtube.com/watch?v=Iss-NKA6X9g", "Iss-NKA6X9g", "Cápsula explicativa sobre la voz de las infancias y la convivencia en el hogar.",
      "¡¿Otro traje nuevo para el emperador?! con Nacho Casas", "Cuentacuentos", "https://www.youtube.com/watch?v=h2_efXIIrQo", "h2_efXIIrQo", "Narración oral dramatizada del cuento de la Colección Árbol.",
      "¡Hazlo en casa! Taller de ilustración con Juan Gedovius", "Taller", "https://www.youtube.com/watch?v=KCrkliD8q_U", "KCrkliD8q_U", "Taller práctico de dibujo e ilustración guiado por Juan Gedovius.",
      "Axolotzilla contrataca, yo mejor me quedo en casa con Yucatán A go-go", "Concierto", "https://www.youtube.com/watch?v=q1CbzSXIz_o", "q1CbzSXIz_o", "Presentación musical infantil para promover valores comunitarios y salud.",
      "¡Hazlo en casa! Tarjeta mágica con Juan Carlos Lagarde", "Taller", "https://www.youtube.com/watch?v=P000YPhfaoI", "P000YPhfaoI", "Taller de manualidades y creación de tarjetas dinámicas.",
      "La prohibición de las lombrices con Marcela Romero", "Cuentacuentos", "https://www.youtube.com/watch?v=sgLl6kfj9hs", "sgLl6kfj9hs", "Lectura del cuento sobre la democracia, reglas y convivencia de la Colección Árbol.",
      "¡Hazlo en casa! Taller de ilustración con Julián Cícero", "Taller", "https://www.youtube.com/watch?v=M4Hwa7cXAUg", "M4Hwa7cXAUg", "Taller de creación de personajes y expresión gráfica.",
      "Columpio con alas con Xareny", "Cuentacuentos con títeres", "https://www.youtube.com/watch?v=WBQvDx0Wrik", "WBQvDx0Wrik", "Representación con títeres del cuento de la Colección Árbol.",
      "¡Hazlo en casa! Taller de cómic con Ricardo Peláez", "Taller", "https://www.youtube.com/watch?v=oTLm_GkWo_A", "oTLm_GkWo_A", "Aprende a estructurar una historieta y cómic cívico.",
      "El universo robado con Marcela Romero", "Cuentacuentos", "https://www.youtube.com/watch?v=FSIY3YP-fCE", "FSIY3YP-fCE", "Cuentacuentos interactivo de la Colección Árbol.",
      "¡Hazlo en casa! Taller de sellos", "Taller", "https://www.youtube.com/watch?v=_IGnu0yxBMw", "_IGnu0yxBMw", "Taller de grabado y sellos caseros para la expresión artística.",
      "Tétrico S.A. con Lalo España", "Narración", "https://www.youtube.com/watch?v=E8xynL4U5aI", "E8xynL4U5aI", "Narración especial de la obra Tétrico S.A. por Lalo España.",
      "La recolectora de votos y Una profesora en Kenya con Tiaré Scanda", "Narración", "https://www.youtube.com/watch?v=mc4gSg2Bsro", "mc4gSg2Bsro", "Narración dramatizada sobre participación y liderazgo femenino.",
      "Inventa juegos y juguetes con Juan Carlos Lagarde", "Narración / Taller", "https://www.youtube.com/watch?v=Qn1rNnRfSFE", "Qn1rNnRfSFE", "Taller creativo para inventar juegos de mesa e historias.",
      "¡Hazlo en casa! Taller con Luis Felipe Rodríguez", "Taller", "https://www.youtube.com/watch?v=pKPVmOsodYw", "pKPVmOsodYw", "Taller de expresión y dinámica familiar.",
      "Taller de collage con Julián Cícero", "Taller de verano", "https://www.youtube.com/watch?v=J9eONqZOG5s", "J9eONqZOG5s", "Taller de artes plásticas y collage.",
      "Aprende 10 palabras en Lengua de Señas Mexicana", "Taller de verano", "https://www.youtube.com/watch?v=MZOUTIjz4ac", "MZOUTIjz4ac", "Cápsula de inclusión para aprender LSM básica.",
      "La madre agua con Ely Guerra", "Narración", "https://www.youtube.com/watch?v=XJ-hledWXk4", "XJ-hledWXk4", "Narración oral de la obra La Madre Agua por la cantante Ely Guerra.",
      "Taller de danza con Ale Marrón", "Taller de verano", "https://www.youtube.com/watch?v=17xEddmNAAc", "17xEddmNAAc", "Taller de movimiento corporal y danza cívica.",
      "Escritura Creativa con Georgina Rábago", "Taller de verano", "https://www.youtube.com/watch?v=q65TAEpeK-w", "q65TAEpeK-w", "Taller para crear cuentos y relatos breves.",
      "Fábulas Mayas", "Narración", "https://www.youtube.com/watch?v=-CN8_zUeGgE", "-CN8_zUeGgE", "Narración de fábulas de la tradición maya.",
      "Cómo alimentarte saludablemente en casa", "Taller de verano", "https://www.youtube.com/watch?v=kQ0tc4raF98", "kQ0tc4raF98", "Taller de hábitos saludables y nutrición.",
      "Dr. Misterio resuelve tus dudas sobre el Covid", "Taller de verano", "https://www.youtube.com/watch?v=NTKg5xeXWg8", "NTKg5xeXWg8", "Cápsula cómica-divulgativa sobre el cuidado de la salud.",
      "Danza Cuatro amigos", "Taller de verano", "https://www.youtube.com/watch?v=-xnwbgjr3G0", "-xnwbgjr3G0", "Interpretación dancística inspirada en el cuento Cuatro Amigos.",
      "Cuatro amigos (Lectura en maya) con Hilario Chi Canul", "Narración en Lengua Indígena", "https://www.youtube.com/watch?v=D5mCT6I0Ioc", "D5mCT6I0Ioc", "Lectura del cuento traducido y narrado en maya.",
      "Un río para todos (Lectura en seri) con Sócrates Rodríguez", "Narración en Lengua Indígena", "https://www.youtube.com/watch?v=XRkPPGoCahI", "XRkPPGoCahI", "Lectura del cuento traducido y narrado en seri.",
      "Columpio con alas (Taller en náhuatl) con Edgar Mesa", "Taller en Lengua Indígena", "https://www.youtube.com/watch?v=HMSDk6bO4jo", "HMSDk6bO4jo", "Taller y lectura en lengua náhuatl.",
      "Fábulas mágicas de las tierras mayas con Amaranta Gómez", "Narración", "https://www.youtube.com/watch?v=dB0LOiz5-ts", "dB0LOiz5-ts", "Narración oral de las fábulas mágicas mayas.",
      "¿Dónde dormí anoche? con Ely Guerra", "Narración", "https://www.youtube.com/watch?v=OVaRR5tbmRQ", "OVaRR5tbmRQ", "Narración oral por la artista Ely Guerra.",
      "Un río para todos", "Cuentacuentos", "https://www.youtube.com/watch?v=IIX7c7pgCGA", "IIX7c7pgCGA", "Cuentacuentos completo del libro Un río para todos.",
      "Fábula tlaxcalteca 'El coyote y la serpiente'", "Cuentacuentos", "https://www.youtube.com/watch?v=z-ZRaXGy4fo", "z-ZRaXGy4fo", "Cuentacuentos tradicional sobre la justicia y el respeto.",
      "Cuatro amigos y Un río para todos", "Cuentacuentos", "https://www.youtube.com/watch?v=mtrwlhKjdj0", "mtrwlhKjdj0", "Cuentacuentos doble de las obras de la Colección Árbol.",
      "El Universo robado. ¡Hazlo en casa!", "Taller de minilibro", "https://www.youtube.com/watch?v=xeqwh0NmRu4", "xeqwh0NmRu4", "Taller paso a paso para confeccionar tu propio minilibro.",
      "Ba'alche'ob. Fábulas mágicas de las tierras mayas", "Cuentacuentos", "https://www.youtube.com/watch?v=3UjPK8a9jf8", "3UjPK8a9jf8", "Narración de Ba'alche'ob."
    )

    tarjetas_yt <- lapply(seq_len(nrow(videos_completos)), function(i) {
      v <- videos_completos[i, ]
      div(
        class = "col-12 col-md-6 col-lg-4 mb-4",
        div(
          class = "card h-100 shadow-sm border-0", style = "border-radius: 12px; overflow: hidden;",
          div(class = "ratio ratio-16x9 bg-dark", tags$iframe(src = paste0("https://www.youtube.com/embed/", v$yt_id), allowfullscreen = TRUE)),
          div(
            class = "card-body d-flex flex-column justify-content-between p-3",
            div(
              span(class = "badge bg-danger mb-2", v$categoria),
              h6(class = "card-title fw-bold mb-2", v$titulo),
              p(class = "card-text small text-secondary mb-3", v$descripcion)
            ),
            a(href = v$url_recurso, target = "_blank", rel = "noopener noreferrer", class = "btn btn-sm btn-outline-danger w-100 rounded-pill fw-bold", icon("youtube"), " Ver en YouTube")
          )
        )
      )
    })
    div(class = "row", tarjetas_yt)
  })

  # ============================================================================
  # MODAL CON PESTAÑAS (RESUMEN EJECUTIVO E ÍNDICE)
  # ============================================================================
  observe({
    df <- datos_filtrados()
    if (is.null(df) || nrow(df) == 0 || !"resumen_ejecutivo_3p" %in% colnames(df)) return()

    lapply(seq_len(nrow(df)), function(i) {
      item <- df[i, ]
      btn_id <- paste0("btn_resumen_", item$id_obra)

      local({
        item_local <- item
        observeEvent(input[[btn_id]], {
          resumen_raw <- coalesce(item_local$resumen_ejecutivo_3p, "Resumen no disponible.")
          resumen_markdown <- formatear_markdown_resumen(resumen_raw)

          titulo_obra_limpio <- limpiar_cadena_corrupta(item_local$titulo)
          indice_raw <- if ("indice_tematico" %in% colnames(item_local) && !is.na(item_local$indice_tematico)) {
            item_local$indice_tematico
          } else {
            ""
          }

          indice_formatted <- formatear_indice_vista(indice_raw)

          showModal(modalDialog(
            title = tagList(icon("book-open"), " Análisis Detallado de la Obra"),
            size = "l",
            easyClose = TRUE,
            footer = modalButton("Cerrar"),

            tags$div(
              class = "mb-3 pb-2 border-bottom",
              tags$h5(titulo_obra_limpio, style = "color: #1D3557; font-weight: 700; margin-bottom: 4px;"),
              tags$p(class = "text-muted small mb-0", paste("Colección:", limpiar_cadena_corrupta(item_local$coleccion), "\vert{} Eje:", limpiar_cadena_corrupta(item_local$eje_tematico)))
            ),

            navset_tab(
              nav_panel(
                title = "Resumen Ejecutivo (IA)",
                icon = icon("brain"),
                tags$div(
                  class = "resumen-markdown-body",
                  style = "max-height: 58vh; overflow-y: auto; padding: 22px; background: #fafafa; border-radius: 8px; border: 1px solid #e2e8f0; margin-top: 10px;",
                  shiny::markdown(resumen_markdown)
                )
              ),
              nav_panel(
                title = "Índice",
                icon = icon("list-check"),
                tags$div(
                  class = "indice-body",
                  style = "max-height: 58vh; overflow-y: auto; padding: 22px; background: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; margin-top: 10px;",
                  tags$div(
                    style = "white-space: pre-wrap; font-size: 0.95rem; line-height: 1.5; color: #1e293b;",
                    shiny::markdown(indice_formatted)
                  )
                )
              )
            )
          ))
        }, ignoreInit = TRUE)
      })
    })
  })

  output$tabla_acervo <- renderDT({
    df_tabla <- datos_filtrados() %>%
      mutate(
        url_limpia = sapply(url_recurso, asegurar_url_absoluta, USE.NAMES = FALSE),
        Enlace = paste0("<a href='", url_limpia, "' target='_blank' rel='noopener noreferrer' class='btn btn-sm btn-dark rounded-pill'><i class='fa-solid fa-download'></i> Acceder</a>")
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
