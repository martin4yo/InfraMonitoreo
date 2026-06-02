# pgBackRest — offsite a Cloudflare R2 (repo2, cifrado)

Segunda copia **offsite** del repositorio de backups en **Cloudflare R2** (S3-compatible),
para que dev-1 deje de ser punto único de falla. Arquitectura **"A": WAL continuo + backups**.

Desplegado con `scripts/50-deploy-r2-offsite.sh` (idempotente, por fases).

## Arquitectura

- **repo1** = repo local en dev-1 (`/backup/pgbackrest`), sin cifrar. Restores rápidos.
- **repo2** = Cloudflare R2 (`s3`), **cifrado del lado cliente** (`aes-256-cbc`). Offsite/DR.
- `archive-push` (corre en cada DB host) empuja **WAL a ambos repos**: repo1 por SSH→dev-1,
  repo2 directo por S3→R2. ⇒ **WAL offsite continuo (RPO ~1 min)**.
- `backup --repo=2` corre en dev-1 (lee la DB por SSH, escribe a R2). Schedule: **espeja repo1**
  → full (dom) + diff (lun-sáb) + incr (cada 4h), corrido **+1h** respecto a repo1 (full/diff 2→3am,
  incr 6,10,14,18,22 → 7,11,15,19,23) para no leer la DB en simultáneo. `backup` sin `--repo` apunta
  SOLO a repo1, por eso repo2 necesita sus propias líneas de cron; el `check` (dom 4am) y el monitor
  horario del crontab de repo1 ya operan sobre todos los repos y cubren repo2 sin duplicar.
- Retención repo2: `repo2-retention-full=4`, `repo2-retention-diff=7`.
- **`repo2-bundle=y`**: agrupa los archivos chicos del backup en objetos de ~20 MB. Una DB con
  miles de relaciones genera decenas de miles de archivos diminutos; sin bundle cada uno es un
  PUT a R2 (operación Class A) y el full inicial tarda 1h+. Con bundle baja a decenas de objetos
  ⇒ minutos. Sólo aplica a backups **nuevos**; los viejos no-bundle conviven sin problema.

Config (idéntica en todos los hosts) inyectada en `[global]` entre marcadores
`# >>> inframonitoreo r2 offsite >>>`. Endpoint: `<account_id>.r2.cloudflarestorage.com`,
`repo2-s3-region=auto`, `repo2-s3-uri-style=path`.

## Credenciales (secrets.sh, gitignored)

```
R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, PGBACKREST_R2_CIPHER_PASS
```

⚠️ **La passphrase de cifrado es CRÍTICA**: si se pierde, los backups en R2 son
**irrecuperables**. Guardarla también fuera del repo (gestor de contraseñas).

## Despliegue

```bash
bash scripts/50-deploy-r2-offsite.sh repo      # config repo2 en dev-1 + stanza-create (GATE)
bash scripts/50-deploy-r2-offsite.sh dbhosts   # config repo2 en los 3 DB hosts (habilita WAL→R2)
bash scripts/50-deploy-r2-offsite.sh verify    # check (valida WAL→repo1 y repo2)
bash scripts/50-deploy-r2-offsite.sh backup    # primer full a R2 de cada stanza (lento)
bash scripts/50-deploy-r2-offsite.sh cron      # cron de backups a repo2 en dev-1
# o todo junto, en orden:
bash scripts/50-deploy-r2-offsite.sh all
```

El orden importa: `stanza-create` en repo2 va **antes** de configurar los DB hosts, para que
el archive-push a R2 no falle por stanza inexistente.

## GOTCHAS (aprendidos en el despliegue)

- **`stanza-create` y `check` NO aceptan `--repo`**: operan sobre TODOS los repos configurados.
  Sólo `backup`/`restore`/`expire`/`info` aceptan `--repo=N`.
- **dev-1 (loopback)**: su `archive_command` usa `--config=/etc/pgbackrest/db.conf` (legible por
  `postgres`), NO el `pgbackrest.conf` principal (que es `pgbackrest:pgbackrest 640`). El bloque
  repo2 hay que ponerlo **también en db.conf**, si no el WAL de dev-1 no llega a R2 (el `check`
  da `WAL ... was not archived before the 60000ms timeout`). El script lo maneja.
- pgBackRest **redacta** los secretos (`--repo2-s3-key=<redacted>`) en sus logs.

## Restore desde R2 (DR: si dev-1 muere)

En un host nuevo con pgBackRest + la config repo2 (mismas credenciales + **misma cipher-pass**):

```bash
pgbackrest --stanza=<STANZA> --repo=2 info                       # ver backups disponibles
pgbackrest --stanza=<STANZA> --repo=2 --type=time \
           --target="2026-05-26 18:00:00" restore                # PITR desde R2
```

Probar un restore real periódicamente (un backup no probado no es un backup).

## Costo R2

Storage ~USD 0.015/GB-mes. **Sin cargos de egress** (ventaja de R2 para restores). Los datos
son chicos (axioma ~128 MB de DB, lz4 + cifrado), así que el costo es marginal. `repo2-bundle=y`
además recorta drásticamente las operaciones Class A (PUT), que es lo que R2 cobra aparte del storage.
