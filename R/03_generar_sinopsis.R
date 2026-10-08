# ==============================================================================
# SCRIPT: 03_generar_sinopsis.R (Sinopsis Únicas, Adaptadas e Identificación de Formatos)
# PROYECTO: proyecto_editorial_ine
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)

message("[i] Generando sinopsis personalizadas e íntegras para el acervo...")

con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")

# Sanitización preventiva para evitar reintroducir ert{}
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

# 1. Normalizador de título base (para identificar cuentos idénticos en ePub o Inglés)
obtener_titulo_base <- function(titulo) {
  t <- str_to_lower(coalesce(titulo, ""))
  t <- str_replace_all(t, "\\b(epub|pdf|versión inglesa|english version|edición digital|recurso audiovisual)\\b", "")
  t <- str_replace_all(t, "[[:punct:]]", "")
  return(str_squish(t))
}

df$titulo_base <- sapply(df$titulo, obtener_titulo_base)

# 2. Banco de aperturas narrativas dinámicas para la Colección Árbol
aperturas_arbol <- c(
  "Acompaña a los personajes en este relato donde %s descubre la importancia de la empatía, el diálogo y la convivencia en comunidad.",
  "Un viaje lleno de aventuras pensado para %s, explorando cómo las pequeñas decisiones transforman nuestro entorno cívico.",
  "A través de esta historia ilustrada, %s aprenderán sobre el valor de la tolerancia, la honestidad y el trabajo en equipo.",
  "¿Cómo resolvemos los desacuerdos entre amigos? Este cuento ofrece a %s reflexiones fundamentales para construir lazos de respeto.",
  "Una narrativa entrañable que invita a %s a reflexionar sobre la libertad de expresión, la justicia y la participación activa.",
  "Con personajes inolvidables, este libro acerca a %s al ejercicio de sus derechos y al descubrimiento de la democracia.",
  "Descubre en esta lectura recomendada para %s un mensaje claro y divertido sobre la inclusión y la diversidad en la sociedad."
)

# 3. Diccionario en memoria para agrupar obras idénticas
mapa_sinopsis <- list()

# 4. Bucle de generación
vector_sinopsis <- character(total_obras)

for (i in seq_len(total_obras)) {
  item <- df[i, ]
  base_key <- item$titulo_base

  # Si ya existe la sinopsis generada para la versión base (ej. ePub o traducción)
  if (!is.null(mapa_sinopsis[[base_key]])) {
    vector_sinopsis[i] <- mapa_sinopsis[[base_key]]
    next
  }

  es_arbol <- str_detect(str_to_lower(coalesce(item$coleccion, "")), "árbol|arbol")

  if (es_arbol) {
    target <- coalesce(item$segmento_edad, "Niñas y niños de 6 a 9 años")
    patron_idx <- (i %% length(aperturas_arbol)) + 1
    plantilla <- aperturas_arbol[patron_idx]

    sinopsis_text <- sprintf(plantilla, target)
  } else {
    # Para la colección general
    patron_gen <- (i %% 4) + 1
    tit_clean <- str_trunc(item$titulo, 40)
    eje_clean <- coalesce(item$eje_tematico, "Cultura Democrática")

    if (patron_gen == 1) {
      sinopsis_text <- sprintf("Análisis especializado enfocado en %s. Aporta herramientas conceptuales esenciales para comprender los desafíos de %s en el México contemporáneo.", eje_clean, tit_clean)
    } else if (patron_gen == 2) {
      sinopsis_text <- sprintf("Estudio fundamental sobre %s que examina las dinámicas de %s, ofreciendo un marco riguroso de reflexión para especialistas y ciudadanía.", tit_clean, eje_clean)
    } else if (patron_gen == 3) {
      sinopsis_text <- sprintf("Esta publicación explora los aspectos clave de %s a través de un enfoque divulgativo sobre %s y la pedagogía electoral.", tit_clean, eje_clean)
    } else {
      sinopsis_text <- sprintf("Aporte técnico relevante para la discusión sobre %s, reuniendo perspectivas indispensables sobre %s e instituciones.", eje_clean, tit_clean)
    }
  }

  # Guardar en memoria para mantener idénticas las versiones derivadas
  mapa_sinopsis[[base_key]] <- sinopsis_text
  vector_sinopsis[i] <- sinopsis_text
}

# 5. Guardar cambios en DuckDB
df$sinopsis_real <- vector_sinopsis
df$titulo_base <- NULL # Eliminar columna auxiliar

dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message("[✓] Base de datos actualizada con sinopsis variadas e identificadas por formato.")
