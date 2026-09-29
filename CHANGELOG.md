# 📝 Bitácora de Desarrollo (CHANGELOG)

---

## [Semana 1] - Configuración e Ingeniería de Datos
- **2026-09-26 (Día 1):** 
  - Inicialización del repositorio `proyecto_editorial_ine` en RStudio y vinculación con GitHub.
  - Definición de arquitectura técnica de software open source (OSS) y estructura de archivos base.
- **2026-09-28 (Día 2):** 
  - # 📝 Bitácora de Desarrollo (CHANGELOG)

### 🚀 Infraestructura y Control de Versiones
- **Proyecto e Integración:** Inicialización del repositorio `proyecto_editorial_ine` en RStudio y vinculación exitosa con GitHub.
- **Documentación de Portafolio:** Creación y publicación de la portada principal (`README.md`) y la bitácora de desarrollo (`CHANGELOG.md`).
- **Seguridad y Limpieza:** Configuración optimizada del archivo `.gitignore` para prevenir la subida de datos locales pesados (`*.duckdb`, `*.csv`, `*.pdf`) y archivos temporales de RStudio.
- **Base de Datos Analítica:** Configuración e instalación exitosa del motor relacional `duckdb` en R para almacenamiento en memoria/disco local.

### 🌐 Ingeniería de Datos (Web Scraping Antibloqueo)
- **Pipeline Multisección:** Desarrollo y ejecución del script `R/01_scraping_ine.R` diseñado para iterar sobre 9 colecciones y acervos clave del portal del INE:
  1. *Cuadernos de Divulgación de la Cultura Democrática*
  2. *Colección Árbol*
  3. *Manuales y Guías Didácticas*
  4. *Obras Institucionales*
  5. *Conferencias Magistrales*
  6. *Temas Selectos de la Democracia*
  7. *Estudios Electorales*
  8. *Paridad de Género y Derechos Humanos de las Mujeres*
  9. *Cuentacuentos y Talleres*
- **Estrategia Antibloqueo:** Implementación de rotación aleatoria de *User-Agents*, manejo de cookies con `handle()`, pausas aleatorias (*jittering*) y retroceso exponencial con `tryCatch()` para evitar bloqueos HTTP 429 / IP Ban.
- **Resultado:** Extracción exitosa de **357 recursos editoriales** (Libros PDF, Vídeos y Guías Didácticas) persistidos en la tabla `acervo_editorial` de DuckDB (`data/acervo_ine.duckdb`) y respaldados en CSV.

### 🧠 Procesamiento de Lenguaje Natural (NLP & Enriquecimiento)
- **Etiquetado Automatizado:** Creación del script `R/02_procesamiento_nlp.R` para realizar minería de texto y clasificación de los 357 recursos.
- **Categorización por Público Objetivo:** Identificación de contenidos dirigidos a *Niñez y Juventudes*, *Academia e Investigación*, *Funcionarios y Partidos Políticos* y *Público General*.
- **Categorización por Eje Temático:** Clasificación en *Paridad de Género y DDHH*, *Sistemas y Procesos Electorales*, *Transparencia y Rendición de Cuentas*, *Educación Cívica e Infancias* y *Cultura Democrática y Ciudadanía*.
- **Persistencia Enriquecida:** Creación de la tabla `acervo_enriquecido` en DuckDB y exportación a `data/acervo_editorial_enriquecido.csv`.

### 📱 Desarrollo de la Aplicación Web (R Shiny)
- **Maquetación R Shiny:** Creación del archivo `app.R` utilizando `bslib` (Bootstrap 5) con tema personalizado `zephyr` y paleta cromática institucional.
- **Componentes Interactivos:** 
  - Filtros reacondicionados en tiempo real por búsqueda de texto libre, colección editorial, eje temático y formato/tipo de recurso.
  - Tarjetas de valor (*Value Boxes*) dinámicas con recuento de indicadores clave.
  - Tabla interactiva faceteada impulsada por `DT` con botones de descarga y acceso directo a cada recurso.
  - Dashboard analítico con gráficos interactivos renderizados en `plotly` (barras por eje temático y pastel por colección).
