# ==============================================================================
# SCRIPT: 04_extraer_portadas.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Extraer la primera página de cada PDF real y convertirla en portada JPG
#           sincronizada exactamente con el id_obra de DuckDB. ==============================================================================

if (!requireNamespace("pdftools", quietly = TRUE)) {
  install.packages("pdftools")
}

library(pdftools)
library(duckdb)
library(dplyr)
library(stringr)

dir_raiz <- getwd()
dir_portadas <- file.path(dir_raiz, "www", "portadas")
if (!dir.exists(dir_portadas)) {
  dir.create(dir_portadas, recursive = TRUE)
}

db_path <- file.path(dir_raiz, "data", "acervo_ine.duckdb")
con <- dbConnect(duckdb::duckdb(), dbdir = db_path)

if ("acervo_enriquecido" %in% dbListTables(con)) {
  df <- dbReadTable(con, "acervo_enriquecido")
} else {
  df <- dbReadTable(con, "acervo_editorial")
}

# Reindexar ID secuencial limpio 1 a N
df$id_obra <- seq_len(nrow(df))
df$ruta_portada <- sprintf("portadas/portada_%d.jpg", df$id_obra)

message(sprintf("[ℹ️] Procesando %d obras para extraer portadas reales desde los PDF...", nrow(df)))

for (i in seq_len(nrow(df))) {
  item <- df[i, ]
  id <- item$id_obra
  out_jpg <- file.path(dir_portadas, sprintf("portada_%d.jpg", id))

  url_pdf <- item$url_recurso
  pdf_local <- file.path(tempdir(), sprintf("temp_%d.pdf", id))

  exito_pdf <- FALSE

  # 1. Intentar descargar el PDF y extraer la Primera Página
  if (!is.null(url_pdf) && nzchar(trimws(url_pdf)) && str_detect(url_pdf, "(?i)\\.pdf$")) {
    tryCatch({
      download.file(url_pdf, pdf_local, mode = "wb", quiet = TRUE)
      if (file.exists(pdf_local) && file.info(pdf_local)$size > 1000) {
        # Extraer página 1 en formato JPG
        pdftools::pdf_convert(pdf_local, pages = 1, format = "jpeg", dpi = 150, filenames = out_jpg, verbose = FALSE)
        exito_pdf <- file.exists(out_jpg) && file.info(out_jpg)$size > 2000
      }
    }, error = function(e) {
      exito_pdf <<- FALSE
    })
  }

  # 2. Respaldo editorial individual si no se puede descargar el PDF directo
  if (!exito_pdf) {
    tit_limpio <- str_replace(coalesce(item$titulo, ""), "(?i)^Conferencia Magistral:\\s*", "")
    tit_limpio <- str_replace(tit_limpio, "(?i)\\(video\\s*/\\s*material audiovisual\\)", "") %>% str_trim()

    num_match <- str_extract(item$titulo, "(?i)No\\.\\s*\\d+")
    num_label <- ifelse(!is.na(num_match), num_match, paste0("Obra #", id))

    es_conf  <- str_detect(tolower(coalesce(item$coleccion, "")), "conferencias magistrales")
    es_video <- str_detect(tolower(coalesce(item$tipo_recurso, "")), "video|audiovisual") ||
      str_detect(tolower(coalesce(item$url_recurso, "")), "youtube|vimeo")

    jpeg(filename = out_jpg, width = 600, height = 850, quality = 95)

    bg_color     <- if (es_video) "#1A252C" else if (es_conf) "#1D3557" else "#2C3E50"
    accent_color <- if (es_video) "#E63946" else "#2A9D8F"
    badge_bg     <- if (es_video) "#D81B60" else "#2A9D8F"

    par(mar = c(0, 0, 0, 0), bg = bg_color)
    plot.new()
    plot.window(xlim = c(0, 100), ylim = c(0, 100))

    rect(0, 0, 100, 100, col = bg_color, border = NA)
    rect(4, 4, 96, 96, col = "#FFFFFF", border = NA)
    rect(4, 82, 96, 96, col = accent_color, border = NA)

    text(50, 89, "INSTITUTO NACIONAL ELECTORAL", col = "#FFFFFF", cex = 1.25, font = 2)
    text(50, 76, toupper(coalesce(item$coleccion, "ACERVO EDITORIAL")), col = bg_color, cex = 1.0, font = 2)
    text(50, 66, num_label, col = badge_bg, cex = 2.4, font = 2)

    lineas_tit <- strwrap(tit_limpio, width = 25)
    y_pos <- 54
    for (line in head(lineas_tit, 4)) {
      text(50, y_pos, line, col = "#1D3557", cex = 1.1, font = 2)
      y_pos <- y_pos - 6.2
    }

    rect(16, 17, 84, 23, col = badge_bg, border = NA)
    text(50, 20, if (es_video) "🎥 VIDEO / AUDIOVISUAL" else "📖 EDICIÓN DIGITAL PDF", col = "#FFFFFF", cex = 0.85, font = 2)

    rect(4, 4, 96, 13, col = "#F8F9FA", border = NA)
    text(50, 8.5, "COLECCIÓN EDITORIAL INE", col = "#6C757D", cex = 0.85, font = 2)

    dev.off()
  }
}

# 3. Guardar cambios en DuckDB y eliminar archivos genéricos residuales
dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

archivo_generico <- file.path(dir_portadas, "portada_generica.jpg")
if (file.exists(archivo_generico)) file.remove(archivo_generico)

message("[✓] PORTADAS REALES EXTRAÍDAS Y BASE DE DATOS ACTUALIZADA CON ÉXITO.")
