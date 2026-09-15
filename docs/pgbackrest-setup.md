# pgBackRest — dual-repo: central en dev-1 (SSH) + Cloudflare R2 (S3)

Los 4 servers hacen backup (full/diff/incr) y archivan WAL contra **dos repositorios en
paralelo** (pgBackRest los mantiene a ambos en cada operación):

- **`repo1` — central en dev-1** (`/backup/pgbackrest`), transporte **SSH**. Los backups se
  inician *desde* dev-1 (repo host), que se conecta a cada db host como `postgres` para leer
  el `PGDATA`; el `archive_command` de cada db host empuja el WAL *hacia* dev-1.
- **`repo2` — Cloudflare R2** (object storage S3-compatible), bucket `axiomacloud-pgbackrest`,
  endpoint `*.r2.cloudflarestorage.com`. Copia **off-site** que elimina el single-point-of-failure
  de tener el único repo en dev-1. **Cifrado en reposo** (`repo2-cipher-type`).

> Este es el estado **realmente implementado** (repo1 desde 2026-05-26; repo2/R2 confirmado
> 2026-07-17). El diseño TLS bocetado se descartó: dev-1 ya era repo host de axioma por SSH
> sin cifrado, se extendió ese esquema probado y luego se sumó R2 como segunda copia off-site.

## Arquitectura

```
                 repo central /backup/pgbackrest  (usuario OS: pgbackrest)
                          ┌──────────────┐
        backup pull ─────►│    dev-1     │◄───── archive-push (WAL)
   (pgbackrest@dev-1 →    │ 149.50.148.198│      (postgres@dbhost →
    postgres@dbhost)      └──────┬───────┘        pgbackrest@dev-1)
                                 │ SSH
        ┌────────────────────────┼────────────────────────┐
        ▼                        ▼                         ▼
   axioma (PG14)           clubix (PG14)            axiodemo (PG16)
   66.97.45.210            179.43.123.248:2222      170.78.73.245
   stanza:AxiomaCloudProd  stanza:clubix            stanza:axiodemo

   dev-1 también respalda su PROPIA DB (PG14) vía SSH loopback → stanza:dev-1

   además, en cada operación pgBackRest escribe TAMBIÉN a:
        repo2 → Cloudflare R2 (S3)  bucket axiomacloud-pgbackrest  [off-site, cifrado]
```

- **Versión unificada:** pgBackRest **2.58.0** en los 4 (repo oficial PGDG). pgBackRest
  exige la misma versión X.YY entre repo host y db hosts.
- **repo1 (dev-1) sin cifrado en reposo** (`repo1-cipher-type` no seteado), igual que el
  repo original; el tránsito va cifrado por SSH. **repo2 (R2) SÍ cifrado** (`repo2-cipher-type`)
  — correcto, porque R2 es de un tercero. Migrar repo1 a cifrado requeriría re-crear las stanzas.
- **repo2 / R2:** `repo2-type=s3`, bucket `axiomacloud-pgbackrest`, `repo2-s3-uri-style=path`,
  `repo2-s3-region=auto`. Retención propia `repo2-retention-full=4`, `repo2-retention-diff=7`.
- **Usuarios OS:** en dev-1 el repo lo maneja el usuario dedicado `pgbackrest`; en los
  db hosts el dueño es `postgres` (corre el `archive_command`).
- **Retención:** `repo1-retention-full=4`, `repo1-retention-diff=7`.

> **✓ Token R2 rotado (2026-07-17):** el API token de R2 (`repo2-s3-key` + `repo2-s3-key-secret`)
> se **rotó** — el viejo (`a8790e48…`) quedó comprometido (expuesto en texto plano + sesión) y
> fue **borrado en Cloudflare**; el nuevo (`b47676fd…`) se aplicó en los **5 archivos**: `dev-1`
> (`pgbackrest.conf`+`db.conf`) y `axioma`/`clubix`/`axiodemo` (`pgbackrest.conf`), con backup
> `.bak-<ts>` de cada uno. Verificado con `pgbackrest check` en las 4 stanzas (archiva a repo2/R2)
> ANTES y DESPUÉS de borrar el viejo. El **`cipher-pass` NO se rotó** (cifra los backups ya en R2).
> Credenciales custodiadas cifradas en `infra-secrets/env/pgbackrest/repo2-r2.env` (SOPS).
>
> **Pendiente menor:** las creds siguen en **texto plano** en los `pgbackrest.conf` (pgBackRest
> las lee de ahí); protegidas por permisos 640 + firewall. SOPS es la copia custodiada, no el
> origen que lee pgBackRest. Mejora futura: que el server las lea desde origen cifrado.

## Confianza SSH (bidireccional por stanza)

Para cada db host hace falta:
1. `postgres@dbhost → pgbackrest@dev-1` (archive-push): la pubkey de postgres va en
   `~pgbackrest/.ssh/authorized_keys` de dev-1.
2. `pgbackrest@dev-1 → postgres@dbhost` (backup pull): la pubkey de pgbackrest va en
   `~postgres/.ssh/authorized_keys` del db host.
3. `known_hosts` pre-cargado en ambos (`ssh-keyscan`).

Gotchas reales encontrados:
- **clubix usa puerto SSH 2222.** dev-1 lo resuelve con un `~pgbackrest/.ssh/config`:
  `Host 179.43.123.248 / Port 2222 / User postgres`.
- **clubix tenía `AllowUsers axiomacloud`** en sshd → bloqueaba el login de `postgres`.
  Se agregó `postgres` a `AllowUsers` y se restringió su key con
  `from="149.50.148.198"` (solo desde dev-1).
- **fail2ban** (activo en clubix, agresivo; y en dev-1) baneaba las IPs por las
  conexiones frecuentes de pgBackRest. Se whitelistearon las 4 IPs internas en
  `ignoreip` de `/etc/fail2ban/jail.local`.

## dev-1 respalda su propia DB (caso repo host = db host)

dev-1 es repo host (`pgbackrest`) y db host (`postgres`) a la vez, con usuarios
distintos, así que se trata como "remoto a sí mismo" por **SSH loopback**:
- Loopback SSH bidireccional entre `postgres@127.0.0.1` y `pgbackrest@127.0.0.1`.
- La stanza `[dev-1]` del repo config usa `pg1-host=127.0.0.1`, `pg1-host-user=postgres`
  y **`pg1-host-config=/etc/pgbackrest/db.conf`** (config legible por postgres).
- `/etc/pgbackrest/db.conf` (dueño postgres) tiene el lado cliente: `repo1-host=127.0.0.1`,
  `repo1-host-user=pgbackrest`, con **`lock-path` y `log-path` propios** (porque los
  default `/tmp/pgbackrest` y `/var/log/pgbackrest` son del usuario pgbackrest).
- `archive_command = pgbackrest --config=/etc/pgbackrest/db.conf --stanza=dev-1 archive-push %p`.
- El directorio `/etc/pgbackrest` debe ser **traversable** por postgres (chmod 755);
  `pgbackrest.conf` queda 640 pgbackrest (postgres no lo lee).

## Archivado en PostgreSQL (cada db host)

`wal_level=replica` ya alcanza (default). Solo se activa:
```sql
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=<stanza> archive-push %p';
ALTER SYSTEM SET archive_mode = on;   -- requiere RESTART (parámetro de postmaster)
```
`systemctl restart postgresql` (corte de segundos; verificar que no haya réplicas).

## Crear stanza + verificar + primer backup (desde dev-1)

```bash
sudo -u pgbackrest pgbackrest --stanza=<stanza> stanza-create
sudo -u pgbackrest pgbackrest --stanza=<stanza> check     # archiva un WAL de prueba
sudo -u pgbackrest pgbackrest --stanza=<stanza> --type=full backup
sudo -u pgbackrest pgbackrest info
```

## Cron de backups (usuario pgbackrest en dev-1)

`sudo crontab -u pgbackrest -e` — full domingo, diff lun-sáb, incr cada 4h, check
semanal. Las stanzas se escalonan de a 15 min para no solapar carga.

## Monitoreo: qué mide cada capa, y el punto ciego que tenía

| Capa | Dónde corre | Responde |
|---|---|---|
| `pgbackrest-collect.py` (15 min) | dev-1, como `pgbackrest` | ¿hay backup reciente y llegó WAL al repo? |
| `archive-push-collect.py` (5 min) | cada db host, como `postgres` | ¿el archiving funciona desde el lado de la base? (avisa aunque dev-1 esté caído) |
| `pgbackrest-verify.sh` (semanal) | dev-1, como `pgbackrest` | ¿los archivos del repo siguen siendo legibles? |
| `hardening-selfcheck.sh` (15 min) | los 5 servers, como root | ¿los colectores de arriba siguen corriendo? |

> **⚠ El punto ciego, confirmado el 2026-09-05.** Los charts de statsd están en
> `gaps when not collected = no`: Netdata **re-emite el último valor cada segundo**. Si un colector
> muere, sus métricas quedan **congeladas en el último valor bueno** y las alarmas se quedan en CLEAR
> para siempre — con el backup roto y sin una sola señal. La evidencia: `last_collected_t` del chart
> `pgbackrest.backup_age` daba **1 segundo** de antigüedad con el cron corriendo **cada 15 min**, y el
> historial se ve plano 14 min y salta exactamente **+900** en cada corrida. Por lo mismo tampoco sirve
> la alarma estándar de Netdata `$now - $last_collected_t`.
>
> **Mitigación:** cada colector toca un *stamp* al completar una corrida
> (`/var/lib/pgbackrest-netdata/repo.stamp` y `/var/lib/pgbackrest-archive/archive.stamp`), y
> `hardening-selfcheck.sh` —**otro cron, otro usuario**— mide su frescura y publica
> `watchdog.self.colectores_backup`. Alarma: `watchdog_colector_backup_muerto`.
> **Residual:** si mueren los dos crones a la vez, nadie avisa. Hacen falta dos fallas simultáneas.

## Verificación de integridad (`verify`) — C13 de G6

`pgbackrest verify` recorre el repo y valida los **checksums de backups y WAL**. Es lo único que
detecta **corrupción silenciosa** (un bit podrido en disco, un objeto truncado en R2) antes de que la
descubras el día del desastre, restaurando. Ninguna de las otras métricas mira adentro de los archivos.

`netdata/pgbackrest/pgbackrest-verify.sh` lo corre **una stanza por noche, mar–sáb 05:00**, contra los
dos repos, fuera de la ventana de backups. Deja el resultado en
`/var/lib/pgbackrest-netdata/verify/<stanza>.repo<N>.json`; **no empuja métricas** — las publica
`pgbackrest-collect.py` en su corrida de cada 15 min. Eso es a propósito: así la **edad se recalcula
sola** y un cron de verify muerto dispara la alarma de edad, en vez de morir con su métrica congelada
en verde.

Alarmas: `pgbackrest_verify_atrasado` (>10 d warn / >21 d crit) y `pgbackrest_verify_fallo`.

> **Costo real, medido en dev-1 el 2026-09-05:** la stanza **más chica** (`axiodemo`, 2.7 GB de
> archive) tardó **17 min 11 s** con un solo proceso, CPU-bound. El repo completo son 48 GB. Por eso
> `--process-max=2` y una sola stanza por noche: no es un chequeo que se pueda correr seguido.
>
> Primera corrida (axiodemo/repo1, 2026-09-05): `verify command end: completed successfully`.

```bash
sudo -u pgbackrest /usr/local/bin/pgbackrest-verify.sh axiodemo        # los 2 repos
sudo -u pgbackrest /usr/local/bin/pgbackrest-verify.sh axiodemo 2      # solo R2
```

## Restore (probarlo periódicamente)

```bash
sudo -u pgbackrest pgbackrest --stanza=<stanza> --delta restore   # en entorno aparte
```
> **Un backup no probado no es un backup.**
