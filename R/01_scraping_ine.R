# ==============================================================================
# SCRIPT: 01_scraping_ine.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Extracción multisección de publicaciones, colecciones y recursos del INE
# ==============================================================================

## 1. Cargar librerías necesarias
library(rvest)
library(httr)
library(dplyr)
library(stringr)
library(purrr)
library(readr)
library(duckdb)

# ==============================================================================
# CONFIGURACIÓN Y CATÁLOGO DE COLECCIONES DEL INE
# ==============================================================================
BASE_URL <- "https://www.ine.mx"

# Catálogo completo de secciones editoriales a extraer
COLECCIONES_INE <- tibble::tribble(
  ~nombre_coleccion, ~url,
  "Cuadernos de Divulgación de la Cultura Democrática", "https://ine.mx/cuadernos-divulgacion-cultura-democratica/",
  "Colección Árbol", "https://ine.mx/cuadernos-divulgacion-coleccion-arbol/",
  "Manuales y Guías Didácticas", "https://ine.mx/cuadernos-divulgacion-manuales-guias/",
  "Obras Institucionales", "https://ine.mx/cuadernos-divulgacion-obras-institucionales/",
  "Conferencias Magistrales", "https://ine.mx/cuadernos-divulgacion-conferencias-magistrales/",
  "Temas Selectos de la Democracia", "https://ine.mx/cuadernos-divulgacion-libros-temas-selectos/",
  "Estudios Electorales", "https://ine.mx/estudios-electorales/",
  "Paridad de Género y Derechos Humanos de las Mujeres", "https://ine.mx/paridad-genero-y-respeto-derechos-humanos-mujeres-ambito-politico-electoral/",
  "Cuentacuentos y Talleres", "https://ine.mx/cuentacuentos-talleres/"
)

# Banco de User-Agents para rotación antibloqueo
USER_AGENTS <- c(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15",
  "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0"
)

# ==============================================================================
# FUNCIONES AUXILIARES DE EXTRACCIÓN Y CLASIFICACIÓN
# ==============================================================================

#' Pausa aleatoria para emular comportamiento de navegación humana
pausa_humana <- function(min_s = 2.0, max_s = 4.5) {
  espera <- runif(1, min = min_s, max = max_s)
  message(sprintf("   [⏳] Pausa de seguridad: %.2f segundos...", espera))
  Sys.sleep(espera)
}

#' Clasifica la tipología del recurso según la URL y el texto descriptivo
clasificar_tipo_recurso <- function(url_recurso, texto_enlace) {
  url_lc <- tolower(url_recurso)
  texto_lc <- tolower(texto_enlace)

  if (str_detect(url_lc, "\\.pdf$") || str_detect(texto_lc, "libro|cuaderno|pdf|descargar|obra|estudio")) {
    return("Libro / Documento PDF")
  } else if (str_detect(url_lc, "youtube\\.com|vimeo\\.com|video|mp4") || str_detect(texto_lc, "video|cápsula|ver|taller|audiovisual")) {
    return("Video / Material Audiovisual")
  } else {
    return("Recurso Didáctico / Complementario")
  }
}

#' Petición HTTP con manejo de errores, reintentos y retroceso exponencial
obtener_html_robusto <- function(url, handle_sesion, max_intentos = 3) {
  intento <- 1
  espera <- 3

  while (intento <= max_intentos) {
    ua <- sample(USER_AGENTS, 1)

    res <- tryCatch({
      GET(
        url = url,
        handle = handle_sesion,
        add_headers(
          `User-Agent` = ua,
          `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          `Accept-Language` = "es-MX,es;q=0.9,en;q=0.8",
          `Referer` = BASE_URL
        ),
        timeout(20)
      )
    }, error = function(e) {
      message(sprintf("   [!] Error de conexión en intento %d: %s", intento, e$message))
      return(NULL)
    })

    if (!is.null(res) && status_code(res) == 200) {
      return(read_html(res))
    }

    message(sprintf("   [🔄] Reintentando (%d/%d) en %d segundos...", intento, max_intentos, espera))
    Sys.sleep(espera)
    espera <- espera * 2
    intento <- intento + 1
  }

  return(NULL)
}

# ==============================================================================
# BUCLE PRINCIPAL DE EXTRACCIÓN MULTI-COLECCIÓN
# ==============================================================================

extraer_todo_acervo_ine <- function(catalogo_colecciones) {
  message("=================================================================")
  message(" INICIANDO SCRAPING DEL ACERVO EDITORIAL DEL INE ")
  message(sprintf(" Total de colecciones/secciones a procesar: %d", nrow(catalogo_colecciones)))
  message("=================================================================\n")

  sesion <- handle(BASE_URL)
  todos_los_registros <- list()

  for (i in seq_len(nrow(catalogo_colecciones))) {
    nombre_col <- catalogo_colecciones$nombre_coleccion[i]
    url_col <- catalogo_colecciones$url[i]

    message(sprintf("[%d/%d] Extrayendo: '%s'...", i, nrow(catalogo_colecciones), nombre_col))
    message(sprintf("      URL: %s", url_col))

    html_doc <- obtener_html_robusto(url_col, sesion)

    if (is.null(html_doc)) {
      message(sprintf("   [!] Omisión: No se pudo obtener respuesta de '%s'\n", nombre_col))
      next
    }

    # Extraer contenedores principales de publicaciones
    elementos <- html_doc %>%
      html_elements("article, .post, .card, .elementor-widget-container, tr, .entry-content p, .vc_column-inner")

    registros_coleccion <- list()

    for (nodo in elementos) {
      enlaces <- nodo %>% html_elements("a")
      if (length(enlaces) == 0) next

      texto_nodo <- nodo %>% html_text2() %>% str_squish()

      for (enlace in enlaces) {
        href <- enlace %>% html_attr("href")
        texto_link <- enlace %>% html_text2() %>% str_squish()

        if (is.na(href) || href == "" || str_starts(href, "#") || str_starts(href, "javascript")) next

        # Normalización de URL relativa a absoluta
        if (!str_starts(href, "http")) {
          href <- paste0(BASE_URL, href)
        }

        # Filtro de relevancia de contenidos
        es_pdf <- str_detect(tolower(href), "\\.pdf$")
        es_video <- str_detect(tolower(href), "youtube|vimeo|video")
        es_recurso <- str_detect(tolower(texto_link), "recurso|guía|fichas|descarga|ver|leer|consultar|descargar")

        if (es_pdf || es_video || es_recurso) {

          # Extraer identificador o número si existe
          num_ejemplar <- str_extract(texto_nodo, "(?i)(cuaderno|número|no\\.|volumen|vol\\.)\\s*\\d+")
          num_ejemplar <- ifelse(is.na(num_ejemplar), "N/A", num_ejemplar)

          # Extraer año de publicación
          anio <- str_extract(texto_nodo, "\\b(19|20)\\d{2}\\b") %>% as.integer()

          # Título del recurso
          titulo <- ifelse(nchar(texto_link) > 5, texto_link, str_trunc(texto_nodo, 90))

          tipo_cat <- clasificar_tipo_recurso(href, texto_link)

          registros_coleccion[[length(registros_coleccion) + 1]] <- tibble(
            coleccion = nombre_col,
            num_ejemplar = num_ejemplar,
            titulo = titulo,
            tipo_recurso = tipo_cat,
            anio = anio,
            descripcion = str_trunc(texto_nodo, 250),
            url_recurso = href,
            fecha_extraccion = Sys.Date()
          )
        }
      }
    }

    if (length(registros_coleccion) > 0) {
      df_col <- bind_rows(registros_coleccion) %>% distinct(url_recurso, .keep_all = TRUE)
      todos_los_registros[[length(todos_los_registros) + 1]] <- df_col
      message(sprintf("   [✓] Éxito: %d recursos extraídos de '%s'.", nrow(df_col), nombre_col))
    } else {
      message(sprintf("   [!] No se encontraron recursos específicos en '%s'.", nombre_col))
    }

    pausa_humana(2.0, 4.0)
  }

  if (length(todos_los_registros) == 0) return(tibble())

  df_consolidado <- bind_rows(todos_los_registros) %>%
    distinct(url_recurso, .keep_all = TRUE)

  return(df_consolidado)
}

# ==============================================================================
# EJECUCIÓN Y ALMACENAMIENTO (CSV + DUCKDB)
# ==============================================================================

# Crear la carpeta data/ en caso de que no exista
if (!dir.exists("data")) {
  dir.create("data")
}

# Ejecutar el proceso
df_acervo_ine <- extraer_todo_acervo_ine(COLECCIONES_INE)

if (nrow(df_acervo_ine) > 0) {
  message("\n=================================================================")
  message(sprintf(" PROCESO FINALIZADO: %d RECURSOS TOTALES EXTRAÍDOS ", nrow(df_acervo_ine)))
  message("=================================================================\n")

  # Resumen por tipo de recurso
  print(df_acervo_ine %>% count(coleccion, tipo_recurso))

  # 1. Guardar copia en CSV en data/
  ruta_csv <- "data/acervo_editorial_ine.csv"
  write_csv(df_acervo_ine, ruta_csv)
  message(sprintf("\n[✓] Respaldo CSV creado en: %s", ruta_csv))

  # 2. Conectar e insertar en DuckDB (data/acervo_ine.duckdb)
  ruta_db <- "data/acervo_ine.duckdb"
  con <- dbConnect(duckdb::duckdb(), dbdir = ruta_db)

  dbWriteTable(con, "acervo_editorial", df_acervo_ine, overwrite = TRUE)
  message(sprintf("[✓] Tabla 'acervo_editorial' actualizada en DuckDB (%s)", ruta_db))

  # Consulta de verificación
  message("\nMuestra de datos almacenados en DuckDB:")
  print(dbGetQuery(con, "SELECT coleccion, titulo, tipo_recurso, url_recurso FROM acervo_editorial LIMIT 5"))

  dbDisconnect(con, shutdown = TRUE)

} else {
  message("\n[!] No se extrajeron registros. Revisa tu conexión a internet o los selectores HTML.")
}
