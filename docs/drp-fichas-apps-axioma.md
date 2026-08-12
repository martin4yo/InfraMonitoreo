# DRP — Fichas por aplicación (axioma → axioma-drp)

> **Se lee junto al [runbook general](./drp-recuperacion-axioma-en-drp.md).** El runbook dice *qué hacer*;
> esta ficha dice *con qué valores*. Cada ficha resuelve las variables `<app>`, `<appuser>`, `<path>`,
> `<puerto>`, `<base>` y las particularidades que no son comunes al resto.
>
> **Datos relevados en vivo el 2026-08-11** desde axioma (`.env` de `infra-secrets`, `ecosystem.config.js`,
> vhosts de nginx, `systemd`, `/etc/passwd`). Lo que no pudo verificarse queda marcado **(a confirmar)**.
>
> **Estado:** v1 — **ninguna ficha fue ejecutada todavía**. La primera prueba de cada una debe corregirla.

## Tabla maestra

| App | Usuario | Puerto | Base | Rol PG | Conexión | PM2 | Repo |
|---|---|---|---|---|---|---|---|
| **mediflow** *(alvera)* | `mediflowapp` (1000) | **5300** | `mediflow_db` | `mediflowuser` | **:6432** pgbouncer | `mediflow-backend` ×2 cluster | `martin4yo/mediflow` (SSH) |
| **hub** | `hubapp` (993) | **5200** back · **8089** front | `hub_db` | `hubuser` | :5432 directo | `hub-backend`, `hub-frontend` | `AxiomaCloud/ProHub` (SSH) |
| **parse** | `parseapp` (117) | **5100** back · **8087** front | `parse_db` | `parseuser` | **:6432** pgbouncer | `parse-backend` | `martin4yo/parse` (SSH) |
| **mini** | `miniapp` (1002) | **8095** back | `mini_db` | `miniuser` | **:6432** pgbouncer | `mini-backend` | `martin4yo/AxiomaWeb` (SSH) |
| **elore** | `eloreapp` (994) | **3700** | `elore_db` | `eloreuser` | :5432 directo | `elore` | `AxiomaCloud/Elore` rama `main` |
| **evolution-api** | `evolutionapp` (996) | **8080** | `evolution` | *(a confirmar)* | *(a confirmar)* | *(vía systemd)* | `EvolutionAPI/evolution-api` |
| **axio-db-agent** | `axioapp` (998) | **3005** | *4 bases ajenas* | ver ficha | :5432 directo | systemd, **sin PM2** | — |
| **checkpoint** | *(a confirmar)* | estático | `checkpoint_db` | *(a confirmar)* | — | — | `AxiomaCloud/checkpointsite` |
| **axioma-corporate** | *(a confirmar)* | estático | — | — | — | — | `rodrigomnaranjo/axioma-corporate` |

> ⚠️ **Bases sin aplicación identificada:** `axiomadocs`, `chequescloud`, `iasqlassistant_db`, `core_db`.
> Se restauran con el cluster (Fase 2) pero **no hay app en axioma que las consuma**. Antes del primer
> simulacro conviene determinar si son de apps decomisionadas o si les falta un consumidor documentado.

---

## 🩺 mediflow (alvera) — PRIORIDAD 1

> 📌 **La app se llama `alvera`; la infraestructura dice `mediflow`.** Ver
> [Apéndice A.0 del DRP](./disaster-recovery-plan.md). Buscá `mediflow`, no `alvera`.

| | |
|---|---|
| **Path** | `/var/www/mediflow` (backend en `/backend`, frontend en `/frontend`) |
| **Usuario** | `mediflowapp` — ⚠️ único con grupo suplementario `www-data` |
| **Puerto** | `5300` |
| **Base / rol** | `mediflow_db` / `mediflowuser` |
| **Conexión** | `localhost:**6432**` (pgbouncer) + `?pgbouncer=true&connection_limit=5` |
| **Dominios** | `alvera.axiomacloud.com`, `api.alvera.axiomacloud.com`, `alvera.com.ar`, `www.alvera.com.ar` |
| **vhosts** | `alvera`, `alvera.com.ar` |
| **PM2** | `mediflow-backend` · **cluster, 2 instancias** · `--max-old-space-size=192` · `max_memory_restart 500M` |
| **RAM medida** | 2 × 146 MB + 60 MB daemon ≈ **350 MB** |
| **Prisma** | ✅ sí — `npx prisma generate` tras `npm ci` |

**🔴 Particularidad crítica — cifrado a nivel de aplicación.** Su `.env` tiene `ENCRYPTION_MASTER_KEY`
(64 caracteres) y `SEARCH_HASH_SALT` (128). **Los datos de `mediflow_db` están cifrados en reposo por la
app**: un restore de pgBackRest devuelve filas cifradas. Sin esas dos claves exactas, los datos de salud
son **permanentemente ilegibles** y ningún backup lo resuelve.

> **La verificación de §9.3 del runbook no es opcional para esta app.** Es la única que distingue una
> recuperación exitosa de una que *parece* exitosa. Riesgo **R15**.

### ✅ SIMULACRO EJECUTADO — 2026-08-12

**alvera levantó en axioma-drp y quedó accesible**, con hub corriendo en paralelo.
`SPA → 200` con `<title>Alvera - Sistema de Gestión Médica</title>`, `API → 401` (auth operativa),
**73 tablas · 4 tenants · 5 pacientes · 3212 audit_logs**. Estado final: 902 MB usados, **2686 MB libres**.

**Código traído desde el repositorio de GitHub**, no desde axioma — el camino que funciona con axioma muerto.

#### 🔴 EL HALLAZGO MÁS IMPORTANTE: el repo NO tiene la configuración de producción

El `ecosystem.config.js` **versionado en GitHub difiere del que corre en axioma**:

| | Repo (GitHub) | axioma (producción) |
|---|---|---|
| `NODE_ENV` | **`development`** | `production` |
| `PORT` | **`5000`** | `5300` |
| `node_args` | *(ausente)* | `--max-old-space-size=192` |

**Desplegar siguiendo el runbook "clonar del repo" levanta la app en modo development, en el puerto
equivocado y escuchando en `*:5000`** (todas las interfaces). La app *parece* funcionar —responde,
autentica— y por eso el error pasa desapercibido: no falla, funciona **mal**.

> 👉 **Por eso [`config/axioma/`](../config/axioma/) no es opcional.** Es la única copia fiel de la
> configuración productiva. En el simulacro, aplicar ese archivo corrigió el arranque de inmediato.
> **Regla: el código sale del repo, la configuración de PM2 sale de `config/axioma/`.**

#### Otros hallazgos

- ✅ **`npm ci` genera el cliente Prisma solo** — el `package.json` tiene
  `postinstall: npm run build → prisma:generate`. **Distinto de hub**, donde hay que correrlo a mano desde
  `backend/`. Dos apps del mismo parque, dos comportamientos: es el argumento para tener fichas separadas.
- 📊 **Build medido en drp: 33 s, y el mínimo de memoria disponible fue 1598 MB** (con hub corriendo).
  El pico consumió ~1,2 GB de los 3,9 GB. **La "regla de oro" del runbook se relaja** — ver §0.2.
- El `.env` de producción conecta por **pgbouncer `:6432`**, que no existe en drp → se ajustó a `:5432`
  quitando `?pgbouncer=true`. Es el desvío previsto en §3.4 del runbook.
- Con `NODE_ENV=production` la app **fuerza redirect a HTTPS** (301). Correcto: nginx termina TLS y hay
  que pasarle `X-Forwarded-Proto: https`, o todo responde 301 en bucle.
- Bindea a **`*:5300`**, no a loopback, pese a `HOST=127.0.0.1` en el `.env`. Es el mismo patrón de
  **H04** y **también ocurre en axioma** — no es un artefacto del simulacro.

#### ⚠️ La verificación 9.3 quedó a medias, y hay que decirlo

Se confirmó que los datos están (5 pacientes, 4 tenants) y que la app arranca y autentica. **No se
verificó que los campos cifrados se lean en claro**, porque eso exige un login funcional con credenciales
reales. **Sigue siendo la única verificación que distingue una recuperación exitosa de una que lo
parece.** Pendiente de ejecución humana sobre el entorno ya montado.

#### Nota de clasificación

El responsable confirmó que **alvera no está productiva con tenants reales**: está en un servidor de
producción pero en testing. Eso responde la acción **A1 de [G8](./gobierno/g8-clasificacion-datos.md)** y
baja de facto la clasificación 🔴 *(a confirmar)*. ⚠️ Con una salvedad: *"en testing"* no garantiza cero
datos reales — si alguna vez se cargó un dump, vuelve a subir. **Los 5 pacientes y 3212 `audit_logs`
merecen una mirada antes de cerrar A1.**

Por decisión del responsable, **`mediflow_db` queda en drp** (sigue en testing).

**Otras particularidades:**
- Es la **única base 🔴 Sensible** del marco (datos de salud, art. 7 Ley 25.326) → cualquier incidente
  durante el DR puede tener obligación de notificación ([G5 §5](./gobierno/g5-respuesta-incidentes.md)).
- `TWILIO_*` está **declarado pero vacío**: no envía SMS. No perder tiempo configurándolo.
- Tiene `ANTHROPIC_API_KEY` cargada.
- Contraseña de `mediflowuser`: **8 caracteres, débil** (R06). El DR es buena ocasión para rotarla.

---

## 🔷 hub — PRIORIDAD 2

| | |
|---|---|
| **Path** | `/var/www/hub` (`/backend`, `/frontend`, `/shared`) |
| **Usuario** | `hubapp` (993) |
| **Puertos** | `5200` backend · `8089` frontend (Next) |
| **Base / rol** | `hub_db` / `hubuser` · `localhost:5432` **directo** |
| **Dominios** | `hub.axiomacloud.com`, `api.hub.axiomacloud.com` |
| **PM2** | `hub-backend` (`dist/server.js`) y `hub-frontend` (`next start -p 8089`) |
| **Logs** | `/var/log/hub/` — **crear el directorio antes de arrancar** |
| **RAM medida** | 217 MB + 61 MB daemon (en drp arrancó con 30 + 36 MB) |
| **Prisma** | ✅ **SÍ** — corregido 2026-08-12 |

**🔴 Es un MONOREPO con npm workspaces** *(verificado 2026-08-12)*. `package.json` declara
`workspaces: ['backend','frontend','shared']` y el `node_modules` está **hoisted en la raíz**
(`/var/www/hub/node_modules`, **1.4 GB**). No hay `node_modules` dentro de `frontend/`.

- 👉 **`npm ci` se corre en `/var/www/hub`, NO en cada paquete.** Correrlo dentro de `backend/` o
  `frontend/` no reproduce el árbol y la app no arranca.
- El `package-lock.json` autoritativo es el de la **raíz**.
- `hub-frontend` arranca con `node_modules/next/dist/bin/next` **relativo a la raíz hoisted**.

**📦 El artefacto a transferir es chico — 22 MB, no 500:**

| Qué | Tamaño |
|---|---|
| `backend/dist` | 3,0 MB |
| `frontend/.next` **sin `cache/`** | **19 MB** |
| `frontend/public` | 120 KB |
| ~~`frontend/.next/cache`~~ | ~~473 MB~~ — **caché de build, NO copiar** |
| ~~`node_modules` (raíz)~~ | ~~1,4 GB~~ — se regenera con `npm ci` en drp |

> `.next` pesa 491 MB en axioma, pero **473 son caché de compilación**. Excluir `cache/` baja la
> transferencia de 491 MB a 19 MB. Es la diferencia entre minutos y segundos en un DR.

### ✅ SIMULACRO EJECUTADO — 2026-08-12

**hub levantó en axioma-drp y quedó accesible.** `frontend → 200` con `<title>Axioma - Hub</title>`,
`backend /health → 200` con `{"status":"ok"}`, **87 tablas** restauradas, 700 MB usados de 3911.
Sin tocar producción: datos desde R2, configuración desde `infra-secrets`.

**Los cuatro tropiezos, en orden de aparición:**

1. 🔴 **`locale-gen en_US.UTF-8` faltaba en drp** → el cluster restaurado no arranca. Bloqueante total,
   y el `pgbackrest restore` dice *"completed successfully"* igual. Ahora es el paso **1.8** del runbook.
2. 🔴 **hub usa Prisma** — esta ficha decía que no. El escaneo buscó `.prisma` en `backend/node_modules`,
   pero por el **hoisting del monorepo** vive en `/var/www/hub/node_modules/.prisma`.
3. 🔴 **`npx prisma generate` se corre desde `backend/`, NO desde la raíz.** El `prisma.config.ts` está en
   la raíz pero declara `schema: "prisma/schema.prisma"` **relativo al cwd**, y el schema real está en
   `backend/prisma/`. Desde la raíz falla con *"Could not load schema"*.
4. 🟡 **Tras `systemctl reload nginx`, el primer request lo atiende el worker viejo** y devuelve la página
   por defecto. Ya estaba documentado en [`nginx-anti-scanner.md`](../nginx-anti-scanner.md); volvió a
   morder. **Re-testear a los pocos segundos.**

### 🔴 Inconsistencias de PRODUCCIÓN que el simulacro destapó

Estas no son del DR: existen hoy en axioma y el ejercicio las hizo visibles.

- **El `.env` tiene un comentario pegado al valor**, sin salto de línea:
  `JWT_SECRET=<valor>== # AWS S3 (configurar cuando sea necesario)`.
  Node lo tolera, pero cualquier parser más estricto —o un `source` de shell— se lleva el comentario
  **dentro del secreto**. Fragilidad latente: si un entorno lo parsea distinto, los JWT dejan de validar.
- **15 archivos que no son código en la raíz de la app**, con datos de terceros identificados: facturas
  (`Factura Mc Joselevich`, `factura_maria_joselevich.html`, un PDF cuyo nombre es un **CUIT**),
  propuestas comerciales (`Ferracioli-…`, `PENDIENTES_UDESA.md`) y capturas. **9 están versionadas en
  git.** No son accesibles por web (nginx hace `proxy_pass`, no sirve el directorio), pero es material
  para [G8](./gobierno/g8-clasificacion-datos.md).

**Particularidades:**
- **Es la app de referencia**: fue la del drill de DRP y la de la remediación de julio (H13). Tiene el
  mejor estado de vulnerabilidades del parque (3 altas).
- ⚠️ **`hub-frontend` escucha en `*:8089` (`0.0.0.0`), no en loopback** — verificado 2026-08-12. Es una de
  las 5 apps Next de **H04**, bloqueada por el patrón `-H`/redirects. En drp queda tapado por ufw.
- El [drill hub → axioma-drp](./drp-app-hub-drill.md) es el antecedente directo de este runbook: tiene
  detalle adicional útil, aunque **nunca se ejecutó**.
- ⚠️ `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` en su `.env` son **peso muerto** (SDK nunca importado,
  R07). **No replicarlas en drp** — el DR es la oportunidad natural de dejarlas afuera.
- Único con `WHATSAPP_BUSINESS_API_TOKEN` y `TWILIO_*` **cargados de verdad**.
- Frontend Next: **compilar afuera** (§0.2 del runbook).

---

## 📄 parse — PRIORIDAD 2

| | |
|---|---|
| **Path** | `/var/www/parse` (`/backend`, `/frontend`, `/frontend/mobile-pwa`) |
| **Usuario** | `parseapp` — ⚠️ **uid 117, gid 124** (usuario de sistema, no 1000+) |
| **Puertos** | `5100` backend · `8087` frontend |
| **Base / rol** | `parse_db` / `parseuser` · `localhost:**6432**` pgbouncer |
| **Dominios** | `parse.axiomacloud.com`, `api.parse.axiomacloud.com` |
| **PM2** | `parse-backend` (`backend/src/index.js`, fork) |
| **RAM medida** | **595 MB** — ⚠️ **la app más pesada del parque** |

**Particularidades:**
- 🔴 **`PM2_HOME` es `/var/www/parse/.pm2`, no `/home/parseapp/.pm2`.** Si PM2 "no encuentra" la app, es
  esto. Es la desviación más fácil de pasar por alto de todo el runbook.
- Es la app con **más dependencias nativas**: 20 binarios `.node`, más `sharp`, `bcrypt` y Prisma.
  **La que más se rompe si se compila en la plataforma equivocada.**
- Su `.env` tiene 45 variables — el más grande. Incluye `GOOGLE_APPLICATION_CREDENTIALS` (Document AI):
  **verificar que el archivo de credenciales al que apunta también se copie**, o la app arranca y falla
  al procesar.
- Tiene `ENCRYPTION_KEY` y `SYNC_PASSWORD_KEY` — mismo problema conceptual que mediflow, a confirmar
  si cifra datos en reposo.
- `:8087` ya está en loopback (fix de H04).
- El `ecosystem.config.js` documenta explícitamente **no correr PM2 como root**.

---

## 🛒 mini — PRIORIDAD 2

| | |
|---|---|
| **Path** | `/var/www/mini` (`/backend`, `/frontend`, `/print-agent`, `/print-manager`, `/web`) |
| **Usuario** | `miniapp` (1002) |
| **Puerto** | `8095` backend |
| **Base / rol** | `mini_db` / `miniuser` · `localhost:**6432**` pgbouncer |
| **Dominios** | `mini.axiomacloud.com` · `axioma.ar` + `www.axioma.ar` (estático desde `/var/www/mini/web`) |
| **Frontend** | **estático**, servido por nginx desde `/var/www/mini/frontend/dist` |
| **RAM medida** | 183 MB + 61 MB daemon |

**Particularidades:**
- 🔴 **Sus credenciales están filtradas en `~/.pm2/pm2.log`** (S18, `hardening.md` §9): `whatsappApiKey`
  de Evolution, `smtpPass` de Gmail y contraseñas de usuarios. **Rotarlas como parte del DR** — levantar
  en drp con credenciales ya comprometidas es desperdiciar la oportunidad.
- ⚠️ **El árbol tiene ~83.000 archivos con owner ≠ `miniapp`** en axioma (H06). En drp se crea limpio:
  **hacer el `chown -R` correcto desde el inicio** y no heredar el problema.
- Tiene `SESSION_SECRET` además de `JWT_SECRET`: rotarlo invalida sesiones activas.
- Sirve **dos frontends**: el SPA de `mini` y el sitio corporativo de `axioma.ar`. Ambos son estáticos —
  copiar los directorios, no compilar.
- La integración MercadoPago existe en código pero **`mercadopago_config` está vacía**: no está operativa.
  No es una app de pagos.

---

## 🎫 elore — PRIORIDAD 3

| | |
|---|---|
| **Path** | `/var/www/elore` (app Next monolítica) |
| **Usuario** | `eloreapp` (994) |
| **Puerto** | `3700` |
| **Base / rol** | `elore_db` / `eloreuser` · `localhost:5432` **directo** |
| **Dominios** | `elore.com.ar`, `www.elore.com.ar`, **`*.elore.com.ar`** (wildcard) |
| **PM2** | `elore` (`next start -p 3700`) · `--max-old-space-size=384` |
| **RAM medida** | 60 MB daemon (el proceso no apareció en la muestra) |

**Particularidades:**
- ✅ **Repo identificado el 2026-08-12: `git@github.com:AxiomaCloud/Elore.git`, rama `main`.** El clon en
  axioma no tiene el remote configurado, pero el repositorio existe y el acceso está verificado. **Bloqueante
  resuelto.** *Acción: correr `git remote add origin` en `/var/www/elore` para que no vuelva a perderse.*
- 🔴 **Su `ecosystem.config.js` NO está en el repo** — existe solo en axioma, y ahora en
  [`config/axioma/pm2/`](../config/axioma/). **Consecuencia grave:** el repo usa
  `America/Argentina/Buenos_Aires` en el código (`sla.ts`, `business-hours/route.ts`), pero **la TZ del
  proceso la fija el ecosystem**. Desplegar elore solo desde el repo lo arranca en **UTC**, y el horario
  laboral del SLA —que se calcula con `setHours`/`getDay` sobre la TZ del proceso— **queda mal en
  silencio**. No falla: da resultados incorrectos. Es el mismo patrón que mediflow, pero **invisible**.
- **`TZ: 'America/Argentina/Buenos_Aires'` se fija en el ecosystem, antes de arrancar Node.** El horario
  laboral del SLA se calcula con la TZ del proceso (`setHours`/`getDay`), no con `BusinessHours.timezone`.
  **Si se omite, los SLA se calculan mal en silencio** — no falla, da resultados incorrectos.
- El **certificado wildcard** `*.elore.com.ar` requiere validación **DNS-01**, no HTTP-01: `certbot --nginx`
  no alcanza. Necesita el plugin de DNS de Cloudflare y acceso a la API (K8).
- Tiene `.next.bak` en axioma — restos de un despliegue anterior, no replicar.

---

## 💬 evolution-api — PRIORIDAD 4 (terceros)

| | |
|---|---|
| **Path** | `/var/www/evolution-api` |
| **Usuario** | `evolutionapp` (996) |
| **Puerto** | `8080` |
| **Base** | `evolution` (vía `DATABASE_CONNECTION_URI`) |
| **Dominio** | `evolution.axiomacloud.com` |
| **Repo** | `EvolutionAPI/evolution-api` (upstream público) |
| **RAM medida** | **330 MB + 43 MB + 62 MB daemon ≈ 435 MB** — el más pesado después de parse |

**Particularidades:**
- **Software de terceros.** No se compila desde el repo propio: se despliega la versión publicada.
  **Verificar qué versión corre en axioma antes de desplegar otra.**
- Arranca con `tsx` (TypeScript en runtime), no con build compilado.
- Su `AUTHENTICATION_API_KEY` es el `whatsappApiKey` que aparece **filtrado en los logs de mini** (S18):
  rotarlo en el DR.
- Tiene 2 críticas y 15 altas de vulnerabilidades — las más del parque — y **su remediación depende del
  upstream**, no del equipo.
- `evolution-api-out.log` llegó a **246 MB** en axioma con tokens en claro: configurar logrotate desde el
  inicio en drp.
- 👉 **Candidata a NO levantar en la primera hora del DR.** Es la que más RAM pide y la que menos
  bloquea al resto.

---

## 🔌 axio-db-agent — PRIORIDAD 4

| | |
|---|---|
| **Path** | `/opt/axio-db-agent` |
| **Usuario** | `axioapp` (998) |
| **Puerto** | `3005` (loopback) |
| **Arranque** | **`axio-db-agent.service`** — systemd, **no PM2** |
| **Publicación** | nginx → `https://prd.axiomacloud.com/axio-agent` |
| **RAM medida** | 79 MB + 51 MB daemon |

**Particularidades:**
- 🔴 **Accede a 4 bases productivas**: `mini_db`, `mediflow_db` (vía `ALVERA_DATABASE_URL`), `parse_db` y
  `elore_db` — **conectando como el rol owner de cada una**.
- Su control de acceso es un blocklist en variables de entorno (`*_BLOCKED_TABLES`, `*_BLOCKED_COLUMNS`)
  que **no incluye ninguna tabla clínica** (R14, [G8 §5.2.2](./gobierno/g8-clasificacion-datos.md)).
- La unidad systemd tiene hardening: `ProtectSystem=strict`, `NoNewPrivileges`, `ProtectHome`.
  **Replicarlo** — no arrancarlo a mano.
- Auth por header `x-agent-key` (`AGENT_API_KEY`).
- 👉 **Recomendación para el DR: no levantarlo, o levantarlo con el blocklist corregido.** Es un canal de
  acceso a datos de salud cuyo control está pendiente de remediación (**A11**). Un DR es mal momento para
  replicar un problema conocido.

---

## 📁 Estáticos — PRIORIDAD 5

| Sitio | vhost | Origen | Repo |
|---|---|---|---|
| `checkpoint.axiomacloud.com` | `checkpoint` | `/var/www/checkpoint/checkpoint` | `AxiomaCloud/checkpointsite` |
| `axioma.ar` / `www.axioma.ar` | `axioma.ar` | `/var/www/mini/web` | *(parte de mini)* |
| `axiomaweb.axiomacloud.com` | — *(a confirmar)* | — | `rodrigomnaranjo/axioma-corporate` |
| `prd.axiomacloud.com` | `prd.axiomacloud.com` | proxy a `axio-db-agent` | — |

Son copias de directorios más un vhost. **La parte rápida del DR**: sin base, sin build, sin PM2.

> ⚠️ `checkpoint_db` existe en el cluster, así que checkpoint **puede** no ser solo estático.
> **(a confirmar)** antes del primer simulacro.

---

## Huecos conocidos de estas fichas

Se listan explícitamente para que el primer simulacro los cierre, en vez de descubrirlos en un incidente:

1. 🔴 **elore no tiene remote de git.** Sin resolverlo, no se puede recuperar.
2. 🔴 **4 bases sin app identificada**: `axiomadocs`, `chequescloud`, `iasqlassistant_db`, `core_db`.
3. **checkpoint** — usuario, puerto y si consume `checkpoint_db`.
4. **evolution-api** — versión exacta desplegada y su rol de PostgreSQL.
5. **Puerto del backend de mini**: el `.env` dice `8095`, pero el vhost de `mini.axiomacloud.com` no
   declara `proxy_pass` a un puerto. Verificar cómo se sirve realmente.
6. **`GOOGLE_APPLICATION_CREDENTIALS` de parse** — a qué archivo apunta y dónde se respalda.
7. **Certificado wildcard de elore** — requiere DNS-01; confirmar acceso a la API de Cloudflare.

---

*Fichas relevadas el 2026-08-11 desde axioma en vivo · **ninguna ejecutada**. Documento hermano del
[runbook general](./drp-recuperacion-axioma-en-drp.md).*
