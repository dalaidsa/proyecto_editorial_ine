# Crear carpetas del proyecto
dir.create("R")          # Funciones y scripts de R (scraping, nlp, utils)
dir.create("data")       # Bases de datos locales (duckdb, csv)
dir.create("www")        # Activos web futuros (estilos CSS, imágenes SVG, JS)

# Crear el script principal
file.create("R/01_scraping_ine.R")
file.edit("R/01_scraping_ine.R")

# Crear script para Procesamiento de Lenguaje Natural
file.create("R/02_procesamiento_nlp.R")
file.edit("R/02_procesamiento_nlp.R")

# Crear estructura de aplicación
file.create("app.R")
file.edit("app.R")

# Script de extracción de portadas
file.create("04_extraer_portadas.R")
file.edit("04_extraer_portadas.R")

# Script de extracción de portadas
file.create("05_generar_resumenes_3pag.R")
file.edit("05_generar_resumenes_3pag.R")#

# Script de extracción de portadas
file.create("06_generar_informe_resumenes.R")
file.edit("06_generar_informe_resumenes.R")

# Script de extracción de portadas
file.create("07_formatear_parrafos_duckdb.R")
file.edit("07_formatear_parrafos_duckdb.R")

# Script de extracción de portadas
file.create("08_extraer_indices.R")
file.edit("08_extraer_indices.R")

# Script de extracción de portadas
file.create("09_reportar_indices.R")
file.edit("09_reportar_indices.R")

# Script de extracción de portadas
file.create("10_inspeccionar_indices.R")
file.edit("10_inspeccionar_indices.R")

# Script de extracción de portadas
file.create("11_identificar_3_obras_faltantes.R")
file.edit("11_identificar_3_obras_faltantes.R")

# Script de extracción de portadas
file.create("12_reintentar_3_faltantes.R")
file.edit("12_reintentar_3_faltantes.R")

# Script de extracción de portadas
file.create("13_resolver_tomos_170_171.R")
file.edit("13_resolver_tomos_170_171.R")
