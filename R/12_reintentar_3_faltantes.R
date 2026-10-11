# ==============================================================================
# SCRIPT: R/12_reintentar_3_faltantes.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Reintentar la extracción literal únicamente para las 3 obras pendientes.
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)
library(httr)
library(jsonlite)
library(pdftools)

con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")

api_key <- Sys.getenv("GEMINI_API_KEY")
modelo_activo <- "gemini-3.6-flash"

# Filtrar solo las 3 faltantes
df_elegibles <- df %>% filter(nchar(coalesce(resumen_ejecutivo_3p, "")) > 1500)
ids_faltantes <- df_elegibles %>%
  filter(!str_detect(coalesce(indice_tematico, ""), "(?i)ÍNDICE GENERAL")) %>%
  pull(id_obra)

message(sprintf("[ℹ️] Reintentando la extracción para los IDs: %s", paste(ids_faltantes, collapse = ", ")))

for (id_target in ids_faltantes) {
  idx <- which(df$id_obra == id_target)
  item <- df[idx, ]

  message(sprintf("\nProcessing ID %d: %s", item$id_obra, str_trunc(item$titulo, 40)))

  # Intentar descarga con mayor margen de tiempo (35 seg)
  tmp <- tempfile(fileext = ".pdf")
  res_dl <- tryCatch({
    GET(
      item$url_recurso,
      write_disk(tmp, overwrite = TRUE),
      user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36"),
      config(ssl_verifypeer = FALSE),
      timeout(35)
    )
  }, error = function(e) NULL)

  txt_res <- NULL
  if (!is.null(res_dl) && status_code(res_dl) == 200 && file.exists(tmp) && file.info(tmp)$size > 3000) {
    txt_res <- tryCatch({
      pags <- min(15, pdf_info(tmp)$pages)
      tmp_sub <- tempfile(fileext = ".pdf")
      pdf_subset(tmp, pages = 1:pags, output = tmp_sub)
      t <- pdf_text(tmp_sub)
      if (file.exists(tmp_sub)) unlink(tmp_sub)
      paste(t, collapse = "\n--- PÁGINA ---\n")
    }, error = function(e) NULL)
  }
  if (file.exists(tmp)) unlink(tmp)

  if (!is.null(txt_res) && nchar(trimws(txt_res)) > 100) {
    # Llamada a Gemini
    prompt_txt <- paste0(
      "Extrae de forma LITERAL Y FIEL el Índice/Tabla de Contenido de estas páginas del INE:\n",
      "• Título: '", item$titulo, "'\n\n",
      str_trunc(txt_res, 12000), "\n\n",
      "REGLAS: Copia nombres exactos de capítulos e incisos. Prohibido usar **. Inicia con 'ÍNDICE GENERAL'."
    )

    url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", modelo_activo, api_key)
    payload <- list(contents = list(list(parts = list(list(text = prompt_txt)))))

    res_gemini <- tryCatch({
      POST(url, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(30))
    }, error = function(e) NULL)

    if (!is.null(res_gemini) && status_code(res_gemini) == 200) {
      parsed <- content(res_gemini, "parsed")
      txt_out <- parsed$candidates[[1]]$content$parts[[1]]$text
      if (!is.null(txt_out)) {
        df$indice_tematico[idx] <- gsub("\\*\\*", "", txt_out)
        message("   [✓ ÍNDICE CORREGIDO Y GUARDADO]")
      }
    }
  } else {
    message("   [!] No se pudo descargar el PDF automáticamente. Revisa la URL manualmente.")
  }
}

dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)
