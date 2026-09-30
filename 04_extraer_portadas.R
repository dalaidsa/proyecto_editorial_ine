# ==============================================================================
# SCRIPT: 04_extraer_portadas.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Extracción y generación de portadas visuales para las 357 obras
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)
library(pdftools)
library(httr)

# 1. Asegurar la existencia de la carpeta de portadas
if (!dir.exists("www")) dir.create("www")
if (!dir.exists("www/portadas")) dir.create("www/portadas", recursive = TRUE)

# 2. Leer datos desde DuckDB
con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")

total_obras <- nrow(df)
message(sprintf("[i] Procesando portadas para las %d obras...", total_obras))

df <- df %>% mutate(id_obra = row_number())

# Paleta cromática por Eje Temático
obtener_color <- function(eje) {
  eje_txt <- coalesce(eje, "")
  if (str_detect(eje_txt, "Paridad")) return("#D81B60")
  if (str_detect(eje_txt, "Sistemas")) return("#1D3557")
  if (str_detect(eje_txt, "Transparencia")) return("#2A9D8F")
  if (str_detect(eje_txt, "Educación")) return("#E76F51")
  return("#457B9D")
}

# 3. Bucle exclusivo para portadas
list_portadas <- character(total_obras)

for (i in seq_len(total_obras)) {
  item <- df[i, ]
  url_pdf <- coalesce(item$url_recurso, "")
  ruta_jpg_local <- file.path("www/portadas", sprintf("portada_%d.jpg", i))
  ruta_relativa <- sprintf("portadas/portada_%d.jpg", i)

  ya_existe <- file.exists(ruta_jpg_local) && file.info(ruta_jpg_local)$size > 5000
  exito <- ya_existe

  # Intento de conversión si no existe
  if (!ya_existe && str_detect(tolower(url_pdf), "\\.pdf$")) {
    tf <- tempfile(fileext = ".pdf")
    res <- tryCatch({ GET(url_pdf, write_disk(tf, overwrite = TRUE), timeout(5)) }, error = function(e) NULL)

    if (!is.null(res) && status_code(res) == 200 && file.exists(tf) && file.info(tf)$size > 3000) {
      tryCatch({
        suppressWarnings({
          out_files <- pdf_convert(pdf = tf, pages = 1, format = "jpg", dpi = 100, verbose = FALSE)
          if (length(out_files) > 0 && file.exists(out_files[1])) {
            file.copy(out_files[1], ruta_jpg_local, overwrite = TRUE)
            file.remove(out_files[1])
            exito <- TRUE
          }
        })
      }, error = function(e) NULL)
      unlink(tf)
    }
  }

  # Generar portada de respaldo si no se pudo descargar/convertir
  if (!exito) {
    color_bg <- obtener_color(item$eje_tematico)
    titulo_c <- str_wrap(coalesce(item$titulo, "Publicación INE"), width = 22)
    coleccion_c <- str_wrap(coalesce(item$coleccion, "Editorial INE"), width = 28)

    jpeg(ruta_jpg_local, width = 300, height = 400, quality = 90)
    par(mar = c(0,0,0,0), bg = color_bg)
    plot.new()
    text(0.5, 0.82, "INE", col = "#FFFFFF", cex = 4.2, font = 2)
    text(0.5, 0.72, "Acervo Editorial", col = rgb(1, 1, 1, 0.8), cex = 1.2)
    lines(c(0.2, 0.8), c(0.65, 0.65), col = "#FFFFFF", lwd = 2)
    text(0.5, 0.52, coleccion_c, col = "#F1FAEE", cex = 1.1, font = 2)
    text(0.5, 0.28, titulo_c, col = "#FFFFFF", cex = 1.0, font = 1)
    text(0.5, 0.08, sprintf("Obra N° %d / %d", i, total_obras), col = "#E0E0E0", cex = 0.8)
    dev.off()
  }

  list_portadas[i] <- ruta_relativa
}

# 4. Actualizar rutas en DuckDB
df$ruta_portada <- list_portadas
dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message(sprintf("[✓] Portadas procesadas. Archivos en www/portadas/: %d", length(list.files("www/portadas"))))
