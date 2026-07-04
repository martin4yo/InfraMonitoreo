# Plan de Recuperación ante Desastres (DRP)
## Infraestructura pgBackRest — InfraMonitoreo

| Campo | Valor |
|---|---|
| Versión | 1.0 |
| Fecha de última actualización | 2026-05-29 |
| Próxima revisión obligatoria | 2026-08-29 (trimestral) |
| Responsable técnico | martin4yo@gmail.com |
| Repositorio | InfraMonitoreo — rama principal |

---

## 1. Información general

### 1.1 Alcance

Este documento define los procedimientos para recuperar los servicios de base de datos PostgreSQL ante eventos de pérdida de datos, falla de hardware o pérdida de infraestructura de backup. Cubre las cuatro stanzas gestionadas con pgBackRest:

| Stanza | Servidor | IP | PG | Rol |
|---|---|---|---|---|
| dev-1 | dev-1 | 149.50.148.198 | 14 | Repo host + db host |
| AxiomaCloudProd | axioma | 66.97.45.210 | 14 | DB producción principal |
| clubix | clubix | 179.43.123.248 (puerto 2222) | 14 | DB producción |
| axiodemo | axiodemo | 170.78.73.245 | 16 | DB demo |

### 1.2 Arquitectura de backup

- **repo1** — SSH local en dev-1 (`/backup/pgbackrest`). Sin cifrado. Acceso directo por red privada.
- **repo2** — Cloudflare R2, bucket `axiomacloud-pgbackrest`, path `/pgbackrest`. Cifrado AES-256-CBC, `repo2-bundle=y`.
- **Retención:** full=4, diff=7 en ambos repositorios.
- **Cron en dev-1:** full los domingos, diff lunes a sábado, incr cada 4 horas.

### 1.3 Objetivos de recuperación

| Tier | Servicio | RPO | RTO |
|---|---|---|---|
| Crítico | AxiomaCloudProd, clubix | 4 horas | 30 minutos |
| No crítico | axiodemo | 4 horas | 60 minutos |
| Infraestructura | dev-1 (repo host) | 4 horas | 45 minutos |

**RPO efectivo:** 4 horas (frecuencia de backup incremental).
**RTO de referencia:** 15–30 min para bases pequeñas (repo1, red local); 30–60 min para bases grandes o restore desde R2 con egress WAN.

---

## 2. Clasificación de escenarios de desastre

### Escenario A — Corrupción de datos en un db host

**Descripción:** Un db host (axioma, clubix o axiodemo) experimenta corrupción de datos: tablas dañadas, escritura incorrecta por bug de aplicación, o eliminación accidental. El servidor sigue en pie. dev-1 está accesible y repo1 está íntegro.

**Fuente de restauración:** repo1 (SSH desde dev-1). Primera opción porque no genera egress de R2 y la velocidad de transferencia es mayor.

**Pasos de alto nivel:**
1. Confirmar corrupción con `pg_dump` o consultas de verificación en tablas afectadas.
2. Determinar el punto de restauración objetivo (última incr antes del evento o PITR a timestamp específico).
3. Detener PostgreSQL en el db host afectado.
4. Ejecutar `pgbackrest restore --stanza=<stanza> --repo=1` con los parámetros de PITR si aplica.
5. Iniciar PostgreSQL y ejecutar validación post-restore.

**RTO estimado:** 15–30 minutos.

---

### Escenario B — Pérdida total del db host

**Descripción:** El VPS o servidor del db host es destruido o irrecuperable (falla de hardware, eliminación accidental del VPS). Hay que aprovisionar un nuevo servidor con la misma IP o actualizar DNS/app. dev-1 y repo1 están disponibles.

**Fuente de restauración:** repo1 (SSH desde dev-1) como primera opción; repo2 como fallback si repo1 tiene problemas de integridad.

**Pasos de alto nivel:**
1. Aprovisionar nuevo servidor con el mismo OS y versión de PostgreSQL.
2. Instalar pgBackRest y copiar la configuración de la stanza desde dev-1.
3. Regenerar o copiar la clave SSH del nuevo host a dev-1 (autorización en `authorized_keys` de dev-1).
4. Ejecutar `pgbackrest restore --stanza=<stanza> --repo=1` desde el nuevo servidor.
5. Validar conectividad, datos y WAL archiving.
6. Actualizar registros DNS o configuración de aplicación si la IP cambió.

**RTO estimado:** 30–45 minutos (más tiempo de aprovisionamiento del VPS, variable según proveedor).

---

### Escenario C — Pérdida de dev-1 (repo host caído)

**Descripción:** dev-1 cae completamente (falla, eliminación) o repo1 queda inaccesible. Los db hosts están operativos pero sin capacidad de restore vía repo1. Solo queda repo2 en Cloudflare R2.

**Fuente de restauración:** repo2 (Cloudflare R2) desde KEYSOFT-UBUNTU o desde cualquier db host con acceso a internet y las credenciales de R2.

**Pasos de alto nivel:**
1. Confirmar que dev-1 es irrecuperable o que repo1 está dañado.
2. Preparar el equipo de restauración (KEYSOFT-UBUNTU o el propio db host) con pgBackRest instalado y configuración de repo2.
3. Proveer credenciales de R2 (cipher-pass, s3-key-id, s3-key-secret) desde el vault.
4. Ejecutar `pgbackrest restore --stanza=<stanza> --repo=2` apuntando al db host destino.
5. Una vez restaurados los db hosts, reaprovisionar dev-1 y reconfigurar repo1.

**RTO estimado:** 45–60 minutos (egress WAN desde R2 agrega latencia).

---

### Escenario D — Pérdida simultánea de dev-1 y un db host (peor caso)

**Descripción:** dev-1 y uno o más db hosts caen al mismo tiempo. Solo R2 está disponible. Este es el escenario de mayor impacto.

**Fuente de restauración:** repo2 (Cloudflare R2) desde KEYSOFT-UBUNTU.

**Pasos de alto nivel:**
1. Declarar disaster — notificar a los stakeholders.
2. Aprovisionar nuevo servidor para el db host perdido.
3. Instalar PostgreSQL y pgBackRest en el nuevo servidor.
4. Configurar pgBackRest con acceso a repo2 usando credenciales del vault.
5. Ejecutar `pgbackrest restore --stanza=<stanza> --repo=2`.
6. Validar el servicio.
7. Reaprovisionar dev-1 y restaurar la arquitectura completa de backup.

**RTO estimado:** 60–90 minutos (aprovisionamiento de infraestructura + egress WAN).

---

## 3. Procedimiento de respuesta paso a paso

> Los comandos exactos de pgBackRest están en el **Restore Drill Procedure** (referencia interna). Este procedimiento cubre el flujo de decisión y coordinación.

---

### 3.1 Escenario A — Corrupción de datos

#### Detección y declaración
- Alerta de Netdata sobre stanza con status degradado, o reporte de usuario de datos inconsistentes.
- Confirmar con consulta directa a PostgreSQL: `pg_dump -t <tabla_afectada> | wc -l` o validación de integridad con `VACUUM ANALYZE`.
- Si la corrupción se confirma, declarar incidente y registrar timestamp del evento.

#### Comunicación
1. Notificar al equipo técnico (responsable de infraestructura).
2. Notificar al cliente/usuario del servicio afectado: ventana de mantenimiento de emergencia activa, ETA según RTO.
3. Mantener canal abierto (chat/email) durante toda la restauración.

#### Restauración técnica
- Determinar PITR: identificar el último incr previo al evento de corrupción con `pgbackrest info --stanza=<stanza>`.
- Seguir el Restore Drill Procedure para los comandos de restore con `--type=time` si se requiere PITR.
- Restaurar desde repo1 si dev-1 está accesible; desde repo2 si no.

#### Verificación post-restore
Ver sección 6 — Checklist de validación post-restore.

#### Post-mortem
- Registrar: timestamp de detección, timestamp de declaración, timestamp de restore completado, causa raíz, acción correctiva.
- Añadir entrada a la tabla de drills/incidentes de la sección 7.

---

### 3.2 Escenario B — Pérdida total del db host

#### Detección y declaración
- Alerta de Netdata: host unreachable + stanza en estado de error.
- Intentar SSH al servidor. Si falla: confirmar desde el panel del proveedor de VPS.
- Si el VPS está destruido o irrecuperable: declarar incidente.

#### Comunicación
1. Notificar al equipo técnico de inmediato.
2. Notificar al cliente: servicio interrumpido, ETA de recuperación.
3. Si la IP va a cambiar: coordinar con el equipo de aplicación el cambio de configuración.

#### Restauración técnica
- Aprovisionar nuevo VPS con el mismo OS/versión de PG.
- Seguir el Restore Drill Procedure para restore completo desde repo1 o repo2.
- Actualizar `authorized_keys` en dev-1 con la nueva clave SSH del servidor.

#### Verificación post-restore
Ver sección 6.

#### Post-mortem
Ídem Escenario A.

---

### 3.3 Escenario C — Pérdida de dev-1

#### Detección y declaración
- Alerta de Netdata: host unreachable en dev-1, o falla de backup cron (Netdata stanza check en error).
- Confirmar desde panel del proveedor.
- Si dev-1 es irrecuperable: declarar incidente.

#### Comunicación
1. Notificar al equipo técnico.
2. Evaluar si los db hosts siguen operativos (probablemente sí — los servicios de aplicación no dependen de dev-1 para funcionar).
3. Informar que la capacidad de backup está degradada hasta restaurar dev-1.

#### Restauración técnica
- Desde KEYSOFT-UBUNTU: instalar pgBackRest, configurar acceso a repo2 con credenciales del vault.
- Validar acceso a R2 con `pgbackrest info --stanza=<stanza> --repo=2`.
- Si algún db host requiere restore: ejecutar desde repo2.
- Reaprovisionar dev-1: ver procedimiento de setup en `docs/pgbackrest-setup.md`.

#### Verificación post-restore
- Confirmar que repo1 vuelve a estar operativo después de reaprovisionar dev-1.
- Confirmar que los backups cron retoman normalmente.
- Ver sección 6 para validación de db hosts.

#### Post-mortem
Ídem Escenario A.

---

### 3.4 Escenario D — Pérdida simultánea de dev-1 y un db host

#### Detección y declaración
- Múltiples alertas simultáneas de Netdata.
- Confirmar cada falla de forma independiente antes de declarar el escenario D.
- Declarar incidente de nivel máximo.

#### Comunicación
1. Notificar al equipo técnico y a la dirección.
2. Notificar a todos los clientes afectados con ETA pesimista (60–90 min + aprovisionamiento).
3. Mantener actualizaciones cada 15 minutos mientras dure el incidente.

#### Restauración técnica
- Priorizar por tier: restaurar primero AxiomaCloudProd y clubix, luego axiodemo.
- Para cada db host perdido: aprovisionar nuevo VPS, instalar PG y pgBackRest.
- Configurar acceso a repo2 desde KEYSOFT-UBUNTU o desde el nuevo servidor.
- Seguir el Restore Drill Procedure para restore desde repo2.
- Reaprovisionar dev-1 al final, una vez que los servicios críticos estén restaurados.

#### Verificación post-restore
Ver sección 6. Validar cada stanza de forma independiente.

#### Post-mortem
Ídem Escenario A. Análisis especial de causa raíz para determinar por qué dos sistemas fallaron simultáneamente.

---

## 4. Árbol de decisión — Fuente de restore

```
¿El incidente requiere restore de datos?
│
├─ SÍ
│   │
│   ├─ ¿dev-1 accesible y repo1 íntegro?
│   │   │
│   │   ├─ SÍ → Usar repo1 (SSH local, sin egress R2, más rápido)
│   │   │         pgbackrest restore --stanza=<stanza> --repo=1
│   │   │
│   │   └─ NO → Usar repo2 (Cloudflare R2)
│   │             Obtener credenciales del vault
│   │             Configurar pgbackrest con acceso a R2 en el equipo de restore
│   │             pgbackrest restore --stanza=<stanza> --repo=2
│   │
│   └─ ¿El db host destino existe?
│       │
│       ├─ SÍ → Restore directo al host existente
│       │
│       └─ NO → Aprovisionar nuevo VPS primero, luego ejecutar restore
│
└─ NO → Incidente no requiere restore (falla de conectividad, config, etc.)
        Resolver según runbook correspondiente
```

**Notas:**
- Nunca restaurar directamente sobre un cluster PG que esté en producción y aceptando escrituras. Siempre detener PG antes del restore.
- Si se usa repo2, verificar que el equipo de restore tiene `cipher-pass` configurado en `pgbackrest.conf` antes de ejecutar el restore.

---

## 5. Credenciales y acceso de emergencia

### 5.1 Credenciales necesarias para restore desde repo2 (Cloudflare R2)

Para ejecutar un restore desde repo2 se necesitan:

| Credencial | Descripción | Almacenamiento |
|---|---|---|
| `repo2-cipher-pass` | Clave AES-256-CBC para descifrar los backups de R2 | `pgbackrest.conf` en dev-1 + vault/gestor de contraseñas |
| `repo2-s3-key` | Access Key ID de Cloudflare R2 | `pgbackrest.conf` en dev-1 + vault/gestor de contraseñas |
| `repo2-s3-key-secret` | Secret Access Key de Cloudflare R2 | `pgbackrest.conf` en dev-1 + vault/gestor de contraseñas |

**IMPORTANTE:** Los valores reales de estas credenciales NO están en este documento. Deben estar registrados en un gestor de contraseñas o vault seguro (ej. Bitwarden, 1Password, HashiCorp Vault) accesible offline o desde KEYSOFT-UBUNTU. Si solo están en `pgbackrest.conf` de dev-1 y dev-1 cae, las credenciales deben obtenerse del vault antes de poder restaurar desde R2.

### 5.2 Acceso SSH de emergencia

El equipo de restauración de referencia es **KEYSOFT-UBUNTU** (Linux local), con acceso SSH a los cuatro servidores usando la clave `~/.ssh/id_ed25519`.

| Servidor | Comando de acceso |
|---|---|
| dev-1 | `ssh -i ~/.ssh/id_ed25519 user@149.50.148.198` |
| axioma | `ssh -i ~/.ssh/id_ed25519 user@66.97.45.210` |
| clubix | `ssh -i ~/.ssh/id_ed25519 -p 2222 user@179.43.123.248` |
| axiodemo | `ssh -i ~/.ssh/id_ed25519 user@170.78.73.245` |

Reemplazar `user` con el usuario del sistema en cada servidor.

### 5.3 Verificación de acceso antes de un incidente

Verificar mensualmente que el acceso SSH desde KEYSOFT-UBUNTU a los cuatro servidores funciona correctamente. No esperar a un incidente para descubrir que una clave expiró o fue revocada.

---

## 6. Checklist de validación post-restore

### 6.1 Checks técnicos — PostgreSQL

- [ ] PostgreSQL arrancó sin errores: `systemctl status postgresql`
- [ ] PostgreSQL acepta conexiones locales: `psql -U postgres -c "SELECT 1"`
- [ ] Todas las bases de datos esperadas están presentes: `psql -U postgres -c "\l"`
- [ ] Las tablas críticas existen y tienen filas: `SELECT count(*) FROM <tabla_crítica>`
- [ ] No hay errores en el log de PG: `journalctl -u postgresql --since "1 hour ago" | grep -i error`
- [ ] El cluster está en modo de lectura/escritura (no en recovery): `psql -U postgres -c "SELECT pg_is_in_recovery()"`
- [ ] WAL archiving activo: `psql -U postgres -c "SHOW archive_mode"` (debe ser `on`)
- [ ] WAL archiving sin errores: `psql -U postgres -c "SELECT * FROM pg_stat_archiver"`

### 6.2 Checks técnicos — pgBackRest

- [ ] La stanza tiene status `ok` después del restore: `pgbackrest info --stanza=<stanza>`
- [ ] El WAL archiving llega correctamente a pgBackRest: verificar que `archive-status` avanza
- [ ] Netdata monitorea la stanza: verificar el dashboard de la stanza en Netdata Cloud
- [ ] El primer backup post-restore (incr) se ejecuta sin errores

### 6.3 Checks de aplicación

- [ ] La aplicación conecta a la base de datos sin errores de autenticación
- [ ] Las funciones críticas del sistema responden correctamente (login, consultas principales)
- [ ] No hay errores 500 ni timeouts de base de datos en los logs de la aplicación
- [ ] Si aplica: replicación o sincronización con otros servicios funcionando

### 6.4 Declaración de servicio restaurado

El servicio puede declararse restaurado solo cuando **todos** los checks de 6.1, 6.2 y 6.3 estén en verde. Registrar el timestamp de la declaración para el cálculo del RTO real del incidente.

---

## 7. Mantenimiento del plan

### 7.1 Cuándo revisar este documento

Este DRP debe revisarse en las siguientes circunstancias:

| Evento | Acción |
|---|---|
| Después de cada incidente de producción | Actualizar con lecciones aprendidas |
| Cambio en la infraestructura (nuevo servidor, cambio de proveedor, nueva stanza) | Actualizar la sección correspondiente |
| Trimestralmente (sin importar si hubo incidentes) | Revisión completa, actualizar fecha |
| Cambio de credenciales de R2 o cipher-pass | Actualizar sección 5, verificar vault |

### 7.2 Drill obligatorio

**Frecuencia mínima:** 1 drill **mensual** de las 3 stanzas productivas (AxiomaCloudProd, clubix, axiodemo), más un drill fuera de cadencia después de cualquier cambio de config de pgBackRest, versión de PostgreSQL o migración de repo. El drill es barato (~1 min/stanza), así que la cadencia mensual da confianza sin costo operativo real.

**Ejecución:** manual (no automatizada) mediante `scripts/70-restore-drill.sh`, corrido en un host **distinto de dev-1** (que aloja el repo) y con los prerequisitos de la sección 2 del Restore Drill Procedure. No se automatiza por cron porque el host ejecutor (KEYSOFT-UBUNTU) no está siempre encendido; el script es auto-evaluante (`exit 0/1`) y su registro es esta tabla.

**Referencia:** Seguir el Restore Drill Procedure (§7 Cadencia, §8 Registro). El drill restaura desde R2 con WAL replay completo y valida frescura del WAL (umbral 30 min), no solo la recuperabilidad del último backup.

**Duración esperada del drill:** ~1 minuto por stanza con el script automatizado (restore + WAL replay + verificación + limpieza).

### 7.3 Registro de drills e incidentes

| Fecha | Tipo | Stanza | Escenario | Repo usado | RTO real | Resultado | Responsable |
|---|---|---|---|---|---|---|---|
| 2026-07-04 | Drill | axiodemo | Restore + WAL replay desde R2 en host != repo | R2 | ~1 min | PASS (WAL lag 0 min, 34 tablas) | martin4yo |

> Completar esta tabla después de cada drill o incidente real. Incluir una fila por evento. Para incidentes reales, agregar también el post-mortem como documento separado referenciado desde aquí.

---

## Apéndice A — Bases de datos por stanza

> **Inventario tomado el 2026-07-04.** Las bases cambian con el tiempo; este apéndice es una
> referencia rápida para un incidente, no la fuente de verdad. Regenerarlo con el comando del
> final antes de confiar en él para un restore selectivo.
>
> Recordá: `pgbackrest restore --stanza=<X>` trae **el cluster completo con TODAS estas bases
> juntas**, no una sola. Para recuperar una base puntual: restaurar la stanza en un host aislado
> → `pg_dump <base>` de ahí → `pg_restore` en el destino. Ver §2 (escenarios) y el Restore Drill
> Procedure para los comandos.

### `AxiomaCloudProd` — servidor **axioma** (66.97.45.210, PG14) — 13 bases

| Base | Tamaño aprox. |
|---|---|
| clubix_db | 256 MB |
| mini_db | 112 MB |
| parse_db | 77 MB |
| mediflow_db | 18 MB |
| elore_db | 13 MB |
| hub_db | 12 MB |
| rendiciones_db | 12 MB |
| axiomadocs | 11 MB |
| chequescloud | 11 MB |
| checkpoint_db | 10 MB |
| evolution | 10 MB |
| iasqlassistant_db | 10 MB |
| core_db | 8.6 MB |

### `clubix` — servidor **clubix** (179.43.123.248:2222, PG14) — 1 base

| Base | Tamaño aprox. |
|---|---|
| clubix_db | 198 MB |

### `axiodemo` — servidor **axiodemo** (170.78.73.245, PG16) — 2 bases

| Base | Tamaño aprox. |
|---|---|
| axio_db | 8.9 MB |
| axio_ml | 11 MB |

### `dev-1` — servidor **dev-1** (149.50.148.198, PG14, repo host) — 16 bases

| Base | Tamaño aprox. |
|---|---|
| clubix_db | 171 MB |
| mini_db | 89 MB |
| rojoplus_db | 68 MB |
| parse_db | 28 MB |
| mediflow_db | 20 MB |
| axioma_erp | 17 MB |
| hub_db | 17 MB |
| elore_db | 14 MB |
| axioma_metadata | 13 MB |
| checkpoint_db | 13 MB |
| axiomaweb_db | 12 MB |
| tally_db | 12 MB |
| core_db | 10 MB |
| axiomadb | 9.8 MB |
| fitness_db | 9.6 MB |
| axio_db | 9.5 MB |

> **Ojo:** `clubix_db` existe en 3 stanzas (axioma, clubix, dev-1) con tamaños distintos — son
> instancias **diferentes**, no la misma base. En un restore de `clubix_db`, definir de qué stanza.

### Cómo regenerar este inventario

```bash
for h in axioma clubix axiodemo dev-1; do
  echo "===== $h ====="
  ssh axiomacloud@$h "sudo -u postgres psql -tAc \
    \"SELECT datname, pg_size_pretty(pg_database_size(datname)) \
      FROM pg_database WHERE datistemplate=false AND datname NOT IN ('postgres') \
      ORDER BY pg_database_size(datname) DESC;\""
done
```

---

*Documento generado el 2026-05-29. Revisión trimestral obligatoria. Apéndice A actualizado 2026-07-04.*
