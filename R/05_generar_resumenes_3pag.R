# ==============================================================================
# SCRIPT: 05_generar_resumenes_3pag.R (Resúmenes Magnos 3k-4k Palabras - Tier 1)
# PROYECTO: proyecto_editorial_ine
# ==============================================================================

library(duckdb)
library(dplyr)
library(stringr)
library(httr)
library(jsonlite)

message("=================================================================")
message(" GENERACIÓN DE RESÚMENES MAGNOS (3,000 - 4,000 PALABRAS) - TIER 1 ")
message("=================================================================\n")

con <- dbConnect(duckdb::duckdb(), dbdir = "data/acervo_ine.duckdb")
df <- dbReadTable(con, "acervo_enriquecido")
total_obras <- nrow(df)

if (!"resumen_ejecutivo_3p" %in% colnames(df)) df$resumen_ejecutivo_3p <- NA_character_

api_key <- Sys.getenv("GEMINI_API_KEY")

# 1. Determinar el modelo activo (Priorizando gemini-3.5-flash para velocidad/ahorro y gemini-2.5-pro)
determinar_modelo <- function(key) {
  if (is.null(key) || nchar(key) < 10) return(NULL)

  modelos <- c(
    "gemini-3.5-flash",
    "gemini-2.5-pro"
  )

  for (mod in modelos) {
    url_test <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", mod, key)
    payload <- list(contents = list(list(parts = list(list(text = "Prueba de conexion")))))

    res <- tryCatch({
      POST(url_test, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(8))
    }, error = function(e) NULL)

    if (!is.null(res) && status_code(res) == 200) {
      message(sprintf("[✓] Conexión activa con el modelo: %s\n", mod))
      return(mod)
    }
  }
  return(NULL)
}

modelo_activo <- determinar_modelo(api_key)

if (is.null(modelo_activo)) {
  dbDisconnect(con, shutdown = TRUE)
  stop("[!] No se pudo validar la API Key con los modelos activos.")
}

# 2. Función generadora con instrucciones estrictas de formato y párrafos (\n\n)
solicitar_resumen_gemini <- function(titulo, coleccion, eje, descripcion, modelo, key) {

  prompt_txt <- paste0(
    "ROL: Eres un reconocido consultor internacional, investigador senior y catedrático experto en derecho constitucional, ciencia política y derecho electoral del Instituto Nacional Electoral (INE) de México.\n\n",
    "TAREA: Redacta un RESUMEN EJECUTIVO MAGNO, TÉCNICO Y PROFUNDO para la siguiente obra institucional:\n",
    "• Título de la Obra: '", titulo, "'\n",
    "• Colección Editorial: '", coleccion, "'\n",
    "• Eje Temático: '", coalesce(eje, "Gobernanza y Cultura Democrática"), "'\n",
    "• Síntesis Contextual: '", coalesce(descripcion, "Obra oficial del acervo del INE"), "'\n\n",
    "REQUISITOS RIGUROSOS DE EXTENSIÓN Y FORMATO PÁRRAFO A PÁRRAFO:\n",
    "1. EXTENSIÓN ESTRICTA: El documento DEBE tener entre 3,000 y 4,000 palabras de redacción fluida, técnica y exhaustiva.\n",
    "2. ESTRUCTURA CON SEPARACIÓN OBLIGATORIA DE PÁRRAFOS: Separa CADA sección y CADA párrafo con DOS SALTOS DE LÍNEA ESTRUCTURALES (un renglón en blanco / \\n\\n). No entregues bloques masivos de texto continuo.\n\n",
    "3. ENCABEZADOS DE SECCIÓN OBLIGATORIOS (Utiliza exactamente los siguientes títulos Markdown):\n\n",
    "### I. CONTEXTO NORMATIVO, HISTÓRICO E INSTITUCIONAL\n",
    "(Desarrolla aquí de 500 a 600 palabras en varios párrafos separados por renglón en blanco)\n\n",
    "### II. MARCO TEÓRICO, DOCTRINAL Y CONCEPTUAL\n",
    "(Desarrolla aquí de 600 a 700 palabras en varios párrafos separados por renglón en blanco)\n\n",
    "### III. DIAGNÓSTICO TÉCNICO Y METODOLÓGICO\n",
    "(Desarrolla aquí de 600 a 700 palabras en varios párrafos separados por renglón en blanco)\n\n",
    "### IV. HALLAZGOS CLAVE, ANÁLISIS EMPÍRICO Y EVIDENCIA DOCTRINAL\n",
    "(Desarrolla aquí de 700 a 800 palabras en varios párrafos separados por renglón en blanco)\n\n",
    "### V. IMPLICACIONES ELECTORALES Y DERECHOS POLÍTICO-ELECTORALES\n",
    "(Desarrolla aquí de 500 a 600 palabras en varios párrafos separados por renglón en blanco)\n\n",
    "### VI. CONCLUSIONES CRÍTICAS Y PERSPECTIVAS FUTURAS\n",
    "(Desarrolla aquí de 400 a 500 palabras en varios párrafos separados por renglón en blanco)\n\n",
    "4. RESTRICCIONES: Prohibido incluir marcas de agua, avisos de página ('--- PÁGINA X ---') o saludos conversacionales. Empieza directamente con 'RESUMEN EJECUTIVO'."
  )

  url <- sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", modelo, key)
  payload <- list(
    contents = list(list(parts = list(list(text = prompt_txt)))),
    generationConfig = list(
      temperature = 0.35,
      maxOutputTokens = 16384 # Permite desarrollar las 4,000 palabras completas sin corte
    )
  )

  res <- tryCatch({
    POST(url, add_headers(`Content-Type` = "application/json"), body = toJSON(payload, auto_unbox = TRUE), encode = "json", timeout(120))
  }, error = function(e) {
    message(sprintf("   [X] Error de red / Timeout (120s): %s", e$message))
    return(NULL)
  })

  if (!is.null(res)) {
    st <- status_code(res)

    if (st == 200) {
      parsed <- tryCatch(content(res, "parsed"), error = function(e) NULL)

      if (!is.null(parsed) && !is.null(parsed$candidates) && length(parsed$candidates) > 0) {
        candidate <- parsed$candidates[[1]]
        finish_reason <- candidate$finishReason

        if (!is.null(candidate$content$parts[[1]]$text)) {
          # PRESERVACIÓN DE SALTOS DE LÍNEA: Se utiliza trimws en lugar de str_squish
          txt <- trimws(candidate$content$parts[[1]]$text)

          if (nchar(txt) > 1000) {
            if (!is.null(finish_reason) && finish_reason == "MAX_TOKENS") {
              message("   [ℹ️ CAPTURA EXITOSA] Resumen extenso alcanzando el tope de tokens.")
            } else {
              message("   [✓ RESUMEN COMPLETO]")
            }
            return(txt)
          }
        }
      }
    } else {
      err_text <- content(res, "text", encoding = "UTF-8")
      message(sprintf("   [!] Error HTTP %d: %s", st, str_trunc(err_text, 150)))
    }
  }

  return(NULL)
}

# 3. Bucle Incremental con Checkpointing
col_fmt <- grep("formato|tipo|extension", colnames(df), value = TRUE, ignore.case = TRUE)
nombre_col_fmt <- if (length(col_fmt) > 0) col_fmt[1] else "tipo_recurso"

obras_procesadas_hoy <- 0

for (i in seq_len(total_obras)) {
  item <- df[i, ]

  # REANUDACIÓN INCREMENTAL: Omitir si ya cuenta con resumen guardado (> 1,500 caracteres)
  resumen_actual <- coalesce(item$resumen_ejecutivo_3p, "")
  if (nchar(trimws(resumen_actual)) > 1500) {
    next
  }

  col_lower <- str_to_lower(coalesce(item$coleccion, ""))
  fmt_lower <- str_to_lower(coalesce(item[[nombre_col_fmt]], ""))

  es_arbol <- str_detect(col_lower, "árbol|arbol")
  es_video <- str_detect(fmt_lower, "video|audiovisual")

  if (!es_arbol && !es_video) {
    message(sprintf("[%d/%d] Generando Resumen Magno [%s]: %s", i, total_obras, modelo_activo, str_trunc(item$titulo, 35)))

    resumen_generado <- solicitar_resumen_gemini(
      titulo = item$titulo,
      coleccion = item$coleccion,
      eje = item$eje_tematico,
      descripcion = item$descripcion,
      modelo = modelo_activo,
      key = api_key
    )

    if (!is.null(resumen_generado)) {
      df$resumen_ejecutivo_3p[i] <- resumen_generado
      obras_procesadas_hoy <- obras_procesadas_hoy + 1

      # Guardado inmediato en DuckDB por cada registro
      dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
      Sys.sleep(0.3)
    } else {
      message(sprintf("   [⚠️ REINTENTO PENDIENTE] La obra %d se reintentará en el siguiente ciclo.", i))
    }
  } else {
    df$resumen_ejecutivo_3p[i] <- NA_character_
  }
}

# 4. Sanitización respetuosa de saltos de párrafo (\n\n)
limpiar_cadena_corrupta <- function(txt) {
  if (is.null(txt) || is.na(txt)) return(txt)
  txt <- as.character(txt)
  # Elimina caracteres de control nulos/raros pero respeta \n
  txt <- gsub("[\\v\\r\\t\\f\\p{C}]", " ", txt, perl = TRUE)
  txt <- gsub("(?i)\\s*ert\\{\\}\\s*", " ", txt, perl = TRUE)
  txt <- gsub(" +", " ", txt)
  txt <- gsub("(\r?\n){3,}", "\n\n", txt) # Estandariza a doble salto de párrafo
  return(trimws(txt))
}

cols_char <- names(df)[sapply(df, is.character)]
for (col in cols_char) {
  df[[col]] <- sapply(df[[col]], limpiar_cadena_corrupta, USE.NAMES = FALSE)
}

dbWriteTable(con, "acervo_enriquecido", df, overwrite = TRUE)
dbDisconnect(con, shutdown = TRUE)

message("\n=================================================================")
message(sprintf(" [✓] EJECUCIÓN CONCLUIDA. Obras generadas en este bloque: %d", obras_procesadas_hoy))
message("=================================================================")
