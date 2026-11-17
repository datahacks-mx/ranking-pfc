# PFC Rating: piloto para GitHub Pages

Este proyecto prepara una primera publicación manual de PFC Rating a partir de la hoja de Google que compartiste. El motor principal está escrito en R y conserva la metodología Glicko-2 Beta 3.1 por evento y rama. El cálculo considera los resultados reales de la base; no se generan atletas ficticios.

## Estado de la prueba

La estructura del flujo, el manejo de datos y el ajuste de `DESERT` se han preparado como piloto. El ajuste equivalente en Python se probó con los datos reales y conservó sin cambios los ratings de los 1,506 atletas reales. **En este entorno no hay R instalado: la ejecución del motor R y el despliegue completo aún deben verificarse en GitHub Actions.** La descarga de la hoja se comprobó desde el navegador; falta comprobar la descarga desde el servidor de GitHub.

El marcador `DESERT` se conserva en el registro de los rivales reales y en los reportes de auditoría, pero no aparece como atleta y el enfrentamiento no modifica el rating. El significado deportivo y estadístico de esos registros debe revisarse con la metodología de PFC.

## Preparar el repositorio

1. Crea un repositorio público en GitHub y activa **Settings → Pages → Build and deployment → Source → GitHub Actions**.
2. Descomprime este archivo ZIP en tu computadora. En GitHub, selecciona **Add file → Upload files** y carga **el contenido** de la carpeta del proyecto en la raíz del repositorio. Incluye la carpeta `.github` y su subcarpeta `workflows`; no subas el ZIP cerrado. Si no ves la carpeta `.github`, habilita la vista de elementos ocultos de tu sistema.
3. Comprueba que aparezcan en la raíz `pfc_glicko2.R`, `descargar_hoja.py`, `preparar_publicacion.py` y `dashboard_template.html`. En la pestaña **Code**, comprueba también que exista `.github/workflows/actualizar-ranking.yml`.
4. En **Settings → Secrets and variables → Actions**, selecciona **New repository secret**. Escribe `GOOGLE_SHEET_ID` como nombre y, como valor, pega únicamente el identificador del documento de Google Sheets: el texto que está entre `/d/` y `/edit` en su dirección. Guarda el secreto.
5. En **Actions**, selecciona **Preparar y publicar PFC Rating** y después **Run workflow → Run workflow**. Si GitHub solicita habilitar Actions, sigue la indicación. Revisa el registro de la primera ejecución; si falla, el paso mostrará el motivo y no se actualizará la publicación.
6. Si termina correctamente, abre el enlace del despliegue mostrado en la ejecución o en **Settings → Pages**, y revisa el ranking antes de enlazarlo desde Point Fight Club.

**La hoja debe poder descargarse mediante su enlace.** Guardar el identificador en Secrets evita escribirlo en el código, pero no vuelve privada una hoja compartida con cualquiera que tenga el enlace. Si más adelante la haces privada, habrá que configurar una autenticación de lectura apropiada; este piloto no la incluye.

El archivo original se descarga de forma temporal durante el proceso. GitHub Pages recibe el HTML, `ranking.json` con los historiales mostrados por el dashboard, y `actualizacion.json`. Estos archivos son públicos al publicar el sitio: revisa que sus campos sean los que deseas compartir. No subas contraseñas, llaves ni copias del archivo de origen al repositorio público.

## Actualización programada

Para que la primera prueba sea controlada, el flujo comienza con ejecución manual. Después de revisar el resultado, puede activarse la sección `schedule` comentada en `.github/workflows/actualizar-ranking.yml`; su ejemplo está programado para las 06:15 de Ciudad de México. Se puede elegir otra frecuencia antes de activarla. La programación puede demorarse y hay que supervisar las ejecuciones.

## Controles

Antes de publicar, el proceso se detiene si hay combates con registros incompletos, si un combate presenta problemas de rama que no sean el marcador `DESERT`, si el ranking contiene nombres vacíos o duplicados, o si los conteos no concuerdan. Un fallo impide el nuevo despliegue y conserva el último sitio publicado correctamente.

Las reglas de la fuente y del motor actual tienen límites: el identificador de una persona es su nombre, por lo que todavía es necesario revisar homónimos; el ranking es experimental y no homologado por peso, edad o modalidad. Los resultados con `DESERT` no generan rating, aunque el marcador original permanece en la auditoría.
