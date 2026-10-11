# ==============================================================================
# SCRIPT: R/09_reportar_indices.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Consultar DuckDB y reportar el avance en la generación de
#           Índices Temáticos / Tablas de Contenido.
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)

ruta_db <- "data/acervo_ine.duckdb"

if (!file.exists(ruta_db)) {
  stop("[!] No se encontró la base de datos en: ", ruta_db)
}

# 1. Conexión en modo lectura a DuckDB
con <- dbConnect(duckdb::duckdb(), dbdir = ruta_db, read_only = TRUE)
df <- dbReadTable(con, "acervo_enriquecido")
dbDisconnect(con, shutdown = TRUE)

# 2. Validación y Métricas
total_obras <- nrow(df)

# Obras con resumen magno activo (> 1,500 caracteres)
obras_elegibles <- sum(nchar(coalesce(df$resumen_ejecutivo_3p, "")) > 1500)

# Obras con índice temático completado (> 50 caracteres y no nulo)
if ("indice_tematico" %in% colnames(df)) {
  indices_guardados <- sum(
    nchar(trimws(coalesce(df$indice_tematico, ""))) > 50 &
      !str_detect(coalesce(df$indice_tematico, ""), "(?i)no disponible")
  )
} else {
  indices_guardados <- 0
}

indices_pendientes <- obras_elegibles - indices_guardados
pct_cobertura <- ifelse(obras_elegibles > 0, (indices_guardados / obras_elegibles) * 100, 0)

# 3. Impresión del Reporte en Consola
message("=================================================================")
message("          REPORTE DE AVANCE: ÍNDICES TEMÁTICOS (DUCKDB)         ")
message("=================================================================")
message(sprintf("  [📚] Total de publicaciones en catálogo : %d", total_obras))
message(sprintf("  [🎯] Obras elegibles (con Resumen Magno) : %d", obras_elegibles))
message(sprintf("  [✓] Índices guardados con éxito        : %d (%.1f%%)", indices_guardados, pct_cobertura))
message(sprintf("  [⏳] Índices pendientes                 : %d", indices_pendientes))
message("=================================================================")
