# ==============================================================================
# SCRIPT: R/11_identificar_3_obras_faltantes.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Verificar el contenido real de la columna 'indice_tematico'
# ==============================================================================


library(duckdb)
library(dplyr)
library(stringr)

con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb", read_only = TRUE)
df <- dbReadTable(con, "acervo_enriquecido")
dbDisconnect(con, shutdown = TRUE)

# Filtrar las obras con resumen magno
df_elegibles <- df %>% filter(nchar(coalesce(resumen_ejecutivo_3p, "")) > 1500)

# Identificar las 3 obras que no tienen 'ÍNDICE GENERAL'
faltantes <- df_elegibles %>%
  filter(!str_detect(coalesce(indice_tematico, ""), "(?i)ÍNDICE GENERAL")) %>%
  select(id_obra, titulo, coleccion, url_recurso)

message("=================================================================")
message("             OBRAS PENDIENTES DE ÍNDICE LITERAL (3)             ")
message("=================================================================")

for (i in seq_len(nrow(faltantes))) {
  cat(sprintf("\n[%d] ID Obra : %s\n", i, faltantes$id_obra[i]))
  cat(sprintf("    Título  : %s\n", faltantes$titulo[i]))
  cat(sprintf("    Colección: %s\n", faltantes$coleccion[i]))
  cat(sprintf("    URL     : %s\n", faltantes$url_recurso[i]))
}
message("=================================================================")
