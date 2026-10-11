# ==============================================================================
# SCRIPT: R/13_resolver_tomos_170_171.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Descargar parcialmente (primeros 15 MB) los PDFs pesados (>1 GB)
#           de los Tomos I y II mediante HTTP Range Requests.
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)
library(httr)
library(jsonlite)
library(pdftools)

message("=================================================================")
message(" EXTRACCIÓN LIGERA DE ÍNDICES EN ARCHIVOS DE >1 GB (RANGE HEADERS) ")
message("=================================================================\n")

ruta_db <- "data/acervo_ine.duckdb"
con <- dbConnect(duckdb::duckdb(), dbdir = ruta_db)
df <- dbReadTable(con, "acervo_enriquecido")

api_key <- Sys.getenv("GEMINI_API_KEY")
modelo_activo <- "gemini-3.6-flash"

tomos_target <- c(170, 171)

for (id_target in tomos_target) {
  idx <- which(df$id_obra == id_target)
  item <- df[idx, ]

  message(sprintf("[%d/2] Procesando ID %d: %s", which(tomos_target == id_target), item$id_obra, item$titulo))
  message("   [🌐] Solicitando fragmento inicial (primeros 15 MB) vía HTTP Range...")

  tmp_partial <- tempfile(fileext = ".pdf")

  # Petición HTTP Range: Solicita solo los bytes del 0 al 15,728,640 (15 MB)
  res_range <- tryCatch({
    GET(
      item$url_recurso,
      write_disk(tmp_partial, overwrite = TRUE),
      add_headers(
        `Range` = "bytes=0-15728640",
        `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36"
      ),
      config(ssl_verifypeer = FALSE),
      timeout(30)
    )
  }, error = function(e) NULL)

  txt_preliminar <- NULL

  if (!is.null(res_range) && status_code(res_range) %in% c(200, 206) && file.exists(tmp_partial)) {
    message(sprintf("   [✓] Descargados %.2f MB con éxito.", file.info(tmp_partial)$size / (1024^2)))

    # Extraer texto de las páginas preliminares
    txt_preliminar <- tryCatch({
      # Extraer primeras páginas del fragmento
      t <- pdf_text(tmp_partial)
      pags_limite <- min(15, length(t))
      paste(t[1:pags_limite], collapse = "\n--- PÁGINA ---\n")
    }, error = function(e) {
      # Si el PDF requiere tabla xref del final, extraer con modo tolerante
      tryCatch({
        tmp_sub <- tempfile(fileext = ".pdf")
        pdf_subset(tmp_partial, pages = 1:min(10, pdf_info(tmp_partial)$pages), output = tmp_sub)
        t_sub <- pdf_text(tmp_sub)
        if (file.exists(tmp_sub)) unlink(tmp_sub)
        paste(t_sub, collapse = "\n--- PÁGINA ---\n")
      }, error = function(e2) NULL)
    })
  }

  if (file.exists(tmp_partial)) unlink(tmp_partial)

  if (!is.null(txt_preliminar) && nchar(trimws(txt_preliminar)) > 100) {
    message("   [🧠] Enviando texto preliminar a Gemini para transcripción de índice...")

    prompt_txt <- paste0(
      "ROL: Catalogador bibliográfico del Instituto Nacional Electoral (INE).\n\n",
      "TAREA: Extrae de forma LITERAL Y FIEL el Índice/Tabla de Contenido impreso en las primeras páginas de esta obra monumental:\n",
      "• Título: '", item$titulo, "'\n",
      "• Colección: '", item$coleccion, "'\n\n",
      "TEXTO DE LAS PRIMERAS PÁGINAS DEL DOCUMENTO:\n",
      "----------------------------------------------------------------\n",
      str_trunc(txt_preliminar, 12000), "\n",
      "----------------------------------------------------------------\n\n",
      "REGLAS ESTRUCTURALES OBLIGATORIAS:\n",
      "1. Copia exactamente los nombres de capítulos, secciones, tomos, autores o incisos impresos.\n",
      "2. Conserva los números de página si figuran en el texto.\n",
      "3. NO uses asteriscos de negrita (prohibido **), ni marcas HTML.\n",
      "4. Inicia directamente con la línea 'ÍNDICE GENERAL'."
    )

    url_api <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", modelo_activo, api_key)
    payload <- list(contents = list(list(parts = list(list(text = prompt_txt)))))

    res_gemini <- tryCatch({
      POST(url_api, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(35))
    }, error = function(e) NULL)

    if (!is.null(res_gemini) && status_code(res_gemini) == 200) {
      parsed <- content(res_gemini, "parsed")
      txt_out <- parsed$candidates[[1]]$content$parts[[1]]$text

      if (!is.null(txt_out) && nchar(trimws(txt_out)) > 50) {
        df$indice_tematico[idx] <- gsub("\\*\\*", "", txt_out)
        message(sprintf("   [✓ ÍNDICE REGISTRADO EN DUCKDB PARA ID %d]", id_target))
      }
    }
  } else {
    message(sprintf("   [!] No se pudo procesar el texto preliminar del ID %d.", id_target))
  }
}

# Guardar cambios finales en DuckDB
dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message("\n=================================================================")
message(" [✓] PROCESO COMPLETADO. Revisa la base de datos DuckDB.")
message("=================================================================")
