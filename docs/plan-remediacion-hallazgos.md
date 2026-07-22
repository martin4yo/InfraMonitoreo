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
| 1 | H06 | `.env` laxos → 600 | dev-1, axiodemo | 🟡 | Muy bajo | [!] **REABIERTO (2026-07-20)** — el verde era falso: se verificó solo dev-1 y contra el proceso vivo → incidente en prod (mini axioma) |
| 1 | H12 | `origin` de axio mal apuntado (a ProHub) | axiodemo | 🟡 | Muy bajo | [x] (2026-07-18) |
| **2 — Monitoreo / verificación (aditivos)** | H08 | Alarma antigüedad backup pgBackRest sin desplegar | dev-1 | 🟡 | Bajo | [x] (2026-07-18) |
| 2 | H07 | Restore drills AxiomaCloudProd+clubix + cadencia mensual | infra (backup) | 🟡 | Bajo | [x] (2026-07-19) |
| **3 — Hardening de servicios (config, recargable)** | H09 | snmpd community `public` + `agentaddress` público | dev-1 | 🟡 | Bajo-Medio | [!] bloqueado — coordinar con dattaweb |
| 3 | H03 | Creds R2 en claro en los `.conf` | dev-1, axioma, clubix, axiodemo (+drp) | 🟡 | Medio | [x] (2026-07-19) |
| **4 — Invasivos sobre apps/DB en prod (⚠ OK explícito)** | H04 | Apps escuchando en `0.0.0.0` → loopback | axioma, dev-1, axiodemo | 🟡 | Medio-Alto | [~] parcial (2026-07-20) — 5 en verde; Next.js bloqueadas por patrón `-H`/redirects |
| 4 | H01 | `pg_hba` `0.0.0.0/0 md5` → rangos + scram | axioma | 🔴→🟡 | Alto | [x] (2026-07-22) |
| 4 | H13 | `npm audit` hub (47 back / 18 front) + higiene | apps (axioma) | 🟡 | Alto | [x] (2026-07-20) — desplegado y verificado |
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

> **HECHO (2026-07-19) — mecanismo (a) endurecido + limpieza de `.bak`; sin tocar ningún `.conf` vivo.**
>
> **El relevamiento corrigió dos premisas del plan:**
> 1. **La postura de los `.conf` ya era correcta**, no "creds expuestas": los 5 están en `640` con owner
>    correcto (`pgbackrest:pgbackrest` o `postgres:postgres`; drp `root:postgres`) y **los grupos tienen
>    un solo miembro**, así que ningún usuario sin `sudo` los lee. Ninguno está versionado en git.
> 2. **La superficie real estaba en otro lado: 4 archivos `.bak` con credenciales en claro** que el
>    inventario de "5 archivos" del plan no contemplaba (axioma, clubix, axiodemo y dev-1 ×2).
>
> **Por qué (a) y no (b)/(c)** (ambas verificadas como viables en 2.58 — `config-include-path` y el
> prefijo `PGBACKREST_` existen en el binario): pgBackRest **siempre** necesita el secreto en claro en
> ejecución, así que (b) solo lo mueve de un archivo `640` owner-only a uno `600` owner-only —
> ganancia marginal a cambio de editar 5 configs de backup productivas. (c) es **peor que el estado
> actual**: las creds por entorno quedan legibles en `/proc/<pid>/environ`. La mejora real estaba en
> eliminar los `.bak`.
>
> **Verificación previa al borrado (clave):** los `.bak-2026071[78]` contenían las claves S3
> **pre-rotación** (distintas del vivo), pero se comparó hash por clave y el **`repo2-cipher-pass` era
> IDÉNTICO al vivo** en los 4 → borrarlos no arriesgaba el cipher (que NO se rota: si se pierde, los
> backups R2 quedan irrecuperables). Los 2 `.bak` de mayo en dev-1 **no tenían creds** (el `grep -l`
> inicial los contó por otra línea) y se limpiaron por higiene.
>
> **Ejecución:** respaldo previo de los 4 en `/root/pgbackrest-bak-archive/creds-bak-20260719-2030.tar.gz`
> (`600`, root-only) en cada server → borrado → **`pgbackrest check` de las 4 stanzas
> `completed successfully` en repo1 y repo2**. Estado final: 0 `.bak` en los 5 servers, `.conf` en `640`.
>
> **Límite documentado (aceptado):** pgBackRest lee su config en claro y no consume SOPS. La fuente de
> verdad cifrada sigue siendo `infra-secrets/env/pgbackrest/repo2-r2.env`; los `.conf` son copias
> operativas protegidas por permisos + firewall. Todo cambio futuro de creds se hace desde SOPS y
> **sin dejar `.bak` con el valor viejo** (usar el archivo de archivo `600` de root si hace falta respaldo).

**Sub-pasos:**
- [x] Relevar los 5 archivos + permisos (lectura, **enmascarando**) → ya en `640`+owner correcto, no versionados
- [x] Decidir mecanismo (a/b/c) con el usuario y documentarlo → **(a)** + limpieza de `.bak` (b/c descartadas con fundamento)
- [x] Verificar que los `.bak` no tienen el `cipher-pass` distinto al vivo (hash por clave) antes de borrar
- [x] Respaldar los 4 `.bak` en tar `600` root-only por server
- [x] Borrar `.bak` con creds en axioma / clubix / axiodemo / dev-1 (×2) + 2 residuos de mayo
- [x] Verificar `pgbackrest check` de las 4 stanzas (repo1+repo2) → `completed successfully`
- [x] Verificar 0 `.bak` restantes + `.conf` en `640` en los 5 servers

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

> **PARCIAL (2026-07-20) — 5 ítems en verde; el resto BLOQUEADO por un hallazgo transversal de Next.js.**
>
> **El relevamiento corrigió tres premisas del plan:**
> 1. **Todos los `proxy_pass` de nginx ya apuntan a loopback** en los 3 servers → el riesgo que más
>    preocupaba al plan (rebindear y romper el proxy) **no existía**. Paso 2 del procedimiento: verde.
> 2. **La lista de puertos estaba desactualizada.** En dev-1, 3 de los 5 puertos listados ya estaban en
>    loopback o cambiaron de dueño; aparecieron listeners nuevos no contemplados en axioma
>    (`:8089` hub, `:8080` evolution-api, `:3700` elore, `:5300` mediflow).
> 3. **`-H 127.0.0.1` en el ecosystem NO arregla 5 de las 12 apps**, contra lo que asume el plan:
>    - **PM2 `exec_mode: 'cluster'`** → el socket lo abre el God Daemon y PM2 **ignora** `--hostname`/
>      `HOST`/`HOSTNAME`. Prueba: dev-1 `elore` **ya tenía** `--hostname localhost` y escuchaba en `*:3000`.
>    - **Código con `server.listen(port, cb)` sin argumento host** → ignora la env var. checkpoint-web
>      (`server.ts:33`), mediflow (`server.js:233`) y axio-backend (`dist/server.js:117`) **ya tenían**
>      `HOSTNAME`/`HOST=127.0.0.1` en su entorno, inerte. Requiere **cambio de código**, no de infra.
>
> **⛔ HALLAZGO TRANSVERSAL — el flag `-H`/`--hostname` de Next.js rompe los redirects.**
> Al aplicarlo en axioma `:3700` elore, el bind funcionó pero Next pasó a construir las **URLs absolutas
> de redirect** con ese host: `307 → https://localhost:3700/login` en vez de `https://elore.com.ar/login`
> → **todo el flujo de login inutilizable**. Se revirtió en el acto (`diff` vacío contra el `.bak`).
> Descartado que sea config: `APP_URL`/`NEXT_PUBLIC_APP_URL` correctos y nginx pasa `Host $host` bien en
> las 5 locations — **el redirect malo lo genera Next desde el hostname de bind**.
> **Afecta a TODAS las Next que quedan** (hub ×2, elore ×2, parse dev-1) → resolver **una sola vez**
> (probablemente `trustHost`/`assetPrefix`/`X-Forwarded-Host`) antes de reintentar app por app.
>
> **⚠ Criterio de verificación ampliado (obligatorio de acá en más).** `curl → 200` **habría dado elore
> por verde con el login roto en producción**: seguía devolviendo 307. Hay que inspeccionar el
> **`Location` de toda respuesta 3xx** y compararlo contra el valor capturado ANTES del cambio.
>
> **Matiz que invalidó el supuesto de "apps gemelas":** axioma y dev-1 comparten el mismo
> `ecosystem.config.js` de parse, pero axioma corre el **build standalone** (`server.js`, que lee
> `process.env.HOSTNAME`) y dev-1 arranca por el **CLI `next start`** (que lo ignora y solo respeta `-H`).
> El ecosystem es idéntico; el binario que corre, no. El cambio en dev-1 fue **inerte** (bind siguió en
> `*:8087`) → se revirtió igual: config que declara algo que no ocurre es peor que no tenerla.
>
> **Hallazgos colaterales (fuera de H04, para la estandarización):**
> - **dev-1 `:5000` mediflow-backend corre como `root`** — viola la regla de propiedad del estándar. Más
>   grave que el bind en sí.
> - **dev-1 `:8086` checkpoint-web corre como `axiomacloud`**, no `checkpointapp`.
> - **`/var/www/elore/ecosystem.config.js` es `root:root`** (debería ser `eloreapp:eloreapp`).
> - **`pm2 reload --update-env` NO aplica cambios de bind** (reusa el env cacheado): hace falta
>   `pm2 restart <ecosystem> --only <app> --update-env` releyendo el archivo.
> - **`PM2_HOME` de `parseapp` en axioma es `/var/www/parse/.pm2`**, no `/home/parseapp/.pm2` (no existe).
>   Un `pm2 save` al home equivocado falla con `EACCES` y **deja sin rollback**.
> - axiodemo tiene `3001/tcp ALLOW` en ufw pero **nada escucha en 3001** → regla huérfana a limpiar.

**Sub-pasos:**
- [x] Mapear listeners `0.0.0.0` + proceso + host que los fija, por server (lectura) → lista del plan corregida
- [x] Confirmar `proxy_pass` de nginx apunta a loopback (lectura) → **los 3 servers ya en loopback**
- [x] ⚠ axioma `:8087` parse-front → `HOSTNAME: '127.0.0.1'` (standalone) + restart — **VERDE** (health 200)
- [x] ⚠ dev-1 CUPS `:631` → **`snap disable cups`** (nadie imprime; menos superficie que loopback) — **VERDE**
- [x] ⚠ netdata `:19999` → `bind to = 127.0.0.1` en axioma + dev-1 + axiodemo — **VERDE** (ACLK saliente intacto: `claimed=true`, `aclk-available=true` en los 3)
- [!] axioma `:3700` elore → **REVERTIDO**: `-H` rompió los redirects de login (ver hallazgo transversal)
- [!] dev-1 `:8087` parse-front → **REVERTIDO**: `HOSTNAME` inerte (corre por CLI, no standalone); necesita `-H`
- [!] dev-1 `:3000` elore → **NO EJECUTADO**: el ecosystem ya trae `--hostname localhost` (hoy inerte por
      `cluster_mode`); pasar a `fork` **activaría el flag conocido-roto** en producción. Frenado antes de tocar
- [ ] hub-frontend axioma `:8089` + dev-1 `:8089` → salteados (misma vía `-H` que falló)
- [ ] **Resolver el patrón Next.js `-H` vs. redirects (una vez, para las 5 apps)** ← desbloquea lo anterior
- [ ] Verificar `ss` en loopback + health **+ `Location` de los 3xx** + boot test, por app

**Reclasificación del alcance (2026-07-20).** Lo que queda NO es todo de infra:

| Tanda | Ítems | Naturaleza | Destino |
|---|---|---|---|
| **A/B/C ejecutadas** | axioma parse, CUPS, netdata ×3 | Infra | ✅ verde |
| **Next.js bloqueadas** | hub ×2, elore ×2, parse dev-1 | Infra, pero bloqueadas por el patrón `-H`/redirects | Resolver el patrón primero |
| **D — cambio de CÓDIGO** | axiodemo `:5300` axio-backend, dev-1 `:8086` checkpoint-web, dev-1 `:5000` + axioma `:5300` mediflow | `server.listen(port, cb)` sin host → **no se arregla desde infra** | **Sale de H04** → issue en cada repo de aplicación |
| **E — excepciones aceptadas** | axiodemo `:8001` axio-ml, axioma `:8080` evolution-api | Ver abajo | Documentadas, **no se rebindean** |

**Puntos de rollback vigentes (2026-07-20).** Si hay que revertir algo de esta pasada:

| Cambio | Cómo revertir |
|---|---|
| axioma `:8087` parse-frontend | `cp /var/www/parse/ecosystem.config.js.bak-20260720-112311 /var/www/parse/ecosystem.config.js` + `pm2 restart` releyendo el ecosystem (`PM2_HOME=/var/www/parse/.pm2`, **no** el home de `parseapp`) |
| CUPS dev-1 | `sudo snap enable cups` (se deshabilitaron `cups.cupsd` + `cups-browsed`) |
| netdata (axioma / dev-1 / axiodemo) | `cp /etc/netdata/netdata.conf.bak-<ts> /etc/netdata/netdata.conf` + `systemctl restart netdata` en el server que corresponda |

axioma `:3700` elore y dev-1 `:8087` parse **ya fueron revertidos** (`diff` vacío contra sus `.bak`) —
no queda nada pendiente de deshacer ahí.

**Excepciones aceptadas (E).**
- **axiodemo `:8001` axio-ml — NO rebindear.** ufw tiene `8001 ALLOW IN 149.50.148.198`: **dev-1 lo
  consume remoto**. Bindear a loopback **rompe esa integración**. Se acepta en `0.0.0.0` acotado por ufw
  a esa única IP. (Alternativa futura: bindear a la IP privada específica en vez de `0.0.0.0`.)
- **axioma `:8080` evolution-api** — app de tercero **sin ecosystem versionado** en `/var/www/evolution-api`;
  el bind sale de su `.env`/código upstream. Baja prioridad, investigar antes de tocar.

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
- [x] Relevar pg_hba actual + orígenes reales (`pg_stat_activity`) + roles con hash md5 (lectura)
- [x] Backup `pg_hba.conf.bak-20260722-100113` + redactar el `pg_hba` nuevo acotado + scram
- [x] ⚠ `password_encryption=scram` + re-setear passwords de roles de app (re-hash) — 0 roles con hash md5
- [x] ⚠ Aplicar pg_hba acotado + `pg_reload_conf()` (NO restart)
- [x] Verificar: sin `0.0.0.0/0` activo + todas las apps conectan (hub/mediflow/mini/parse/evolution/netdata por loopback, 0 auth failures) + `password_encryption=scram`
- [x] Actualizar `hardening.md` (fila axioma #1 → verde)

> **Residual cerrado el mismo día (2026-07-22, 2ª pasada):** las 2 reglas de `mediflow_db`/`mediflowuser`
> con método `md5` fueron migradas a `scram-sha-256` (backup previo + `pg_reload_conf()`), y se verificó
> una **conexión nueva** de `mediflowuser` autenticando OK tanto directa (`:5432`) como vía pgbouncer
> (`:6432` — mediflow conecta por pgbouncer, dato relevado en esta pasada). **0 líneas `md5` activas**
> en el `pg_hba` de axioma. H01 queda cerrado sin residual.

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
   **`prisma generate` desde `backend/`** (⚠ **corregido 2026-07-20**: el plan decía "desde la raíz" y
   **eso hace fallar el deploy** — `prisma.config.ts` apunta a `prisma/schema.prisma` pero el schema vive
   en `backend/prisma/schema.prisma` y no existe `prisma/` en la raíz, ni siquiera en prod), build
   backend+frontend, `pm2 reload hub` + `chown -R hubapp:hubapp /var/www/hub` final +
   `find … -not -user hubapp` vacío. ⚠ **REQUIERE OK EXPLÍCITO**, ventana de bajo tráfico (hub reinicia).
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

> **TRABAJO EN CHECKOUT COMPLETO (2026-07-20) — listo para desplegar, NO desplegado.**
> Prod verificado intacto al terminar (mismo md5 de lockfile, commit `311a6ed`, ambos procesos `online`).
>
> **Resultado: 61 → 11 vulnerabilidades · critical 3 → 0 · high 20 → 3**, sin un solo `--force` (todo
> dentro de semver: 92 versiones cambiadas, 8 agregadas, 85 eliminadas). El fix más valioso:
> `axios 1.13.2 → 1.18.1`, que cerró **23 advisories**. La cifra del plan ("47 back / 18 front") estaba
> desactualizada: hoy son **61 en total** contando el árbol de workspaces desde la raíz — no se pueden
> sumar back+front por separado porque el monorepo hoistea y hay doble conteo.
>
> **Build y tests en verde, pero el `audit fix` ROMPIÓ el build del backend.** El bump de axios endureció
> el tipado de `resp.headers` y `tsc` falla en `parseOAuthService.ts:99` (TS2322). Causalidad **probada**
> con un checkout de control sin el fix (que compila limpio). Arreglo: **2 líneas**, sin tocar lógica
> (`String(resp.headers['content-type'] || …)` + cast en `content-disposition`). Con eso: backend OK,
> frontend OK (Next 15.5.20), **36/36 tests backend + 21/21 frontend PASS**.
> → **El deploy ya no es solo un lockfile: requiere un commit de código en ProHub.**
>
> **Los 3 high remanentes** (ninguno tiene fix no-breaking — lo que npm ofrece son *downgrades*):
> - **`pdfjs-dist`** 🔴 — **el único con cadena de explotación real**: ejecución de JS arbitrario al abrir
>   un PDF malicioso, y el input **lo controla el usuario** (portal de proveedores subiendo facturas).
>   **NO aceptar sin mitigar**: aplicar `isEvalSupported: false`/`disableEval: true` en el `getDocument()`
>   de `basicParseService.ts` (una línea, no rompe nada) y planificar el salto a v4+ aparte.
> - **`nodemailer`** 🟡 — runtime alcanzable, pero las advisories se explotan vía direcciones/contenido
>   controlados por atacante y en hub los destinatarios salen de la DB. Aceptar; agendar bump a v7.
> - **`serialize-javascript`** 🟢 — **build-time puro** (vía `@rollup/plugin-terser` ← `next-pwa`), no llega
>   a runtime. Aceptar sin reservas.
>
> **Sobre dev vs runtime:** `npm audit --omit=dev` **no sirve acá** — da los mismos 11 porque `next-pwa` y
> `webpack` están declarados en `dependencies` aunque solo se usen al buildear. La separación hay que
> hacerla por análisis de uso.
>
> **Dos errores del plan corregidos:** (1) `prisma generate` va **desde `backend/`**, no desde la raíz —
> seguir el plan literal **haría fallar el deploy**; (2) la suite de tests no corre tal cual: falta
> `ts-node` en el manifiesto (falla igual en la línea base) → agregarlo a `devDependencies`.
>
> **Riesgo que NO se puede validar desde el checkout:** ningún test toca S3 ni envío de mails reales, y
> hubo dos movimientos grandes — **AWS SDK `3.932.0 → 3.1090.0`** (~158 minors) y `@prisma/engines-version`
> saltando a línea **7.1.1** mientras `@prisma/client` queda en **6.19.0**. `prisma generate` funciona,
> pero es lo primero a mirar si algo se comporta raro. → El post-deploy debe incluir **una subida real a
> S3 y un envío de mail de prueba**, además del health 200 y el login.
>
> **Artefactos:** `package-lock.AFTER.json` y `parseOAuthService.PATCHED.ts` en el scratchpad de la sesión;
> en axioma, `~/h13-scratch/hub` (remediado) y `~/h13-scratch/hub-base` (control) + los `audit-*.json`.

**Sub-pasos:**
- [x] Foto `npm audit --json` back+front en checkout de trabajo + clasificación por severidad (lectura) → **61 vulns (3 critical / 20 high)**
- [x] `npm audit fix` (no-breaking) en el checkout + build + tests → **61→11**; requirió fix de 2 líneas por el bump de axios; **57/57 tests PASS**
- [x] Evaluar majors que requieran `--force`, una a una → **ninguno aplicado** (los 3 restantes solo ofrecen downgrade) + justificación por severidad
- [x] **Decidido:** deploy con lockfile + fix de tipos + **mitigación de `pdfjs`** (el usuario confirmó que hub **no es productiva** — publicada pero sin usuarios reales)
- [x] Backup: tar `/var/www/hub` + `pg_dump hub_db` + `dump.pm2` → `/var/backups/hub-h13-predeploy-20260720-164637.*`
- [x] ⚠ Desplegado a `/var/www/hub` como `hubapp` + `pm2 reload` + `chown -R` final
- [x] Verificar: **0 critical** + health/login OK + `find -not -user hubapp` **vacío** + prueba real de mail y de parseo PDF (**S3: N/A, ver abajo**)
- [ ] Documentar rutina mínima de higiene (npm audit por deploy/mensual)

> **✅ DESPLEGADO Y VERIFICADO (2026-07-20).** Sin rollback. Commit `67a9d83` sobre `311a6ed`, **local sin push**
> (se desplegó copiando los 4 archivos, no con `git pull` — eso además evitó pisar los `sw.js`/`workbox-*.js`
> sin commitear que prod tenía por el build).
>
> **Verificación:** `hub.axiomacloud.com` **200** · `api.hub.axiomacloud.com/health` **200** · `/auth/login` **200** ·
> login → **401 `Invalid credentials`** (prueba que **Prisma consulta la tabla `User` OK** — era el riesgo real del
> engine 7.1.1 con client 6.19.0) · `npm audit` en prod → **11 vulns, 0 critical** · `find -not -user hubapp` **vacío** ·
> `pm2-hubapp` enabled+active, sin restart loop. Aplicado el criterio ampliado del incidente de H04: se verificó el
> **`Location`** de cada 3xx (el único es 80→443 y apunta al dominio público, no a `localhost`).
>
> **Los 2 riesgos que no se podían validar desde el checkout:**
> 1. **AWS SDK — el riesgo NO existía.** hub **no usa el SDK**: 0 imports de `@aws-sdk` en `backend/src`,
>    `frontend/src`, `shared` y en el `dist` compilado. Está declarado en el manifiesto pero nunca se importa; los
>    archivos se guardan **en disco local vía multer** (`process.cwd()/uploads`). → **No hay flujo de S3 que probar.**
>    Dos consecuencias: son **~85 paquetes de peso muerto** removibles del manifiesto, y las credenciales
>    `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` del `.env` **no las usa nadie** → **revisar si siguen activas en AWS
>    y revocarlas**.
> 2. **Mail — PASS real**: `SMTP verify OK` + `sendMail OK`, aceptado por Gmail. **Mitigación de `pdfjs` validada**
>    con un parseo real (3819 chars) → la vuln explotable vía PDFs del portal de proveedores queda cerrada.
>
> **`ts-node`: el fix no era donde parecía.** Agregarlo a las `devDependencies` de backend y frontend **no alcanza** —
> jest lo resuelve desde la **raíz del monorepo**. Movido a la raíz, la suite corre sin trucos por primera vez.
>
> **Confirmado en vivo el error del plan:** `prisma generate` desde la raíz **falla**; desde `backend/` funciona.
>
> **Hallazgo colateral (no tocado, requiere OK aparte):** el `/var/www/hub/backend/.env` está **malformado** —
> línea 13: `JWT_SECRET=<...>==# AWS S3 (configurar cuando sea necesario)`, comentario pegado al valor sin salto de
> línea. `dotenv` lo tolera, pero **rompe cualquier `source`/`set -a` desde bash** (`syntax error near unexpected
> token '('`) → va a morder a cualquier script de deploy o backup que lea el `.env` desde shell.

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
| 2026-07-19 | H03 | Relevamiento mostró los `.conf` ya en `640`+owner correcto (no versionados) y la superficie real en **4 `.bak` con creds pre-rotación**. Mecanismo **(a)**: verificado que el `cipher-pass` de los `.bak` era idéntico al vivo → respaldo en tar `600` root-only → borrados los 4 (+2 residuos sin creds) | ✅ verde — 0 `.bak` en los 5 servers, `check` de las 4 stanzas OK (repo1+repo2); ningún `.conf` vivo tocado |
| 2026-07-20 | H04 | Relevamiento: **todos los `proxy_pass` ya en loopback** (riesgo principal inexistente); lista de puertos del plan corregida; detectado que `-H`/`HOSTNAME` **no sirve en 5 de 12 apps** (PM2 `cluster` ignora el flag; 4 apps hacen `server.listen(port, cb)` sin host) | ⚠ el plan asumía un fix universal que no aplica |
| 2026-07-20 | H04 | Aplicado: axioma `:8087` parse-front → loopback; **CUPS dev-1 deshabilitado** (`snap disable`, nadie imprime); netdata → `bind to = 127.0.0.1` en los 3 servers | ✅ 5 ítems en verde — health 200, ACLK de netdata intacto (`claimed`/`aclk` true en los 3) |
| 2026-07-20 | H04 | axioma `:3700` elore: `-H` bindeó bien pero **Next pasó a redirigir el login a `https://localhost:3700`** → rollback inmediato. `curl → 200` no lo detectaba (seguía 307): **criterio de verificación ampliado al `Location` de los 3xx** | ⛔ revertido — hallazgo transversal que bloquea las 5 apps Next |
| 2026-07-20 | H04 | dev-1 `:8087` parse: `HOSTNAME` **inerte** (corre por CLI `next start`, no standalone como axioma — mismo ecosystem, distinto binario) → revertido. dev-1 `:3000` elore: **frenado ANTES de tocar** — pasar a `fork` activaría el `--hostname localhost` ya presente, reproduciendo el fallo | ⏸ pendientes de resolver el patrón Next.js |
| 2026-07-20 | **H06** | ⛔ **Incidente en prod**: el usuario reinició **mini en axioma** → 500 por `.env` ilegible. El `chmod 600` del 17/07 se validó **solo en dev-1** y **contra el proceso vivo** (que no revalida permisos) → bomba latente 3 días. El usuario lo destrabó con `chmod 640` | ⚠️ **hallazgo reabierto** — regla de verificación corregida (owner vs. usuario *configurado*, app por app y server por server) |
| 2026-07-20 | H06 | Auditoría owner-vs-proceso en los **5 servers**: el `640` de mini **no expuso nada** (grupo de 1 miembro que ya era owner). Detectadas 2 bombas latentes (mini frontend/print-agent en axioma), **`axio/.env` en 664 world-readable** en dev-1, y directorios `/var/www/mini` en **777** (el `.env` es sustituible pese al 600) | 📋 inventario completo en `hardening.md` §5 |
| 2026-07-20 | **(nuevo)** | Al investigar lo anterior: **`checkpoint-web` en dev-1 en crash loop desde hace 3 días** (`restart_time=108455`, ~24/min) por una **migración a `checkapp` abandonada en enero** — el `.env` quedó en el owner viejo. Costaba **~0.6 de load sostenido**. `pm2 stop` + `save` de la instancia rota | ✅ contenido — **load 1m 1.50→0.88 (−41%)**, sitio intacto (lo sirve la instancia vieja); decisión completar/abortar pendiente |
| 2026-07-20 | H13 | Trabajo completo en checkout aislado (axioma, Node 20): **61 → 11 vulns, critical 3 → 0**, sin `--force`. El `audit fix` rompió el build (tipado de axios) → fix de 2 líneas, **57/57 tests PASS**. Detectados 2 errores del plan (`prisma generate` desde la raíz **haría fallar el deploy**; falta `ts-node`) | ⏸ listo, **NO desplegado** — el deploy requiere commit de código en ProHub + decisión sobre mitigar `pdfjs` |
| 2026-07-20 | H06 | `axio/.env` en dev-1: resultaron **7 archivos** en `664` (no 2), incluidos `.env.example` de 2588/2037 bytes → todos a `600 axioapp:axioapp`. Owner ya era el configurado (4 fuentes: ecosystem, árbol, barrido de 11 PM2_HOME, ausencia de unit/vhost) → sin bomba | ✅ cerrado — control negativo `hubapp` NO_LEE; antes lo leían los 8 usuarios de apps del server |
| 2026-07-20 | **(nuevo)** | Relevado el **axio-db-agent** a pedido del usuario: vive **solo en axioma** (`/opt/axio-db-agent`), no uno por server; `/var/www/axio` en dev-1 es un **clone abandonado de mayo**. Su `.env` estaba en **`644` con 4 `DATABASE_URL` de producción + 2 API keys** → `600` (regla corregida aplicada: `User=` de la unit vs. owner, comparados ANTES) | ✅ cerrado — `getent group axioapp` vacío ⇒ el `644` exponía por el bit `other` a **todo usuario del server** |
| 2026-07-20 | (nuevo) | db-agent: rename `"Servidor Clubix"` → **`"Agente Axioma"`** (el agente corre en axioma, no en clubix) + **`clubix` fuera de `APPS`**. El restart sinceró que el agente **no podía servir clubix hace semanas** (`/var/www/clubix` no existe en axioma); `schema_tables` 416 → **254** (el 416 era un valor rancio en memoria desde el 27/06) | ✅ ambos aplicados — sin duplicar la fila (upsert por `agent_url`), `error_count=0`. **3 arranques con el `.env` en 600 ⇒ ausencia de bomba VERIFICADA** |
| 2026-07-20 | H06 | **mini dev-1 migrada a `miniapp`** + normalizados los ~90 dirs en `777` → `750` (con `755` en las 3 rutas que nginx sirve). Incluyó `/var/log/mini`, **fuera de `/var/www`**, sin el cual PM2 no arranca. Detectado en el relevamiento, antes de ejecutar | ✅ verde — `find -not -user miniapp` vacío, health 200, **`restart_time`=0 estable a 70s**, checkpoint-web intacto, load 0.08. Caída de ~1 min por el gotcha del cwd |
| 2026-07-20 | H06 | mini axioma: backend `.env` `640 axiomacloud:miniapp` → **`600 miniapp:miniapp`** (sin corte). Verificado que el deploy como `miniapp` es viable (deploy key propia, `ls-remote` rc=0) | 🟡 parcial — el `chown -R` del árbol de axioma **requiere ventana** (es productiva) |
| 2026-07-22 | **H01** | `pg_hba` de axioma: backup `pg_hba.conf.bak-20260722-100113` → regla `0.0.0.0/0 md5` eliminada (queda comentada), reglas `host` acotadas a `127.0.0.1/32`/`::1/128` con `scram-sha-256`; `password_encryption=scram-sha-256` + re-hash de roles (**0 con hash md5**, incl. `mediflowuser`). Aplicado con `pg_reload_conf()`, sin restart | ✅ verde — apps conectando por loopback (hub/mediflow/mini/parse/evolution/netdata), 0 auth failures. Residual inicial: 2 reglas de `mediflow_db` con método `md5` |
| 2026-07-22 | H01 | 2ª pasada — residual de mediflow: las 2 reglas (`local` + `host 127.0.0.1/32`) `md5` → `scram-sha-256` con backup + `pg_reload_conf()`. Verificada **conexión nueva** de `mediflowuser`: directa `:5432` OK y vía **pgbouncer `:6432`** OK (mediflow conecta por pgbouncer — relevado acá) | ✅ **H01 cerrado sin residual** — 0 líneas `md5` activas en el pg_hba de axioma. ⚠ colateral anotado: password de `mediflowuser` corto/débil (8 chars) → candidato a rotación |
| 2026-07-22 | — | **Reconciliación docs ↔ servers** (lectura en los 5): H04/H06/H09/H11/checkpoint-web/creds-AWS-hub verificados vigentes tal como están documentados; **logrotate dev-1 verificado** (rotó y comprimió las 00:00 del 21 y 22 — pendiente del 07-20 cerrado); netdata `:19999` en `0.0.0.0` también en **clubix y drp** (tapado por ufw; la comparativa de hardening decía "solo sshd" en drp) | ✅ foto real consolidada; desincronías documentales corregidas en `hardening.md` (tabla axioma #2/#4, fila drp) y tracker de estandarización (F4) |

---

## Relación con otros documentos

- **Fuente de los hallazgos:** [`dossier-auditoria-seguridad.md`](./dossier-auditoria-seguridad.md) §7 (H01–H14) y §8 (G1–G9, fuera de alcance).
- **H01/H03/H04/H06/H09:** detalle técnico y estado por server en [`hardening.md`](./hardening.md).
- **H07:** procedimiento y cadencia en [`restore-drill-procedure.md`](./restore-drill-procedure.md); traza en `drill-history.csv`.
- **H08:** config de alarma en [`netdata/health.d/pgbackrest.conf`](../netdata/health.d/pgbackrest.conf) + `setup-netdata-cloud.md` §5.
- **H11/H12/H13:** ciclo de ejecución en [`plan-trabajo-estandarizacion.md`](./plan-trabajo-estandarizacion.md) (Fases 4/6) y molde en [`estandar-despliegue.md`](./estandar-despliegue.md).
- **H03:** custodia SOPS en `infra-secrets/env/pgbackrest/repo2-r2.env`; arquitectura en [`pgbackrest-setup.md`](./pgbackrest-setup.md).
