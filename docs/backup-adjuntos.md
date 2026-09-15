# Backup de adjuntos a R2 (restic)

> **Qué cubre:** los archivos que suben los usuarios de una app (adjuntos de consultas, legajos,
> documentos). **pgBackRest respalda la base, no el filesystem**: sin esto, un DR recupera las filas que
> apuntan a los archivos, pero no los archivos.
>
> **Estado:** ✅ **en producción desde 2026-09-15 para alvera (axioma).** Restore desde R2 verificado el
> mismo día: 7/7 archivos con sha256 idéntico a producción. Checkpoint (dev-1) queda pendiente con el mismo
> mecanismo (§6).
>
> Origen: hallazgo **A-5** de [drp-alvera-en-drp.md](./drp-alvera-en-drp.md) y **H-2** de
> [drp-checkpoint-en-drp.md](./drp-checkpoint-en-drp.md).

---

## 1. Diseño

| | Decisión | Por qué |
|---|---|---|
| **Herramienta** | restic **0.19.1**, binario oficial con sha256 fijado en el deploy | Cifra del lado del cliente, deduplica, snapshots incrementales, `check` de integridad. Sin servicio residente. |
| **Destino** | R2, bucket **`axiomacloud-adjuntos`**, repositorio restic id `2ee12bdb` | Off-site y en otro proveedor que axioma y dev-1. **Bucket y token propios**: un token filtrado o un prune mal hecho no alcanzan los backups de PostgreSQL. |
| **Token R2** | *Object Read & Write* **solo** sobre ese bucket + **filtro de IP** | Aunque se filtre, no sirve desde otro lado. Verificado: desde fuera del filtro → `Access Denied`. |
| **Frecuencia** | cada **15 min** (`/etc/cron.d/adjuntos-backup-<app>`), `--skip-if-unchanged` | La base tiene RPO de minutos; un backup diario deja adjuntos huérfanos tras un PITR. Sin cambios no crea snapshot. |
| **Retención** | `--keep-within 48h --keep-daily 14 --keep-weekly 8 --keep-monthly 12` | 12 meses: un adjunto borrado se descubre tarde y no se reconstruye. |
| **Mantenimiento** | domingo 04:30: `forget --prune` + `check --read-data-subset=5%` | En ~8 semanas se valida (probabilísticamente) casi todo el repositorio. |
| **Cifrado** | `RESTIC_PASSWORD` aleatorio de 48 bytes | **Sin él, el repositorio es ilegible.** Custodia en infra-secrets (§5). |
| **Carga en producción** | `nice -n 19`, `ionice -c 3`, `GOMAXPROCS=1`, `flock` | Cede ante la app; nunca se superponen dos corridas. |
| **Convive con** | el rsync diario a dev-1 (`/etc/cron.daily/alvera-adjuntos-backup`) | **No se reemplazó.** Dos copias, dos lugares, dos herramientas. |

**Consumo medido en axioma (2026-09-15):**

| Corrida | Tiempo | CPU | RAM máx. |
|---|---|---|---|
| Primera (7 archivos, 1,65 MB) | 6,7 s | 0,68 s | 66 MB |
| Sin cambios | 3–4 s | < 0,5 s | — |
| Caché local (`/var/cache/restic`) | — | — | 52 KB en disco |

### 1.1 Un bug encontrado antes de producción

Respaldar la **ruta absoluta** (`restic backup /var/www/alvera/backend/uploads`) hace que restic guarde también
los metadatos de los directorios **padres**. Cualquier escritura en `backend/` cambia ese árbol, y
`--skip-if-unchanged` crea un snapshot **en cada corrida** (96 por día sin un solo adjunto nuevo). Se respalda
`.` **desde adentro** de `ORIGEN`. Detectado en la prueba local, antes de desplegar.

---

## 2. Componentes

| Archivo en el repo | En el server | Qué hace |
|---|---|---|
| [`restic/adjuntos-backup.sh`](../restic/adjuntos-backup.sh) | `/usr/local/bin/adjuntos-backup.sh` | `backup` y `mantenimiento`; deja estado en `/var/lib/adjuntos-backup/<app>.json` |
| [`scripts/37-deploy-adjuntos-backup.sh`](../scripts/37-deploy-adjuntos-backup.sh) | — | Despliegue idempotente (binario, credenciales, script, cron, selfcheck) |
| — | `/etc/restic/<app>-adjuntos.env` (`600 root`) | `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `AWS_*`, `ORIGEN` |
| [`netdata/watchdog/hardening-selfcheck.sh`](../netdata/watchdog/hardening-selfcheck.sh) | `/usr/local/bin/` | Publica `watchdog.self.adjuntos_fresco` y `adjuntos_integro` |
| [`netdata/health.d/watchdog-self.conf`](../netdata/health.d/watchdog-self.conf) | `/etc/netdata/health.d/` | Alarmas `watchdog_adjuntos_atrasado` (crit, >1 h sin OK) y `watchdog_adjuntos_integridad` (crit, check FAIL o >8 días) |

Logs: `journalctl -t adjuntos-backup-alvera`.

---

## 3. Operación

```bash
# Estado
sudo cat /var/lib/adjuntos-backup/alvera.json
sudo journalctl -t adjuntos-backup-alvera -n 20 --no-pager

# Corrida manual
sudo /usr/local/bin/adjuntos-backup.sh alvera backup
sudo /usr/local/bin/adjuntos-backup.sh alvera mantenimiento

# Listar snapshots (en el server)
sudo bash -c 'set -a; . /etc/restic/alvera-adjuntos.env; set +a; RESTIC_CACHE_DIR=/var/cache/restic restic snapshots'
```

**Desplegar en otra app o re-desplegar:**

```bash
APP=alvera HOST_NAME=axioma scripts/37-deploy-adjuntos-backup.sh
```

---

## 4. Restore

### 4.1 En un DR (axioma no existe) — 🛟 en el server destino

El destino tiene que tener restic (drp ya lo tiene) y **su IP de salida en el filtro del token** (§5.1).
Las credenciales se pasan por stdin desde la custodia, sin dejarlas en el server:

```bash
# 💻 en el equipo del operador
cd ~/Desarrollos/infra-secrets
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops --decrypt env/restic/alvera-adjuntos.env \
  | grep -E '^(RESTIC_REPOSITORY|RESTIC_PASSWORD|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_DEFAULT_REGION)=' \
  | ssh axiomacloud@170.78.75.249 'sudo bash -c "set -a; eval \"\$(cat)\"; set +a
      export RESTIC_CACHE_DIR=\$(mktemp -d)
      restic snapshots --compact
      restic restore latest --target /var/www/alvera/backend/uploads
      rm -rf \$RESTIC_CACHE_DIR"'
ssh axiomacloud@170.78.75.249 'sudo chown -R alveraapp:alveraapp /var/www/alvera/backend/uploads'
```

- `latest` = último snapshot. Para un momento dado: `restic snapshots` y `restic restore <id>`.
- **Coordinar con la base:** si la base se restaura con PITR a una hora T, restaurar el snapshot de adjuntos
  **igual o posterior** a T, así ninguna fila apunta a un archivo inexistente.
- `restic restore` sobre un directorio con archivos existentes **solo trae los que faltan** o difieren.

### 4.2 Verificación (si producción vive)

```bash
ssh axiomacloud@66.97.45.210 'cd /var/www/alvera/backend/uploads && sudo find . -type f -exec sha256sum {} + | sort -k2' > /dev/shm/p
ssh axiomacloud@170.78.75.249 'cd /var/www/alvera/backend/uploads && sudo find . -type f -exec sha256sum {} + | sort -k2' > /dev/shm/d
diff -q /dev/shm/p /dev/shm/d && echo OK; rm -f /dev/shm/p /dev/shm/d
```

**Ejecutado 2026-09-15:** restore a directorio temporal → 7/7 sha256 == producción (5 s); después
restore sobre la alvera recuperada en drp → 7/7 == producción.

---

## 5. Credenciales y custodia

| Qué | Dónde |
|---|---|
| `RESTIC_PASSWORD`, token R2, repositorio | `infra-secrets/env/restic/alvera-adjuntos.env` (SOPS) |
| En el server | `/etc/restic/alvera-adjuntos.env` (`600 root`, dir `700`) |
| Token en Cloudflare | R2 → Manage API tokens → token del bucket `axiomacloud-adjuntos` |

⚠️ **`RESTIC_PASSWORD` no se rota como una API key**: cambiarla con `restic key passwd` es seguro, pero
**perderla hace ilegibles todos los snapshots**. Va en el kit de continuidad (G9) igual que `repo2-cipher-pass`.

### 5.1 🔴 Filtro de IP: la IP de SALIDA no es la de entrada

Se configuró el filtro con las IPs públicas conocidas y **R2 negó el acceso a los dos servers**:

| Server | IP de entrada (la que figura en el inventario) | IP con la que **sale** hacia R2 |
|---|---|---|
| axioma | `66.97.45.210` | **`2800:6c0:5::222f`** (IPv6 por defecto) |
| axioma-drp | `170.78.75.249` | **`170.78.75.248`** |

El filtro vigente tiene las cuatro. **Antes de sumar un server al filtro, preguntarle a Cloudflare qué IP ve:**

```bash
curl -s https://d5914f72b00f61186e0166703e39cb96.r2.cloudflarestorage.com/cdn-cgi/trace | grep ^ip=
```

Si un server cambia de IP o de proveedor, el backup empieza a fallar con `Access Denied` y salta
`watchdog_adjuntos_atrasado` a la hora.

---

## 6. Pendientes

- [ ] **Checkpoint (dev-1):** mismo mecanismo. Antes, mover `UPLOAD_DIR` fuera de `public/` (H-3) y
      crear bucket/token o prefijo propio. `APP=checkpoint-web` requiere adaptar `ORIGEN` (no usa `backend/`).
- [ ] **dev-1:** `chmod 700 /backup/alvera-adjuntos` (hoy `755`, con documentos de salud) — toca dev-1, pedir OK.
- [ ] **Restore de adjuntos en el drill mensual** de drp (`scripts/70`): hoy prueba solo las stanzas.
- [ ] Verificar que las alarmas `watchdog_adjuntos_*` pasen de `UNINITIALIZED` a `CLEAR` (ventanas de 15 min / 1 h).
