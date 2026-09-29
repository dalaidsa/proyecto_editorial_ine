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
