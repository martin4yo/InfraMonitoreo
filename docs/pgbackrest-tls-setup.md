# pgBackRest con repositorio central TLS en dev-1

Objetivo: que **prod-1, prod-2, prod-3 y dev-1** hagan sus backups (full/incr) y
archiven WAL contra un **repositorio central en dev-1**, comunicándose por **TLS**
con certificados propios. Backups iniciados desde el repo host (dev-1).

> ⚠️ **Esto toca PostgreSQL de producción.** Seguí el rollout escalonado: validá
> primero con dev-1 + prod-1 y recién después sumá prod-2 y prod-3.

## Antes de empezar (checklist)

- [ ] **Disco en dev-1**: estimá tamaño de cada BD × retención (2 full + incr). Con
      `du -sh <PG_DATA>` en cada server tenés una base. El repo vive en
      `/var/lib/pgbackrest` de dev-1 — asegurá espacio de sobra.
- [ ] **Red/firewall**: el puerto **8432/tcp** debe estar abierto **bidireccional**
      entre los 4 servers (repo↔db), restringido a esas 4 IPs. En cada proveedor:
      abrí 8432 solo desde las IPs del resto (security group / ufw).
- [ ] **Versión de PostgreSQL y data dir** de cada server (para `pg1-path`):
      `sudo -u postgres psql -c 'show data_directory;'`
- [ ] **Migración**: prod-1 y dev-1 **ya tienen pgBackRest**. Vamos a repuntar su
      config al repo central. Sus backups/stanza viejos quedan donde estén; conviene
      conservarlos hasta validar el primer backup nuevo OK. No borres nada todavía.

## Paso 1 — Generar y distribuir certificados (desde tu máquina)

```bash
./scripts/pgbackrest/gen-certs.sh        # crea pgbackrest/certs/{ca,<server>}.{crt,key}
```

Copiá a cada server **su** cert + key + la CA (a `/etc/pgbackrest/cert/`):

```bash
# ejemplo para prod-1 (repetí por server con su nombre)
scp pgbackrest/certs/ca.crt pgbackrest/certs/prod-1.crt pgbackrest/certs/prod-1.key \
    root@<IP-prod-1>:/tmp/
ssh root@<IP-prod-1> '
  mkdir -p /etc/pgbackrest/cert &&
  mv /tmp/{ca.crt,prod-1.crt,prod-1.key} /etc/pgbackrest/cert/ &&
  chown -R postgres:postgres /etc/pgbackrest/cert &&
  chmod 600 /etc/pgbackrest/cert/*.key'
```

dev-1 recibe `ca.crt` + `dev-1.crt` + `dev-1.key` (es repo host y db host a la vez).

## Paso 2 — Instalar pgBackRest donde falte (prod-2 y prod-3)

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y pgbackrest
# verificar
pgbackrest version
```

## Paso 3 — Configurar el REPO HOST (dev-1)

1. Copiá `pgbackrest/repo-host/pgbackrest.conf.example` a
   `/etc/pgbackrest/pgbackrest.conf` en dev-1 y completá IPs, `pg1-path` de cada
   stanza y una `<PASSPHRASE>` fuerte para `repo1-cipher-pass`
   (**guardá esa passphrase**: sin ella los backups no se pueden restaurar).
2. Creá el repo y permisos:
   ```bash
   sudo mkdir -p /var/lib/pgbackrest
   sudo chown postgres:postgres /var/lib/pgbackrest
   sudo chmod 750 /var/lib/pgbackrest
   ```
3. Instalá el servicio TLS (`pgbackrest/systemd/pgbackrest.service`) y arrancalo:
   ```bash
   sudo cp pgbackrest.service /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now pgbackrest
   sudo systemctl status pgbackrest
   ```

## Paso 4 — Configurar cada DB HOST

Por cada server (empezá por dev-1 y prod-1):

1. Copiá `pgbackrest/db-host/pgbackrest.conf.example` a
   `/etc/pgbackrest/pgbackrest.conf`, reemplazando `prod-1` por el nombre real,
   la IP de dev-1 y el `pg1-path`. (En **dev-1** el stanza es local y va en la
   config del repo host del Paso 3, no necesita esta config de cliente.)
2. Instalá y arrancá el servicio TLS (mismo `pgbackrest.service`).
3. Configurá el archivado de WAL en `postgresql.conf`:
   ```
   archive_mode = on
   archive_command = 'pgbackrest --stanza=prod-1 archive-push %p'
   max_wal_senders = 3
   wal_level = replica
   ```
   y reiniciá PostgreSQL (requiere restart si cambió `archive_mode`/`wal_level`):
   ```bash
   sudo systemctl restart postgresql
   ```

## Paso 5 — Crear stanza, verificar y primer backup (desde dev-1)

```bash
# crear el stanza (una vez por cluster)
sudo -u postgres pgbackrest --stanza=prod-1 stanza-create

# verificar archiving + repo (esto detecta el 90% de los errores de config)
sudo -u postgres pgbackrest --stanza=prod-1 check

# primer backup full
sudo -u postgres pgbackrest --stanza=prod-1 --type=full backup

# ver estado
sudo -u postgres pgbackrest info
```

Si `check` falla, revisá: puerto 8432 abierto en ambos sentidos, CN de los certs
vs `tls-server-auth`, y que el servicio `pgbackrest` esté activo en ambos hosts.

## Paso 6 — Programar backups (cron en dev-1)

`/etc/cron.d/pgbackrest` en dev-1 (corre como postgres):

```
# full domingo 02:00, incremental el resto de los días 02:00
0 2 * * 0 postgres pgbackrest --stanza=prod-1 --type=full backup
0 2 * * 1-6 postgres pgbackrest --stanza=prod-1 --type=incr backup
# (repetí el par de líneas por cada stanza: prod-2, prod-3, dev-1)
```

## Paso 7 — Rollout escalonado

1. **dev-1** (repo + su propio stanza) → `check` + backup OK.
2. **prod-1** (ya tenía pgBackRest) → repuntar al repo central, `check`, backup OK.
   Recién ahí dar de baja su repo viejo.
3. **prod-2** y **prod-3** (instalación nueva) → uno por vez.

## Paso 8 — Monitoreo

Una vez que cada stanza hace backups OK, desplegá el monitoreo (ya cubre los 4):

```bash
./scripts/30-deploy-pgbackrest-monitoring.sh
```

Esto deja en Netdata las alarmas de antigüedad de backup, backup fallido y
`check` fallido, con aviso a Telegram + Email.

## Restore (tenelo a mano)

Probá un restore en un entorno aparte para validar que los backups sirven:

```bash
sudo -u postgres pgbackrest --stanza=prod-1 --delta restore
```

> **Un backup no probado no es un backup.** Agendá una prueba de restore periódica.
