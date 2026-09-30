# 📚 Proyecto Editorial INE: Buscador y Galería Interactiva

![R](https://img.shields.io/badge/R-4.3+-blue.svg)
![DuckDB](https://img.shields.io/badge/DuckDB-Analytics-yellow.svg)
![R Shiny](https://img.shields.io/badge/R_Shiny-Interactive-magenta.svg)
![Architecture](https://img.shields.io/badge/Pipeline-Modular_R/-008080.svg)
![AI-Powered](https://img.shields.io/badge/AI_Powered-Google_Gemini-4285F4.svg?logo=google&logoColor=white)

## 📌 Descripción del Proyecto

Caso de estudio para rediseñar la experiencia de usuario en la búsqueda, exploración y visualización de las **publicaciones editoriales** del Instituto Nacional Electoral (INE).

Este proyecto aborda la extracción automatizada de datos, el almacenamiento analítico eficiente, el desarrollo de un motor de búsqueda por facetas y la creación de infografías vectoriales interactivas.

Plataforma interactiva para la exploración, filtrado por ejes temáticos y consulta de sinopsis del acervo de publicaciones del Instituto Nacional Electoral (INE).

---

## 🛠️ Stack Tecnológico (Software open source)
- **Lenguaje Principal:** R
- **Web Scraping & Pipeline:** `rvest`, `httr`, `dplyr`, `stringr`
- **Base de Datos Analítica:** `duckdb` (servidor embebido local)
- **Interfaz Web & Dashboard:** R Shiny + `bslib` (Bootstrap 5)
- **Diseño & Animación Interactiva:** Figma, SVG, JavaScript + GSAP
- **Control de Versiones & Hosting:** Git, GitHub, Hugging Face Spaces / Shinyapps.io

---

## 🏗️ Arquitectura del Pipeline (`R/`)

El procesamiento de datos sigue una estructura modular y reproducible:

1. **`R/01_scraping_ine.R`**: Descarga y extracción inicial de metadatos desde el portal del INE.
2. **`R/02_procesamiento_nlp.R`**: Clasificación por Ejes Temáticos, palabras clave (#Keywords) y separación estricta de colecciones.
3. **`R/03_generar_sinopsis.R`**: Redacción y limpieza de resúmenes ejecutivos directos (< 45 palabras) para cada obra.
4. **`R/04_extraer_portadas.R`**: Extracción protegida de portadas PDF a JPG (`pdftools`) y generación sintética para enlaces/videos.
5. **`app.R`**: Interfaz de usuario en R Shiny con galería de tarjetas y vista tabular.

---

## 🤖 Integración de Inteligencia Artificial & PLN

Este proyecto incorpora técnicas avanzadas de **Procesamiento de Lenguaje Natural (PLN)** y **Modelos de Lenguaje Grande (LLMs)** para la estructuración y enriquecimiento del acervo editorial:

* **Generación de Sinopsis Ejecutivas:** Utilización de la API de **Google Gemini (`gemini-1.5-flash` / `gemini-2.0-flash`)** mediante prompts estructurados para la síntesis de contenido, garantizando resúmenes directos, profesionales y menores a 50 palabras.
* **Minería de Texto & Clasificación Temática:** Algoritmos en R para la asignación automatizada de **Ejes Temáticos** y extracción de palabras clave (*#Keywords*) a partir de los metadatos y descripciones oficiales de cada obra.
* **Arquitectura de Resiliencia (Fallback local):** Implementación de un generador sintáctico determinista en R que asegura la disponibilidad del 100% de las sinopsis incluso ante eventualidades en la conexión o límites de API.

---

## 📅 Diario de Desarrollo (Build in Public)
Consulta el archivo [`CHANGELOG.md`](./CHANGELOG.md) para revisar el historial de avances diarios, retos superados y decisiones de arquitectura técnica.

---

## 👨‍💻 Autor
**Dalaí Serrano Alavez** - Analista de Datos  
- LinkedIn: https://www.linkedin.com/in/dalser/
- GitHub: https://github.com/dalaidsa
- X: https://x.com/dalai_dsa
