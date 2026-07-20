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

### 4. Puertos de app en 0.0.0.0 🟡
`:8087` (parse frontend Next) escucha en `0.0.0.0` → accesible salteando nginx (sin TLS/headers/rate-limit). nginx igual lo proxya. Fix: bindear Next a `127.0.0.1` (`-H 127.0.0.1` o `HOSTNAME`), tocando el ecosystem de parse + restart. Requiere ventana (parse está en producción). `:5408` es `sshd` (SSH alterno), no una app — no tocar.

### 5. `.env` laxos 🟡 ✅ CORREGIDO
Eran 777 (mini print-agent/frontend), 664 (mini backend), 644 (mediflow, parse-front, elore, evolution). Todos pasados a `chmod 600` el 2026-07-17. Pendiente aparte: normalizar owner de los `.env` de mini (hoy `axiomacloud`) en Fase 5.

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
| 4 | App en `0.0.0.0` | 🟡 `:8087` | 🟡 19999, 25 | 🟡 `:5300`, 19999 | 🟢 solo sshd | 🟡 **firewall tapa 19999/631/3000/5000/8086/8087/8089** (fix 2026-07-17); snmp 161 acotado a dattaweb. Bind 0.0.0.0 sigue (defensa por fw); rebindear a loopback en Fase 4 |
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
- 🟡 **P2 restante (defensa en profundidad, no urgente ya que el fw tapa)**: snmpd → `agentaddress 127.0.0.1` + cambiar community `public`; apps Node `:3000/5000/8086/8087/8089` → rebindear a `127.0.0.1`; CUPS `:631` → loopback/off; netdata 19999 → loopback; `.env` 644/664/755 → normalizar en Fase 4.

### Notas
- axiodemo #1 es el inverso de axioma: pg_hba bien pero `listen='*'`; lo contiene el **firewall**, no el bind.
- La IP `149.50.148.198` autorizada en axiodemo (pg_hba+ufw) para `axio_ml` es **dev-1**.
