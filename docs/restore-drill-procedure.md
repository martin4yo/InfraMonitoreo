# Procedimiento de Drill de Restauración — pgBackRest

**Versión:** 1.1  
**Fecha de referencia:** 2026-05-29  
**Redactor:** Equipo infraestructura — ejecutar desde KEYSOFT-UBUNTU

---

## 1. Objetivo y alcance

### Qué valida este drill

- Que los backups almacenados en **repo2 (Cloudflare R2)** son recuperables y completos.
- Que el WAL archivado en R2 es continuo y puede reproducirse hasta los **últimos minutos antes del desastre** — no solo hasta el último backup incremental.
- Que el proceso de restauración funciona de extremo a extremo: descarga desde R2, descifrado AES-256-CBC, descompresión lz4, WAL replay completo y promoción automática de PostgreSQL.
- Que el tiempo de recuperación real (RTO) es conocido y documentado para cada stanza.
- Que las credenciales de acceso a R2 y la clave de cifrado son correctas y accesibles desde KEYSOFT-UBUNTU.

### Qué NO hace este drill

- **No reemplaza ni afecta producción.** La restauración se realiza en directorios temporales aislados en `/var/lib/postgresql/restore-drill/`.
- No valida repo1 (SSH local en dev-1). Ese es un objetivo separado.
- No prueba failover ni cambio de DNS.

### Diferencia entre drill básico y drill con WAL replay (este documento)

Un drill **sin** WAL replay solo confirma que el último backup incremental es recuperable — el RPO efectivo sería de hasta 4 horas (frecuencia del cron). Este drill aplica **todo el WAL archivado disponible en R2** y verifica que el último xact reproducido tiene menos de 30 minutos de antigüedad, lo que confirma que en un desastre real se puede restaurar hasta pocos minutos antes del evento.

---

## 2. Prerequisitos

### En KEYSOFT-UBUNTU

| Requisito | Verificación |
|---|---|
| `pgbackrest` instalado | `pgbackrest version` |
| Binarios PG 14 | `ls /usr/lib/postgresql/14/bin/pg_ctl` |
| Binarios PG 16 | `ls /usr/lib/postgresql/16/bin/pg_ctl` |
| `sudo -u postgres` sin contraseña | `sudo -u postgres -H echo ok` |
| SSH a dev-1 | `ssh axiomacloud@149.50.148.198 echo ok` |
| ~500 MB libres en `/var/lib/postgresql` | `df -h /var/lib/postgresql` |

### Acceso SSH

| Desde | Hacia | Usuario | Puerto |
|---|---|---|---|
| KEYSOFT-UBUNTU | dev-1 | axiomacloud | 22 |

El script lee las credenciales R2 directamente desde `/etc/pgbackrest/pgbackrest.conf` en dev-1 vía SSH. No es necesario acceso SSH desde KEYSOFT-UBUNTU a los db-hosts para este drill — el restore corre localmente.

### Espacio en disco estimado (en KEYSOFT-UBUNTU)

| Stanza | Backup comprimido en R2 | Espacio descomprimido estimado |
|---|---|---|
| AxiomaCloudProd | ~8 MB (repo bundle) | ~1.5–2 GB |
| clubix | ~8 MB (repo bundle) | ~600 MB–1 GB |
| axiodemo | ~8 MB (repo bundle) | ~120–200 MB |

---

## 3. Script automatizado

El drill se ejecuta con `scripts/70-restore-drill.sh` desde KEYSOFT-UBUNTU. El script:

1. Lee las credenciales R2 desde dev-1 vía SSH.
2. Genera un `pgbackrest.conf` local temporal con esas credenciales (como usuario `postgres`, permisos 600).
3. Para cada stanza: restaura el último backup incremental con `--type=standby`, lo que hace que pgbackrest escriba el `restore_command` apuntando a R2 en `postgresql.auto.conf`.
4. Reemplaza `standby.signal` por `recovery.signal` para que PG aplique todo el WAL archivado y promueva al llegar al último segmento disponible (en lugar de quedarse esperando un primary).
5. Arranca la instancia en un puerto efímero (5442/5443/5444), espera la promoción y verifica:
   - Conectividad
   - `pg_is_in_recovery() = f`
   - `pg_last_xact_replay_timestamp()` con menos de 30 minutos de antigüedad
   - Conteo de tablas por base
   - Antigüedad del backup (umbral 25h)
6. Detiene la instancia y elimina el directorio temporal.
7. Imprime un resumen con backup usado, tiempo de restore, WAL lag y estado.

### Uso

```bash
# Todas las stanzas
bash scripts/70-restore-drill.sh

# Solo una stanza
bash scripts/70-restore-drill.sh axiodemo

# Subset
bash scripts/70-restore-drill.sh AxiomaCloudProd clubix
```

Logs en `/tmp/restore-drill-logs/drill-<timestamp>.log`.

---

## 4. Procedimiento manual por stanza

> Usar este procedimiento solo si el script falla o se necesita ejecutar el drill paso a paso con más control. El script implementa exactamente este flujo.

### Flujo común a todas las stanzas

El restore se hace en dos fases:

**Fase 1 — pgbackrest restore con `--type=standby`:** pgbackrest descarga el backup desde R2 y escribe `restore_command = 'pgbackrest --config=... --stanza=... archive-get %f "%p"'` en `postgresql.auto.conf`. Esto permite que PG, al arrancar, busque los segmentos WAL en R2 usando pgbackrest como agente de restauración.

**Fase 2 — WAL replay en startup:** PG arranca en modo recovery, lee `recovery.signal`, ejecuta el `restore_command` para cada segmento WAL que necesita desde R2, y promueve al llegar al último disponible. El resultado es un cluster con los datos al día al momento del último segmento archivado.

**Por qué `recovery.signal` y no `standby.signal`:** `standby.signal` haría que PG entre en modo hot standby y espere indefinidamente a un primary que no existe. `recovery.signal` le indica que aplique el WAL disponible y promueva.

### 4.1 AxiomaCloudProd

**DB host:** axioma — 66.97.45.210, PG 14, PGDATA producción: `/var/lib/postgresql/14/main`

#### Paso 1 — Preparar directorio destino (en KEYSOFT-UBUNTU, como postgres)

```bash
sudo -u postgres mkdir -p /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata
sudo -u postgres chmod 700 /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata
```

#### Paso 2 — Restaurar desde R2 con WAL replay habilitado

```bash
sudo -u postgres pgbackrest \
  --config=/var/lib/postgresql/restore-drill/pgbackrest-local.conf \
  --stanza=AxiomaCloudProd \
  --type=standby \
  restore
```

Tiempo estimado: 10–20 minutos (descarga desde R2).

#### Paso 3 — Reemplazar standby.signal por recovery.signal

```bash
sudo -u postgres bash -c "
  rm -f /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/standby.signal
  touch /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/recovery.signal
"
```

#### Paso 4 — Agregar overrides al postgresql.conf

```bash
sudo -u postgres bash -c "cat >> /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/postgresql.conf" <<EOF

# restore-drill overrides
port = 5442
hba_file = '/var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/pg_hba.conf'
ident_file = '/var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/pg_ident.conf'
EOF
```

Generar pg_hba.conf mínimo si no existe:

```bash
sudo -u postgres bash -c "cat > /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/pg_hba.conf" <<'EOF'
local   all   all                trust
host    all   all   127.0.0.1/32 trust
EOF
sudo -u postgres touch /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata/pg_ident.conf
```

#### Paso 5 — Arrancar la instancia temporal (WAL replay)

```bash
sudo -u postgres /usr/lib/postgresql/14/bin/pg_ctl \
  -D /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata \
  -l /var/lib/postgresql/restore-drill/AxiomaCloudProd/pg.log \
  start -w -t 300
```

PG tardará varios minutos descargando segmentos WAL de R2 durante el recovery. Monitorear el progreso:

```bash
sudo -u postgres psql -h 127.0.0.1 -p 5442 -tAq \
  -c "SELECT to_char(pg_last_xact_replay_timestamp(),'YYYY-MM-DD HH24:MI:SS');"
```

#### Paso 6 — Verificación

```bash
# Confirmar promoción (debe retornar f)
sudo -u postgres psql -h 127.0.0.1 -p 5442 -tAq -c "SELECT pg_is_in_recovery();"

# Frescura del WAL (debe ser reciente — minutos, no horas)
sudo -u postgres psql -h 127.0.0.1 -p 5442 -tAq \
  -c "SELECT pg_last_xact_replay_timestamp();"

# Bases de datos presentes
sudo -u postgres psql -h 127.0.0.1 -p 5442 -c "\l"

# Conteo de tablas
sudo -u postgres psql -h 127.0.0.1 -p 5442 -tAq \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');"
```

#### Paso 7 — Apagar y limpiar

```bash
sudo -u postgres /usr/lib/postgresql/14/bin/pg_ctl \
  -D /var/lib/postgresql/restore-drill/AxiomaCloudProd/pgdata stop

sudo -u postgres rm -rf /var/lib/postgresql/restore-drill/AxiomaCloudProd
```

---

### 4.2 clubix

**DB host:** clubix — 179.43.123.248:2222, PG 14, PGDATA producción: `/var/lib/postgresql/14/main`

Mismo flujo que 4.1, reemplazando:
- Stanza: `clubix`
- Path: `/var/lib/postgresql/restore-drill/clubix/pgdata`
- Puerto efímero: `5443`
- Binarios: `/usr/lib/postgresql/14/bin/`

---

### 4.3 axiodemo

**DB host:** axiodemo — 170.78.73.245, PG 16, PGDATA producción: `/var/lib/postgresql/16/main`

Mismo flujo que 4.1, reemplazando:
- Stanza: `axiodemo`
- Path: `/var/lib/postgresql/restore-drill/axiodemo/pgdata`
- Puerto efímero: `5444`
- Binarios: `/usr/lib/postgresql/16/bin/`

---

## 5. Verificación de integridad sin restaurar

pgBackRest tiene el comando `verify` que valida checksums de todos los archivos en el repositorio (backups + WAL) sin necesidad de restaurar. Ejecutar desde dev-1 antes del drill para confirmar que no hay corrupción silenciosa en R2:

```bash
# en dev-1
sudo -u pgbackrest pgbackrest --repo=2 --stanza=AxiomaCloudProd verify
sudo -u pgbackrest pgbackrest --repo=2 --stanza=clubix verify
sudo -u pgbackrest pgbackrest --repo=2 --stanza=axiodemo verify
```

Output esperado:

```
P00   INFO: verify command begin ...
P00   INFO: verify backup/wal files completed successfully
```

Si aparece `ERROR` o `WARN: archive_check`, investigar antes de continuar.

---

## 6. Criterios de éxito y fallo

### Criterios de éxito (drill aprobado)

- [ ] `pgbackrest restore` completa sin errores (`restore command end: completed successfully`).
- [ ] `pg_ctl start` arranca PostgreSQL sin errores en el log.
- [ ] `SELECT pg_is_in_recovery()` retorna `f` — el cluster promovió.
- [ ] `SELECT pg_last_xact_replay_timestamp()` tiene menos de **30 minutos** de antigüedad — confirma WAL archive fresco.
- [ ] `\l` lista las bases de datos de aplicación (no solo las del sistema).
- [ ] Conteo de tablas de aplicación mayor a 0.

### Criterios de fallo (drill rechazado — acción requerida antes del próximo drill)

| Síntoma | Acción |
|---|---|
| `pgbackrest restore` termina con `ERROR` | Ver sección 9. No marcar el drill como exitoso. |
| `pg_ctl start` falla | Revisar `pg.log` en el directorio de la stanza. |
| `pg_is_in_recovery()` retorna `t` | WAL replay no terminó o promote falló. Ver sección 9.1. |
| `pg_last_xact_replay_timestamp()` es NULL | No se aplicó WAL archive — `restore_command` no funcionó. Ver sección 9.2. |
| `pg_last_xact_replay_timestamp()` tiene más de 30 min | WAL archive desactualizado — hay una brecha en el archivado. Investigar `archive_status` en producción. |
| `\l` muestra solo bases del sistema | Restore incompleto o path incorrecto. |

---

## 7. Cadencia y ejecución regular

Este drill es un **chequeo manual recurrente**, no automatizado. La decisión y su fundamento:

- **Cadencia acordada: mensual** (y siempre después de un cambio en la config de pgBackRest,
  cambio de versión de PostgreSQL, o migración de repo). Un drill viejo no vale: valida el
  estado del backup+WAL *al momento de correrlo*.
- **No hay cron.** El ejecutor natural (`KEYSOFT-UBUNTU`) no está siempre encendido, así que un
  cron generaría falsos "no corrió". El drill es rápido (~1 min/stanza) y auto-evaluante
  (`exit 0/1` + resumen), por lo que correrlo a mano y registrarlo acá es suficiente.
- **NO se corre en `dev-1`.** `dev-1` aloja el repositorio de backups. Un drill debe restaurar en
  un host **distinto** del repo: es lo único que prueba el escenario real de desastre (perder el
  host del repo) y evita colisiones con el PG/repo productivo. Correrlo en dev-1 invalidaría el
  drill como prueba de DR.
- **NO hace falta un agente** para esto: no hay nada que interpretar más allá del veredicto
  binario que ya emite el script.

### Cómo correr el chequeo regular

```bash
# En KEYSOFT-UBUNTU (o cualquier host != dev-1 con PG14/16 + pgbackrest 2.58 + sudo→postgres)
cd ~/Desarrollos/InfraMonitoreo
./scripts/70-restore-drill.sh            # las 3 stanzas de prod
echo "exit=$?"                            # 0 = todas PASS, 1 = alguna FAIL
```

1. **Registro automático:** al terminar, el script agrega una fila por stanza a
   `docs/drill-history.csv` (fecha, ejecutor, stanza, backup, repo, restore, wal_lag, resultado).
   Es la traza objetiva versionada — **hacé `git commit` de ese archivo** después de cada corrida.
2. Si `exit=0` y el resumen dice `✓ DRILL EXITOSO`: la fila queda como `PASS`. Commitear el CSV.
3. Si `exit=1`: NO marcar como exitoso. La fila del CSV queda `FAIL`. Leer el log en
   `/tmp/restore-drill-logs/drill-*.log`, identificar la stanza y el criterio que falló (§6),
   diagnosticar con §9 (Troubleshooting). El fallo del drill es una alerta de DR: el problema
   está en el backup/WAL de producción, no en el drill.
4. La tabla narrativa de §8 es un **resumen curado** (hitos, primeras corridas, incidentes con
   observaciones). No hace falta duplicar ahí cada corrida rutinaria — para eso está el CSV. Sí
   agregá una fila a §8 cuando la corrida tenga algo digno de nota (un FAIL, un cambio de setup).
5. Si una máquina distinta corre el drill, ajustar los prerequisitos de §2 en ese host.

---

## 8. Registro de drills

**Traza completa (todas las corridas):** `docs/drill-history.csv`, actualizado automáticamente
por el script. La tabla de abajo es un **resumen curado** con hitos, primeras corridas por stanza
e incidentes con observaciones — no duplica cada corrida rutinaria del CSV.

| Fecha | Ejecutor | Stanza | Backup usado | Repo | Restore | WAL lag | Tablas | Resultado |
|---|---|---|---|---|---|---|---|---|
| 2026-05-29 | martin4yo | axiodemo | 20260529-091303F_20260529-193004I | repo2 | 14s | 1 min | 33 | PASS |
| 2026-07-04 | martin4yo | axiodemo | 20260628-033014F_20260704-153017I | R2 (repo1 local) | 15s | 0 min | 34 | PASS |
| 2026-07-19 | martin4yo | AxiomaCloudProd | 20260719-030015F_20260719-190019I | R2 | 71s | 0 min | 585 | **PASS — 1ª corrida** |
| 2026-07-19 | martin4yo | clubix | 20260719-031514F_20260719-191516I | R2 | 44s | 1 min | 178 | **PASS — 1ª corrida** |
| 2026-07-19 | martin4yo | axiodemo | 20260719-033013F_20260719-193017I | R2 | 11s | 1 min | 34 | PASS |

> **Nota sobre las corridas FAIL previas del 2026-07-19** (12:26 y 12:51 en el CSV): fueron **falsos
> negativos del script**, no fallas de backup. Dos bugs, ambos corregidos en `70-restore-drill.sh`
> antes de la corrida de las 20:08:
> 1. El script copiaba el `pg_hba.conf` del cluster local al PGDATA temporal cuando existía. El de
>    PG14 del ejecutor trae `scram-sha-256` → la instancia restaurada pedía password y el `psql` del
>    drill era rechazado **por autenticación**, leído como "PG no responde". Solo fallaban las stanzas
>    PG14 (AxiomaCloudProd, clubix); axiodemo (PG16) pasaba porque no hay `/etc/postgresql/16` y caía
>    en el `trust` por defecto. Ahora **siempre** se genera el `pg_hba` mínimo `trust`.
> 2. El chequeo de conectividad no esperaba: durante el replay inicial PG responde `the database
>    system is starting up`, y un intento único daba falso FAIL en las bases grandes. Ahora reintenta
>    hasta 300s.
>
> **Lección:** ante un FAIL, distinguir *fallo de restore* de *fallo de verificación* antes de
> escalarlo como incidente de DR. Acá los backups estaban íntegros en los 3 casos.

**Resultados posibles:** `PASS` / `FAIL` / `PARCIAL` (especificar observaciones en el commit o ticket correspondiente).

---

## 9. Troubleshooting

### 9.1 Instancia queda en recovery — no promueve

**Síntoma:** `pg_is_in_recovery()` retorna `t` después de varios minutos.

**Causa probable:** `standby.signal` no fue reemplazado por `recovery.signal`, o hay un `recovery_target` configurado que no se alcanzó.

**Acción:**
```bash
# Verificar señales presentes
ls -la /var/lib/postgresql/restore-drill/<stanza>/pgdata/{standby,recovery}.signal 2>/dev/null

# Si standby.signal persiste, reemplazar con la instancia detenida:
sudo -u postgres /usr/lib/postgresql/<ver>/bin/pg_ctl \
  -D /var/lib/postgresql/restore-drill/<stanza>/pgdata stop -m immediate
sudo -u postgres bash -c "
  rm -f /var/lib/postgresql/restore-drill/<stanza>/pgdata/standby.signal
  touch /var/lib/postgresql/restore-drill/<stanza>/pgdata/recovery.signal
"
# Reiniciar
```

O promover manualmente si la instancia está corriendo:
```bash
sudo -u postgres psql -h 127.0.0.1 -p <puerto> -c "SELECT pg_promote();"
```

### 9.2 pg_last_xact_replay_timestamp() es NULL

**Síntoma:** La instancia promovió pero el timestamp es NULL.

**Causa probable:** El `restore_command` en `postgresql.auto.conf` no pudo contactar R2, o la stanza no tiene WAL archivado más allá del backup restaurado.

**Acción:**
1. Revisar `pg.log` buscando líneas `restore_command` con errores.
2. Verificar que el conf local tiene las credenciales R2 correctas:
   ```bash
   sudo -u postgres cat /var/lib/postgresql/restore-drill/pgbackrest-local.conf | grep -E 'repo1-s3|cipher'
   ```
3. Verificar que hay WAL archivado en repo2:
   ```bash
   ssh axiomacloud@149.50.148.198 "sudo -u pgbackrest pgbackrest --repo=2 --stanza=<stanza> info"
   ```
   La línea `wal archive min/max` debe mostrar segmentos más allá del stop WAL del último backup.

### 9.3 Cipher mismatch

**Síntoma:**
```
ERROR: [055]: cipher header invalid
```

**Causa:** `repo2-cipher-pass` en dev-1 no coincide con el usado al crear el backup.

**Acción:** Verificar el valor en dev-1 contra el vault. No modificar la clave — todos los backups anteriores quedarían irrecuperables.

### 9.4 Lock file / postmaster.pid existente

**Síntoma:**
```
ERROR: [056]: unable to restore to path ... because postmaster.pid exists
```

**Acción:**
```bash
sudo -u postgres /usr/lib/postgresql/<ver>/bin/pg_ctl \
  -D /var/lib/postgresql/restore-drill/<stanza>/pgdata stop -m immediate 2>/dev/null
sudo -u postgres rm -f /var/lib/postgresql/restore-drill/<stanza>/pgdata/postmaster.pid
```

### 9.5 Error de permisos en el directorio destino

**Síntoma:**
```
ERROR: [015]: unable to open file ... permission denied
```

**Acción:**
```bash
sudo chown -R postgres:postgres /var/lib/postgresql/restore-drill/<stanza>
sudo -u postgres chmod 700 /var/lib/postgresql/restore-drill/<stanza>/pgdata
```

### 9.6 pg_ctl — versión incorrecta del binario

**Síntoma:** `pg_ctl: invalid data directory` o error de versión de catálogo en el log.

**Causa:** Binario de una versión de PG distinta a la del backup.

**Versiones por stanza:**
- AxiomaCloudProd y clubix: `/usr/lib/postgresql/14/bin/pg_ctl`
- axiodemo: `/usr/lib/postgresql/16/bin/pg_ctl`
