# ==============================================================================
# SCRIPT: 02_procesamiento_nlp.R (Versión Enriquecida: Sinopsis y Keywords)
# PROYECTO: proyecto_editorial_ine
# OBJETIVO: Generación de sinopsis corta, palabras clave y ejes temáticos
# ==============================================================================

library(dplyr)
library(stringr)
library(duckdb)
library(readr)

# 1. Leer datos crudos desde DuckDB
con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df_raw <- dbGetQuery(con, "SELECT * FROM acervo_editorial")

message(sprintf("[i] Procesando sinopsis, ejes temáticos y palabras clave para %d obras...", nrow(df_raw)))

# 2. Función de asignación de Eje Temático
asignar_eje_tematico <- function(texto, coleccion) {
  t <- tolower(paste(coalesce(texto, ""), coalesce(coleccion, "")))

  if (str_detect(t, "género|mujer|paridad|violencia política|derechos humanos")) {
    return("Paridad de Género y DDHH")
  } else if (str_detect(t, "voto|sistem|comicio|elecci|casilla|distrit|partido")) {
    return("Sistemas y Procesos Electorales")
  } else if (str_detect(t, "transparen|fiscaliz|rendición|cuenta|corrup")) {
    return("Transparencia y Rendición de Cuentas")
  } else if (str_detect(t, "cuento|taller|árbol|juego|didáct|infan")) {
    return("Educación Cívica e Infancias")
  } else {
    return("Cultura Democrática y Ciudadanía")
  }
}

# 3. Función para generar Sinopsis Dinámica Corta
generar_sinopsis <- function(titulo, descripcion, coleccion, tipo) {
  desc_limpia <- str_squish(coalesce(descripcion, ""))

  if (nchar(desc_limpia) > 40 && !str_detect(desc_limpia, "^http")) {
    sinopsis <- str_trunc(desc_limpia, 220)
  } else {
    sinopsis <- sprintf("Obra perteneciente a la colección '%s' del INE. Presenta un análisis especializado en formato %s orientado a promover los valores de la cultura democrática y el debate político electoral.", coalesce(coleccion, "General"), coalesce(tipo, "Digital"))
  }
  return(sinopsis)
}

# 4. Función para extraer y asignar Palabras Clave (Keywords)
extraer_palabras_clave <- function(texto_completo, coleccion) {
  t <- tolower(paste(coalesce(texto_completo, ""), coalesce(coleccion, "")))
  kw <- c()

  # Diccionario semántico de keywords
  if (str_detect(t, "voto|elecc|sufrag|casilla|comicio")) kw <- c(kw, "Voto", "Elecciones", "Procesos Electorales")
  if (str_detect(t, "género|mujer|paridad|femin|violencia")) kw <- c(kw, "Paridad de Género", "Derechos Políticos", "Mujeres")
  if (str_detect(t, "joven|juventud|niñ|infan|escuela|árbol|cuento")) kw <- c(kw, "Educación Cívica", "Infancias", "Participación Ciudadana")
  if (str_detect(t, "transparen|fiscaliz|rendición|cuenta")) kw <- c(kw, "Transparencia", "Rendición de Cuentas", "Fiscalización")
  if (str_detect(t, "derecho|fundamental|justicia|constituc")) kw <- c(kw, "Derechos Humanos", "Estado de Derecho", "Justicia")
  if (str_detect(t, "digital|redes|medios|periodis|fake news")) kw <- c(kw, "Entorno Digital", "Libertad de Expresión", "Medios")
  if (str_detect(t, "partido|candidat|campaña|sistema")) kw <- c(kw, "Partidos Políticos", "Campañas", "Democracia")

  if (length(kw) == 0) kw <- c("Cultura Democrática", "INE", "Educación Cívica")

  return(paste(unique(kw), collapse = ", "))
}

# 5. Enriquecimiento del dataset en orden correcto de variables
df_enriquecido <- df_raw %>%
  rowwise() %>%
  mutate(
    # Primero asignamos las columnas base
    eje_tematico = asignar_eje_tematico(paste(titulo, descripcion), coleccion),
    sinopsis = generar_sinopsis(titulo, descripcion, coleccion, tipo_recurso),
    palabras_clave = extraer_palabras_clave(paste(titulo, descripcion), coleccion),

    # Después creamos la columna de texto consolidado para la búsqueda
    texto_busqueda = tolower(paste(
      coalesce(titulo, ""),
      coalesce(descripcion, ""),
      coalesce(coleccion, ""),
      coalesce(eje_tematico, ""),
      coalesce(palabras_clave, ""),
      coalesce(sinopsis, "")
    ))
  ) %>%
  ungroup()

# 6. Persistencia en DuckDB y CSV
dbWriteTable(con, "acervo_enriquecido", df_enriquecido, overwrite = TRUE)
write_csv(df_enriquecido, "data/acervo_editorial_enriquecido.csv")

message("\n[✓] Proceso NLP finalizado exitosamente.")
message("Sinopsis, Ejes Temáticos y Palabras Clave almacenados en la tabla 'acervo_enriquecido' de DuckDB.")

dbDisconnect(con, shutdown = TRUE)
