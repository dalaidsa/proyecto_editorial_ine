# ==============================================================================
# SCRIPT: 06_generar_informe_resumenes.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Exportar a un archivo TXT el listado y métricas de todas las obras
#           que ya tienen resumen ejecutivo guardado en DuckDB.
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)

# 1. Conexión en modo lectura a la base de datos
ruta_db <- "data/acervo_ine.duckdb"

if (!file.exists(ruta_db)) {
  stop("[!] No se encontró la base de datos en la ruta: ", ruta_db)
}

con <- dbConnect(duckdb::duckdb(), dbdir = ruta_db, read_only = TRUE)
df <- dbReadTable(con, "acervo_enriquecido")
dbDisconnect(con, shutdown = TRUE)

# 2. Filtrar obras con resumen completado (> 1,500 caracteres)
if (!"resumen_ejecutivo_3p" %in% colnames(df)) {
  stop("[!] La columna 'resumen_ejecutivo_3p' no existe en la tabla 'acervo_enriquecido'.")
}

df_completadas <- df %>%
  mutate(
    resumen_txt = coalesce(resumen_ejecutivo_3p, ""),
    num_caracteres = nchar(resumen_txt),
    num_palabras = str_count(resumen_txt, "\\S+")
  ) %>%
  filter(num_caracteres > 1500) %>%
  arrange(id_obra)

total_acervo <- nrow(df)
total_completadas <- nrow(df_completadas)
porcentaje <- ifelse(total_acervo > 0, (total_completadas / total_acervo) * 100, 0)

# 3. Construcción estructurada del archivo TXT
lineas_informe <- c()

lineas_informe <- c(lineas_informe, "================================================================================")
lineas_informe <- c(lineas_informe, "            INFORME DE OBRAS CON RESUMEN EJECUTIVO COMPLETADO")
lineas_informe <- c(lineas_informe, "                     INSTITUTO NACIONAL ELECTORAL (INE)")
lineas_informe <- c(lineas_informe, "================================================================================")
lineas_informe <- c(lineas_informe, sprintf("Fecha de generación          : %s", Sys.time()))
lineas_informe <- c(lineas_informe, sprintf("Total de obras en catálogo  : %d", total_acervo))
lineas_informe <- c(lineas_informe, sprintf("Obras con resumen completado : %d (%.1f%%)", total_completadas, porcentaje))
lineas_informe <- c(lineas_informe, sprintf("Obras pendientes por procesar: %d", total_acervo - total_completadas))
lineas_informe <- c(lineas_informe, "================================================================================")
lineas_informe <- c(lineas_informe, "")

if (total_completadas == 0) {
  lineas_informe <- c(lineas_informe, "No se encontraron obras con resumen ejecutivo completado (> 1,500 caracteres).")
} else {
  lineas_informe <- c(lineas_informe, "LISTADO DETALLADO DE OBRAS COMPLETADAS:")
  lineas_informe <- c(lineas_informe, "--------------------------------------------------------------------------------")

  for (i in seq_len(total_completadas)) {
    obra <- df_completadas[i, ]

    lineas_informe <- c(lineas_informe, sprintf("[%03d] ID Obra  : %s", i, obra$id_obra))
    lineas_informe <- c(lineas_informe, sprintf("      Título   : %s", obra$titulo))
    lineas_informe <- c(lineas_informe, sprintf("      Colección: %s", coalesce(obra$coleccion, "Sin colección")))
    lineas_informe <- c(lineas_informe, sprintf("      Eje      : %s", coalesce(obra$eje_tematico, "Sin eje")))
    lineas_informe <- c(lineas_informe, sprintf("      Métricas : %s palabras | %s caracteres",
                                                format(obra$num_palabras, big.mark = ","),
                                                format(obra$num_caracteres, big.mark = ",")))
    lineas_informe <- c(lineas_informe, "--------------------------------------------------------------------------------")
  }
}

# 4. Guardar en disco el archivo de texto
archivo_salida <- "informe_obras_con_resumen.txt"
writeLines(lineas_informe, con = archivo_salida, useBytes = TRUE)

# 5. Notificación en consola R
message("=================================================================")
message(sprintf("[✓] Informe generado exitosamente: '%s'", archivo_salida))
message(sprintf("    Total de obras procesadas con resumen completo: %d de %d (%.1f%%)",
                total_completadas, total_acervo, porcentaje))
message("=================================================================")
