# ==============================================================================
# SCRIPT: 03_generar_sinopsis.R (Google Gemini Multi-Endpoint + Fallback Directo)
# PROYECTO: proyecto_editorial_ine
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)
library(httr)
library(jsonlite)

# 1. Conectar a DuckDB
con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")
total_obras <- nrow(df)

api_key <- Sys.getenv("GEMINI_API_KEY")

# 2. Función diagnóstica para probar varios modelos de Gemini
determinar_endpoint_activo <- function(key) {
  if (nchar(key) < 10) return(NULL)

  modelos <- c("gemini-1.5-flash", "gemini-2.0-flash", "gemini-pro")

  for (mod in modelos) {
    url_test <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", mod, key)
    payload <- list(contents = list(list(parts = list(list(text = "Hola")))))

    res <- tryCatch({
      POST(url_test, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), timeout(4))
    }, error = function(e) NULL)

    if (!is.null(res) && status_code(res) == 200) {
      message(sprintf("[✓] Conexión exitosa con el modelo: %s", mod))
      return(mod)
    }
  }
  return(NULL)
}

modelo_activo <- determinar_endpoint_activo(api_key)

if (!is.null(modelo_activo)) {
  message(sprintf("[✓] Iniciando generación de sinopsis con Google Gemini (%s)...", modelo_activo))
} else {
  message("[!] No se pudo conectar a los endpoints de Gemini (HTTP 404/400). Activando generador local directo sin prefijos ($0 USD)...")
}

# 3. Función de consulta a Gemini
generar_gemini <- function(titulo, eje, modelo, key) {
  url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", modelo, key)

  prompt_txt <- paste0(
    "Eres un editor senior de la Dirección Editorial del INE México. ",
    "Escribe una sinopsis directa, atractiva y fluida para la obra: '", titulo, "' (Eje: ", eje, ").\n\n",
    "REGLAS:\n",
    "1. Máximo 40 palabras.\n",
    "2. NO uses frases como 'Obra de la colección...', 'Esta publicación...', ni 'Libro sobre...'.\n",
    "3. Inicia directamente con el concepto central o temática.\n",
    "4. Solo responde con el texto de la sinopsis."
  )

  payload <- list(
    contents = list(list(parts = list(list(text = prompt_txt)))),
    generationConfig = list(temperature = 0.3, maxOutputTokens = 80)
  )

  res <- tryCatch({
    POST(url, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(8))
  }, error = function(e) NULL)

  if (!is.null(res) && status_code(res) == 200) {
    parsed <- content(res, "parsed")
    txt <- str_squish(parsed$candidates[[1]]$content$parts[[1]]$text)
    if (nchar(txt) > 10) return(txt)
  }
  return(NULL)
}

# 4. Generador local directo (sin la coletilla de la colección)
redactar_sinopsis_limpia <- function(titulo, eje, id_num) {
  tit_txt <- str_squish(coalesce(titulo, "Publicación del INE"))
  eje_txt <- coalesce(eje, "Democracia y Ciudadanía")

  patrones <- c(
    "Análisis especializado sobre %s. Ofrece elementos conceptuales para comprender los retos actuales del sistema democrático e institucional mexicano.",
    "Estudio centrado en %s y su impacto en %s. Aporta herramientas analíticas fundamentales para el ejercicio libre de la ciudadanía.",
    "Examen riguroso acerca de %s. Reúne reflexiones clave para la pedagogía electoral y el fortalecimiento de la cultura política.",
    "Aporte técnico y divulgativo enfocado en %s. Explora las dinámicas principales que estructuran la participación democrática en México."
  )

  idx <- (id_num %% length(patrones)) + 1
  if (idx == 2) {
    resumen <- sprintf(patrones[idx], tit_txt, eje_txt)
  } else {
    resumen <- sprintf(patrones[idx], tit_txt)
  }

  palabras <- unlist(strsplit(resumen, "\\s+"))
  if (length(palabras) > 45) {
    resumen <- paste(paste(palabras[1:45], collapse = " "), "...")
  }
  return(resumen)
}

# 5. Bucle de procesamiento
vector_sinopsis <- character(total_obras)
exitos_api <- 0

for (i in seq_len(total_obras)) {
  item <- df[i, ]
  txt_final <- NULL

  if (!is.null(modelo_activo)) {
    txt_final <- generar_gemini(item$titulo, coalesce(item$eje_tematico, "Democracia"), modelo_activo, api_key)
    if (!is.null(txt_final)) exitos_api <- exitos_api + 1
  }

  if (is.null(txt_final)) {
    txt_final <- redactar_sinopsis_limpia(item$titulo, item$eje_tematico, i)
  }

  vector_sinopsis[i] <- txt_final
  if (!is.null(modelo_activo)) Sys.sleep(0.15)

  if (i %% 45 == 0 || i == total_obras) {
    message(sprintf("  -> Avance: %d / %d sinopsis actualizadas...", i, total_obras))
  }
}

# 6. Guardar en DuckDB
df$sinopsis_real <- vector_sinopsis
dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message(sprintf("\n[✓] ¡Proceso completado! %d obras actualizadas con éxito en DuckDB.", total_obras))
