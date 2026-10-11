# ==============================================================================
# SCRIPT: R/10_inspeccionar_indices.R
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
df_resumen <- df %>%
  filter(nchar(coalesce(resumen_ejecutivo_3p, "")) > 1500)

# Evaluar cuántos índices tienen formato estructurado por la IA
con_formato_ia <- sum(str_detect(coalesce(df_resumen$indice_tematico, ""), "(?i)ÍNDICE|CAPÍTULO|PRESENTACIÓN|INTRODUCCIÓN"))

message("=================================================================")
message("         INSPECCIÓN DE LA COLUMNA 'INDICE_TEMATICO'             ")
message("=================================================================")
message(sprintf(" Total de obras elegibles (con resumen)  : %d", nrow(df_resumen)))
message(sprintf(" Índices con estructura jerárquica de IA : %d", con_formato_ia))
message("=================================================================\n")

# Mostrar una muestra de 3 obras para revisión visual
set.seed(42)
muestra_indices <- df_resumen %>% slice_sample(n = min(3, nrow(df_resumen)))

for (i in seq_len(nrow(muestra_indices))) {
  cat("----------------------------------------------------------------\n")
  cat(sprintf("[%d] OBRA: %s\n", i, muestra_indices$titulo[i]))
  cat("CONTENIDO EN DUCKDB (Primeros 250 caracteres):\n")
  cat(substring(coalesce(muestra_indices$indice_tematico[i], "VACÍO"), 1, 250), "...\n")
}
cat("----------------------------------------------------------------\n")
