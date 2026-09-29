# 📝 Bitácora de Desarrollo (CHANGELOG)

---

- **2026-09-26 (Día 1):**
##  - Configuración e Ingeniería de Datos

  - Inicialización del repositorio `proyecto_editorial_ine` en RStudio y vinculación con GitHub.
  - Definición de arquitectura técnica de software open source (OSS) y estructura de archivos base.
  
- **2026-09-28 (Día 2):** 

## - Jornada Completa: Pipeline de Datos, Enriquecimiento NLP, UX E-Commerce y App R Shiny

### 🚀 Infraestructura, Repositorio y Control de Versiones
- **Inicialización del Proyecto:** Vinculación del repositorio local en RStudio con GitHub (`proyecto_editorial_ine`).
- **Configuración de Seguridad (`.gitignore`):** Optimización de reglas para ignorar archivos temporales y bases de datos locales (`*.duckdb`, `*.wal`, `*.tmp`, `data/*.csv`, `downloads/`), evitando subir archivos pesados e impidiendo conflictos de sincronización.
- **Base de Datos Analítica Embebida:** Configuración de `duckdb` como motor relacional en disco local para consultas de alta velocidad a costo $0 USD.

---

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
  
- **Estrategias Antibloqueo de Nivel Industrial:**
  - Rotación dinámica de *User-Agents* aleatorios entre navegadores (Chrome, Safari, Firefox).
  - Gestor de sesiones activas con `handle()` para preservación de cookies.
  - Pausas aleatorias con *jittering* (`2.0` a `4.5` segundos) para simular hábitos de navegación humana.
  - Manejo de reintentos y retroceso exponencial con `tryCatch()` ante respuestas latentes o HTTP 429.
- **Resultado del Scraping:** Extracción exitosa de **357 recursos editoriales** (Libros PDF, Vídeos y Recursos Didácticos) almacenados en DuckDB (`data/acervo_ine.duckdb`) y respaldados en CSV.

---

### 🧠 Procesamiento de Lenguaje Natural (NLP & Enriquecimiento)
- **Desarrollo de `R/02_procesamiento_nlp.R`:**
  - **Categorización por Ejes Temáticos:** Reglas de minería de texto para clasificar las obras en *Paridad de Género y DDHH*, *Sistemas y Procesos Electorales*, *Transparencia y Rendición de Cuentas*, *Educación Cívica e Infancias* y *Cultura Democrática y Ciudadanía*.
  - **Categorización por Público Objetivo:** Clasificación en *Niñez y Juventudes*, *Academia e Investigación*, *Funcionarios y Partidos Políticos* y *Público General*.
  - **Generación de Sinopsis Contextual:** Lógica automatizada para sintetizar resúmenes ejecutivos a partir de descripciones y metadatos de las publicaciones.
  - **Extracción de Palabras Clave (`#Keywords`):** Asignación automática de etiquetas semánticas (`#Voto`, `#Paridad`, `#DerechosHumanos`, `#Transparencia`, `#Infancias`, `#Democracia`).
- **Desarrollo de `R/03_extraer_portadas_sinopsis.R`:**
  - Integración de `pdftools` para renderizado de portadas (Página 1 -> JPG) y lectura sintáctica de las primeras páginas para sinopsis de contenido real.
  - **Blindaje ante Errores `DF Error: Invalid Font Weight` y Recursos de Video:** Implementación de `suppressWarnings()`, manejo de excepciones para enlaces externos (YouTube) y generación automatizada de portadas locales JPG asignadas por ID de obra (`portada_1.jpg`, `portada_2.jpg` ... `portada_357.jpg`).

---

### 📱 Desarrollo de la Aplicación Web e-Commerce (`app.R`)
- **Interfaz Moderna con Bootstrap 5 (`bslib`):** Maquetación responsiva utilizando el tema `zephyr` y paleta cromática institucional (`#1D3557`, `#D81B60`).
- **Servidor de Archivos Estáticos:** Adición de `addResourcePath("portadas", "www/portadas")` para forzar a R Shiny a servir dinámicamente las imágenes JPG del catálogo local.
- **Experiencia de Usuario Estilo Librería Digital:**
  - Vista dual conmutable mediante conmutador en panel lateral: **"Galería de Libros 📚"** y **"Vista de Tabla 📊"**.
  - Tarjetas de producto (*Book Cards*) con simulación de portada, etiquetas de formato (PDF / Video), badge por Eje Temático, **sección destacada de Sinopsis**, `#Keywords` y botón de enlace directo.
- **Motor de Búsqueda Multidimensional:** Filtro en tiempo real que consulta simultáneamente en títulos, colecciones, ejes temáticos, sinopsis y palabras clave.
- **Indicadores y Módulo Analítico:** *Value Boxes* con contadores en tiempo real e integración de gráficos interactivos de barras y pastel en `plotly`.

---

### 🛠️ Resolución de Errores y Lecciones de Ingeniería
- **Error de Instalación DuckDB:** Resuelto forzando la instalación binaria (`type = "binary"`).
- **Error `mutate()` por variable ausente (`eje_tematico`):** Solucionado reordenando la secuencia de asignación de variables en el `mutate()` de dplyr y aplicando `coalesce()` para prevenir valores `NA`.
- **Error `argumento tiene longitud cero` en `lapply`:** Corregido reemplazando `1:min()` por `seq_len(limite)` y agregando una validación previa para datasets vacíos `nrow(df) == 0`.
- **Error en Íconos Shiny:** Reemplazada la llamada no válida `i()` por `icon()` nativo de FontAwesome.
- **Error de fuentes Poppler (`Invalid Font Weight`):** Superado creando un generador local de portadas JPG respaldado por un gestor de errores HTML (`onerror`) en las etiquetas `<img>` de Shiny.
