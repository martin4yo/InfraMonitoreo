# Hardening de seguridad — infra Axioma

> Hallazgos de la auditoría del 2026-07-17. **axioma** relevado primero; **clubix** y **axiodemo**
> replicados el mismo día (read-only, sin cambios). Comparativa de los 3 al final del doc.
> Los fixes invasivos (SSH, firewall, pg_hba) requieren ventana + OK explícito:
> un error deja el server inaccesible.

## Estado (axioma)

| # | Hallazgo | Sev | Estado |
|---|---|---|---|
| 1 | `pg_hba.conf`: `host all all 0.0.0.0/0 md5` (cualquier IP puede intentar conectar) | 🔴 | ✅ **corregido 2026-07-22**: loopback-only + scram, 0 roles md5, **0 líneas `md5` activas** (residual mediflow cerrado el mismo día) |
| 2 | Sin firewall (`ufw inactive`, iptables ACCEPT sin reglas) | 🔴 | ✅ **corregido 2026-07-17** (ufw default-deny + allowlist) |
| 3 | SSH: `PermitRootLogin yes` (en `sshd_config.d/custom.conf`) + `PasswordAuthentication yes` | 🔴 | ✅ **corregido 2026-07-17** |
| 4 | Puertos de app en `0.0.0.0` en vez de `127.0.0.1` (`:8087` parse-front) | 🟡 | 🟡 parcial 2026-07-20 (`:8087` + netdata → loopback; quedan `:3700`/`:5300`/`:8080`/`:8089`, bloqueadas por patrón Next `-H` — H04) |
| 5 | `.env` con permisos laxos (777/644/664) en vez de 600 | 🟡 | ⚠️ **REABIERTO 2026-07-20** — el cierre del 07-17 era un falso verde (incidente en prod, ver §5); re-auditado en los 5, `.env` de mini/axioma backend ya en 600; pendiente el `chown -R` del árbol de mini (~83k archivos, requiere ventana — H06) |
| 6 | Credenciales R2 en texto plano en `pgbackrest.conf` (+ expuestas en sesión) | 🟡 | ✅ cerrado (2026-07-19): token rotado + `.bak` con creds purgados |

## Bien (no tocar)
- Postgres escucha solo en `127.0.0.1:5432` (mitiga el #1 mientras no cambie `listen_addresses`).
- Apps corren como usuarios dedicados `<app>app` (no root).
- hub con TLS + headers de seguridad + `block-scanners` (molde a replicar).

## Detalle y fix propuesto

### 1. pg_hba.conf `0.0.0.0/0` 🔴 → ✅ CORREGIDO (axioma, 2026-07-22)
La regla `host all all 0.0.0.0/0 md5` permitía intentos de conexión desde cualquier IP; solo la salvaba que Postgres bindea a localhost. **Aplicado**: regla eliminada (queda comentada como evidencia), reglas `host` acotadas a `127.0.0.1/32`/`::1/128` con `scram-sha-256`; `password_encryption = scram-sha-256` + re-hash de todos los roles (**0 con hash md5**). Backup `pg_hba.conf.bak-20260722-100113` + `pg_reload_conf()` (sin restart). Verificado: apps conectando por loopback, 0 auth failures. **Residual cerrado el mismo día (2ª pasada)**: las 2 reglas de `mediflow_db` con método `md5` → `scram-sha-256` (backup + `pg_reload_conf()`), verificada conexión nueva de `mediflowuser` directa (`:5432`) y vía **pgbouncer `:6432`** (mediflow conecta por pgbouncer). **0 líneas `md5` activas** en el pg_hba.

### 2. Firewall ausente 🔴 → ✅ CORREGIDO (axioma, 2026-07-17)
Sin `ufw`/nftables, cualquier puerto que una app abra queda expuesto. Fix: `ufw` default-deny inbound, permitir sólo 22/2222 (SSH), 80, 443, y el 5408 (SSH alterno). **MUY delicado**: habilitar ufw sin permitir SSH primero = perder acceso al server. Orden estricto: `ufw allow <puertos-ssh>` ANTES de `ufw enable`, y con sesión SSH de respaldo abierta.

**axioma hecho**: ufw active, default-deny inbound / allow outbound, allowlist `22, 5408, 80, 443`. Verificado desde afuera: SSH nuevo OK, HTTPS 200, y **5432/19999 bloqueados** (5432 = mitiga en la práctica el #1, aunque falta arreglar el `pg_hba` a nivel config). Servicios decididos sin allow: netdata `:19999` (claimed a la nube, sin uso directo), SNMP `:161` (monitoreo Contabo; collectd habla **saliente** a `200.58.96.51`, no afectado), postfix `:25` (relay-only, `mydestination` sin dominios propios → no recibe mail de apps).
**Gotcha encontrado**: axioma tenía una config ufw **heredada corrupta** (inactive) en `/etc/ufw/user.rules` que abría `5432`, `19999`, `2222` y una IP `200.58.112.191` a todo — daba `ERROR: problem running` al aplicar. Se resolvió con `ufw --force reset` (backup previo `user*.rules.bak-<ts>`) y allowlist limpia.

**clubix hecho (2026-07-17)**: ufw active, default-deny, allowlist `2222, 80, 443` (SSH es **2222**, no 22). Su config ufw heredada estaba sana (solo 2222/80/443, sin 5432), igual se reseteó por prolijidad. Verificado desde afuera: SSH nuevo OK, HTTPS 200, `19999`/`25` bloqueados. netdata claimed a la nube, postfix relay-only (`vps-5969131-x`, sin dominios propios). Postgres ya estaba en loopback.
**Nota de método**: el dead-man switch (`sleep 180 && ufw disable` en background) NO se cancela con `pkill -f "sleep 180"` — mata el árbol de la sesión SSH y corta la conexión (pasó en axioma y clubix, sin consecuencias porque el firewall ya estaba validado). Cancelarlo con el PID exacto, y verificar que no quede ningún `sleep 180`/`ufw --force disable` pendiente reconectando.
Pendiente: axiodemo ya tenía ufw (no requiere acción); auditar/configurar firewall en axioma-drp.

### 3. SSH root + password 🔴
`sshd_config.d/custom.conf` tiene `PermitRootLogin yes` (sobreescribe el `no` del principal) y `PasswordAuthentication yes` → root por fuerza bruta. Fix: `PermitRootLogin no` + `PasswordAuthentication no` (solo llaves). **Delicado**: confirmar que hay acceso por llave funcionando ANTES, y no cerrar la sesión actual hasta validar una nueva.

### 4. Puertos de app en 0.0.0.0 🟡 ✅ PARCIAL (2026-07-20)
`:8087` (parse frontend Next) escuchaba en `0.0.0.0` → accesible salteando nginx (sin TLS/headers/rate-limit). **Corregido**: `HOSTNAME: '127.0.0.1'` en el `env` del ecosystem de parse + restart → `127.0.0.1:8087`, health 200. Funciona porque axioma corre el **build standalone** (`server.js` lee `process.env.HOSTNAME`).

⚠ **El fix NO es universal.** En dev-1 la misma app arranca por el **CLI `next start`**, que ignora `HOSTNAME` y solo respeta el flag `-H` — y **`-H` rompe los redirects de Next** (ver abajo). Mismo ecosystem, distinto binario. `:5408` es `sshd` (SSH alterno), no una app — no tocar.

**Patrón bloqueante de Next.js (verificado en elore `:3700`, revertido):** el flag `-H`/`--hostname` bindea correctamente pero Next lo usa además para armar las **URLs absolutas de redirect** → `307 → https://localhost:3700/login` en vez del dominio público, dejando el login inutilizable. Un `curl` de código HTTP **no lo detecta** (sigue devolviendo 307): hay que inspeccionar el header `Location`. Afecta a las 5 apps Next pendientes (hub ×2, elore ×2, parse dev-1) → resolver una sola vez antes de reintentar.

### 5. `.env` laxos 🟡 ⚠️ REABIERTO — el "corregido" era falso

Eran 777 (mini print-agent/frontend), 664 (mini backend), 644 (mediflow, parse-front, elore, evolution). Todos pasados a `chmod 600` el 2026-07-17.

> **⛔ INCIDENTE EN PRODUCCIÓN (2026-07-20 ~14:17) — el chequeo de este hallazgo estaba mal hecho.**
> El usuario reinició **mini en axioma** y la app dio **error 500: no podía leer su `.env`**. Causa: el
> proceso corre como **`miniapp`** (migración deliberada del **29/06**) pero el `chmod 600` del 17/07 dejó
> el archivo como `axiomacloud:axiomacloud`. El usuario lo destrabó con `chmod 640` a las 14:19 y la app
> levantó (el grupo `miniapp` tiene un solo miembro suplementario, `axiomacloud`, que ya era el owner y
> tiene sudo → **el 640 no expuso las credenciales a nadie nuevo**).
>
> **Los dos errores de método que lo causaron (no repetirlos):**
> 1. **Se verificó solo `dev-1`.** mini también existe en **axioma**, y ese server nunca se miró. El
>    hallazgo se dio por verde con un relevamiento parcial.
> 2. **Se verificó contra el proceso VIVO, no contra el usuario CONFIGURADO.** Un `chmod`/`chown` no
>    rompe un proceso ya corriendo —el descriptor sigue abierto—, así que "la app sigue viva" **no prueba
>    nada**. El fallo aparece recién en el **próximo arranque**: quedó latente 3 días y estalló al primer
>    restart.
>
> **⚠ REGLA CORREGIDA (obligatoria para cerrar este hallazgo).** El owner del `.env` se compara contra el
> usuario **configurado en PM2/systemd** (`pm2 jlist` del PM2_HOME correcto, `User=` de la unit), **app por
> app y server por server** — nunca contra el proceso que casualmente está corriendo. Verificación efectiva:
> `sudo -u <usuario-configurado> test -r <.env>` → debe dar OK. Y con `640`, revisar **`getent group <grupo>`**:
> el modo es aceptable solo si el grupo no suma lectores inesperados.

**Inventario owner-vs-proceso (auditoría 2026-07-20, los 5 servers).** Estado real tras el incidente:

| Server | App | `.env` | Modo | owner:grupo | Proceso corre como | Estado |
|---|---|---|---|---|---|---|
| axioma | **mini backend** | `/var/www/mini/backend/.env` | ~~640~~ **600** | ~~`axiomacloud:miniapp`~~ **`miniapp:miniapp`** | `miniapp` | ✅ **normalizado (2026-07-20)** — era `640 axiomacloud:miniapp` (leía por grupo) |
| axioma | **mini frontend** | `/var/www/mini/frontend/.env` | 600 | `axiomacloud:axiomacloud` | (build) | ⚠️ **bomba latente** si se levanta como `miniapp` |
| axioma | **mini print-agent** | `/var/www/mini/print-agent/.env` | 600 | `axiomacloud:axiomacloud` | (sin proceso) | ⚠️ **bomba latente** |
| dev-1 | **checkpoint-web** | `/var/www/checkpoint-web/.env` | 600 | `axiomacloud:axiomacloud` | `axiomacloud` (viva) + `checkapp` (crash loop) | ⛔ ver sección 7 |
| dev-1 | **axio** | `/var/www/axio/.env`, `backend/.env` | **664** | `axioapp:axioapp` | sin proceso | 🔴 **H06 abierto de verdad: world-readable** en el server de backups |
| dev-1 | mediflow | `/var/www/mediflow/backend/.env` | 600 | `root:root` | `root` | 🟡 coincide, pero **corre como root** (viola el estándar) |
| dev-1 | mini, hub, elore, fitness, parse, tally, core | varios | 600 | `<app>app` | idem | ✅ |
| axioma | mediflow | `/var/www/mediflow/backend/.env` | 600 | `mediflowapp:www-data` | `mediflowapp` | 🟡 owner OK, grupo `www-data` raro |
| axioma | hub, parse, elore, evolution-api | varios | 600 | `<app>app` | idem | ✅ |
| clubix / axiodemo | clubix, axio | varios | 600 | `<app>app` | idem | ✅ |

**Pendientes de este hallazgo:** ~~(1) `axio/.env` 664 → 600 en dev-1~~ ✅ **hecho (2026-07-20)** — resultaron **7 archivos** en `664`, no 2 (incluidos `.env.example` de 2588 y 2037 bytes, demasiado grandes para plantillas vacías) → todos a `600 axioapp:axioapp`, con respaldo en `/root/env-bak/` (`700` root-only). Control negativo verificado: `sudo -u hubapp test -r` → **NO_LEE** (antes, con `664`, lo leían los 8 usuarios de apps de dev-1). Sin riesgo de bomba: el owner **ya era** el usuario configurado. ~~(3) `chown miniapp:miniapp` + 600 del backend de mini~~ ✅ **hecho (2026-07-20)** — `600 miniapp:miniapp`, sin corte. Quedan: (2) las 2 bombas latentes de mini en axioma (se resuelven junto al `chown -R` del árbol — **~83k archivos**, requiere ventana); (4) mediflow: sacar de root (dev-1) y normalizar grupo (axioma); (5) `ecosystem.config.js` de axio en dev-1 sigue en `664`.

### 8. `axio-db-agent` — dónde vive realmente y su `.env` en `644` (2026-07-20)

Relevado a raíz de una pregunta del usuario: el **db-agent** provee a axiodemo los diccionarios de datos y ejecuta queries contra las apps tenant.

**Arquitectura real (corrige la suposición de que se instala "en los servidores de las aplicaciones"):** hay **un solo agente**, en **axioma**, en `/opt/axio-db-agent` — **NO** en `/var/www/axio/db-agent`. Corre por `axio-db-agent.service` (`enabled`+`active`, `User=axioapp`, con hardening `ProtectSystem=strict`/`NoNewPrivileges`/`ProtectHome`), **uptime desde 2026-06-27 sin reiniciar**. Bindea **`127.0.0.1:3005`** y se publica vía nginx en `https://prd.axiomacloud.com/axio-agent` → **no requiere regla ufw para 3005** (el README sugiere abrirlo; el despliegue real eligió el proxy HTTPS, más seguro). Auth por header `x-agent-key`; `curl 127.0.0.1:3005/health` → 401 (vivo). Cubre **4 apps configuradas** (`clubix`, `mini`, `alvera`, `parse`) con `APPS=clubix, mini, alvera` habilitadas. Registrado en la tabla `hub_agents` de `axio_ml` (axiodemo) con `status: online` y heartbeat al día — nombre `"Servidor Clubix"`, **engañoso: el agente corre en axioma**. En clubix y axiodemo **no existe** el agente.

🔴 **Hallazgo → ✅ CERRADO (2026-07-20).** `/opt/axio-db-agent/.env` estaba en **`644`** (world-readable) con **4 `DATABASE_URL` de producción + 2 API keys**. Mismo agujero que el de dev-1 pero con las credenciales de las bases reales. **Pasado a `600 axioapp:axioapp`** (`.env.example` de `664` a `640`), con respaldo en `/root/env-bak/`.

Aplicada la **regla corregida**: se comparó el `User=axioapp` **declarado en la unit systemd** contra el owner del archivo **antes** de tocar — coinciden, por eso no había bomba latente (en mini era al revés). Refuerzos verificados: la unit **no usa `EnvironmentFile=`** (el `.env` lo lee el propio proceso Node vía `dotenv`, ya como `axioapp`), el sandbox `ProtectSystem=strict` tiene `ReadWritePaths=/opt/axio-db-agent`, y **`getent group axioapp` está vacío** → el `644` no daba acceso por grupo a nadie: el bit `other` era el único acceso real, y se lo daba a **todo usuario del server**. Control negativo: `hubapp` y `www-data` → NO_LEE. Integración intacta (heartbeat 18s después del cambio, `error_count=0`).

**Rename `"Servidor Clubix"` → `"Agente Axioma"` (2026-07-20).** El rótulo era engañoso (el agente corre en axioma). Datos del relevamiento previo, útiles para futuros cambios de config del agente:
- **El upsert contra el hub es por `agent_url`**, NO por `server_name` (`ml-service/main.py:2343`) → renombrar es seguro, no duplica la fila. ⚠ **Tocar `AGENT_PUBLIC_URL` sí crearía un registro nuevo y dejaría el viejo huérfano.**
- `hub_agents` **no tiene UNIQUE** sobre `server_name` ni `agent_url` (el upsert es lógica de aplicación, no constraint). La fila `id=1` está referenciada por `hub_alerts.agent_id` (`ON DELETE SET NULL`) → no borrarla y recrearla.
- El **heartbeat no pisa `server_name`**, pero **el registro del arranque sí** → un `UPDATE` directo en la DB se revierte en el próximo restart. La fuente de verdad es el `.env`.
- **`SERVER_NAME` se captura una sola vez al arrancar** (`index.js:19`), sin reload en caliente → **el rename exige restart**.
- El nombre es **cosmético** (panel admin): `grep "Servidor Clubix"` en la app de axiodemo → 0 resultados; nada depende del literal.

**`/var/www/axio` en dev-1 = clone abandonado, candidato a baja.** Es una copia completa del repo de la app (no del agente), congelada el **2026-05-14**: sin un solo `node_modules`, sin `dist/`, sin `package-lock.json`, con un `ecosystem.config.js` de una versión que axiodemo ya abandonó. No corre ni puede correr; no participa de la integración (dev-1 no aloja DB de ninguna app tenant). **No es una integración rota: el agente nunca fue diseñado para correr ahí.** Antes de borrar: preservar `/var/www/axio/backups/` (dump `backup_axio_ml_20260412.sql` + tar del ml-service) y **cifrar los `.env` con credenciales reales** (Gemini, Anthropic, JWT, Parse API) a `infra-secrets`. El borrado es invasivo → regla de oro.

**Hallazgo mayor asociado — directorios en `777`.** `/var/www/mini` y subdirectorios estaban en `drwxrwxrwx` en **axioma y dev-1** (**~90 dirs por server**, no 4). El `.env` en 600/640 protege el *contenido*, pero **manda el permiso de escritura del directorio**: cualquier usuario local podía **borrar o sustituir** ese `.env`. **Pesaba más que el hallazgo original.**

> **✅ dev-1 NORMALIZADO + MIGRADO A `miniapp` (2026-07-20).** El usuario pidió que mini corra como `miniapp` en ambos servers; en dev-1 corría como `axiomacloud` → migración completa (no es un `chmod`).
>
> **Resultado dev-1:** proceso `miniapp` (God Daemon propio en `/home/miniapp/.pm2`, `pm2-miniapp.service` enabled), árbol entero en **`750 miniapp:miniapp`** con `find -not -user miniapp` **vacío**, `.env` ×3 en `600 miniapp:miniapp`, `uploads`/`backend/logs` en 750. Health 200 local + por los 2 dominios públicos, **`restart_time`=0 estable tras 70s**. `checkpoint-web` (que comparte el God Daemon viejo) **intacto**. Load del server **0.08**.
>
> **⚠ Hallazgo que casi rompe la migración — `/var/log/mini` está FUERA de `/var/www`.** Era `755 axiomacloud` y el ecosystem de dev-1 escribe ahí (`out_file`/`error_file`). Sin `chown miniapp:miniapp /var/log/mini`, **PM2 no puede escribir los logs y la app no arranca**. Se detectó en el relevamiento, antes de ejecutar. **Regla: al migrar de usuario, el `chown` debe cubrir los paths de log declarados en el ecosystem, no solo el árbol de la app.**
>
> **Riesgo #1 controlado — nginx.** `/var/www/mini`, `frontend/` y `frontend/dist/` deben quedar en **`755`** (traverse + lectura de `www-data`); el resto en 750. Un `750 miniapp:miniapp` en esas 3 rutas **tira el sitio**. Verificado con `sudo -u www-data test -r .../dist/index.html` en la misma pasada del chmod.
>
> **Dos gotchas reproducibles:** (1) tras migrar a usuario dedicado, los comandos PM2 hay que correrlos **desde un cwd neutro** (`/tmp`) — el primer `pm2 start` falló con `spawn EACCES` porque se ejecutaba parado en `/home/axiomacloud`, que `miniapp` no puede atravesar (mini estuvo caída ~1 min); (2) `chown -R` **no sigue symlinks**: 80 symlinks de `node_modules/.bin` quedaron con el owner viejo → normalizar con `chown -h`.
>
> **axioma: solo el `.env` del backend** (`640 axiomacloud:miniapp` → **`600 miniapp:miniapp`**, sin corte, metadata pura). **El `chown -R` del árbol queda PENDIENTE de ventana: mini en axioma ES productiva.**

**Deploy de mini como `miniapp` — verificado viable (axioma).** El usuario pasa a desplegar con `sudo -u miniapp git -C /var/www/mini pull`. `miniapp` tiene **deploy key propia** (`/home/miniapp/.ssh/id_ed25519`, no depende del home de `axiomacloud`), `ls-remote` rc=0 y GitHub autentica. Origin: `git@github.com:martin4yo/AxiomaWeb.git` (**SSH**; el nombre del repo no es "mini" pero es el correcto y activo — no se repite el caso H12 de axio→ProHub). `safe.directory` ya configurado. En **dev-1 no existe `.git`** (el deploy no es por git) y `miniapp` **no tiene `~/.ssh`** ahí.

⚠ **Riesgo para el próximo `git pull` en axioma:** hay **uploads de usuarios reales sin trackear dentro del working tree** (logos, `products/product-*.webp`, imágenes de WhatsApp). Un `git clean -fd` **los borraría**. Sacarlos del árbol o agregarlos a `.gitignore`.

**Archivos sueltos con bits laxos (pendiente).** En dev-1 quedaron con bits 777 propios pero **contenidos por directorios en 750** → inocuos en la práctica (nadie los atraviesa). En **axioma siguen expuestos** hasta la ventana: `.env.local`, `.env.production` (777), `IIBB_*.txt`, `.xlsx` de comprobantes, `consola.log`, y **`/var/www/mini/.claude/`** con `memory.md`, `settings.local.json` y un **`worktrees/agent-a59cf71a` dentro del árbol de producción**. Ninguno es alcanzable por HTTP (el vhost sirve desde `frontend/dist`, un nivel abajo; axioma además bloquea dotfiles) — la exposición es **local**.

**⚠ uid dispares:** `miniapp` es **1002 en axioma** y **1005 en dev-1**. No afecta la operación normal, pero un `rsync -a`/restore cruzado entre servers asignaría owners equivocados.

### 7. `checkpoint-web` (dev-1) — migración a `checkapp` abandonada + crash loop 🔴 ✅ CONTENIDO

Detectado al investigar el incidente de mini. **Migración iniciada el 23/01/2026 y nunca terminada**: el árbol `/var/www/checkpoint-web` ya es `checkapp:checkapp` (755) y `pm2-checkapp.service` está `enabled`, pero **el `.env` quedó en `axiomacloud:axiomacloud` 600** → `checkapp` **NO_LEE**.

Consecuencia: la instancia `checkapp` **nunca llegó a bindear** y estuvo en **crash loop `restart_time=108455` (~24 reinicios/minuto durante 3 días)**, costando **~0.6 de load sostenido** en dev-1 — la caja que aloja los backups de toda la infra. El sitio nunca se cayó: lo sirve la instancia vieja (`axiomacloud`, pid 1817, `:8086`, nginx `proxy_pass localhost:8086`).

**✅ Contenido (2026-07-20 15:21):** `pm2 stop checkpoint-web` + `pm2 save` en el PM2_HOME de `checkapp` (no revive al reboot). Verificado: `restart_time` congelado tras 95s, sitio intacto (307 local / 200 público en 3 lecturas), **load 1m 1.50 → 0.88 (−41%)**. Rollback: `pm2 start checkpoint-web` en `/home/checkapp/.pm2`.

**Nota:** no se pudo probar que la causa fuera *solo* el `.env` — el stderr real no queda registrado. Hipótesis viva adicional: `EADDRINUSE` por el `:8086` ocupado por la instancia vieja. Probablemente ambas → arreglar solo el `.env` no alcanzaría.

**Decisión pendiente del usuario: completar la migración o abortarla.** Si se completa, antes hay que hacer `chown -R checkapp:checkapp` — hay **archivos `root:root` sueltos** (`.next/`, `package-lock.json`, `next.config.ts`, `public/`, `scripts/`…). Revisar aparte `cookies.txt` y **`backup_checkpoint_db.sql`** (dump de base) dentro del directorio servido por la app.

### 9. Credenciales en texto plano dentro de los LOGS de aplicación 🔴 (2026-07-20)

Detectado al investigar por qué el log de mini en axioma pesaba 130 MB. **Es un riesgo de clase, no un caso puntual**: los logs se tratan con permisos mucho más laxos que un `.env` (`664` vs. `600`), se copian a backups, se mandan a soporte y se pegan en tickets — pero pueden contener exactamente los mismos secretos.

**Causa: `console.log` que vuelcan objetos enteros.** Ningún punto loguea una credencial a propósito; viajan como campos dentro del objeto. En mini (`/var/www/mini/backend`):
- `src/middleware/validateRequest.ts:7` → `console.log('[VALIDATE] ...', req.body)` — **middleware genérico en el camino caliente de todos los requests**: en un alta de usuario, `req.body` trae la contraseña **en claro, pre-hash**.
- `src/middleware/validateRequest.ts:9` → la imprime **otra vez** (`validated`).
- `src/routes/tenants.ts:154` → vuelca el objeto `settings` completo, con `smtpPass` y `whatsappApiKey`.

**Qué se filtró (axioma):** `whatsappApiKey` de **Evolution API** (instancia `laslomas` — el endpoint corre en el mismo server), `smtpPass` de **Gmail** (`info.viverolaslomas@gmail.com`, app-password), y **12 contraseñas de 4 usuarios** de `nutriarroz`. Alcance temporal acotado: las contraseñas son de **77 segundos del 2026-07-07** (un alta masiva). También 1.421 CUIT/DNI y 208 emails (PII). Los 1.737 números que parecían tarjetas son **CAE de AFIP** — falso positivo descartado.

**Exposición real:** el log es `664` pero `/home/miniapp` está en `750`, que corta el traverse → hoy solo `miniapp` y root llegan. **Defensa frágil**: un `chmod 755` del home expondría todo a los 8 usuarios de apps del server. Mismo patrón que H06 (archivo protegido solo por el permiso del directorio padre).

**Panorama por app** (barrido parcial): **mini** (winston SIN redacción, 7 volcados) y **hub** (winston SIN redacción, 2 volcados) son los casos a corregir; mediflow, parse, axio y elore ya redactan o no vuelcan. Aparte, `evolution-api-out.log` en axioma (**246,7 MB**) tiene `token` ×14 y `password` ×3 — es software de terceros, el fix es de verbosidad, no de código propio.

**Fix (repo de la aplicación, NO infra — lo hace quien mantiene mini):** (1) borrar o condicionar los 3 `console.log`; (2) **estructural**: centralizar en winston con lista de redacción (`password`, `smtpPass`, `whatsappApiKey`, `token`, `apiKey`, `secret`, `authorization`) — sin esto, el próximo `console.log(req.body)` reintroduce el problema. **Rotar el log NO lo arregla.**

**Credenciales a rotar, priorizadas:** (1) `whatsappApiKey` de Evolution — da control sobre el WhatsApp del cliente; (2) `smtpPass` de Gmail — permite enviar correo en su nombre (phishing); (3) contraseñas de los 4 usuarios de `nutriarroz`. **Rotar ANTES de truncar el log**, que es la evidencia del alcance.

**Hallazgo colateral (para el repo de mini):** el frontend poletea `GET /api/<tenant>/mercadopago/recent-payments` **cada 15 s** (mediana medida) por tenant y pestaña → **152.633 requests en 47 días desde 9 tenants**, y la tabla `mercadopago_config` está **completamente vacía**: el **100% del tráfico es inútil** y golpea la DB para devolver vacío. La guarda natural es no montar el polling si el tenant no tiene fila activa; existe `src/routes/mercadopago-webhooks.ts` como reemplazo correcto.

### 10. Rotación de logs 🟡 ✅ DESPLEGADA (2026-07-20)

**No había ninguna rotación en los 5 servers** (ni `logrotate.d` ni el módulo `pm2-logrotate`). Se eligió **logrotate nativo con `copytruncate`** sobre `pm2-logrotate`: no toca el God Daemon de PM2, no requiere reload, y el rollback es borrar un archivo. Config versionada en [`logrotate/`](../logrotate/) (una por server) — `daily`, `rotate 7`, `compress`+`delaycompress`, `su <user> <group>`, `create 640`.

**⚠ Hallazgo central — `~/.pm2/logs/*.log` NO alcanza.** El stdout real de las apps va a **`~/.pm2/pm2.log`**, un nivel arriba. Un inventario de `logs/` da el relevamiento por completo y deja sin rotar el archivo que importa: en dev-1 había un **`pm2.log` de 2,07 GB** (el mayor de la infra, 9× el de evolution-api), alimentado por los **1.117.267 arranques** del crash loop de checkpoint-web. **Se detecta con `/proc/<pid>/fd/1`**, que muestra a dónde apunta realmente el descriptor de salida.

**⚠ Criterio de verificación corregido.** "Archivo activo en 0 bytes tras 60 s" **NO prueba que `copytruncate` falló** — puede ser simplemente que la app no emite stdout. La prueba concluyente es **escribir al descriptor**: `echo TEST >> /proc/<pid>/fd/1` y confirmar que el archivo crece. Con el criterio ingenuo se revertirían rotaciones correctas y se reiniciarían apps sanas.

**Otros gotchas:** logrotate **ignora en silencio** cualquier config writable por grupo/otros → los archivos van `644 root:root`. Los globs `/home/*/...` **no sirven** acá: los dirs `.pm2` son `775` y logrotate exige `su`, que no puede declararse por usuario en un glob → configs específicas por server. Y **`create` no aplica con `copytruncate`** (trunca el existente, no crea uno nuevo): el `640` rige sobre los rotados, los activos necesitan `chmod` explícito.

**Estado:** desplegado y verificado en los 5. dev-1 con rotación forzada (2,07 GB copiados en 59 s, apps en 200, `restart_time` sin cambios, fd verificado sano); axioma y el resto rotan naturalmente a las 00:00. **mini en axioma queda EXCLUIDO** (bloque comentado) hasta que se roten las credenciales del §9. Espacio recuperado: **0 hoy** por `delaycompress` — los ~2,2 GB de dev-1 se liberan en la corrida siguiente. ✅ **Verificado 2026-07-22** (dev-1): la rotación corrió las 00:00 del 21 y del 22, con compresión aplicada (`pm2.log.2.gz`, `.3.gz` con los 46M viejos) y `logrotate.status` al día.

### 6. Credenciales R2 🟡 → ✅ TOKEN ROTADO (2026-07-17)
`repo2-s3-key-secret` + `repo2-cipher-pass` en texto plano en `/etc/pgbackrest/pgbackrest.conf`; además se expusieron en una sesión el 2026-07-17. **Hecho**: rotado el API token R2 (viejo `a8790e48…` borrado en Cloudflare, nuevo `b47676fd…` aplicado en los **5 archivos** con backup), verificado con `pgbackrest check` en las 4 stanzas; `cipher-pass` conservado; credenciales cifradas en `infra-secrets/env/pgbackrest/repo2-r2.env` (SOPS). Ver `pgbackrest-setup.md`. **Cerrado (2026-07-19, H03 del plan de remediación).** Se evaluaron las 3 opciones (mantener+endurecer / archivo dedicado `600` vía `config-include-path` / variables `PGBACKREST_*`) y se eligió **mantener en el `.conf` + endurecer**: pgBackRest siempre necesita el secreto en claro en ejecución, así que mover a otro archivo owner-only es ganancia marginal frente a editar 5 configs productivas, y las env vars serían **peores** (legibles en `/proc/<pid>/environ`).

La superficie real no eran los `.conf` (ya en `640`, grupos de un solo miembro, no versionados) sino **4 archivos `.bak` con las claves S3 pre-rotación** — incluidos los backups que dejó la propia rotación del 17-jul. Se verificó por hash que su `repo2-cipher-pass` era **idéntico al vivo** (el cipher NO se rota; perderlo haría irrecuperables los backups R2), se respaldaron en `/root/pgbackrest-bak-archive/*.tar.gz` (`600` root-only) y se borraron. Resultado: **0 `.bak` en los 5 servers**, `.conf` en `640`, `pgbackrest check` OK en las 4 stanzas (repo1+repo2).

**Límite aceptado y documentado:** las creds siguen en texto plano en los `.conf` que lee pgBackRest (protegidas por `640` + owner + firewall); la fuente de verdad cifrada es SOPS. **Regla operativa:** al rotar creds, no dejar `.bak` con el valor viejo.

---

> **📌 Nomenclatura: `alvera` = `mediflow`.** La app se llama **alvera**; `mediflow` es el nombre anterior,
> **conservado a propósito** en la infraestructura (renombrar base, rol y systemd en producción tiene más
> riesgo que beneficio). El rename llegó a los **dominios y vhosts** (`alvera.axiomacloud.com`,
> `alvera.com.ar`) y a la config del `axio-db-agent` (`ALVERA_DATABASE_URL`), y **se detuvo ahí**: siguen
> como `mediflow` el directorio `/var/www/mediflow`, el usuario `mediflowapp`, la unidad
> `pm2-mediflowapp.service`, la app PM2 `mediflow-backend`, la base `mediflow_db` y el rol `mediflowuser`.

### 11. Relevamiento in-situ con acceso restaurado — 4 hallazgos nuevos (2026-08-09) 🔴

Primer relevamiento **contra los servers** desde que se compiló el dossier. Los cuatro hallazgos tienen algo
en común: **ninguno era deducible leyendo el repo**, y tres contradicen algo que este documento afirmaba.

**11.1 🔴 Llaves del proveedor de hosting en la cuenta de operación de dev-1.**
`/home/axiomacloud/.ssh/authorized_keys` de dev-1 tiene **53 entradas, 48 de ellas `@donweb.com`** — y
`axiomacloud` tiene **`sudo` sin contraseña**. Sin `from=` ni `command=`. En `/root/.ssh/authorized_keys`
hay además ~43 llaves de donweb en **axioma (46), clubix (43) y dev-1 (43)**; **axiodemo tiene 0**, lo que
prueba que un server puede operar sin ellas. Las de `root` están **inertes** por `PermitRootLogin no` — el
fix del 2026-07-17 les cortó el acceso sin que quedara registrado ese efecto colateral. Las de dev-1 **no**.
**Uso confirmado en `auth.log`:** `santiago.fernandez@donweb.com` autenticó como root el **2026-07-14 a las
11:29 y 12:32** desde `200.58.112.191`, y `lastlog` marca otro acceso el **2026-06-11 02:39**. Sin evidencia
de exploración interactiva (el `bash_history` de root, continuo de enero a agosto, no tiene comandos el
13–15 de julio), pero eso **no descarta** acceso a datos: `ssh host <cmd>` y `scp` no dejan rastro ahí.
→ **R20** en G3 · [G8 §4.2](./gobierno/g8-clasificacion-datos.md).

**11.2 🔴 Cambio de `sshd` escrito y nunca aplicado — habilitación latente de password auth.**
El 2026-08-09 20:54 se creó `/etc/ssh/sshd_config.d/99-temp-password-axiomacloud.conf` en los **4 servers**
con `Match User axiomacloud` + `PasswordAuthentication yes`. **Nunca tomó efecto**: `sshd` no se recargó
(activo desde jul-14 / jul-16 / jul-17 / ago-01) y `sshd -T` sigue devolviendo `passwordauthentication no`.
El archivo **sigue en disco**: el próximo `reload`, actualización de OpenSSH o reboot lo activa en silencio,
con una contraseña ya expuesta. **Un cambio que no se aplicó es más peligroso que uno que sí, porque nadie
lo está mirando.** *Fix:* borrar el archivo, no confiar en no recargar. → **R18**.

**11.3 ⚠️ Existe un segundo `axio-db-agent`, en clubix.**
El §8 de este documento afirma: *"hay **un solo agente**, en **axioma**… En clubix y axiodemo **no existe**
el agente."* Es falso desde el **2026-07-24**: clubix tiene `/opt/axio-db-agent` **`enabled` y `active`**,
con `SERVER_NAME="Servidor Clubix"` y acceso a `clubix_db`. Se desplegó **un día después de entregar el
dossier al auditor** — no es un error del relevamiento, es **deriva post-entrega** de un canal de acceso a
datos que no quedó registrado en ningún lado.

**11.4 🔴 El blocklist del `axio-db-agent` no protege los datos que debía proteger.**
Verificado en el `.env` del server: `BLOCKED_TABLES = admins, admin_tokens, tenant_configuracion,
configuracion, audit_log, sessions` y `BLOCKED_COLUMNS = password, token, tokenPortal, apiKey, secret,
hash`. **Idéntico en las 5 configuraciones** (`MINI_`, `ALVERA_` → `mediflow_db`, `PARSE_`, `ELORE_` en axioma;
`CLUBIX_` en clubix): nunca se escribió un blocklist por aplicación. Protege **el sistema**, no a las
personas — **ninguna tabla clínica figura en la lista**, y las historias clínicas quedan legibles hasta
`MAX_ROWS=1000` por consulta. El agente conecta como **`mediflowuser`**, que por el estándar es **owner de
la base y de todos sus objetos**, y es el rol de la contraseña débil de 8 caracteres (R06).
→ **R14** · [G8 §5.2.2](./gobierno/g8-clasificacion-datos.md).

## Comparativa 5 servers (2026-07-17)

| # | Hallazgo | axioma | clubix | axiodemo | axioma-drp | dev-1 |
|---|----------|--------|--------|----------|------------|-------|
| 1 | pg_hba / listen | 🟢 ✅ **loopback + scram (fix 2026-07-22)**, bind localhost, 0 líneas `md5` (residual mediflow cerrado el mismo día) | 🟢 deny + scram, `listen=localhost` | 🟡 acotado + scram, `listen='*'` (lo salva ufw) | ⬜ sin Postgres | 🟢 `listen=localhost`, solo loopback + scram |
| 2 | Firewall | ✅ ufw active, allow 22/5408/80/443 | ✅ ufw active, allow 2222/80/443 | 🟢 ufw active + allowlist | ✅ **ufw active** allow 22/80/443 (fix 2026-07-17) | ✅ **ufw active** allow 22/5782/80/443 + snmp 161 solo dattaweb (fix 2026-07-17) |
| 3 | SSH root/password | 🟡 `sshd -T` OK, pero con `99-temp-password…conf` latente (§11.2) | 🟡 ídem | 🟡 ídem | ✅ root+pass `no` (homologado) | 🟡 ídem (fix 2026-07-17) |
| 3b | **Llaves en `authorized_keys`** *(nuevo 2026-08-09, §11.1)* | 🟡 root **46** (43 donweb, inertes) · axiomacloud 6 | 🟡 root **43** (44 donweb, inertes) · axiomacloud 8 | 🟢 root **0** · axiomacloud 5 | ⬜ no relevado (22 filtrado) | 🔴 **axiomacloud 53, 48 de donweb, con sudo sin password** · root 43 |
| 4 | App en `0.0.0.0` | 🟡 `:8087` ✅ **loopback (2026-07-20)**; netdata ✅ loopback. Quedan `:3700` elore, `:8089` hub, `:8080` evolution-api, `:5300` mediflow | 🟡 19999, 25 | 🟡 `:5300` axio-back (needs código), `:8001` axio-ml **excepción aceptada** (dev-1 lo consume remoto); netdata ✅ loopback | 🟡 sshd + netdata `:19999` en `0.0.0.0` (tapado por ufw — relevado 2026-07-22; netdata se instaló post-foto del 07-17) | 🟡 **firewall tapa todo** (fix 2026-07-17). ✅ **CUPS `:631` deshabilitado + netdata loopback (2026-07-20)**. Quedan `:3000` elore, `:8087` parse, `:8089` hub (bloqueadas por patrón Next `-H`), `:8086`/`:5000` (needs código) |
| 5 | `.env` laxos | ✅ 600 | 🟢 600 | 🟡 `axio*/.env` 664 | ⬜ sin apps | 🟡 mini **777→600 ✅ (fix 2026-07-17)**; quedan varios 644/664/755 |
| 6 | pgBackRest R2 claro | ✅ rotado + `.bak` purgados | ✅ | ✅ | ⬜ sin pgBackRest | ✅ rotado + `.bak` purgados (640 OK) |

Puerto SSH: axioma 22+5408 · clubix **2222** · axiodemo 22 · axioma-drp 22 · **dev-1 22+5782**.

**Objetivo SSH homogéneo (pedido del owner):** acceso solo por `axiomacloud`, sin root =
`PermitRootLogin no` + `PasswordAuthentication no` + `PubkeyAuthentication yes`.
✅ **CUMPLIDO en los 5 (2026-07-17)**. Patrón: verificar pubkey de `axiomacloud` antes de apagar password,
fix vía drop-in `sshd_config.d` (`sshd -t` + `reload`, no restart), validar sesión nueva + rechazo de password
sin cerrar la de respaldo. En axioma/clubix/**dev-1** el `yes` venía de `custom.conf` (se corrigió ese archivo);
en axiodemo de `50-cloud-init.conf`. Drop-in de hardening ordena `00-` para ganar. En dev-1 **no** se tocó
`80-step.conf` (CA Smallstep) ni la confianza SSH con los db hosts; verificado con `pgbackrest check` post-fix.

### dev-1 (149.50.148.198) — NO es "solo test": es el server más sensible
**Repo host central de pgBackRest** (backups+WAL de los 4 servers + escribe a R2) **Y** server multi-app
cargado (15+ apps Node/Next de 8 usuarios, nginx, Docker, CUPS). Cualquier app vulnerable corre en la misma
caja que `/backup/pgbackrest`. Tenía brute-force SSH activo (185 baneos / 1459 fallos). **Bien**: pg_hba/listen
acotados, y permisos pgBackRest correctos (`pgbackrest.conf` 640, `/backup/pgbackrest` 750, netdata sin acceso
a los secretos). Los 🔴 iniciales tras el fix SSH (3 `.env` de mini en 777, firewall ausente) se cerraron el
2026-07-17 (P1/P2 abajo). **Pendientes vigentes (mitigados por el fw)**: snmpd community `public` (H09,
bloqueado por dattaweb), apps Node/Next en `0.0.0.0` (H04, patrón `-H`/redirects + 3 que requieren cambio de
código). Ver "Pendientes dev-1" abajo.

### axioma-drp (170.78.75.249) — server bare + **REINSTALADO 2026-08-08, rearmado 2026-08-11**

> 🔴 **Se reinstaló el sistema operativo el 2026-08-08** (boot 23:28 UTC), sin aviso ni registro previo.
> **Todo el hardening del 2026-07-17/07-20 se perdió.** Detectado el 2026-08-11 al fallar el acceso SSH
> (la llave no estaba en el server). Estado encontrado: `ufw` **desinstalado**, `fail2ban` en **failed**,
> Netdata/pgBackRest/PostgreSQL **ausentes**, disco de vuelta en **12 G**, `PasswordAuthentication yes` +
> `PermitRootLogin without-password`, y la password de `linuxadmin` **desbloqueada** (el `passwd -l` se
> perdió). **Lección**: este server no está bajo ninguna gestión de configuración — cualquier reinstalación
> del proveedor lo devuelve a fábrica y no hay quién lo detecte. Ver gap abierto al final de la sección.

**Rol (sin cambios): banco de pruebas de DRP _por aplicación, de a una_** — NO réplica de infra completa.

Rearmado completo el **2026-08-11**, todo verificado en vivo:

- ✅ **Llave ajena eliminada**: `mfourgeaux@KEYSOFT-I7` (`SHA256:K/yJkjhyAQ/hO2WS9ybqZc6/eR0j6VFGRxL6WJoC1ko`)
  **sobrevivió a la reinstalación** en el `authorized_keys` de `linuxadmin` — es decir, venía en la imagen de
  provisioning del proveedor, no era un resto local. Purgada de `linuxadmin` y de `axiomacloud`
  (backups `.bak-<ts>`). Hoy ambos tienen **solo** `axiomacloud@keysoft-i5`.
- ✅ **Usuario `axiomacloud` creado** (uid 1002, grupo sudo, `NOPASSWD` en `/etc/sudoers.d/90-axiomacloud`),
  alineado con los otros 4 servers y con lo que declara `inventory.sh`. Los scripts del repo ya corren acá
  sin editar el inventario. `linuxadmin` queda como **acceso de emergencia** (password activa, sudo con
  password). **Desvío deliberado respecto de julio**: NO se re-aplicó `passwd -l` a `linuxadmin`, porque sin
  `NOPASSWD` eso deja la cuenta de emergencia sin poder autenticar `sudo` — el objetivo de H10 (cortar el
  brute-force) lo cumple `PasswordAuthentication no`, que es más fuerte y no tiene ese efecto lateral.
- ✅ **SSH homologado**: drop-in `/etc/ssh/sshd_config.d/99-hardening.conf` con `PermitRootLogin no` +
  `PasswordAuthentication no` + `PubkeyAuthentication yes` + `KbdInteractiveAuthentication no`. `sshd -t` OK,
  aplicado con `reload` (no restart). Verificado desde sesión nueva: llave entra, password y root **rechazados**.
- ✅ **Password de root definida** (2026-08-11) para que `su -` funcione como en los otros 4 (root estaba en
  `L`/bloqueada desde el provisioning 2022, herencia de la imagen). Solo sirve por consola local: root
  sigue cerrado por SSH.
- ✅ **Disco reampliado, en dos pasadas** (misma cadena LVM online las dos veces: backup de tabla de
  particiones → `growpart /dev/sda 3` → `pvresize` → `lvextend -l +100%FREE` → `resize2fs`, sin reboot).
  Primero **12 G → 51 G** sobre el disco de 55 G que dejó la reinstalación (la reinstalación había revertido
  también el tamaño del VPS, que en julio era de 64 G). Después se agrandó el VPS a **70 G** y se repitió la
  cadena: **51 G → 66 G** (54 G libres). VG sin espacio remanente. Backups en
  `/root/sda-parttable.bak-*.sfdisk`.
- ✅ **ufw reinstalado y activo**: default deny incoming / allow outgoing, allow 22/80/443 (v4 y v6),
  `enabled` al boot. SSH verificado vivo después de habilitarlo.
- ✅ **fail2ban arreglado** (mismo fallo que en julio: `Have not found any log file for sshd jail`, porque el
  server usa journald y no tiene `/var/log/auth.log`). `jail.local` con `backend = systemd` + jail sshd
  puerto 22 + `ignoreip` con las 5 IPs de la infra. `fail2ban-client -t` OK, servicio `active`, leyendo del
  journal (enganchó 2 intentos fallidos en el primer minuto).
- ✅ **Netdata reinstalado + claimed**: v2.10.4 stable (igual que los otros 4), reclamado al mismo Space/Room,
  `Claimed: Yes` + `Online: Yes`. `bind to = 127.0.0.1` (ACLK es saliente por 443) y override
  `hostname = axioma-drp` en `netdata.conf`, ambos en bloques marcados idempotentes. Backup `.bak-<ts>`.
  ⚠ El kickstart imprime `Failed to write claiming configuration` como warning — es **falso**: el claim se
  escribió bien, confirmar siempre con `netdatacli aclk-state`.
- ✅ **PostgreSQL 14.23 + pgBackRest instalados** desde PGDG (`postgresql-14`, `pgbackrest`). PG `active`.
  ⚠ **pgBackRest quedó en 2.59.0, no 2.58.0** como los otros 4: PGDG ya no sirve 2.58.0. No es problema para
  el rol de drp (lee S3 directo, sin protocolo SSH contra el repo host, y 2.59 lee repos escritos por 2.58).
- ✅ **pgBackRest apuntado a R2 y verificado**: `/etc/pgbackrest/pgbackrest.conf` (640 `postgres:postgres`)
  con **repo1 = Cloudflare R2** (bucket `axiomacloud-pgbackrest`, path `/pgbackrest`, `aes-256-cbc`),
  stanza `AxiomaCloudProd` con `pg1-path=/var/lib/postgresql/14/main`. `pgbackrest info` devuelve
  **`status: ok`** y la cadena completa, con el último incremental del **2026-08-11 18:00 UTC** (backups de
  producción al día). Credenciales recuperadas de `axioma`. **No tiene `repo1-host` contra dev-1**: drp
  restaura desde R2 directamente. ⚠ **No correr `expire` desde drp** — ese repo es el de producción.

**Pendientes**: colectores específicos de Netdata (postgres/nginx/pgBackRest) — se suman con
`scripts/20-deploy-configs.sh` cuando haya apps para cada prueba de restore. `ubuntu` NOPASSWD del cloud-init.

**Gap de gobierno — CERRADO el 2026-08-11 con el watchdog** (ver §12). El problema de fondo sigue vivo: el
rearmado es manual, así que una próxima reinstalación vuelve a borrar todo. Lo que cambia es que ahora **se
detecta en 15 minutos en vez de 3 días**.

## 12. Watchdog de flota — detección de reinstalaciones y de controles caídos

Motivado por la reinstalación de axioma-drp del 2026-08-08, que pasó 3 días sin que nadie la notara.
Desplegado y **validado end-to-end** el 2026-08-11 con `scripts/35-deploy-watchdog.sh`. Dos piezas:

### 12.1 Watchdog externo (en dev-1) — `hostkey-watchdog.py`

Cron cada 15 min. Mira los 5 servers **desde afuera** con `ssh-keyscan`, que **no autentica**: no hace falta
ninguna llave ni usuario del watchdog en los servers vigilados, así que no abre ninguna vía de acceso nueva.

**La idea central**: la alarma de "nodo unreachable" de Netdata Cloud **no sirve** para esto — un server
reinstalado vuelve a estar online enseguida y para Cloud simplemente "volvió". Lo que no vuelve igual es la
**host key de SSH**: una instalación nueva genera claves nuevas. Comparar la huella contra una línea de base
detecta la reinstalación aunque el server esté perfectamente vivo.

- Línea de base: `/etc/watchdog/baseline.json` en dev-1, sembrada desde los servers vivos por el script de
  despliegue. Las IPs no viven en el repo (salen de `inventory.sh`, gitignoreado).
- Métricas `watchdog.fleet.*` → charts `watchdog_fleet.*` vía statsd.
- Alarmas: **`watchdog_hostkey_changed`** (crítica, sin warning: una host key que cambia es un hecho, no una
  degradación) y **`watchdog_server_ausente`** (warn <5 servers, crit <4, con 15 min de gracia por reboots).
- Un server que no responde reporta `desconocido`, **no** `CAMBIÓ` — si no, cada corte de red sería una
  falsa alarma de reinstalación.
- **Tras una reinstalación legítima**: `hostkey-watchdog.py --reseed <server>` en dev-1, y asentarlo acá.
  Nunca re-sembrar sin confirmar por un canal independiente que la reinstalación era esperada.

### 12.2 Auto-chequeo local (hoy solo en axioma-drp) — `hardening-selfcheck.sh`

Cron cada 15 min, como root. Mira hacia adentro y empuja a su propio Netdata: `ufw` activo, `fail2ban`
activo **y con el jail sshd realmente levantado** (chequear solo el servicio no alcanza: es exactamente el
modo en que estuvo roto en julio y de nuevo tras la reinstalación), `sshd -T` con `PasswordAuthentication no`
y `PermitRootLogin no` (config **efectiva**, no los archivos: un drop-in puede existir sin estar aplicado), y
el agente Netdata claimed+online. Cinco alarmas, una por control, para que el mensaje diga qué se cayó.

**Límite conocido**: si el server se reinstala, esta pieza desaparece con él. Por eso el control de "server
ausente" es el de dev-1, no éste. Se despliega solo donde el estado esperado está verificado — sumarlo a un
server sin auditarlo primero arranca las alarmas en rojo y se vuelve ruido que se ignora.

### 12.3 Validación

`watchdog_hostkey_changed` se probó end-to-end simulando una reinstalación (huella falsa en una línea de base
de `/tmp`, sin tocar la real): pasó a **CRITICAL en 20 segundos**. Las 7 alarmas quedaron en CLEAR con la
línea de base real. Una alarma que nunca se vio disparar no es un control.

### Bien por server (no tocar)
- **clubix**: pg_hba deny explícito + scram; Node (5400)/PG (5432) en loopback; `.env` 600; fail2ban en 2222.
- **axiodemo**: ufw active + allowlist; PG externo restringido a `149.50.148.198` (dev-1, para `axio_ml`); ollama en loopback.
- **dev-1**: pg_hba/listen en loopback + scram; permisos pgBackRest correctos (secretos no world-readable); CA Smallstep OK.

### Pendientes dev-1 (prioridad, tras SSH ya hecho)
- ✅ **P1 HECHO (2026-07-17)**: 3 `.env` de `/var/www/mini/{backend,frontend,print-agent}` pasados **777→600** (owner `axiomacloud` ya correcto, coincide con el proceso backend pid 1326; verificado legible y app viva).
- ✅ **P2 firewall HECHO (2026-07-17)**: ufw active default-deny, allow 22/5782/80/443 + snmp 161/udp solo desde `200.58.112.191`/`200.58.109.50`. Tuples heredadas reseteadas (backup `.bak-<ts>`). Verificado: SSH ambos puertos + web OK, 19999/631/3000/8087 bloqueados, **y `pgbackrest check` OK en las 4 stanzas** (flujo de backups intacto). Las apps Node crudas y netdata/CUPS quedan tapadas por el fw (van por nginx localhost igual).
- ✅ **CUPS + netdata HECHO (2026-07-20)**: CUPS `:631` **deshabilitado** (`snap disable cups` + `cups-browsed`; nadie imprime → menos superficie que rebindear). netdata `:19999` → `bind to = 127.0.0.1` en los **3 servers** (ACLK es saliente por 443: `agent-claimed`/`aclk-available` siguen en true, Cloud intacto). Backups: `netdata.conf.bak-<ts>`; revertir CUPS con `snap enable cups`.
- 🟡 **P2 restante (defensa en profundidad, no urgente ya que el fw tapa)**: snmpd → community `public` (H09, **bloqueado**: dattaweb poletea cada ~1s, requiere coordinar el nuevo secreto); `.env` 644/664/755 → normalizar en Fase 4.
- ⛔ **Apps Node `:3000/8087/8089` (Next.js) — BLOQUEADAS por hallazgo transversal (2026-07-20)**: el flag `-H`/`--hostname` bindea bien pero hace que **Next construya los redirects absolutos con ese host** (`307 → https://localhost:<port>/login`) → rompe el login. Verificado en axioma `:3700` elore y revertido. No es config (`APP_URL` correcto, nginx pasa `Host $host`). **Resolver el patrón una sola vez** (`trustHost`/`assetPrefix`/`X-Forwarded-Host`) antes de reintentar. Ojo: dev-1 `:3000` elore **ya tiene `--hostname localhost` en su ecosystem**, hoy inerte por `exec_mode: 'cluster'` — pasar a `fork` lo activaría.
- 🔧 **Apps que necesitan cambio de CÓDIGO (fuera de infra)**: `:8086` checkpoint-web (`server.ts:33`), `:5000` mediflow (`server.js:233`) y axiodemo `:5300` axio-backend (`dist/server.js:117`) hacen `server.listen(port, cb)` **sin argumento host** → ignoran `HOST`/`HOSTNAME` (que ya están seteados, inertes). Va como issue en cada repo de aplicación.
- ⚠ **Desvíos del estándar detectados (2026-07-20, más graves que el bind)**: dev-1 `:5000` mediflow-backend corre como **`root`**; dev-1 `:8086` checkpoint-web corre como `axiomacloud` (no `checkpointapp`); `/var/www/elore/ecosystem.config.js` es `root:root`. Corregir en Fase 4/5.
- 📌 **Gotchas de PM2 relevados**: `pm2 reload --update-env` **no** aplica cambios de bind (reusa el env cacheado) → usar `pm2 restart <ecosystem> --only <app> --update-env`. El `PM2_HOME` de `parseapp` en axioma es `/var/www/parse/.pm2` (no el home) → un `pm2 save` al lugar equivocado falla con `EACCES` y deja sin rollback. axiodemo tiene una regla ufw huérfana `3001/tcp ALLOW` (nada escucha ahí).

### Notas
- axiodemo #1 es el inverso de axioma: pg_hba bien pero `listen='*'`; lo contiene el **firewall**, no el bind.
- La IP `149.50.148.198` autorizada en axiodemo (pg_hba+ufw) para `axio_ml` es **dev-1**.
