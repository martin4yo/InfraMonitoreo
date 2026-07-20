# Hardening de seguridad — infra Axioma

> Hallazgos de la auditoría del 2026-07-17. **axioma** relevado primero; **clubix** y **axiodemo**
> replicados el mismo día (read-only, sin cambios). Comparativa de los 3 al final del doc.
> Los fixes invasivos (SSH, firewall, pg_hba) requieren ventana + OK explícito:
> un error deja el server inaccesible.

## Estado (axioma)

| # | Hallazgo | Sev | Estado |
|---|---|---|---|
| 1 | `pg_hba.conf`: `host all all 0.0.0.0/0 md5` (cualquier IP puede intentar conectar) | 🔴 | pendiente |
| 2 | Sin firewall (`ufw inactive`, iptables ACCEPT sin reglas) | 🔴 | pendiente |
| 3 | SSH: `PermitRootLogin yes` (en `sshd_config.d/custom.conf`) + `PasswordAuthentication yes` | 🔴 | ✅ **corregido 2026-07-17** |
| 4 | Puertos de app en `0.0.0.0` en vez de `127.0.0.1` (`:8087` parse-front) | 🟡 | pendiente |
| 5 | `.env` con permisos laxos (777/644/664) en vez de 600 | 🟡 | ✅ **corregido 2026-07-17** |
| 6 | Credenciales R2 en texto plano en `pgbackrest.conf` (+ expuestas en sesión) | 🟡 | ✅ cerrado (2026-07-19): token rotado + `.bak` con creds purgados |

## Bien (no tocar)
- Postgres escucha solo en `127.0.0.1:5432` (mitiga el #1 mientras no cambie `listen_addresses`).
- Apps corren como usuarios dedicados `<app>app` (no root).
- hub con TLS + headers de seguridad + `block-scanners` (molde a replicar).

## Detalle y fix propuesto

### 1. pg_hba.conf `0.0.0.0/0` 🔴
La regla `host all all 0.0.0.0/0 md5` permite intentos de conexión desde cualquier IP. Hoy sólo lo salva que Postgres bindea a localhost. Fix: acotar a `127.0.0.1/32` (y la subred de backups si aplica), y migrar `md5` → `scram-sha-256`. **Invasivo** (mal hecho corta las apps): ventana + `pg_hba` de rollback + `SELECT pg_reload_conf()` (no restart).

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
| axioma | **mini backend** | `/var/www/mini/backend/.env` | 640 | `axiomacloud:miniapp` | `miniapp` | ✅ funciona (lee por grupo); pendiente `chown miniapp:miniapp` + 600 por prolijidad |
| axioma | **mini frontend** | `/var/www/mini/frontend/.env` | 600 | `axiomacloud:axiomacloud` | (build) | ⚠️ **bomba latente** si se levanta como `miniapp` |
| axioma | **mini print-agent** | `/var/www/mini/print-agent/.env` | 600 | `axiomacloud:axiomacloud` | (sin proceso) | ⚠️ **bomba latente** |
| dev-1 | **checkpoint-web** | `/var/www/checkpoint-web/.env` | 600 | `axiomacloud:axiomacloud` | `axiomacloud` (viva) + `checkapp` (crash loop) | ⛔ ver sección 7 |
| dev-1 | **axio** | `/var/www/axio/.env`, `backend/.env` | **664** | `axioapp:axioapp` | sin proceso | 🔴 **H06 abierto de verdad: world-readable** en el server de backups |
| dev-1 | mediflow | `/var/www/mediflow/backend/.env` | 600 | `root:root` | `root` | 🟡 coincide, pero **corre como root** (viola el estándar) |
| dev-1 | mini, hub, elore, fitness, parse, tally, core | varios | 600 | `<app>app` | idem | ✅ |
| axioma | mediflow | `/var/www/mediflow/backend/.env` | 600 | `mediflowapp:www-data` | `mediflowapp` | 🟡 owner OK, grupo `www-data` raro |
| axioma | hub, parse, elore, evolution-api | varios | 600 | `<app>app` | idem | ✅ |
| clubix / axiodemo | clubix, axio | varios | 600 | `<app>app` | idem | ✅ |

**Pendientes de este hallazgo:** (1) `axio/.env` 664 → 600 en dev-1 (**prioridad**, sin proceso corriendo → sin riesgo); (2) las 2 bombas latentes de mini en axioma; (3) `chown miniapp:miniapp` + 600 del backend de mini; (4) mediflow: sacar de root (dev-1) y normalizar grupo (axioma).

**Hallazgo mayor asociado — directorios en `777`.** `/var/www/mini` y subdirectorios están en `drwxrwxrwx` en **axioma y dev-1**. El `.env` en 600/640 protege el *contenido*, pero **manda el permiso de escritura del directorio**: cualquier usuario local puede **borrar o sustituir** ese `.env`. Hay además `.env.local`/`.env.production`/`.env.example` en 777 y archivos de negocio sueltos (`IIBB_Ventas.txt`, `.xlsx` de comprobantes, `consola.log`). **Esto pesa más que el hallazgo original.** Normalizar a `750 <app>app:<app>app` + `.env.*` a 600.

### 7. `checkpoint-web` (dev-1) — migración a `checkapp` abandonada + crash loop 🔴 ✅ CONTENIDO

Detectado al investigar el incidente de mini. **Migración iniciada el 23/01/2026 y nunca terminada**: el árbol `/var/www/checkpoint-web` ya es `checkapp:checkapp` (755) y `pm2-checkapp.service` está `enabled`, pero **el `.env` quedó en `axiomacloud:axiomacloud` 600** → `checkapp` **NO_LEE**.

Consecuencia: la instancia `checkapp` **nunca llegó a bindear** y estuvo en **crash loop `restart_time=108455` (~24 reinicios/minuto durante 3 días)**, costando **~0.6 de load sostenido** en dev-1 — la caja que aloja los backups de toda la infra. El sitio nunca se cayó: lo sirve la instancia vieja (`axiomacloud`, pid 1817, `:8086`, nginx `proxy_pass localhost:8086`).

**✅ Contenido (2026-07-20 15:21):** `pm2 stop checkpoint-web` + `pm2 save` en el PM2_HOME de `checkapp` (no revive al reboot). Verificado: `restart_time` congelado tras 95s, sitio intacto (307 local / 200 público en 3 lecturas), **load 1m 1.50 → 0.88 (−41%)**. Rollback: `pm2 start checkpoint-web` en `/home/checkapp/.pm2`.

**Nota:** no se pudo probar que la causa fuera *solo* el `.env` — el stderr real no queda registrado. Hipótesis viva adicional: `EADDRINUSE` por el `:8086` ocupado por la instancia vieja. Probablemente ambas → arreglar solo el `.env` no alcanzaría.

**Decisión pendiente del usuario: completar la migración o abortarla.** Si se completa, antes hay que hacer `chown -R checkapp:checkapp` — hay **archivos `root:root` sueltos** (`.next/`, `package-lock.json`, `next.config.ts`, `public/`, `scripts/`…). Revisar aparte `cookies.txt` y **`backup_checkpoint_db.sql`** (dump de base) dentro del directorio servido por la app.

**Higiene de logs (pendiente):** sin rotación — `mini-backend-out-0.log` en axioma **130 MB creciendo**; `checkpoint-web-out-0.log` 7,2 MB (ya frenado); `/var/log/mini/backend-out-1.log` 7,3 MB en dev-1.

### 6. Credenciales R2 🟡 → ✅ TOKEN ROTADO (2026-07-17)
`repo2-s3-key-secret` + `repo2-cipher-pass` en texto plano en `/etc/pgbackrest/pgbackrest.conf`; además se expusieron en una sesión el 2026-07-17. **Hecho**: rotado el API token R2 (viejo `a8790e48…` borrado en Cloudflare, nuevo `b47676fd…` aplicado en los **5 archivos** con backup), verificado con `pgbackrest check` en las 4 stanzas; `cipher-pass` conservado; credenciales cifradas en `infra-secrets/env/pgbackrest/repo2-r2.env` (SOPS). Ver `pgbackrest-setup.md`. **Cerrado (2026-07-19, H03 del plan de remediación).** Se evaluaron las 3 opciones (mantener+endurecer / archivo dedicado `600` vía `config-include-path` / variables `PGBACKREST_*`) y se eligió **mantener en el `.conf` + endurecer**: pgBackRest siempre necesita el secreto en claro en ejecución, así que mover a otro archivo owner-only es ganancia marginal frente a editar 5 configs productivas, y las env vars serían **peores** (legibles en `/proc/<pid>/environ`).

La superficie real no eran los `.conf` (ya en `640`, grupos de un solo miembro, no versionados) sino **4 archivos `.bak` con las claves S3 pre-rotación** — incluidos los backups que dejó la propia rotación del 17-jul. Se verificó por hash que su `repo2-cipher-pass` era **idéntico al vivo** (el cipher NO se rota; perderlo haría irrecuperables los backups R2), se respaldaron en `/root/pgbackrest-bak-archive/*.tar.gz` (`600` root-only) y se borraron. Resultado: **0 `.bak` en los 5 servers**, `.conf` en `640`, `pgbackrest check` OK en las 4 stanzas (repo1+repo2).

**Límite aceptado y documentado:** las creds siguen en texto plano en los `.conf` que lee pgBackRest (protegidas por `640` + owner + firewall); la fuente de verdad cifrada es SOPS. **Regla operativa:** al rotar creds, no dejar `.bak` con el valor viejo.

---

## Comparativa 5 servers (2026-07-17)

| # | Hallazgo | axioma | clubix | axiodemo | axioma-drp | dev-1 |
|---|----------|--------|--------|----------|------------|-------|
| 1 | pg_hba / listen | 🔴 `0.0.0.0/0 md5`, salvado por bind localhost | 🟢 deny + scram, `listen=localhost` | 🟡 acotado + scram, `listen='*'` (lo salva ufw) | ⬜ sin Postgres | 🟢 `listen=localhost`, solo loopback + scram |
| 2 | Firewall | ✅ ufw active, allow 22/5408/80/443 | ✅ ufw active, allow 2222/80/443 | 🟢 ufw active + allowlist | ✅ **ufw active** allow 22/80/443 (fix 2026-07-17) | ✅ **ufw active** allow 22/5782/80/443 + snmp 161 solo dattaweb (fix 2026-07-17) |
| 3 | SSH root/password | ✅ root+pass `no` | ✅ root+pass `no` | ✅ root+pass `no` | ✅ root+pass `no` (homologado) | ✅ root+pass `no` (fix 2026-07-17) |
| 4 | App en `0.0.0.0` | 🟡 `:8087` ✅ **loopback (2026-07-20)**; netdata ✅ loopback. Quedan `:3700` elore, `:8089` hub, `:8080` evolution-api, `:5300` mediflow | 🟡 19999, 25 | 🟡 `:5300` axio-back (needs código), `:8001` axio-ml **excepción aceptada** (dev-1 lo consume remoto); netdata ✅ loopback | 🟢 solo sshd | 🟡 **firewall tapa todo** (fix 2026-07-17). ✅ **CUPS `:631` deshabilitado + netdata loopback (2026-07-20)**. Quedan `:3000` elore, `:8087` parse, `:8089` hub (bloqueadas por patrón Next `-H`), `:8086`/`:5000` (needs código) |
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
a los secretos). **Pendientes 🔴 tras el fix SSH**: 3 `.env` de mini en 777, firewall ausente, snmpd público
(community `public`), apps Node crudas en IP pública. Ver "Pendientes dev-1" abajo.

### axioma-drp (170.78.75.249) — server bare, casi vacío
Ubuntu 22.04, solo SSH escucha. Sin Postgres/nginx/apps/pgBackRest/Netdata. SSH ya homologado. **Hallazgo
🔴**: usuario `linuxadmin` (provisioning 2022, ajeno a Axioma) con password activa + sudo + llave ajena
`mfourgeaux@KEYSOFT-I7` → **password bloqueada** (`passwd -l`, 2026-07-17); usuario+sudo conservados para
emergencia (solo entra por llave). ✅ **ufw instalado y activo** (2026-07-17): default-deny, allow 22/80/443.
**Rol definido (2026-07-17): banco de pruebas de DRP _por aplicación, de a una_** — NO réplica de infra completa.
✅ **Disco ampliado (2026-07-17)**: el VPS se agrandó y se propagó la cadena LVM online (growpart sda3 →
pvresize → lvextend +100%FREE → resize2fs ext4, sin reboot). `/` pasó de **12 G a 64 G** (53 G libres).
Backup de la tabla de particiones en `/root/sda-parttable.bak-*.sfdisk`. Queda ~2 G sin asignar en el VG
(remanente por redondeo de extents; disponible para un LV aparte de `/var/lib/postgresql` si hiciera falta).
✅ **Netdata instalado + claimed (2026-07-17)**: agente v2.10.4 (stable, igual que los otros 4) reclamado al
mismo Space/Room de Netdata Cloud, ACLK conectado, reportando. `:19999` no expuesto en ufw (reporta saliente).
Faltan los colectores específicos (postgres/nginx/pgBackRest) — se suman con `scripts/20-deploy-configs.sh`
cuando haya apps para cada prueba de restore.
✅ **fail2ban arreglado (2026-07-17)**: el jail sshd estaba caído (buscaba `/var/log/auth.log` inexistente,
el server usa journald). Fix: `jail.local` con `backend = systemd` + jail sshd puerto 22 + `ignoreip` con las
5 IPs de la infra. Config test OK, servicio active, leyendo del journal. SSH con rate-limiting de nuevo.
Pendiente menor: `ubuntu` NOPASSWD del cloud-init (password ya bloqueada). Para integrar: pgBackRest cuando se arme cada prueba.

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
