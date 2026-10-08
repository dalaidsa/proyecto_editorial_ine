# ==============================================================================
# SCRIPT: 02_procesamiento_nlp.R (Limpieza, Tags y Colecciones Actualizadas)
# PROYECTO: proyecto_editorial_ine
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)

message("[i] Iniciando procesamiento de metadatos, tags y colecciones...")

# 1. Conexión a la base de datos DuckDB
con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")

# --- SANITIZACIÓN ANTI-ERT Y CARACTERES INVISIBLES ---
limpiar_cadena_corrupta <- function(txt) {
  if (is.null(txt) || is.na(txt)) return(txt)
  txt <- as.character(txt)
  txt <- gsub("[\\v\\r\\n\\t\\f\\p{C}]", " ", txt, perl = TRUE)
  txt <- gsub("(?i)\\s*ert\\{\\}\\s*", " ", txt, perl = TRUE)
  return(trimws(gsub("\\s+", " ", txt)))
}

cols_char <- names(df)[sapply(df, is.character)]
for (col in cols_char) {
  df[[col]] <- sapply(df[[col]], limpiar_cadena_corrupta, USE.NAMES = FALSE)
}
# -----------------------------------------------------

# 2. Identificación dinámica de la columna de formato
col_formato_vec <- grep("formato|tipo|extension|recurso", colnames(df), value = TRUE, ignore.case = TRUE)

if (length(col_formato_vec) > 0) {
  col_formato <- col_formato_vec[1]
  message(sprintf("[i] Columna de formato identificada: '%s'", col_formato))
} else {
  col_formato <- "formato"
  df$formato <- "PDF" # Columna por defecto si no existía
  message("[!] No se detectó columna de formato; se creó 'formato' con valor por defecto 'PDF'.")
}

# 3. Depuración: Eliminar material audiovisual mal ubicado en Cuadernos de Divulgación
df <- df %>%
  filter(!(
    str_detect(str_to_lower(coalesce(coleccion, "")), "cuadernos de divulgación") &
      str_detect(str_to_lower(coalesce(.data[[col_formato]], "")), "video|audiovisual")
  ))

# 4. Renombrar obras con versión EPUB
es_epub <- str_detect(str_to_lower(coalesce(df[[col_formato]], "")), "epub")
ya_tiene_suffix <- str_detect(str_to_lower(coalesce(df$titulo, "")), "\\(versión epub\\)")

df$titulo <- ifelse(es_epub & !ya_tiene_suffix, paste0(df$titulo, " (versión epub)"), df$titulo)

# 5. Asignación de Nombres a Videos de Conferencias Magistrales
es_conf_video <- str_detect(str_to_lower(coalesce(df$coleccion, "")), "conferencias magistrales") &
  str_detect(str_to_lower(coalesce(df[[col_formato]], "")), "video|audiovisual")

df$titulo[es_conf_video] <- paste0("Conferencia Magistral: ", str_replace_all(df$titulo[es_conf_video], "(?i)video|conferencia", ""))

# 6. Generación de Tags Temáticos y de Edad (Sin Tag "INE")
generar_tags <- function(coleccion, titulo, segmento_edad, valor_formato) {
  tags <- c()
  col_lower <- str_to_lower(coalesce(coleccion, ""))
  tit_lower <- str_to_lower(coalesce(titulo, ""))
  fmt_lower <- str_to_lower(coalesce(valor_formato, ""))

  # Tags por Edad en Colección Árbol
  if (str_detect(col_lower, "árbol|arbol")) {
    if (str_detect(coalesce(segmento_edad, ""), "10|13|16") || str_detect(tit_lower, "adolescente")) {
      tags <- c(tags, "Adolescentes")
    } else {
      tags <- c(tags, "Infantil")
    }
  }

  # Tags Temáticos por palabras clave
  if (str_detect(tit_lower, "democracia|democrátic")) tags <- c(tags, "Democracia")
  if (str_detect(tit_lower, "elección|electoral|voto")) tags <- c(tags, "Elecciones")
  if (str_detect(tit_lower, "género|paridad|mujer")) tags <- c(tags, "Paridad de Género")
  if (str_detect(tit_lower, "justicia|tribunal|tepjf")) tags <- c(tags, "Justicia Electoral")
  if (str_detect(tit_lower, "gobernanza|política")) tags <- c(tags, "Cultura Política")
  if (str_detect(tit_lower, "partido|militan")) tags <- c(tags, "Partidos Políticos")
  if (str_detect(tit_lower, "participación|ciudadan")) tags <- c(tags, "Participación Ciudadana")
  if (str_detect(fmt_lower, "video|audiovisual")) tags <- c(tags, "Recurso Audiovisual")

  if (length(tags) == 0) tags <- c("Publicación Oficial")
  return(paste(unique(tags), collapse = ";"))
}

# Aplicación de la función generadora de tags
df$tags_cadena <- mapply(
  generar_tags,
  df$coleccion,
  df$titulo,
  if ("segmento_edad" %in% colnames(df)) df$segmento_edad else NA_character_,
  df[[col_formato]]
)

# 7. Sobrescribir la base de datos DuckDB
dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message("[✓] Base de datos 'acervo_enriquecido' reestructurada y guardada exitosamente en DuckDB.")
