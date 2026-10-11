# 📝 Bitácora de Desarrollo (CHANGELOG)

## [v1.3.0] - 2026-10-10

### 🚀 Cobertura 100% de Índices Literales (203/203)
- **Extracción Completa:** Finalizada la extracción literal y fiel de las tablas de contenido impresas para el 100% de las obras elegibles en DuckDB (`acervo_enriquecido`).
- **Descarga Parcial para PDFs Masivos (>1 GB):**
  - Desarrollo del script `R/13_resolver_tomos_170_171.R` con peticiones de rango HTTP (`Range: bytes=0-15728640`).
  - Descarga ligera de los primeros 15 MB de los Tomos I (ID 170) y II (ID 171) de Obras Institucionales, logrando procesar sus preliminares en segundos sin descargar el archivo completo de +1 GB.

### 🎨 Refinamiento de Interfaz y Estilos CSS (`app.R`)
- **Estandarización Tipográfica a Arial:** Configuración de `font-family: 'Arial', sans-serif !important;` en todas las vistas de detalle (Resumen Ejecutivo e Índice).
- **Formatos de Encabezados:** Los seis bloques analíticos del Resumen Ejecutivo y su título principal se presentan destacados en Arial Negritas (`#1D3557`).
- **Limpieza y Estructura del Índice:**
  - Depuración automática de cabeceras redundantes (`ÍNDICE GENERAL`, `Contenido`, `Tabla de Contenidos`).
  - Ajuste de interlineado compacto a salto sencillo (`\n`) con `line-height: 1.5` para eliminar espaciado excesivo entre secciones.
  - Inserción de puntos suspensivos formateados antes y después de la numeración de página (`... 15 ...`).
  - Restricción estricta de itálicas exclusivamente para el cuerpo del texto en la pestaña `Índice`, removiéndolas de las tarjetas de la galería, la tabla general y los encabezados modales.
- **Pestaña Modal Simplificada:** Renombrada la pestaña de la ventana emergente de detalle a solo **`Índice`**.

## [v1.2.1] - 2026-10-07

### 🐛 Fixed & Patched
- **`app.R`**: Corregida la errata en la línea 285 donde una secuencia de escape `\vert{}` en la cadena del `paste()` reinyectaba el texto `ert{}` y caracteres de control invisibles en la ventana modal de resúmenes ejecutivos.
- **Sanitización al Vuelo**: Integrada la función auxiliar `limpiar_cadena_corrupta()` al renderizar `Colección`, `Eje Temático` y `Título` dentro de las tarjetas de la galería y en las vistas modales.
- **Pipeline de Directorios (`R/create_dir.R`)**: Actualizada la lógica de creación y verificación defensiva de directorios locales (`data/`, `www/portadas/`).

### 🛠️ Refactoring & Data Pipeline
- **`R/02_procesamiento_nlp.R`**: Incorporada desinfección preventiva contra `ert{}` y caracteres de control al leer y reescribir metadatos en DuckDB (`acervo_enriquecido`).
- **`R/03_generar_sinopsis.R`**: Sanitización agregada al inicio del pipeline para evitar la propagación de cadenas corruptas durante la generación de sinopsis adaptadas.
- **`R/04_extraer_portadas.R`**: Estandarizada la extracción e independización del proceso masivo de portadas visuales JPG en `www/portadas/`.
- **`R/05_generar_resumenes_3pag.R`**: Ajustado el formato con saltos de línea dobles (`\n\n`) tras el encabezado `RESUMEN EJECUTIVO` y reforzada la desinfección masiva en DuckDB antes del cierre de conexión.

---

## [v1.2.0] - 2026-09-29

### 🚀 Añadido
- **Pipeline Modular:** Separación estricta de responsabilidades en la carpeta `R/`:
  - `R/01_scraping_ine.R`: Extracción de metadatos de la web del INE.
  - `R/02_procesamiento_nlp.R`: Minería de texto, asignación de ejes temáticos y reestructuración de colecciones.
  - `R/03_generar_sinopsis.R`: Generación estricta y limpia de sinopsis editoriales sin repetitividad.
  - `R/04_extraer_portadas.R`: Extracción aislada de JPGs desde PDF e imágenes sintéticas de respaldo.
  - `R/05_generar_resumenes_3pag.R`: Generación de resúmenes ejecutivos profundos continuos mediante la API de Google Gemini.

### 🛠️ Cambios y Correcciones
- **Reclasificación de Colecciones:** Se separó la categoría *Manuales y Guías Didácticas* de la colección *Cuadernos de Divulgación de la Cultura Democrática* en DuckDB.
- **Resiliencia de Sinopsis:** Implementación de un generador sintáctico determinista local e integraciones seguras con LLMs, eliminando errores `HTTP 429` (Quota) y `HTTP 404`.
- **Renderizado en Shiny:** Eliminación de texto basura de scraping (`Publicado el:...`) e integración de `addResourcePath()` en `app.R` para asegurar la carga inmediata de las 357 portadas locales en `www/portadas/`.

---

## [v1.1.0] - 2026-09-28

### 🚀 Infraestructura, Repositorio y Control de Versiones
- **Inicialización del Proyecto:** Vinculación del repositorio local en RStudio con GitHub (`proyecto_editorial_ine`).
- **Configuración de Seguridad (`.gitignore`):** Optimización de reglas para ignorar archivos temporales y bases de datos locales (`*.duckdb`, `*.wal`, `*.tmp`, `data/*.csv`, `downloads/`), evitando subir archivos pesados e impidiendo conflictos de sincronización.
- **Base de Datos Analítica Embebida:** Configuración de `duckdb` como motor relacional en disco local para consultas de alta velocidad a costo $0 USD.

### 🌐 Ingeniería de Datos (Web Scraping Antibloqueo)
- **Desarrollo de `R/01_scraping_ine.R`:** Implementación de un pipeline de extracción multi-colección capaz de navegar de forma autónoma por las 9 secciones editoriales del INE:
  1. *Cuadernos de Divulgación de la Cultura Democrática*
  2. *Colección Árbol*
  3. *Manuales y Guías Didácticas*
  4. *Obras Institucionales*
  5. *Conferencias Magistrales*
  6. *Temas Selectos de la Democracia*
  7. *Estudios Electorales*
  8. *Paridad de Género y Derechos Humanos de las Mujeres*
  9. *Cuentacuentos y Talleres*
- **Estrategias Antibloqueo:** Rotación de *User-Agents*, pausas aleatorias (*jittering* de 2.0s a 4.5s) y manejo de reintentos exponenciales.
- **Resultado del Scraping:** Extracción exitosa de **357 recursos editoriales** almacenados en DuckDB (`data/acervo_ine.duckdb`) y respaldados en CSV.

### 🧠 Procesamiento de Lenguaje Natural (NLP & Enriquecimiento)
- **Categorización por Ejes Temáticos y Público Objetivo:** Clasificación en *Paridad de Género*, *Sistemas Electorales*, *Transparencia*, *Educación Cívica* y *Cultura Democrática*.
- **Extracción de Palabras Clave (`#Keywords`):** Asignación de etiquetas semánticas (`#Voto`, `#Paridad`, `#DerechosHumanos`, `#Transparencia`, `#Infancias`).
- **Portadas y Sinopsis Real:** Integración de `pdftools` para renderizado de portadas en JPG y extracción de contexto de primeras páginas.

### 📱 Aplicación Web e-Commerce (`app.R`)
- Interfaz Bootstrap 5 (`bslib` zephyr) con paleta institucional (`#1D3557`, `#D81B60`).
- Vista dual conmutable: **"Galería de Libros 📚"** y **"Vista de Tabla 📊"**.
- Motor de búsqueda multidimensional en tiempo real y módulo de análisis con `plotly`.

---

## [v1.0.0] - 2026-09-26
- Inicialización del repositorio `proyecto_editorial_ine` en RStudio y vinculación con GitHub.
- Definición de arquitectura técnica de software open source (OSS) y estructura de archivos base.
