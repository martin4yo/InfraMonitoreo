# Relevamiento de vulnerabilidades — 2026-08-09

> **Primera ejecución de la cadencia C3** de [G6](./gobierno/g6-revisiones-periodicas.md), aplicando la
> política de [G4](./gobierno/g4-gestion-vulnerabilidades.md). Cubre las dos capas que G4 define como
> alcance: **dependencias npm de las aplicaciones propias** y **paquetes del sistema operativo**.
>
> **Método no invasivo.** Todo el escaneo se hizo con `npm audit --package-lock-only`, que resuelve el
> árbol de dependencias **desde el `package-lock.json`** sin tocar `node_modules`, sin instalar nada y sin
> reiniciar ningún proceso. No se modificó un solo archivo en los servidores.

## 1. Resumen ejecutivo

Se auditaron **42 proyectos Node** con lockfile en los 4 servidores; **20 de ellos en producción**. Solo 2
proyectos están completamente limpios.

| Alcance | 🔴 Críticas | 🟠 Altas | 🟡 Medias |
|---|---|---|---|
| **Producción — todo** (runtime + build) | **13** | 224 | 140 |
| **Producción — solo runtime** (`--omit=dev`) | **8** | **154** | 107 |
| dev-1 (desarrollo) — todo | 23 | 343 | 197 |

**La distinción runtime/build es la más importante del informe.** Alrededor de un tercio de las "altas"
viven en herramientas que solo corren al compilar (`vite`, `rollup`, `postcss`, `@typescript-eslint`): un
ReDoS ahí lo dispara el propio equipo compilando, no un atacante por internet. **Las cifras sobre las que
hay que decidir son las de runtime: 8 críticas y 154 altas.**

La buena noticia está en la accionabilidad: de los **73 paquetes distintos** con vulnerabilidad crítica o
alta en runtime, **53 se arreglan con un `npm audit fix` compatible**. El grueso del problema no requiere
reescribir nada — requiere ejecutar y probar.

## 2. Panorama por aplicación (producción, solo runtime)

| Servidor | Aplicación | 🔴 | 🟠 | 🟡 | Total |
|---|---|---:|---:|---:|---:|
| clubix | **`clubix/server`** | **4** | 30 | 14 | **48** |
| axioma | `evolution-api` *(tercero)* | **2** | 15 | 35 | 53 |
| axioma | `parse/backend` | 1 | 14 | 8 | 24 |
| axioma | `mini/frontend` | 1 | 6 | 3 | 10 |
| axioma | **`mediflow/backend`** *(app **alvera**, base 🔴)* | 0 | **23** | 8 | 33 |
| axioma | `mini/backend` | 0 | 16 | 5 | 21 |
| axioma | `parse/frontend/mobile-pwa` | 0 | 13 | 4 | 18 |
| axioma | `elore` | 0 | 9 | 1 | 10 |
| axioma | `parse/frontend` | 0 | 8 | 1 | 9 |
| axioma | `mediflow/frontend` | 0 | 6 | 3 | 9 |
| axiodemo | `axio/frontend` | 0 | 4 | 3 | 7 |
| axioma | `hub/backend` | 0 | 3 | 2 | 5 |
| clubix | `clubix/molinete-service` | 0 | 3 | 3 | 6 |
| clubix | `clubix/client` | 0 | 3 | 6 | 9 |
| axioma | `mini/print-manager` | 0 | 1 | 3 | 4 |
| axiodemo | `axio/backend` | 0 | 0 | 2 | 3 |
| axioma · clubix | `axio-db-agent` (×2) | 0 | 0 | 3 | 3 |

**Dos aplicaciones concentran la atención, por razones distintas:**

- **`clubix/server`** es el peor caso absoluto: **4 críticas y 30 altas**, y es la única app con
  **pasarela de pago viva** (`MERCADOPAGO_ACCESS_TOKEN`, ver [G7 S12](./gobierno/g7-rotacion-secretos.md)).
- **`mediflow/backend`** (la app **alvera**) no tiene críticas, pero es la aplicación de la **única base
  🔴 Sensible** del marco. Sus 23 altas pesan más que las de cualquier otra app por el dato que protege.
  **21 de esas 23 tienen fix compatible** — es la app con mejor relación esfuerzo/beneficio del informe.

`hub/backend` con solo 3 altas es el resultado visible de la remediación de julio (H13): es el mejor
puntaje del parque y sirve como referencia de a dónde se puede llegar.

## 3. Clasificación por accionabilidad — los 3 niveles

Los 73 paquetes distintos con vulnerabilidad **crítica o alta en runtime**, clasificados por **lo que hace
falta para resolverlos** (no por severidad):

| Nivel | Qué significa | Paquetes | Esfuerzo |
|---|---|---:|---|
| **1 — Aplicable ya** | Existe fix **semver-compatible**. `npm audit fix` lo resuelve sin cambiar API | **53** | Bajo |
| **2 — Requiere ventana** | El fix implica **salto de versión mayor**: puede romper la app | **17** | Medio/Alto |
| **3 — Sin solución** | No hay versión corregida upstream. Requiere **decisión**, no ejecución | **3** | Decisión |

### 🟢 Nivel 1 — Aplicable ya (53 paquetes)

Fixes compatibles, sin cambio de API. Los más extendidos:

| Paquete | Apps | Problema |
|---|---:|---|
| `brace-expansion` | 30 | DoS por expansión exponencial |
| `js-yaml` | 28 | Consumo cuadrático de CPU en `!!omap` |
| `picomatch` | 27 | ReDoS vía cuantificadores extglob |
| `axios` | 25 | Asignación de recursos sin límite |
| `form-data` | 24 | Inyección CRLF en multipart |
| `lodash` | 19 | Prototype pollution en `_.unset` |
| `nanoid` | 17 | Loop infinito con `size` cero |
| `path-to-regexp` | 13 | ReDoS |
| `jws` | 9 | **Verificación incorrecta de firma HMAC** |

**Cómo se aplica:** `npm audit fix` por aplicación, con `package-lock.json` versionado antes, la batería de
tests de la app, y verificación **contra el próximo arranque** (no contra el proceso vivo — la regla
corregida tras el incidente de H06). El caso de referencia es hub en julio: 61 → 11 vulnerabilidades,
57/57 tests en PASS, sin rollback.

> ⚠️ **`jws` merece atención aparte.** "Verifica incorrectamente la firma HMAC" en una librería de JWT no es
> un DoS: es una potencial **omisión de autenticación**. Está en 9 aplicaciones y su fix es compatible.
> **Debería ser el primero de la lista.**

### 🟡 Nivel 2 — Requiere ventana y pruebas (17 paquetes)

El fix existe pero implica un salto mayor. Aplicarlos con `npm audit fix --force` sin probar **es la vía
directa a un incidente en producción**.

| Paquete | Apps | Problema | Riesgo del salto |
|---|---:|---|---|
| `minimatch` | 25 | ReDoS catastrófico con extglobs anidados | Transitivo, bajo |
| `ws` | 19 | DoS con muchas cabeceras HTTP | Medio — afecta websockets |
| `postcss` | 17 | XSS vía `</style>` sin escapar | Build, bajo |
| `nodemailer` | 15 | **Inyección de comandos SMTP vía CRLF** | Medio — cambia API de envío |
| `sharp` | 10 | CVEs heredados de libvips | Alto — binario nativo |
| `vite` | 10 | Lectura arbitraria de archivos (dev server) | Build |
| `@xmldom/xmldom` | 8 | Inyección XML | Medio |
| `next` | 5 | DoS en Server Components | **Alto** — ver nota |
| `pdfjs-dist` | 3 | **Ejecución de JS al abrir un PDF** | Medio |
| `adm-zip` | 3 | ZIP malicioso reserva 4 GB | Bajo |

> **`next` arrastra un bloqueo ya conocido.** Subir Next.js de versión mayor toca el mismo terreno que el
> patrón `-H`/redirects que dejó **H04 parcial** desde julio. Conviene resolver las dos cosas en la misma
> ventana, no por separado.

### 🔴 Nivel 3 — Sin solución disponible (3 paquetes)

No hay versión corregida. **La acción no es técnica sino una decisión**: reemplazar la librería, mitigar
por diseño, o aceptar el riesgo formalmente.

| Paquete | Apps | Problema | Opciones |
|---|---|---|---|
| **`xlsx`** (SheetJS) | elore, mini/backend, parse/backend, clubix/client, +1 | Prototype pollution | Migrar a `exceljs`, o **aislar el parseo** y no procesar archivos de origen no confiable |
| `expr-eval` | mini/frontend | No restringe funciones pasadas a `evaluate()` | Reemplazar por un evaluador con sandbox, o restringir la entrada |
| `@figuro/chatwoot-sdk` | evolution-api | — | Es de **evolution-api**, software de terceros: depende de su upstream |

`xlsx` es el más relevante: está en **5 aplicaciones** y el vector es un archivo Excel subido por un
usuario. La mitigación de diseño (validar y aislar el parseo) puede ser más barata que la migración.

## 4. Las 8 críticas de runtime

| Paquete | Aplicación | Problema | Nivel |
|---|---|---|---|
| `protobufjs` | evolution-api, parse/backend | **Ejecución arbitraria de código** | 1 |
| `handlebars` | clubix/server | DoS vía sintaxis de decorador malformada | 1 |
| `basic-ftp` | clubix/server | Path traversal en `downloadToDir()` | 1 |
| `jsrsasign` | mini/frontend | DoS por loop infinito | 1 |
| `baileys` | evolution-api | Spoofing de mensajes / corrupción de estado | 1 |
| `shell-quote` | mini, clubix/server | No escapa saltos de línea | 1 |
| `fast-xml-parser` | mini/backend | Bypass de límites de expansión de entidades | 1 |
| **`request`** | clubix/server | **SSRF** | **2** |
| **`form-data`** | clubix/server | Frontera multipart con random inseguro | **2** |

**6 de las 8 son de Nivel 1.** `protobufjs` (ejecución arbitraria de código) debería ir junto con `jws` en
la primera tanda. Las dos de Nivel 2 están en clubix; `request` además está **deprecado desde 2020**, así
que su fix real es sacarlo, no actualizarlo.

## 5. Sistema operativo

| Servidor | Distro | Actualizables | De seguridad | Reboot |
|---|---|---:|---:|---|
| axioma | Ubuntu 22.04.5 LTS | 7 | **0** | 🔴 **Sí** |
| clubix | Ubuntu 22.04.5 LTS | 16 | **0** | 🔴 **Sí** |
| axiodemo | Ubuntu 24.04.4 LTS | 45 | **0** | 🔴 **Sí** |
| dev-1 | Ubuntu 22.04.5 LTS | 12 | **0** | 🔴 **Sí** |

**Lo que funciona:** `unattended-upgrades` opera correctamente vía `apt-daily-upgrade.timer` en los 4
(últimas corridas 06 y 07 de agosto) y **no hay ni un paquete de seguridad pendiente de descargar**. El
parcheo automático hace su trabajo.

**Lo que no:** los **4 servidores requieren reboot** y ninguno lo hizo. Es la consecuencia directa de
`Automatic-Reboot=false`, que G4 documenta como decisión deliberada — pero **sin una ventana de reinicio
programada, esa decisión se convierte en parches instalados que nunca se activan**:

- **axioma y clubix** corren el kernel `5.15.0-185` con **`-186` y `-187` instalados y esperando**: dos
  versiones de atraso.
- **axiodemo** tiene tres kernels en cola (`-134`, `-136`, `-137`).
- **Los 4** tienen **`libc6` pendiente de activación** — los procesos vivos siguen usando la glibc anterior.

Un parche de kernel instalado y no arrancado **no protege de nada**. Este es, a nivel de sistema, el
hallazgo más concreto del relevamiento.

**Versiones de runtime** (sin EOL a la vista): Node 20.20.2 en axioma/clubix/dev-1 y 22.22.2 en axiodemo ·
PostgreSQL 14.23 en axioma/clubix/dev-1 y 16.14 en axiodemo · nginx 1.18.0 / 1.24.0.

> Nota menor: en axioma y dev-1 el **cliente** `psql` es 18.4 mientras el **servidor** es 14.23 (repo
> pgdg). No es un problema —el cliente nuevo habla con servidores viejos— pero puede confundir a quien
> verifique versiones con `psql --version` en un incidente.

## 6. Plan sugerido

**Tanda 1 — alto impacto, riesgo bajo.** `jws` (firma HMAC, 9 apps) y `protobufjs` (ejecución de código,
2 apps). Ambos Nivel 1. Empezar por **`mediflow/backend`**: 21 de sus 23 altas se resuelven acá, y es la
app de la base 🔴.

**Tanda 2 — el peor caso.** `clubix/server`: 4 críticas y 30 altas, con pasarela de pago viva. Incluye las
dos de Nivel 2 (`request` → sacarlo; `form-data`). Requiere ventana.

**Tanda 3 — ventana de reinicio de los 4 servidores.** Activa los kernels y `libc6` ya descargados. Es la
acción de menor esfuerzo y mayor cobertura de todo el informe: no hay que decidir ni probar nada, solo
programarla.

**Tanda 4 — decisiones de Nivel 3.** `xlsx` en 5 apps y `expr-eval`. Requieren definición de producto,
no de infraestructura.

**Fuera de alcance de estas tandas:** `evolution-api` es software de terceros (2 críticas, 15 altas) — su
remediación depende del upstream, no del equipo. Conviene evaluar si la versión desplegada está al día.

## 7. Limitaciones de este relevamiento

Para que el próximo ciclo no arrastre supuestos:

- **`npm audit` no sabe si el código vulnerable se ejecuta.** Una dependencia con ReDoS en una función que
  la app nunca llama figura igual. Los números son un **techo**, no una medición de explotabilidad real.
  G4 pide ajustar el CVSS por explotabilidad; eso exige revisar cada caso.
- **Apps sin lockfile no se auditaron.** `hub/frontend` (axioma) y varios proyectos de dev-1 no tienen
  `package-lock.json` — quedan **fuera de toda medición**. Generar el lockfile es prerrequisito para que
  el próximo ciclo los cubra.
- **dev-1 se midió pero no se analizó en detalle.** Sus cifras (23 críticas, 343 altas) son mayores que
  las de producción y merecen ciclo propio — sobre todo dado **R13**: si aloja datos productivos reales,
  su superficie deja de ser "de desarrollo".
- **No se auditó Python.** No se encontraron `requirements.txt` ni `pyproject.toml` en `/var/www` ni
  `/opt`; el colector `pgbackrest-collect.py` usa solo biblioteca estándar.

---

*Relevamiento del 2026-08-09, solo lectura, sin modificar nada en los servidores. Registrado como primera
ejecución de C3 en [G6 §4](./gobierno/g6-revisiones-periodicas.md).*
