# ==============================================================================
# SCRIPT: 02_procesamiento_nlp.R
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Limpieza de texto y clasificación/etiquetado inteligente (NLP)
# ==============================================================================

library(dplyr)
library(stringr)
library(duckdb)
library(readr)

# 1. Leer los datos crudos desde DuckDB
con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df_raw <- dbGetQuery(con, "SELECT * FROM acervo_editorial")

message(sprintf("[i] Registros leídos de DuckDB para procesamiento: %d", nrow(df_raw)))

# 2. Función de asignación de Población Objetivo según palabras clave
asignar_poblacion_objetivo <- function(texto) {
  t <- tolower(texto)

  poblaciones <- c()
  if (str_detect(t, "niñ|infan|cuento|taller|escuela|joven|juven|estudiant|árbol")) {
    poblaciones <- c(poblaciones, "Niñez y Juventudes")
  }
  if (str_detect(t, "investig|académ|estudio|investigador|ciencia política|ensayo")) {
    poblaciones <- c(poblaciones, "Academia e Investigación")
  }
  if (str_detect(t, "funci|partido|candidat|casilla|electoral|capacit|manual|guía")) {
    poblaciones <- c(poblaciones, "Funcionarios y Partidos Políticos")
  }

  if (length(poblaciones) == 0) {
    return("Público General")
  }

  return(paste(poblaciones, collapse = "; "))
}

# 3. Función de asignación de Eje Temático
asignar_eje_tematico <- function(texto, coleccion) {
  t <- tolower(paste(texto, coleccion))

  if (str_detect(t, "género|mujer|paridad|violencia política|derechos humanos")) {
    return("Paridad de Género y DDHH")
  } else if (str_detect(t, "voto|sistem|comicio|elecci|casilla|distrit|partido")) {
    return("Sistemas y Procesos Electorales")
  } else if (str_detect(t, "transparen|fiscaliz|rendición|cuenta|corrup")) {
    return("Transparencia y Rendición de Cuentas")
  } else if (str_detect(t, "cuento|taller|árbol|juego|didáct")) {
    return("Educación Cívica e Infancias")
  } else {
    return("Cultura Democrática y Ciudadanía")
  }
}

# 4. Aplicar transformaciones y vectorización
df_enriquecido <- df_raw %>%
  mutate(
    texto_completo = paste(titulo, descripcion, coleccion),
    poblacion_objetivo = sapply(texto_completo, asignar_poblacion_objetivo),
    eje_tematico = mapply(asignar_eje_tematico, texto_completo, coleccion),
    # Limpieza de títulos
    titulo_limpio = str_to_title(str_squish(titulo))
  ) %>%
  select(-texto_completo)

# 5. Guardar dataset enriquecido en DuckDB (tabla: acervo_enriquecido)
dbWriteTable(con, "acervo_enriquecido", df_enriquecido, overwrite = TRUE)
write_csv(df_enriquecido, "data/acervo_editorial_enriquecido.csv")

message("\n[✓] Procesamiento NLP finalizado exitosamente.")
message("\nDistribución por Eje Temático:")
print(dbGetQuery(con, "SELECT eje_tematico, COUNT(*) as total FROM acervo_enriquecido GROUP BY eje_tematico"))

dbDisconnect(con, shutdown = TRUE)
