# Plan de Remediación — Hallazgos técnicos del dossier de auditoría

> **Tracker accionable** para dejar en 🟢 VERDE todos los hallazgos técnicos pendientes del
> [dossier de auditoría](./dossier-auditoria-seguridad.md) §7. Se tilda hallazgo por hallazgo a
> medida que se ejecuta y se **verifica** el verde.
>
> **Alcance de este plan:** los hallazgos técnicos **H01–H14 que siguen pendientes** (los ya ✅
> corregidos —H02 firewall, H05 SSH, H10 linuxadmin, y la parte ya hecha de H03 token rotado / H06
> axioma+mini— NO se re-trabajan). **FUERA de alcance:** los gaps de gobierno **G1–G9** del §8 del
> dossier — son artefactos de documentación/proceso, no fixes técnicos sobre servers; se cubren en
> un plan de gobierno aparte.
>
> Convención de estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho y verificado verde · `[!]` bloqueado
> Fecha de arranque: 2026-07-18.

---

## Regla transversal (NO negociable)

Se hereda la regla de oro del repo. Para **cada** hallazgo que toca un server vivo:

1. **Una intervención a la vez.** Nunca dos servers ni dos apps en la misma pasada.
2. **Ventana de bajo tráfico** acordada con el usuario para lo que pueda cortar servicio.
3. **Backup / snapshot / rollback listo ANTES de tocar** (copia del config, `pg_dump`, `dump.pm2`,
   `.bak-<ts>` del archivo, según aplique).
4. **OK explícito del usuario antes de CADA acción invasiva.** Presentar el plan concreto (qué
   comando, qué se respalda, cómo se revierte) y esperar aprobación. Aprobar una cosa NO aprueba la
   siguiente.
5. **Verificar el verde ANTES de tildar.** El criterio de "Verificación" de cada hallazgo debe dar
   OK con el comando real; solo entonces se marca `[x]`.

Los sub-pasos **de solo lectura** (relevar, medir, `pgbackrest info/check/verify`, `ss`, `find`,
`grep` de configs) se hacen sin pedir permiso. Los marcados **⚠ REQUIERE OK EXPLÍCITO** son los
invasivos: no se ejecutan sin aprobación puntual.

---

## Leyenda de progreso — una fila por hallazgo (ordenado por riesgo de intervención)

> Riesgo de intervención = qué tan fácil es romper un servicio vivo al aplicar el fix (no la
> severidad del hallazgo). Se ejecuta de **arriba (bajo riesgo) hacia abajo (alto riesgo)**.

| Ola | # | Hallazgo (corto) | Server(s) | Sev | Riesgo interv. | Estado |
|---|---|---|---|---|---|---|
| **1 — Quick wins (no cortan servicio)** | H14 | `stub_status` nginx sin datos | los 3 con nginx | 🟢 | Muy bajo | [x] (2026-07-18) |
| 1 | H06 | `.env` laxos → 600 | dev-1, axiodemo | 🟡 | Muy bajo | [x] (2026-07-18) |
| 1 | H12 | `origin` de axio mal apuntado (a ProHub) | axiodemo | 🟡 | Muy bajo | [x] (2026-07-18) |
| **2 — Monitoreo / verificación (aditivos)** | H08 | Alarma antigüedad backup pgBackRest sin desplegar | dev-1 | 🟡 | Bajo | [x] (2026-07-18) |
| 2 | H07 | Restore drills AxiomaCloudProd+clubix + cadencia mensual | infra (backup) | 🟡 | Bajo | [x] (2026-07-19) |
| **3 — Hardening de servicios (config, recargable)** | H09 | snmpd community `public` + `agentaddress` público | dev-1 | 🟡 | Bajo-Medio | [!] bloqueado — coordinar con dattaweb |
| 3 | H03 | Creds R2 en claro en los `.conf` | dev-1, axioma, clubix, axiodemo (+drp) | 🟡 | Medio | [ ] |
| **4 — Invasivos sobre apps/DB en prod (⚠ OK explícito)** | H04 | Apps escuchando en `0.0.0.0` → loopback | axioma, dev-1, axiodemo | 🟡 | Medio-Alto | [ ] |
| 4 | H01 | `pg_hba` `0.0.0.0/0 md5` → rangos + scram | axioma | 🔴→🟡 | Alto | [ ] |
| 4 | H13 | `npm audit` hub (47 back / 18 front) + higiene | apps (axioma) | 🟡 | Alto | [ ] |
| 4 | H11 | `axio-ml` corre como `axiomacloud` → usuario dedicado | axiodemo | 🟢 | Alto | [ ] |

**Total: 10 hallazgos técnicos pendientes** en 4 olas de riesgo creciente.

> Los gaps de gobierno **G1–G9 quedan FUERA de este plan** (son documentación/proceso, no fixes
> técnicos). Se abordan por separado.

---

# OLA 1 — Quick wins (no cortan servicio)

Cambios aditivos o de permisos que no detienen ningún proceso vivo. Se pueden hacer sin ventana
formal (igual, OK explícito para el que toca `.env`/git en un server vivo).

## H14 — `stub_status` de nginx sin datos (colector `go.d/nginx`)

- **Server(s):** los 3 con nginx (axioma, axiodemo, dev-1) · **Sev:** 🟢 · **Riesgo interv.:** Muy bajo · **CIS 13**

**Objetivo (verde).** El colector `go.d/nginx` recibe métricas: `curl -s http://127.0.0.1/stub_status`
en cada server con nginx devuelve el bloque `Active connections: … server accepts handled requests …`,
y en Netdata Cloud aparecen charts `nginx.*` con datos (no "no data").

**Procedimiento.**
1. **(lectura)** Diagnosticar en cada server si el `server {}` interno de stub_status existe y responde:
   `curl -sS http://127.0.0.1/stub_status` y `sudo -n nginx -T 2>/dev/null | grep -n stub_status`.
2. **(lectura)** Ver cómo apunta el colector: `netdata/go.d/nginx.conf` en el repo (URL esperada) vs.
   lo que responde el server. Confirmar si el problema es (a) falta el bloque stub_status, (b) escucha
   en un `listen`/`server_name` que el colector no pega, o (c) `allow/deny` que bloquea a 127.0.0.1.
3. Si falta el bloque, agregarlo según `setup-netdata-cloud.md` §4 (server interno `listen 127.0.0.1:80`,
   `location /stub_status { stub_status; allow 127.0.0.1; deny all; }`). **Reflejar el snippet en el repo**
   (no editar solo en el server). ⚠ **REQUIERE OK EXPLÍCITO** para tocar la config nginx viva.
4. Aplicar sin corte: `sudo nginx -t && sudo systemctl reload nginx` (**reload, no restart**).
5. Si el colector apunta a la URL equivocada, ajustar `netdata/go.d/nginx.conf` y redesplegar con
   `scripts/20-deploy-configs.sh` (o el `30-…` de netdata según corresponda).

**Riesgo.** Muy bajo: un `stub_status` mal escrito lo caza `nginx -t` antes del reload; el reload no
corta conexiones. El único riesgo real sería introducir un `server {}` que colisione con `server_name _`
existente → validar con `nginx -T` que no cambió el ruteo de los vhosts productivos.

**Rollback.** Revertir el snippet agregado (quitar el `location`/`server` nuevo) + `nginx -t && reload`.
Guardar copia previa del sitio tocado (`.bak-<ts>`) antes de editar.

**Verificación.**
- `curl -s http://127.0.0.1/stub_status` en cada server → devuelve las 4 líneas de stub_status.
- En Netdata Cloud (o `curl 127.0.0.1:19999/api/v1/data?chart=nginx.connections`): chart `nginx.*` con datos.

> **RESUELTO (2026-07-18) — no requirió intervención.** El diagnóstico reveló que la premisa del
> plan era incorrecta: el colector NO apunta a `:80` sino a **`:8088`**, donde el bloque
> `stub_status` ya existe en `/etc/nginx/conf.d/netdata_stub_status.conf` en los 3 servers y
> responde. Netdata recibe el chart **`nginx_local.connections`** con datos vivos (axioma 9.57,
> dev-1 3.97, axiodemo 2.00). Solo se corrigió el comentario obsoleto (`:80`→`:8088`) en
> `netdata/go.d/nginx.conf` (repo, sin tocar servers).

**Sub-pasos:**
- [x] Diagnosticar stub_status en axioma / axiodemo / dev-1 (lectura) — colector en `:8088`, responde
- [x] Determinar causa → **ninguna**: bloque presente y colector OK; solo comentario obsoleto en repo
- [x] Corregir comentario `:80`→`:8088` en `netdata/go.d/nginx.conf` (repo, no invasivo)
- [x] Verificar datos: chart `nginx_local.connections` con valores en los 3

---

## H06 — `.env` con permisos laxos → 600

- **Server(s):** dev-1 (`.env` 644/664/755 varios), axiodemo (`axio*/.env` 664) · **Sev:** 🟡 · **Riesgo interv.:** Muy bajo · **CIS 3, 4**

> axioma ya está en 600 ✅ y mini de dev-1 (777→600) ✅ (hardening.md). Falta el resto de dev-1 y axiodemo.

**Objetivo (verde).** Todo `.env` de app es `chmod 600` y **owner = el usuario que corre el proceso
que lo lee** (típicamente `<app>app`, o `axiomacloud` donde la app aún no fue migrada). Cero `.env`
world/group-readable.

**Procedimiento.**
1. **(lectura)** Inventariar los `.env` y sus permisos/owner en cada server:
   `sudo -n find /var/www /opt -maxdepth 3 -name '.env' -printf '%m %u:%g %p\n' 2>/dev/null`.
2. **(lectura)** Para cada `.env`, confirmar **quién lee ese archivo** (el proceso PM2/uvicorn):
   `ps -eo user,args | grep <app>` → el `chmod 600` solo sirve si el owner coincide con ese usuario.
   Si el owner NO coincide (ej. `.env` root pero proceso corre como `<app>app`), primero `chown` al
   usuario correcto, después `chmod 600`.
3. Aplicar por archivo, uno a uno: `sudo chown <user>:<group> <ruta> && sudo chmod 600 <ruta>`.
   ⚠ **REQUIERE OK EXPLÍCITO** por server (toca archivos de apps vivas; con owner correcto no reinicia
   nada, pero si el owner estaba mal, un chmod 600 con owner equivocado **deja al proceso sin poder leer
   su `.env` en el próximo restart** — de ahí el paso 2).

**Riesgo.** Bajo. El peligro real es hacer `chmod 600` dejando un owner que NO es el del proceso →
la app pierde acceso a su `.env` en el siguiente restart (no de inmediato, porque ya lo tiene abierto).
Mitigación: paso 2 obligatorio (owner == proceso) antes del chmod.

**Rollback.** Restaurar permisos/owner previos anotados en el paso 1 (`chmod <modo-viejo>` / `chown <owner-viejo>`).
No hace falta reiniciar la app (el descriptor sigue abierto).

**Verificación.**
- `sudo -n find /var/www /opt -maxdepth 3 -name '.env' -printf '%m %u:%g %p\n'` en dev-1 y axiodemo → **todos `600`** y owner == usuario del proceso.
- Boot test de al menos una app tocada por server: reiniciar su servicio y confirmar que arranca y lee el `.env`.

> **HECHO (2026-07-18).** Con backup `.bak-<ts>` de cada archivo. **axiodemo** (owner ya OK):
> `axio/.env` 664→600, `axio-ml-service/.env` 664→600 (`axio/backend/.env` ya estaba 600).
> **dev-1**: `elore/.env` 755→600 (owner OK); `mediflow/backend/.env` 644→600 con
> `chown root:root` (el proceso corre como root vía PM2 de root); `checkpoint-web/.env` 644→600
> con `chown axiomacloud` (el proceso corre como axiomacloud). Verificado: los 5 en 600, cada
> owner LEE su `.env` (`sudo -u <owner> test -r` OK), apps siguen vivas (no se reinició nada;
> descriptor abierto). Migrar mediflow/checkpoint a usuario dedicado sigue pendiente en Fase 5
> (no es de esta ola).

**Sub-pasos:**
- [x] Inventariar `.env` (perms+owner+proceso lector) en dev-1 y axiodemo (lectura)
- [x] Normalizar owner (mediflow→root, checkpoint→axiomacloud) + `chmod 600` en dev-1
- [x] `chmod 600` en axiodemo (owner ya OK)
- [x] Verificar 600 en los 5 + lectura efectiva por owner + apps vivas

---

## H12 — `origin` de axio en axiodemo mal apuntado (a ProHub)

- **Server(s):** axiodemo (`/var/www/axio`) · **Sev:** 🟡 · **Riesgo interv.:** Muy bajo · **CIS 2 (integridad de deploy)**

> Detalle completo en `plan-trabajo-estandarizacion.md` (líneas 60–68). El `origin` de `/var/www/axio`
> apunta a `AxiomaCloud/ProHub` (repo de **hub**). Si se arregla la credencial HTTPS SIN re-apuntar
> primero, el próximo `deploy.sh` haría `pull origin main` desde ProHub → traería hub → **rompe axio
> en prod**. ProHub NO fue ensuciado (verificado 2026-07-17) → el enredo es solo de config.

**Objetivo (verde).** `git -C /var/www/axio remote get-url origin` devuelve
`git@github.com:AxiomaCloud/axio.git` (repo canónico de axio), y un `git fetch` de prueba trae el árbol
de axio (`name: axio`, con `ml-service/`+`db-agent/`), NO hub. Deploy de axio vuelve a ser seguro.

**Procedimiento.**
1. **(lectura)** Confirmar el estado actual: `git -C /var/www/axio remote -v` (espera ProHub) +
   `git -C /var/www/axio status` + `git -C /var/www/axio log --oneline -3` (HEAD `22eaff3`).
2. **(lectura)** Confirmar que hay cambios locales sin commitear a reconciliar
   (`ml-service/main.py`, `kb_repo.py`, `frontend/.env.production`) → `git -C /var/www/axio diff --stat`.
3. Re-apuntar el remote (como el owner `axioapp`, no root):
   `sudo -u axioapp git -C /var/www/axio remote set-url origin git@github.com:AxiomaCloud/axio.git`.
   ⚠ **REQUIERE OK EXPLÍCITO** (toca la config del deploy de una app viva; en sí no despliega nada,
   pero habilita el próximo deploy → hay que acordar que NO se corre `deploy.sh` hasta reconciliar).
4. `sudo -u axioapp git -C /var/www/axio fetch origin` (verifica que la deploy key SSH funciona y que
   trae axio) — **NO** hacer `pull`/`reset` en esta remediación; reconciliar los 3 cambios locales vs
   `axio.git` es tarea de la Fase 6 de estandarización (fuera de alcance de este fix puntual).
5. **NO tocar ProHub** (es de hub).

**Riesgo.** Muy bajo si se limita a `set-url` + `fetch`. El riesgo grande sería hacer un `pull`/`reset`
que mezcle el árbol → por eso este fix **solo cambia el puntero y verifica el fetch**; el `pull`/build
queda para la ventana de Fase 6 con su propio OK.

**Rollback.** `git -C /var/www/axio remote set-url origin <url-vieja-ProHub>` (anotar la URL previa
exacta en el paso 1 antes de cambiarla). El working tree no se toca → rollback trivial.

**Verificación.**
- `git -C /var/www/axio remote get-url origin` → `git@github.com:AxiomaCloud/axio.git`.
- `git -C /var/www/axio ls-remote origin main` funciona (deploy key OK) y el árbol remoto es axio, no hub
  (spot-check: `git -C /var/www/axio cat-file -e origin/main:ml-service/main.py` existe; el marcador de
  hub `pricing_hub.html` NO).

> **HECHO (2026-07-18).** Corrección respecto del plan: se apuntó a **SSH vía alias**, no HTTPS.
> El diagnóstico mostró que `axioapp` no tiene credencial HTTPS (fetch pedía usuario) pero **sí**
> una deploy key SSH funcional (`~/.ssh/github-axio`, alias `github-axio` en su ssh config) que
> autentica en GitHub. Origin final: **`github-axio:AxiomaCloud/axio.git`**. `ls-remote`/`fetch`
> contra el remoto REAL OK (SHA `afa7461`), spot-check confirma árbol de axio (`ml-service/main.py`
> existe), working tree intacto (los 3 cambios locales siguen; queda `behind 5` para Fase 6).
> Rollback ref: `https://github.com/AxiomaCloud/ProHub.git`. NO se corrió `pull`/`deploy.sh`.

**Sub-pasos:**
- [x] Confirmar estado actual del remote (ProHub HTTPS) + HEAD `22eaff3` + 3 cambios locales (lectura)
- [x] `remote set-url origin → github-axio:AxiomaCloud/axio.git` (SSH, no HTTPS) como `axioapp`
- [x] `ls-remote`/`fetch origin` — deploy key SSH OK, trae axio (no hub)
- [x] Verificar `remote get-url` + spot-check árbol remoto (axio ≠ hub) + working tree intacto
- [x] Registrado: reconciliación de cambios locales + `pull` queda para Fase 6 (no acá)

---

# OLA 2 — Monitoreo / verificación (aditivos, no tocan apps)

Suman capacidad de detección o ejecutan pruebas en hosts aislados. No modifican servicios productivos.

## H08 — Alarma de antigüedad de backup pgBackRest sin desplegar

- **Server(s):** dev-1 (repo host) · **Sev:** 🟡 · **Riesgo interv.:** Bajo · **CIS 11, 13**

> La config de la alarma ya está en el repo: `netdata/health.d/pgbackrest.conf` (backup_age >25h/48h,
> backup_failed, wal_delayed por stanza). Falta el **colector custom (statsd)** que alimenta los charts
> `pgbackrest.*` + desplegar ambos. Ver `setup-netdata-cloud.md` §5 para el script emisor.

**Objetivo (verde).** En Netdata Cloud existen los charts `pgbackrest.backup_age`, `pgbackrest.status`
y `pgbackrest.wal_age_stanza` (por stanza) con datos reales, y las alarmas de `health.d/pgbackrest.conf`
están en estado `CLEAR` (no `UNDEFINED`/"no data"). Un backup viejo/fallido dispararía Telegram/Email.

**Procedimiento.**
1. **(lectura)** Verificar qué falta en dev-1: si existe el colector emisor
   (`/usr/local/bin/pgbackrest-backup-age.sh` o equivalente statsd), si `netdata/statsd.d/` del repo lo
   define, y si `health.d/pgbackrest.conf` ya está desplegado (`sudo -n ls /etc/netdata/health.d/pgbackrest.conf`).
2. **(lectura)** Confirmar que el chart aún no llega: en dev-1 `curl -s 127.0.0.1:19999/api/v1/charts | grep pgbackrest`.
3. Completar/ajustar el **colector emisor** en el repo (parsea `pgbackrest info --output=json`, emite
   `backup_age`, `backup_ok` y `wal_age_stanza` por dimensión de stanza vía statsd/charts.d). Correrlo
   como el usuario `pgbackrest` (o vía sudo acotado) para que lea el repo.
4. Desplegar colector + `health.d/pgbackrest.conf` + `statsd.d/` con `scripts/20-deploy-configs.sh`
   (netdata) hacia dev-1, y programar su ejecución periódica (timer systemd o cron del emisor).
   ⚠ **REQUIERE OK EXPLÍCITO** para desplegar en dev-1 (la caja más sensible) y reiniciar/recargar netdata.
5. `sudo systemctl reload netdata` (o `restart` si hace falta para cargar statsd) — netdata reload no
   afecta backups ni apps.

**Riesgo.** Bajo. Es aditivo (un colector de solo-lectura sobre `pgbackrest info` + una config de alarma).
El único cuidado en dev-1: no correr el emisor con permisos de más ni imprimir secretos (H03: el
`pgbackrest info` NO expone las creds R2, pero el script no debe volcar el `.conf`). Un `restart netdata`
corta el agente unos segundos (reconecta a Cloud, no afecta métricas ya en la nube).

**Rollback.** Quitar `health.d/pgbackrest.conf` desplegado + el colector + su timer/cron, `reload netdata`.
Como es aditivo, revertir no deja rastro en el flujo de backups.

**Verificación.**
- dev-1: `curl -s 127.0.0.1:19999/api/v1/charts | grep pgbackrest` → aparecen los 3 charts.
- Netdata Cloud: alarmas `pgbackrest_backup_age`, `_backup_failed`, `_wal_delayed_<stanza>` en `CLEAR`.
- **Prueba activa** (opcional, controlada): simular antigüedad (offset temporal en el emisor) y confirmar
  que la alarma pasa a WARN y llega la notificación → luego revertir.

> **RESUELTO (2026-07-18) — ya estaba desplegado y en verde; no requirió intervención en dev-1.**
> El diagnóstico en vivo reveló que la premisa del plan ("sin desplegar") era **incorrecta**: el
> monitoreo completo se desplegó el **26-May-2026** en dev-1 y funciona. El colector es
> `/usr/local/bin/pgbackrest-collect.py` (no el `pgbackrest-backup-age.sh` que asumía el plan),
> corre por **cron cada 15 min** (`/etc/cron.d/pgbackrest-netdata`, como usuario `pgbackrest`), y
> `health.d/pgbackrest.conf` + `statsd.d/pgbackrest.conf` están desplegados (md5 idénticos al repo).
> Los charts `pgbackrest.backup_age/.status` (agregados) + `.backup_age_stanza/.wal_age_stanza/
> .status_stanza` (por stanza, 4 dims: AxiomaCloudProd/clubix/axiodemo/dev-1) llegan con datos
> reales, y **todas las alarmas están en CLEAR** (backup_age 3557s, backup_failed status_ok=1, los
> 4 wal_delayed en CLEAR). `pgbackrest info --output=json` corre OK como `pgbackrest` (4 stanzas,
> status_code=0). **La única acción fue de repo (sin tocar dev-1):** el colector del repo estaba una
> versión atrás (pre dual-repo) → se reemplazó por la versión multi-repo del server (md5-idéntica),
> que evita falsos positivos de `backup_failed` cuando el status agregado da `mixed`(4)/`running`(3)
> con repo2 R2 atrasado o durante un backup. **Corrección al plan:** el deploy real es
> `scripts/30-deploy-pgbackrest-monitoring.sh` (con `systemctl restart netdata`), NO
> `20-deploy-configs.sh`; y no hubo que desplegar nada porque el server ya estaba en verde.

**Sub-pasos:**
- [x] Diagnosticar qué falta en dev-1 (colector emisor / statsd.d / health.d desplegado) (lectura) → **ya todo desplegado 26-May, en verde**
- [x] Completar/ajustar el colector emisor en el repo → reconciliado: traída la versión multi-repo del server (md5-idéntica), sin editar dev-1
- [x] ~~Desplegar a dev-1~~ **innecesario**: server ya en verde desde 26-May; no se tocó dev-1 ni se reinició netdata
- [x] Verificar charts `pgbackrest.*` con datos + alarmas en CLEAR en Cloud → **verificado en vivo (todas CLEAR)**
- [ ] ~~(Opcional) prueba activa de disparo de alarma~~ → no se ejecuta (aditivo ya verificado en CLEAR)
- [x] Marcar el pendiente como cerrado en `setup-netdata-cloud.md` §5 (actualizado: nombre real del colector, multi-repo, deploy `30-…`, estado verde)

---

## H07 — Restore drills de AxiomaCloudProd + clubix y cadencia mensual

- **Server(s):** infra (backup) · **Sev:** 🟡 · **Riesgo interv.:** Bajo · **CIS 11**

> Hoy solo la stanza `axiodemo` tiene corridas registradas (última 2026-07-04). El drill se corre en un
> host **distinto de dev-1** (KEYSOFT-UBUNTU o similar), restaura en `/var/lib/postgresql/restore-drill/`
> aislado, **no toca producción** (`restore-drill-procedure.md`). AxiomaCloudProd/clubix son PG14, axiodemo PG16.

**Objetivo (verde).** `docs/drill-history.csv` tiene al menos una corrida **PASS** de cada stanza de
prod — `AxiomaCloudProd`, `clubix` y `axiodemo` — reciente, y queda establecida la cadencia mensual
(próxima corrida agendada). El §8 del `restore-drill-procedure.md` refleja las nuevas corridas de nota.

**Procedimiento.**
1. **(lectura)** Prerequisitos en el host ejecutor (§2 del procedimiento): `pgbackrest version` (2.58),
   binarios PG14 y PG16 (`ls /usr/lib/postgresql/{14,16}/bin/pg_ctl`), `sudo -u postgres -H echo ok`,
   `ssh axiomacloud@149.50.148.198 echo ok`, `df -h /var/lib/postgresql` (~2 GB libres para AxiomaCloudProd).
2. **(lectura)** Integridad previa sin restaurar, desde dev-1:
   `sudo -u pgbackrest pgbackrest --repo=2 --stanza=AxiomaCloudProd verify` (y `clubix`, `axiodemo`).
   Output esperado `verify … completed successfully`.
3. Correr el drill (auto-evaluante, no invasivo sobre prod — restaura en dir temporal y limpia):
   `./scripts/70-restore-drill.sh AxiomaCloudProd clubix axiodemo` → `echo "exit=$?"`.
   Este paso escribe SOLO en el host ejecutor (dir temporal + CSV); **no** requiere OK invasivo sobre
   servers productivos, pero **sí conviene confirmar con el usuario la ventana** por el egress WAN desde
   R2 y el consumo de disco/CPU en el ejecutor.
4. `exit=0` + `✓ DRILL EXITOSO` → `git commit docs/drill-history.csv` (traza objetiva). Si `exit=1`:
   NO marcar verde; diagnosticar con §6/§9 del procedimiento (el fallo es una alerta de DR real del
   backup/WAL de prod, no del drill).
5. **Cadencia:** agendar la corrida mensual (recordatorio/routine) y registrar la próxima fecha. La
   sostenibilidad de la cadencia se apoya en H08 (alarma proactiva) como red complementaria.

**Riesgo.** Bajo. El drill está diseñado para NO tocar producción (restaura aislado en el ejecutor).
Riesgos acotados: llenar disco del ejecutor (mitigado por §2, ~2 GB) y egress de R2. **No se corre en
dev-1** (invalidaría la prueba de DR y colisionaría con el repo/PG productivo).

**Rollback.** No aplica en sentido estricto (no modifica producción). El script limpia su dir temporal;
si abortó, borrar `/var/lib/postgresql/restore-drill/<stanza>` a mano (§9.4/§9.5 del procedimiento).

**Verificación.**
- `docs/drill-history.csv` con fila **PASS** reciente de `AxiomaCloudProd`, `clubix` y `axiodemo`.
- Cada corrida: `pg_is_in_recovery()=f`, `pg_last_xact_replay_timestamp()` < 30 min, conteo de tablas > 0.
- Próxima corrida mensual agendada y anotada.

> **HECHO (2026-07-19) — las 3 stanzas en PASS, pero primero hubo que arreglar el drill.**
> Las 2 corridas iniciales del día dieron **FAIL sistemático en AxiomaCloudProd y clubix** (PG14) con
> axiodemo (PG16) en PASS. El diagnóstico mostró que **los backups estaban sanos: el bug era del
> script**, por dos causas acumuladas (ambas corregidas en `scripts/70-restore-drill.sh`):
> 1. **`pg_hba.conf` copiado del cluster local.** El script copiaba
>    `/etc/postgresql/<v>/main/pg_hba.conf` al PGDATA temporal si existía. En el ejecutor existe el de
>    PG14 y trae `host all all 127.0.0.1/32 scram-sha-256` → la instancia restaurada **pedía password**
>    y el `psql` del drill (sin credencial) era rechazado por **autenticación**, no porque PG estuviera
>    caído. axiodemo pasaba solo porque no hay `/etc/postgresql/16` y caía en el `trust` del `else`.
>    Fix: **generar siempre** un `pg_hba` mínimo `trust` (PGDATA temporal, loopback, se borra al final).
> 2. **Chequeo de conectividad sin espera.** Durante el replay inicial PG responde
>    `FATAL: the database system is starting up`; un intento único daba falso FAIL en las bases grandes.
>    Fix: reintentar hasta 300s, igual que el paso 2.
>
> **Corrida verificada (2026-07-19 20:08, KEYSOFT-UBUNTU, exit=0, `✓ DRILL EXITOSO`):**
> `AxiomaCloudProd` PASS (restore 71s, 585 tablas en 11 bases, backup 1h), `clubix` PASS (44s, 178
> tablas, backup 0h), `axiodemo` PASS (11s, 34 tablas, backup 0h). Las 3 con WAL replay progresando
> hasta el último segmento archivado y `wal_lag` ≤ 1m. **Primera corrida exitosa registrada de
> AxiomaCloudProd y clubix.** Producción no fue tocada (restore aislado en el ejecutor).

**Sub-pasos:**
- [x] Verificar prerequisitos del host ejecutor (PG14+PG16, SSH dev-1, 114 GB libres) (lectura)
- [x] Estado de las stanzas desde dev-1 (lectura) → las 4 en `status: ok`
- [x] **Arreglar el drill** (falsos FAIL en PG14): `pg_hba` trust siempre + espera de 300s en conectividad
- [x] Correr `70-restore-drill.sh AxiomaCloudProd clubix axiodemo` (host ≠ dev-1) → `exit=0`
- [x] Confirmar PASS de las 3 + `git commit` de `drill-history.csv`
- [ ] Agendar cadencia mensual + registrar próxima fecha (próxima: **2026-08-19**)
- [x] Agregar fila de nota a `restore-drill-procedure.md` §8 (primeras corridas de AxiomaCloudProd/clubix)

---

# OLA 3 — Hardening de servicios (config recargable)

Editan configs de servicios de infra (snmpd, pgbackrest). Reversibles con backup del `.conf` y un
reload; no detienen apps de negocio, pero sí requieren ventana + OK por tocar servers vivos (dev-1 crítico).

## H09 — snmpd en dev-1: community `public` → cambiar + `agentaddress 127.0.0.1`

- **Server(s):** dev-1 · **Sev:** 🟡 · **Riesgo interv.:** Bajo-Medio · **CIS 4, 12**

> Mitigado hoy por ufw (161/udp solo desde IPs dattaweb `200.58.112.191`/`200.58.109.50`). Falta la
> defensa en profundidad a nivel servicio. **Cuidado:** snmpd lo consume el monitoreo del proveedor
> (Contabo/dattaweb) → cambiar la community o el bind puede **romper ese monitoreo externo** si no se
> coordina. Verificar antes si el proveedor realmente lo scrapea o si es residual.

**Objetivo (verde).** `snmpd` no responde con la community por defecto `public` desde afuera y/o
escucha solo en loopback (`agentaddress udp:127.0.0.1:161`). Sin exposición de community pública en la
red. El monitoreo del proveedor sigue funcionando **o** se confirmó que no lo usa y se desactiva/acota.

**Procedimiento.**
1. **(lectura)** Relevar la config actual y el uso real:
   `sudo -n grep -E '^(agentaddress|rocommunity|com2sec|rouser)' /etc/snmp/snmpd.conf`,
   `sudo -n ss -ulnp | grep :161`, y en logs si hay polls entrantes desde las IPs dattaweb
   (`sudo -n journalctl -u snmpd --since '-7d' | grep -i <ip-dattaweb>`). **Decidir** con el usuario:
   ¿el proveedor scrapea SNMP o es residual?
2. **Camino A — el proveedor NO lo usa (o se acepta perderlo):** `agentaddress udp:127.0.0.1:161`
   (bind solo loopback) y/o `systemctl disable --now snmpd`. Es lo más simple y seguro.
3. **Camino B — el proveedor SÍ lo usa:** mantener bind acotado pero **cambiar la community** de `public`
   a una robusta (`rocommunity <fuerte> <ip-dattaweb>/32` por IP), coordinar el nuevo secreto con el
   proveedor, y guardarlo cifrado en infra-secrets.
4. Backup del `.conf` (`sudo cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak-<ts>`) → editar →
   `sudo systemctl restart snmpd`. ⚠ **REQUIERE OK EXPLÍCITO** (server crítico dev-1; puede romper el
   monitoreo del proveedor).

**Riesgo.** Bajo-Medio. Reiniciar snmpd no afecta apps ni backups. El riesgo es **cortar el monitoreo del
proveedor** (Camino A/B mal elegido) o, si se cambia la community sin coordinar, dejar al proveedor sin
polls. Mitigación: paso 1 (decidir uso real) antes de tocar. ufw ya tapa el 161 salvo dattaweb → el
riesgo de seguridad residual es bajo, esto es defensa en profundidad.

**Rollback.** `sudo cp /etc/snmp/snmpd.conf.bak-<ts> /etc/snmp/snmpd.conf && sudo systemctl restart snmpd`.
Si se hizo `disable`, `systemctl enable --now snmpd`.

**Verificación.**
- Desde el propio host, la community vieja no responde: `snmpwalk -v2c -c public 127.0.0.1 2>&1` → sin datos
  (timeout/authorizationError), y `snmpwalk` con la nueva community/desde la IP autorizada sí (Camino B).
- `sudo -n ss -ulnp | grep :161` → bind en `127.0.0.1` (Camino A) o solo escuchando para las IPs esperadas.
- (Camino B) confirmar con el proveedor que sigue recibiendo datos.

> **DIAGNÓSTICO (2026-07-19) — Camino B confirmado por evidencia directa; el proveedor SÍ usa SNMP.**
> Config actual en dev-1: **no hay `agentaddress`** (bind en `0.0.0.0:161`, confirmado por `ss`) y la
> community es `public`, pero **ya está acotada por IP de origen** vía `com2sec dattaweb` a las dos IPs
> de dattaweb (`200.58.112.191`, `200.58.109.50`) — mejor de lo que asumía el plan (no es un
> `rocommunity public` abierto). Servicio `active`+`enabled`, uptime 2d11h.
>
> **El journal NO sirve como evidencia** (snmpd no loguea consultas exitosas por defecto: 0 líneas en
> 30d). La prueba real fue `tcpdump udp port 161`: dattaweb (`200.58.112.191`) **poletea activamente
> cada ~1s** (`GetNextRequest .1.3.6.1.4.1.2021.10.1.3.1` = load average) y **snmpd responde**
> (`GetResponse … ="1.78"/"1.89"`). → **Camino A (loopback/disable) rompería el monitoreo del
> proveedor: queda descartado.** Se ejecuta **Camino B** (community fuerte por IP), que **requiere
> coordinar el nuevo secreto con dattaweb ANTES de aplicar** — si se cambia sin avisar, el proveedor
> deja de recibir métricas. Bloqueado a la espera de esa coordinación (acción del usuario con el
> proveedor), no de una decisión técnica.

**Sub-pasos:**
- [x] Relevar config snmpd + bind + uso real por el proveedor (lectura) → **Camino B** (dattaweb poletea y snmpd responde, verificado por tcpdump)
- [ ] ⚠ **Coordinar la nueva community con dattaweb** (prerequisito bloqueante del resto)
- [ ] Backup `snmpd.conf.bak-<ts>`
- [ ] ⚠ Aplicar Camino A (loopback/disable) o B (community fuerte + acotar) + restart — **OK explícito**
- [ ] Verificar: community `public` no responde + bind correcto (+ proveedor OK si Camino B)
- [ ] Guardar nueva community (si aplica) cifrada en infra-secrets

---

## H03 — Credenciales R2 en texto plano en los `.conf`

- **Server(s):** dev-1, axioma, clubix, axiodemo (+drp) · **Sev:** 🟡 · **Riesgo interv.:** Medio · **CIS 3**

> El **token ya fue rotado** (2026-07-17) y hay custodia SOPS en `infra-secrets/env/pgbackrest/repo2-r2.env`.
> Lo que falta para el verde es sacar las creds del **texto plano** en los `.conf` que lee pgBackRest.
> **Restricción dura:** pgBackRest lee su config en claro; **no** consume SOPS directamente. Y el
> `repo2-cipher-pass` NO se rota (invalida los backups en R2). Este es el hallazgo más delicado de la
> Ola 3: un `.conf` mal armado **rompe el backup a R2 de ese server**, y hay que tocar los **5 archivos**
> de forma consistente (o el server con config vieja falla).

**Objetivo (verde).** Las credenciales R2 (`repo2-s3-key`, `repo2-s3-key-secret`, `repo2-cipher-pass`)
NO figuran en texto legible dentro de los `.conf` versionados/inspeccionables por cualquiera con lectura
del archivo; se resuelven vía un mecanismo soportado por pgBackRest (ver opciones abajo) manteniendo
permisos `640` + firewall. `pgbackrest check` sigue OK en las 4 stanzas y el backup a repo2 (R2) sigue
funcionando en los 4 db/repo hosts.

**Procedimiento.**
1. **(lectura, SIEMPRE enmascarando)** Confirmar dónde viven hoy y con qué permisos, **sin imprimir el
   valor**: `sudo -n grep -l 'repo2-s3-key' /etc/pgbackrest/*.conf` y
   `sudo -n grep -E 'repo2-(s3-key|cipher)' <archivo> | sed 's/=.*/=<redacted>/'`. Confirmar los **5
   archivos**: dev-1 (`pgbackrest.conf` + `db.conf`), axioma/clubix/axiodemo (`pgbackrest.conf`). Verificar `640`.
2. **(decisión con el usuario)** Elegir el mecanismo de resguardo. pgBackRest **no** lee SOPS, así que
   las opciones reales son:
   - **(a) Mantener en `.conf` pero endurecer el aislamiento** (perms `640` owner-only, `.conf` fuera de
     cualquier repo, firewall) + documentar que la fuente de verdad cifrada es SOPS. Es el estado actual
     "mitigado"; para pasar a verde formal habría que argumentar defensa suficiente. **Menor cambio.**
   - **(b) Externalizar a un archivo de credenciales separado** con permisos aún más estrictos, referenciado
     desde el `.conf` (según lo que soporte la versión 2.58: p. ej. mover `repo2-s3-key*` a un
     `config-include-path`/archivo dedicado `600` propiedad de `pgbackrest`), reduciendo la superficie.
   - **(c) Variables de entorno** (`PGBACKREST_REPO2_S3_KEY…`) inyectadas por el runner de los cron/timers
     de backup, sacándolas del archivo en reposo. Requiere ajustar las units/cron de cada server.
   Documentar la elegida y sus límites (pgBackRest siempre necesita el secreto en algún punto en claro
   en ejecución).
3. Aplicar el cambio **de a un server por vez**, con backup del `.conf` (`cp … .bak-<ts>`), y **verificar
   `pgbackrest check` inmediatamente después** en ese server antes de pasar al siguiente. Recordar la
   restricción de H03: si se toca el valor en un server, mantener consistencia con los otros 4 (aunque
   este fix es de *ubicación/permisos*, no de rotación → el valor no cambia). ⚠ **REQUIERE OK EXPLÍCITO**
   por server; dev-1 último y con más cuidado (repo host).
4. **Nunca imprimir las líneas de credenciales** al inspeccionar (enmascarar de entrada con `sed`).

**Riesgo.** Medio. Un `.conf` con la credencial mal referenciada/movida **rompe el backup a R2** de ese
server (y `pgbackrest check` falla). Tocar los 5 sin consistencia deja un server fuera de sincronía. El
`cipher-pass` NO se toca en su valor (si se pierde/cambia, los backups R2 quedan irrecuperables). Por eso:
un server a la vez + `check` inmediato + no rotar el cipher.

**Rollback.** Restaurar el `.conf.bak-<ts>` del server tocado + `pgbackrest check` de sus stanzas. Como se
va de a uno con verificación, un fallo se contiene en ese único server.

**Verificación.**
- Por server tocado: `sudo -u pgbackrest pgbackrest --stanza=<X> check` (repo1 y repo2) → OK.
- El secreto ya no aparece en el `.conf` versionable / queda solo en el archivo restringido elegido
  (`grep` sobre lo que corresponda, enmascarado).
- Un backup incremental real a repo2 corre sin error (o esperar al cron y ver el `pgbackrest info` de repo2).

**Sub-pasos:**
- [ ] Relevar los 5 archivos + permisos (lectura, **enmascarando**)
- [ ] Decidir mecanismo (a/b/c) con el usuario y documentarlo
- [ ] ⚠ Aplicar en axiodemo → `check` — **OK explícito**
- [ ] ⚠ Aplicar en axioma → `check` — **OK explícito**
- [ ] ⚠ Aplicar en clubix → `check` — **OK explícito**
- [ ] ⚠ Aplicar en dev-1 (2 archivos, último) → `check` de las 4 stanzas — **OK explícito**
- [ ] Verificar backup R2 real OK + secreto fuera del `.conf` versionable en los 5

---

# OLA 4 — Invasivos sobre apps / DB en producción

Reinician procesos productivos, tocan autenticación de PostgreSQL, bumpean dependencias o migran el
owner de un servicio. **Todos requieren ventana de bajo tráfico + OK explícito puntual + rollback listo.**

## H04 — Apps escuchando en `0.0.0.0` → rebindear a `127.0.0.1`

- **Server(s):** axioma (`:8087` parse-front), dev-1 (`:3000/5000/8086/8087/8089`, CUPS `:631`, netdata `:19999`), axiodemo (`:5300`) · **Sev:** 🟡 · **Riesgo interv.:** Medio-Alto · **CIS 4, 12**

> Ya **mitigado por ufw** (esos puertos están tapados desde afuera). Esto es defensa en profundidad:
> que la app escuche solo en loopback y pase obligatoriamente por nginx (TLS/headers/rate-limit).
> Requiere **reiniciar cada app** (cambia su bind) → ventana + una app a la vez.

**Objetivo (verde).** Cada puerto de app listado escucha en `127.0.0.1:<puerto>` (no `0.0.0.0`),
verificable con `ss -tlnp`, y la app sigue respondiendo por su nginx (health HTTP OK). Servicios de
sistema (CUPS `:631`, netdata `:19999`) a loopback o confirmados como intencionales tras el fw.

**Procedimiento (por app, una a la vez).**
1. **(lectura)** Mapear exacto cada listener y su proceso:
   `sudo -n ss -tlnp | grep -E ':8087|:3000|:5000|:8086|:8089|:5300|:631|:19999'` por server, y el
   ecosystem/env que fija el host (Next: `-H 127.0.0.1`/`HOSTNAME=127.0.0.1`; Node: `HOST`/`address`).
2. **(lectura)** Confirmar que nginx ya proxya a `127.0.0.1:<puerto>` (si proxya a `0.0.0.0` o a la IP
   pública, ajustar el `proxy_pass` a loopback **en la misma ventana** o el rebind rompe el proxy).
3. Editar el bind: para Next, `-H 127.0.0.1` en el `script`/env del ecosystem; para Node, la variable de
   host correspondiente. Reflejar el cambio en el repo/manifiesto de la app.
4. Backup de rollback en segundos: `sudo -u <app>app pm2 save` (`dump.pm2`) + copia del ecosystem.
5. `sudo -u <app>app pm2 reload <app>` (o restart si el bind no se aplica en reload). ⚠ **REQUIERE OK
   EXPLÍCITO** por app; **una app a la vez**, en ventana de bajo tráfico.
6. Para CUPS `:631` y netdata `:19999` en dev-1: rebindear a loopback (CUPS `Listen localhost:631`;
   netdata `bind to = 127.0.0.1` en `netdata.conf`) o confirmar que quedan tapados por fw y documentarlo.

**Riesgo.** Medio-Alto. Rebindear a loopback una app cuyo nginx apunta a la IP pública/`0.0.0.0` la deja
**inaccesible por web** hasta corregir el `proxy_pass` → validar el paso 2 antes. Un `-H` mal puesto puede
impedir que la app arranque. Por eso: una app a la vez, health check inmediato, rollback con `pm2` listo.

**Rollback.** Restaurar el ecosystem previo + `pm2 reload` (o `pm2 resurrect` desde el `dump.pm2` guardado).
La app vuelve al bind anterior en segundos.

**Verificación.**
- `sudo -n ss -tlnp | grep :<puerto>` → `127.0.0.1:<puerto>` (ya no `0.0.0.0`).
- Health por nginx: `curl -k https://<dominio>/…` sigue 200; endpoint interno responde solo en loopback.
- Boot test de la app tocada (reinicio del servicio → sigue en loopback).

**Sub-pasos:**
- [ ] Mapear listeners `0.0.0.0` + proceso + host que los fija, por server (lectura)
- [ ] Confirmar `proxy_pass` de nginx apunta a loopback (o ajustarlo en la misma ventana) (lectura)
- [ ] ⚠ axioma `:8087` parse-front → `-H 127.0.0.1` + reload — **OK explícito**
- [ ] ⚠ axiodemo `:5300` → loopback + reload — **OK explícito**
- [ ] ⚠ dev-1 apps Node `:3000/5000/8086/8087/8089` → loopback, una a una — **OK explícito**
- [ ] ⚠ dev-1 CUPS `:631` + netdata `:19999` → loopback/confirmado — **OK explícito**
- [ ] Verificar `ss` en loopback + health por nginx + boot test, por app

---

## H01 — `pg_hba.conf` `0.0.0.0/0 md5` → restringir rangos + `scram-sha-256`

- **Server(s):** axioma · **Sev:** 🔴→🟡 · **Riesgo interv.:** Alto · **CIS 3, 4, 6**

> Mitigado en la práctica (PG bindea a `127.0.0.1` + ufw bloquea 5432), pero la config sigue amplia y en
> `md5`. **Muy invasivo:** un `pg_hba` mal hecho **corta la conexión de todas las apps a su DB**. Migrar
> a `scram-sha-256` puede dejar afuera roles cuyo password esté guardado como hash md5 hasta re-setearlos.

**Objetivo (verde).** En axioma, `pg_hba.conf` ya no tiene `host all all 0.0.0.0/0 md5`: las reglas
`host` quedan acotadas a `127.0.0.1/32` (y las subredes de backup/monitoreo estrictamente necesarias) y
el método es `scram-sha-256`. Todas las apps siguen conectando; `password_encryption = scram-sha-256`.

**Procedimiento.**
1. **(lectura)** Relevar el `pg_hba.conf` actual completo y quién conecta:
   `sudo -n cat /etc/postgresql/14/main/pg_hba.conf`, `sudo -n grep password_encryption /etc/postgresql/14/main/postgresql.conf`,
   y `SELECT usename, client_addr FROM pg_stat_activity` para saber qué orígenes reales hay (esperado:
   solo loopback, ya que PG bindea localhost). Verificar qué roles tienen password md5:
   `SELECT rolname FROM pg_authid WHERE rolpassword LIKE 'md5%';`.
2. **Preparar rollback ANTES:** copia del `pg_hba.conf` (`sudo cp … pg_hba.conf.bak-<ts>`). Redactar el
   `pg_hba` nuevo: reemplazar `0.0.0.0/0` por `127.0.0.1/32` (+ las subredes indispensables), método
   `scram-sha-256`, dejando `local` como está.
3. **Orden seguro para scram:** primero `ALTER SYSTEM SET password_encryption = 'scram-sha-256';` +
   `SELECT pg_reload_conf();`, luego **re-setear el password de cada rol de app** (`\password <rol>` o
   `ALTER ROLE … PASSWORD …` con el mismo secreto) para que se re-hashee como scram, ANTES de cambiar el
   método en `pg_hba`. Si no, esos roles no podrán autenticar con scram.
4. Aplicar el `pg_hba` nuevo → **`SELECT pg_reload_conf();` (NO restart)**. ⚠ **REQUIERE OK EXPLÍCITO**,
   en ventana de bajo tráfico, con la sesión `postgres` de respaldo abierta.
5. Validar de inmediato que las apps reconectan (health de cada app en axioma). Si algo falla, restaurar
   el `.bak` + `pg_reload_conf()` en el acto.

**Riesgo.** Alto. Errores típicos: (a) quitar una regla que alguna app/servicio sí usaba → esa app pierde
la DB; (b) pasar a scram sin re-hashear los passwords → auth failures; (c) recargar con `restart` en vez
de `reload` → corte innecesario. Mitigación: relevar orígenes reales (paso 1), re-hashear antes (paso 3),
`reload` no `restart`, health check inmediato, rollback en segundos.

**Rollback.** `sudo cp /etc/postgresql/14/main/pg_hba.conf.bak-<ts> /etc/postgresql/14/main/pg_hba.conf` +
`SELECT pg_reload_conf();`. Para scram, `md5` sigue funcionando aunque `password_encryption` sea scram
(los hashes md5 viejos autentican), así que revertir el `pg_hba` restaura el acceso; el cambio de
`password_encryption` puede quedar (no rompe md5 existente).

**Verificación.**
- `sudo -n grep -nE '0\.0\.0\.0/0|md5' /etc/postgresql/14/main/pg_hba.conf` → sin resultados (ni `0.0.0.0/0` ni `md5`).
- Todas las apps de axioma con health HTTP OK y conectando a su DB (ninguna auth failure en el log de PG).
- `SHOW password_encryption;` → `scram-sha-256`; `SELECT count(*) FROM pg_authid WHERE rolpassword LIKE 'md5%';` → roles de app en 0 (o justificados).

**Sub-pasos:**
- [ ] Relevar pg_hba actual + orígenes reales (`pg_stat_activity`) + roles con hash md5 (lectura)
- [ ] Backup `pg_hba.conf.bak-<ts>` + redactar el `pg_hba` nuevo acotado + scram
- [ ] ⚠ `password_encryption=scram` + re-setear passwords de roles de app (re-hash) — **OK explícito**
- [ ] ⚠ Aplicar pg_hba acotado + `pg_reload_conf()` (NO restart) — **OK explícito**
- [ ] Verificar: sin `0.0.0.0/0`/`md5` + todas las apps conectan + `password_encryption=scram`
- [ ] Actualizar `hardening.md` (fila axioma #1 → verde)

---

## H13 — `npm audit` de hub (47 backend / 18 frontend) + higiene de dependencias

- **Server(s):** apps en axioma (hub) · **Sev:** 🟡 · **Riesgo interv.:** Alto · **CIS 7**

> Bumpear dependencias puede introducir **breaking changes** en una app viva. hub ya está online y
> estandarizada (Fase 4). El fix combina remediar las vulnerabilidades **sin romper el build/runtime** +
> definir una higiene mínima repetible. (El *proceso formal* de gestión de vulnerabilidades es el gap
> G4, fuera de este plan; acá solo la remediación técnica puntual de hub + una rutina básica.)

**Objetivo (verde).** `npm audit` de hub (backend y frontend) sin vulnerabilidades **high/critical**
(las `moderate/low` aceptadas quedan documentadas con justificación), hub sigue construyendo y corriendo
(health 200, login OK), y queda una rutina mínima documentada (correr `npm audit` en cada deploy/mensual).

**Procedimiento.**
1. **(lectura)** Foto exacta en un checkout de trabajo (NO en `/var/www/hub` directamente; clonar/copiar
   a un scratch): `npm audit --json` en backend y frontend del monorepo → clasificar por severidad y ver
   cuáles tienen fix por `npm audit fix` (no-breaking) vs. cuáles requieren major bump.
2. Aplicar primero lo no-breaking en el checkout de trabajo: `npm audit fix` (sin `--force`). Correr el
   **build + tests** ahí. Revisar `git diff package-lock.json`.
3. Para las que requieren `--force`/major bump: evaluar una a una, buildear y probar en el checkout; si
   rompen, anotarlas como aceptadas con justificación (o planificar el upgrade en su propia ventana).
4. Desplegar a `/var/www/hub` **como `hubapp`** (nunca root — regla de propiedad del estándar), respetando
   el flujo de deploy de hub: `sudo -u hubapp npm ci` desde la RAÍZ del monorepo (workspaces),
   `prisma generate` desde la raíz, build backend+frontend, `pm2 reload hub` + `chown -R hubapp:hubapp
   /var/www/hub` final + `find … -not -user hubapp` vacío. ⚠ **REQUIERE OK EXPLÍCITO**, ventana de bajo
   tráfico (hub reinicia).
5. Backup previo: `tar /var/backups/hub-preaudit-<ts>.tar.gz` + `pg_dump hub_db` (por si algún bump toca
   Prisma/migraciones) + `dump.pm2`.

**Riesgo.** Alto. Un bump mayor puede romper el build o el runtime de hub. `npm audit fix --force` es
especialmente peligroso (sube majors). Mitigación: **todo se prueba en un checkout de trabajo aislado
primero**; a prod solo va lo que buildeó y pasó health; una app (hub), una ventana, rollback con tar+pm2.

**Rollback.** Restaurar `node_modules`/lockfile desde el tar previo (o `git checkout package-lock.json` +
`npm ci` de la versión anterior) + `pm2 reload hub`. Si tocó DB, restaurar `hub_db` desde el dump.

**Verificación.**
- `npm audit` backend y frontend de hub → 0 high/critical (o listado justificado de lo aceptado).
- hub: `https://hub.axiomacloud.com` 200, `https://api.hub.axiomacloud.com/health` 200, login funcional.
- `find /var/www/hub -not -user hubapp` vacío (regla de propiedad tras el deploy).
- Rutina de higiene documentada (correr `npm audit` en cada deploy / mensual).

**Sub-pasos:**
- [ ] Foto `npm audit --json` back+front en checkout de trabajo + clasificación por severidad (lectura)
- [ ] `npm audit fix` (no-breaking) en el checkout + build + tests
- [ ] Evaluar majors que requieran `--force`, una a una (build/prueba) → aplicar o justificar aceptación
- [ ] Backup: tar `/var/www/hub` + `pg_dump hub_db` + `dump.pm2`
- [ ] ⚠ Desplegar a `/var/www/hub` como `hubapp` + `pm2 reload` + `chown -R` final — **OK explícito**
- [ ] Verificar: 0 high/critical + hub health/login OK + `find -not -user hubapp` vacío
- [ ] Documentar rutina mínima de higiene (npm audit por deploy/mensual)

---

## H11 — `axio-ml` corre como `axiomacloud` → usuario dedicado

- **Server(s):** axiodemo · **Sev:** 🟢 · **Riesgo interv.:** Alto · **CIS 5**

> Es la **Fase 6** de la estandarización (hook ollama + normalizar owner). Riesgo de intervención alto:
> cambiar el owner de un servicio Python/uvicorn + su relación con ollama (~31 GB de modelos) y los
> permisos de `/opt/axio-ml-service` puede dejar el servicio caído. Se ejecuta con el ciclo de la Fase 6,
> no de forma suelta. Este plan lo referencia para completar el verde; la ejecución sigue el tracker de
> estandarización.

**Objetivo (verde).** `axio-ml` corre bajo un usuario dedicado (ej. `axiomlapp`/`axioapp` según se
decida en Fase 6), NO `axiomacloud`; `/opt/axio-ml-service` es propiedad de ese usuario; el servicio
(uvicorn :8001 + ollama) arranca en boot bajo ese usuario y responde. Sin residuos de `axiomacloud`.

**Procedimiento.**
1. **(lectura)** Relevar el estado actual: `ps -eo user,args | grep -E 'uvicorn|axio-ml'`, unit systemd
   del servicio, owner de `/opt/axio-ml-service` y del venv, cómo se lanza ollama y de quién son los
   modelos (`~/.ollama` de qué usuario). Decidir el nombre del usuario dedicado con el usuario.
2. **Preparación (regla de oro):** ventana + backup: `.env` (ya cifrado SOPS), copia de la unit systemd,
   `dump.pm2` si aplica, y anotar el comando de arranque actual para rollback. Los **modelos ollama NO se
   respaldan** (se re-descargan; estándar §11) — pero confirmar de dónde los lee el nuevo usuario para no
   re-bajar 31 GB innecesariamente (mover/compartir `~/.ollama` o apuntar `OLLAMA_MODELS`).
3. **Ejecución (Fase 6):** crear usuario dedicado (nologin), `chown -R` de `/opt/axio-ml-service` + venv,
   ajustar la unit systemd para correr bajo el nuevo usuario, resolver el hook ollama (bind loopback ya
   OK), arrancar y `systemctl enable`. ⚠ **REQUIERE OK EXPLÍCITO**, una acción a la vez.
4. **Verificación + cierre** por el ciclo de Fase 6 (health :8001 + boot test + sin residuos de
   `axiomacloud` + tildar tracker de estandarización + inventario §2).

**Riesgo.** Alto. Cambiar owner + unit + relación con ollama puede dejar uvicorn sin permisos sobre el
venv/modelos o sin poder hablar con ollama → servicio caído. axiodemo es demo (no crítico), lo que baja
el impacto de negocio, pero el fix es delicado. Mitigación: relevar bien de dónde salen los modelos,
una acción a la vez, rollback con la unit vieja.

**Rollback.** Restaurar la unit systemd previa (owner `axiomacloud`) + `systemctl daemon-reload` +
restart. Revertir el `chown` si se hizo (volver a `axiomacloud`). El servicio vuelve al estado anterior.

**Verificación.**
- `ps -eo user,args | grep uvicorn` → corre bajo el usuario dedicado, no `axiomacloud`.
- `curl -s 127.0.0.1:8001/…` (health del servicio) responde; axio-backend sigue usándolo.
- `systemctl is-enabled <unit>` → enabled; boot test levanta bajo el usuario dedicado.
- Sin procesos/archivos residuales de `axiomacloud` para axio-ml.

**Sub-pasos:**
- [ ] Relevar owner/unit/venv/ollama de axio-ml + decidir usuario dedicado (lectura)
- [ ] Preparación: ventana + backup (unit, `.env` SOPS) + plan de modelos ollama (no re-bajar 31 GB)
- [ ] ⚠ Crear usuario dedicado + `chown` + ajustar unit + arrancar + enable (ciclo Fase 6) — **OK explícito**
- [ ] Verificar: uvicorn bajo usuario dedicado + health :8001 + boot test + sin residuos
- [ ] Cerrar en el tracker de estandarización (Fase 6) + inventario §2 + `estandar-despliegue.md`

---

## Registro de ejecución

> Bitácora corta: fecha · hallazgo · qué se hizo · resultado. Se completa a medida que se avanza.

| Fecha | Hallazgo | Acción | Resultado |
|---|---|---|---|
| 2026-07-18 | — | Redacción del plan de remediación (solo escritura de doc, sin tocar servers) | ✅ 10 hallazgos técnicos en 4 olas de riesgo |
| 2026-07-18 | H14 | Diagnóstico: colector nginx apunta a `:8088` (no `:80`), stub_status ya presente y con datos en los 3 | ✅ verde — sin intervención; solo comentario `:80`→`:8088` corregido en repo |
| 2026-07-18 | H12 | `remote set-url origin` de axio → `github-axio:AxiomaCloud/axio.git` (SSH, deploy key funcional; el plan asumía HTTPS/no había credencial) + fetch de verificación | ✅ verde — trae axio (no hub), working tree intacto, sin pull |
| 2026-07-18 | H06 | `.env` → 600 con backup: axiodemo x2 (owner OK), dev-1 x3 (elore directo; mediflow `chown root`; checkpoint `chown axiomacloud`) | ✅ verde — 5 en 600, owners leen OK, apps vivas |
| 2026-07-18 | H08 | Diagnóstico: monitoreo pgBackRest **ya desplegado 26-May** en dev-1 (colector `pgbackrest-collect.py` + cron 15min + health.d + statsd.d), charts con datos, alarmas en CLEAR. Solo se reconcilió el colector del repo (versión multi-repo del server, md5-idéntica) — sin tocar dev-1 | ✅ verde — ya estaba andando; repo puesto al día |
| 2026-07-19 | H07 | FAIL sistemático en PG14 diagnosticado como **bug del drill, no de los backups** (pg_hba `scram` copiado del cluster local → rechazo por auth; + chequeo de conectividad sin esperar el replay). Arreglado `70-restore-drill.sh` y re-corrido | ✅ verde — las 3 stanzas PASS (585/178/34 tablas, WAL al día); 1ª corrida OK de AxiomaCloudProd y clubix |
| 2026-07-19 | H09 | Relevamiento (lectura) en dev-1: community `public` pero ya acotada por `com2sec` a 2 IPs dattaweb; bind `0.0.0.0:161`. `tcpdump` prueba que **dattaweb poletea cada ~1s y snmpd responde** | ⏸ bloqueado — Camino A descartado; Camino B exige coordinar la nueva community con el proveedor |

---

## Relación con otros documentos

- **Fuente de los hallazgos:** [`dossier-auditoria-seguridad.md`](./dossier-auditoria-seguridad.md) §7 (H01–H14) y §8 (G1–G9, fuera de alcance).
- **H01/H03/H04/H06/H09:** detalle técnico y estado por server en [`hardening.md`](./hardening.md).
- **H07:** procedimiento y cadencia en [`restore-drill-procedure.md`](./restore-drill-procedure.md); traza en `drill-history.csv`.
- **H08:** config de alarma en [`netdata/health.d/pgbackrest.conf`](../netdata/health.d/pgbackrest.conf) + `setup-netdata-cloud.md` §5.
- **H11/H12/H13:** ciclo de ejecución en [`plan-trabajo-estandarizacion.md`](./plan-trabajo-estandarizacion.md) (Fases 4/6) y molde en [`estandar-despliegue.md`](./estandar-despliegue.md).
- **H03:** custodia SOPS en `infra-secrets/env/pgbackrest/repo2-r2.env`; arquitectura en [`pgbackrest-setup.md`](./pgbackrest-setup.md).
