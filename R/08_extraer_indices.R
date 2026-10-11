# ==============================================================================
# SCRIPT: R/08_corregir_indices_reales.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Extraer y reescribir el ÍNDICE LITERAL impreso en las páginas
#           preliminares de las 203 obras desde sus archivos/URLs de origen.
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)
library(httr)
library(jsonlite)
library(rvest)
library(pdftools)

message("=================================================================")
message(" CORRECCIÓN Y EXTRACCIÓN LITERAL DE ÍNDICES REALES EN DUCKDB ")
message("=================================================================\n")

ruta_db <- "data/acervo_ine.duckdb"
con <- dbConnect(duckdb::duckdb(), dbdir = ruta_db)
df <- dbReadTable(con, "acervo_enriquecido")
total_obras <- nrow(df)

api_key <- Sys.getenv("GEMINI_API_KEY")

# 1. Validar modelo de conexión Gemini
determinar_modelo <- function(key) {
  if (is.null(key) || nchar(key) < 10) return(NULL)
  modelos <- c("gemini-3.6-flash", "gemini-2.5-pro")
  for (mod in modelos) {
    url_test <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", mod, key)
    payload <- list(contents = list(list(parts = list(list(text = "Test")))))
    res <- tryCatch({
      POST(url_test, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(8))
    }, error = function(e) NULL)
    if (!is.null(res) && status_code(res) == 200) return(mod)
  }
  return(NULL)
}

modelo_activo <- determinar_modelo(api_key)
if (is.null(modelo_activo)) {
  dbDisconnect(con, shutdown = TRUE)
  stop("[!] No se pudo validar la API Key con los modelos activos.")
}

# 2. Función robusta para descargar y extraer preliminares del PDF
extraer_texto_preliminar_pdf <- function(url_recurso, ruta_local = NULL) {
  # A) Buscar primero en archivo local
  if (!is.null(ruta_local) && file.exists(ruta_local)) {
    txt <- tryCatch({
      paginas <- pdf_info(ruta_local)$pages
      pdf_text(ruta_local)[1:min(12, paginas)]
    }, error = function(e) NULL)
    if (!is.null(txt)) return(paste(txt, collapse = "\n--- PÁGINA ---\n"))
  }

  # B) Si no hay archivo local, resolver e intentar descarga remota
  if (!is.null(url_recurso) && nchar(trimws(url_recurso)) > 10 && url_recurso != "#") {
    url_pdf <- url_recurso

    # Si la URL es una página HTML de aterrizaje, raspar el enlace directo al PDF
    if (!str_detect(url_pdf, "(?i)\\.pdf")) {
      html_doc <- tryCatch(read_html(url_pdf), error = function(e) NULL)
      if (!is.null(html_doc)) {
        enlaces <- html_doc %>% html_nodes("a") %>% html_attr("href")
        pdf_enlace <- enlaces[str_detect(coalesce(enlaces, ""), "(?i)\\.pdf")][1]
        if (!is.na(pdf_enlace)) {
          url_pdf <- xml2::url_absolute(pdf_enlace, url_pdf)
        }
      }
    }

    tmp <- tempfile(fileext = ".pdf")
    res_dl <- tryCatch({
      GET(
        url_pdf,
        write_disk(tmp, overwrite = TRUE),
        user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
        config(ssl_verifypeer = FALSE),
        timeout(25)
      )
    }, error = function(e) NULL)

    if (!is.null(res_dl) && status_code(res_dl) == 200 && file.exists(tmp) && file.info(tmp)$size > 5000) {
      txt <- tryCatch({
        paginas <- pdf_info(tmp)$pages
        pdf_text(tmp)[1:min(12, paginas)]
      }, error = function(e) NULL)

      unlink(tmp)
      if (!is.null(txt) && nchar(trimws(paste(txt, collapse = ""))) > 100) {
        return(paste(txt, collapse = "\n--- PÁGINA ---\n"))
      }
    } else {
      if (file.exists(tmp)) unlink(tmp)
    }
  }

  return(NULL)
}

# 3. Transcripción literal del índice mediante Gemini
extraer_indice_literal_gemini <- function(titulo, texto_paginas, modelo, key) {
  prompt_txt <- paste0(
    "ROL: Eres un transcritor y catalogador bibliográfico experto del Instituto Nacional Electoral (INE).\n\n",
    "TAREA: Extrae de forma LITERAL, EXACTA Y FIEL el Índice o Tabla de Contenido impreso en las primeras páginas de la siguiente obra:\n",
    "• Título: '", titulo, "'\n\n",
    "TEXTO EXTRAÍDO DE LAS PRIMERAS PÁGINAS DEL DOCUMENTO ORIGINAL:\n",
    "----------------------------------------------------------------\n",
    str_trunc(texto_paginas, 12000), "\n",
    "----------------------------------------------------------------\n\n",
    "REGLAS ESTRUCTURALES OBLIGATORIAS:\n",
    "1. Copia FIELMENTE los nombres exactos de capítulos, secciones, apartados y subapartados tal como aparecen impresos en el índice original.\n",
    "2. Conserva los números de página originales si están presentes en la obra.\n",
    "3. NO inventes, NO resumas, NO agregues capítulos que no estén explícitamente impresos en la obra.\n",
    "4. NO uses asteriscos de negrita (prohibido **), ni HTML.\n",
    "5. Comienza directamente con la línea 'ÍNDICE GENERAL' seguida de la estructura."
  )

  url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", modelo, key)
  payload <- list(
    contents = list(list(parts = list(list(text = prompt_txt)))),
    generationConfig = list(temperature = 0.1, maxOutputTokens = 4096)
  )

  res <- tryCatch({
    POST(url, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(45))
  }, error = function(e) NULL)

  if (!is.null(res) && status_code(res) == 200) {
    parsed <- tryCatch(content(res, "parsed"), error = function(e) NULL)
    if (!is.null(parsed) && !is.null(parsed$candidates) && length(parsed$candidates) > 0) {
      txt <- parsed$candidates[[1]]$content$parts[[1]]$text
      if (!is.null(txt) && nchar(trimws(txt)) > 50) {
        txt <- gsub("\\*\\*", "", txt)
        return(trimws(txt))
      }
    }
  }
  return(NULL)
}

# 4. Bucle principal de reextracción
obras_corregidas <- 0

for (i in seq_len(total_obras)) {
  item <- df[i, ]
  resumen_txt <- coalesce(item$resumen_ejecutivo_3p, "")

  if (nchar(trimws(resumen_txt)) > 1500) {
    message(sprintf("[%d/%d] Reextrayendo índice literal: %s", i, total_obras, str_trunc(item$titulo, 40)))

    ruta_pdf_local <- sprintf("data/pdfs/%s.pdf", item$id_obra)
    texto_preliminar <- extraer_texto_preliminar_pdf(item$url_recurso, ruta_pdf_local)

    if (!is.null(texto_preliminar) && nchar(trimws(texto_preliminar)) > 100) {
      indice_fiel <- extraer_indice_literal_gemini(item$titulo, texto_preliminar, modelo_activo, api_key)

      if (!is.null(indice_fiel)) {
        df$indice_tematico[i] <- indice_fiel
        obras_corregidas <- obras_corregidas + 1
        dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
        message("   [✓ ÍNDICE REAL GUARDADO EN DUCKDB]")
        Sys.sleep(0.3)
        next
      }
    }

    message("   [⚠️ ALERTA] No se pudo descargar/leer el PDF. Se conservará la versión sintética.")
  }
}

dbDisconnect(con, shutdown = TRUE)

message("\n=================================================================")
message(sprintf(" [✓] PROCESO REESTRUCTURADO. Índices corregidos: %d", obras_corregidas))
message("=================================================================")
