# ==============================================================================
# SCRIPT: R/07_formatear_parrafos_duckdb.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Separar encabezados (###) del cuerpo del texto mediante \n\n
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)

message("=================================================================")
message(" CORRIGIENDO SEPARACIÓN DE ENCABEZADOS Y PÁRRAFOS EN DUCKDB ")
message("=================================================================\n")

con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")

separar_encabezados_de_parrafos <- function(txt) {
  if (is.null(txt) || is.na(txt) || nchar(trimws(txt)) == 0) return(txt)

  res <- as.character(txt)

  # 1. Eliminar marcas de negrita
  res <- gsub("\\*\\*", "", res)
  res <- gsub("__", "", res)

  # 2. Reemplazar encabezados pegados al texto insertando \n\n al final del título de cada sección
  res <- gsub("(?i)(#+\\s*)?I[\\.\\:-]\\s*CONTEXTO NORMATIVO, HISTÓRICO E INSTITUCIONAL\\s*", "\n\n### I. CONTEXTO NORMATIVO, HISTÓRICO E INSTITUCIONAL\n\n", res, perl = TRUE)
  res <- gsub("(?i)(#+\\s*)?II[\\.\\:-]\\s*MARCO TEÓRICO, DOCTRINAL Y CONCEPTUAL\\s*", "\n\n### II. MARCO TEÓRICO, DOCTRINAL Y CONCEPTUAL\n\n", res, perl = TRUE)
  res <- gsub("(?i)(#+\\s*)?III[\\.\\:-]\\s*DIAGNÓSTICO TÉCNICO Y METODOLÓGICO\\s*", "\n\n### III. DIAGNÓSTICO TÉCNICO Y METODOLÓGICO\n\n", res, perl = TRUE)
  res <- gsub("(?i)(#+\\s*)?IV[\\.\\:-]\\s*HALLAZGOS CLAVE, ANÁLISIS EMPÍRICO Y EVIDENCIA DOCTRINAL\\s*", "\n\n### IV. HALLAZGOS CLAVE, ANÁLISIS EMPÍRICO Y EVIDENCIA DOCTRINAL\n\n", res, perl = TRUE)
  res <- gsub("(?i)(#+\\s*)?V[\\.\\:-]\\s*IMPLICACIONES ELECTORALES Y DERECHOS POLÍTICO-ELECTORALES\\s*", "\n\n### V. IMPLICACIONES ELECTORALES Y DERECHOS POLÍTICO-ELECTORALES\n\n", res, perl = TRUE)
  res <- gsub("(?i)(#+\\s*)?VI[\\.\\:-]\\s*CONCLUSIONES CRÍTICAS Y PERSPECTIVAS FUTURAS\\s*", "\n\n### VI. CONCLUSIONES CRÍTICAS Y PERSPECTIVAS FUTURAS\n\n", res, perl = TRUE)

  # 3. Formatear encabezado inicial
  res <- gsub("(?i)^\\s*(#+\\s*)?RESUMEN EJECUTIVO\\s*", "### RESUMEN EJECUTIVO\n\n", res, perl = TRUE)

  # 4. Normalizar saltos de línea
  res <- gsub("\n{3,}", "\n\n", res)

  return(trimws(res))
}

# Aplicar corrección a la tabla
df <- df %>%
  mutate(
    resumen_ejecutivo_3p = sapply(resumen_ejecutivo_3p, separar_encabezados_de_parrafos, USE.NAMES = FALSE)
  )

# Guardar en DuckDB
dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message("=================================================================")
message(" [✓] REPARACIÓN COMPLETADA.")
message("=================================================================")
