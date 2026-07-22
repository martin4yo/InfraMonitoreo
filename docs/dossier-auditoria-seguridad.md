# Dossier de Auditoría de Seguridad y Continuidad — Infraestructura Axioma

> **Propósito.** Material estructurado para una **auditoría externa formal** de la postura de
> seguridad, monitoreo y recuperación ante desastres de la infraestructura Axioma (5 servers).
> Alineado a **CIS Controls v8**. Incluye un **registro de hallazgos** con severidad, estado y
> owner: exponer los pendientes es una señal de madurez del programa, no una debilidad.
>
> **Naturaleza del documento.** Todo lo aquí afirmado se deriva de evidencia versionada en el repo
> `InfraMonitoreo` (y su repo hermano `infra-secrets`). Cuando un control esperado por el auditor
> **no existe como documento o implementación**, se marca explícitamente como **gap**.
>
> **Fecha de compilación:** 2026-07-18 · **Última actualización de estado:** 2026-07-22
> **Responsable técnico:** mfourgeaux@axiomacloud.com
> **Fuentes primarias:** `docs/hardening.md`, `docs/disaster-recovery-plan.md`,
> `docs/drp-app-hub-drill.md`, `docs/restore-drill-procedure.md`, `docs/pgbackrest-setup.md`,
> `docs/setup-netdata-cloud.md`, `docs/estandar-despliegue.md`, `docs/plan-remediacion-hallazgos.md`,
> `docs/plan-estandarizacion-y-redespliegue.md`, `docs/plan-trabajo-estandarizacion.md`,
> `docs/nginx-anti-scanner.md`, `README.md`, `netdata/`, `scripts/`, `docs/drill-history.csv`.

---

## 1. Resumen ejecutivo

La infraestructura Axioma (5 VPS en múltiples proveedores) tiene una **postura de seguridad base
sólida y verificada** — los tres riesgos críticos de superficie de ataque (acceso SSH, firewall,
credenciales de backup expuestas) fueron cerrados en los 5 servers el 2026-07-17 — y una
**capacidad de recuperación de datos probada** mediante backups dual-repo cifrados off-site
(pgBackRest → dev-1 SSH + Cloudflare R2) con restore drills que validan recuperación con WAL replay
hasta minutos antes de un evento. En la pasada de remediación del 19–20 de julio se cerraron además
la exposición de credenciales R2 en respaldos (H03), la cadencia de restore drills con las **3 stanzas
productivas en PASS** (H07), parte del rebindeo de servicios a loopback (H04) y la remediación de
dependencias vulnerables de hub **desplegada a producción** (H13: 61 → 11 vulnerabilidades, críticas
3 → 0, sin rollback). La brecha principal
**no es técnica sino de gobierno**: no existen todavía documentos formales de política de seguridad,
gestión de riesgos, gestión de vulnerabilidades ni plan de respuesta a incidentes, y quedan hallazgos
técnicos de defensa en profundidad (pg_hba amplio en un server, apps Next.js aún en `0.0.0.0`,
propiedad de archivos en una app productiva).

> **Nota de transparencia para el auditor.** El hallazgo H06 (permisos de `.env`) fue declarado
> cerrado el 2026-07-18 y **reabierto el 2026-07-20**: la verificación original era insuficiente
> (se validó un solo server y contra el proceso ya en ejecución, en vez de contra el próximo
> arranque y en los 5 servers), y un cierre posterior derivado de ese criterio provocó un
> **incidente en producción**. El criterio de verificación fue corregido y la re-auditoría en los
> 5 servers detectó exposiciones que el cierre original no había visto (ver §7 y §7.1). Se deja
> registrado deliberadamente: la capacidad de detectar y revertir un falso verde es parte de la
> evidencia de control.

### Tabla de madurez por dominio

| Dominio | Semáforo | Fundamento |
|---|---|---|
| Seguridad / Hardening | 🟡 Amarillo | Críticos cerrados en los 5 (SSH sin root/pass, ufw default-deny, token R2 rotado) y respaldos con credenciales purgados (H03, 07-19). Pendientes de defensa en profundidad: pg_hba `0.0.0.0/0` en axioma (H01), 5 apps Next.js aún en `0.0.0.0` (H04, bloqueado por un patrón del framework), propiedad de archivos de mini/axioma (H06, requiere ventana). |
| Monitoreo | 🟢 Verde | Netdata Cloud v2.10.4 claimed en los 5; colectores PG/nginx/httpcheck/apps + alarmas custom; notificaciones Telegram+Email. La alarma de antigüedad de backup pgBackRest se verificó **desplegada y en CLEAR** desde 2026-05-26 (H08 cerrado 07-18). Rotación de logs PM2 desplegada en los 5 (07-20). |
| Backup | 🟢 Verde | Dual-repo pgBackRest 2.58.0: repo1 SSH dev-1 + repo2 R2 **cifrado** off-site; retención full=4/diff=7; cron full/diff/incr; `verify` disponible. |
| DRP (recuperación) | 🟡 Amarillo | DRP de DB formal (4 escenarios, RPO/RTO, checklist post-restore) + DRP de aplicación en definición (drill hub→axioma-drp). Drills de restore ejecutados y registrados, pero **cadencia mensual aún no sostenida** (últimas corridas 2026-07-04). |
| Gestión de secretos | 🟢 Verde | SOPS+age: 15 `.env` cifrados por-valor en repo privado `infra-secrets`; clave age fuera de banda; roundtrip verificado. Gap: creds R2 que lee pgBackRest siguen en texto plano en los `.conf` (SOPS es copia custodiada, no el origen). |
| Estandarización de despliegues | 🟡 Amarillo | Estándar oficial v1 + inventario cerrado + fases 0–3 completas. Fases invasivas (4+) en curso: hub estandarizada; resto de apps pendiente. |
| **Gobierno / Documentación formal** | 🔴 Rojo | No existen (aún) política de seguridad, matriz de roles, registro de riesgos, gestión de vulnerabilidades/parches ni plan formal de respuesta a incidentes. Ver §8. |

---

## 2. Alcance

### Cubre
- **5 servidores VPS**: axioma, clubix, axiodemo, dev-1, axioma-drp.
- **Controles de seguridad de host**: acceso SSH, firewall (ufw), fail2ban, `pg_hba`/autenticación PostgreSQL, TLS y cabeceras HTTP, permisos de archivos de configuración/secretos, protección anti-scanner nginx.
- **Backup y recuperación de bases de datos** PostgreSQL (pgBackRest dual-repo) y **recuperación de aplicaciones** (DRP de app en definición).
- **Monitoreo y alertas** (Netdata Cloud + colectores + alarmas custom).
- **Gestión de secretos** (SOPS + age).
- **Estandarización de despliegues** de aplicaciones propias.

### No cubre (fuera de alcance / no documentado)
- Seguridad de las **aplicaciones a nivel de código** (SAST/DAST, revisión de código, dependencias — solo se registra `npm audit` pendiente en hub).
- Seguridad física de los datacenters de los proveedores (Contabo, dattaweb, etc.).
- Gestión de identidades/usuarios de las **aplicaciones** (autenticación de usuarios finales).
- Continuidad de servicios que **no** son PostgreSQL ni apps Node (ej. Docker/CUPS en dev-1) más allá de su exposición de red.
- **Gobierno formal**: los documentos de política, riesgo, incidentes y vulnerabilidades **no existen todavía** (declarados como gaps en §8).

---

## 3. Inventario de activos

### 3.1 Servidores

| Server | IP | Puerto(s) SSH | OS | PostgreSQL | Rol principal | Apps / servicios |
|---|---|---|---|---|---|---|
| **axioma** | 66.97.45.210 | 22 + 5408 | (prod, PGDG) | **14** | DB producción principal + host multi-app | corporate (backend 3005), checkpoint (estático), elore (3700), evolution-api (8080, tercero), **hub** (5200/8089), mediflow (5300), mini (8095), parse (5100/8087) |
| **clubix** | 179.43.123.248 | **2222** | (prod) | **14** | DB producción + app | clubix (5400) |
| **axiodemo** | 170.78.73.245 | 22 | (prod) | **16** | DB demo + app | axio-backend (3001), axio-ml (8001, Python/uvicorn+ollama) |
| **dev-1** | 149.50.148.198 | 22 + 5782 | (multi-app) | **14** | **Repo host central pgBackRest** (repo1 + escritura a R2) + server multi-app | 15+ apps Node de 8 usuarios, nginx, Docker, CUPS, postfix relay |
| **axioma-drp** | 170.78.75.249 | 22 | Ubuntu 22.04.5 LTS | **14** (instalado, sin datos) | Banco de pruebas de DRP por aplicación (no productivo) | bare: SSH + Netdata + pgBackRest 2.58.0 (apunta a stanza AxiomaCloudProd en R2) |

> Node por server: axioma/clubix **v20.20.2**, axiodemo **v22.22.2**. pgBackRest **2.58.0** unificado en los 4 db/repo hosts.
> Nota de sensibilidad: **dev-1 es la caja más crítica** — comprometerla compromete los backups de toda la infra (aloja `/backup/pgbackrest`).

### 3.2 Aplicaciones y bases de datos

| App | Server | Owner | Puerto | Base de datos | Repo git | Estado estandarización |
|---|---|---|---|---|---|---|
| axioma-corporate | axioma | 🟡 backend root | 3005 + estático | axiomadocs | rodrigomnaranjo/axioma-corporate | sacar de root (F5) |
| checkpoint | axioma | 🟡 estático root | — | checkpoint_db | AxiomaCloud/checkpointsite | sacar de root (F5) |
| elore | axioma | eloreapp | 3700 | elore_db | ⚠ sin remote git | menor (F5); bloqueante F7 |
| evolution-api | axioma | evolutionapp | 8080 | evolution | EvolutionAPI/evolution-api (tercero) | setup separado (F6) |
| **hub** | axioma | hubapp | 5200 + 8089 | hub_db | AxiomaCloud/ProHub (SSH) | ✅ estandarizada (F4) |
| mediflow | axioma | mediflowapp | 5300 | mediflow_db | martin4yo/mediflow | casi estándar |
| mini | axioma | miniapp | 8095 | mini_db | martin4yo/AxiomaWeb | owner ✅; `.cjs`→`.js` pend. |
| parse | axioma | parseapp | 5100 + 8087 | parse_db | martin4yo/parse | estándar ✅ |
| clubix | clubix | clubixapp | 5400 | clubix_db | martin4yo/rojoplus | casi estándar |
| axio-backend | axiodemo | axioapp | 3001 | axiodemo (axio_db) | AxiomaCloud/axio.git | molde común (F6) |
| axio-ml | axiodemo | 🟡 axiomacloud | 8001 | — | parte de axio | hook ollama + owner (F6) |

> Dadas de baja en Fase 1 (2026-07-05): **AxiomaWeb** (sin DB) y **rendiciones** (+ DROP de `rendiciones_db`), con backup previo.

### 3.3 Inventario consolidado de bases por stanza pgBackRest (Apéndice A del DRP, 2026-07-04)

| Stanza | Server | PG | # bases | Bases principales (tamaño aprox.) |
|---|---|---|---|---|
| **AxiomaCloudProd** | axioma | 14 | 11 | mini_db (113M), parse_db (77M), mediflow_db (18M), elore_db (13M), **hub_db (12–15M)**, axiomadocs (11M), chequescloud (11M), iasqlassistant_db (10M), checkpoint_db (10M), evolution (10M), core_db (8.6M) |
| **clubix** | clubix | 14 | 1 | clubix_db (198M) — producción real |
| **axiodemo** | axiodemo | 16 | 2 | axio_db (8.9M), axio_ml (11M) |
| **dev-1** | dev-1 | 14 | 16 | clubix_db (171M, copia), mini_db (89M), rojoplus_db (68M), parse_db (28M), mediflow_db (20M), axioma_erp (17M), hub_db (17M), elore_db (14M), + 8 más |

> Advertencia de auditoría: `clubix_db` existe en 2 stanzas (clubix = producción real; dev-1 = copia) con tamaños distintos → en un restore selectivo hay que definir la stanza. El Apéndice A se regenera con el comando documentado antes de confiar en él para un restore.

---

## 4. Arquitectura

### 4.1 Monitoreo (Netdata Cloud, sin server central)

- **Netdata v2.10.4** instalado y **claimed a Netdata Cloud** en los **5 servers** (axioma-drp sumado 2026-07-17).
- **Sin servidor central que mantener**: cada agente sale **outbound por HTTPS/443** hacia Netdata Cloud. Un firewall default-deny inbound NO lo afecta (el `:19999` no se abre; reporta saliente).
- **Notificaciones centralizadas** en la nube (una sola vez, aplican a todos): **Telegram** (critical+warning) + **Email** (critical), a `martin4yo@gmail.com`.
- **Colectores** (en servers con apps): `go.d/postgres` (usuario read-only `netdata` con `pg_monitor`), `go.d/nginx` (stub_status), `go.d/httpcheck` (disponibilidad HTTP de endpoints), `apps.plugin` (pm2/Node/Python vía `apps_groups.conf` custom).
- **Alarmas custom versionadas** en `netdata/health.d/`: `apps_http.conf` (endpoint caído / lento), `pgbackrest.conf` (antigüedad de backup >25h/48h, backup fallido, WAL atrasado por stanza).
- Configs versionadas en `netdata/`; deploy vía `scripts/20-deploy-configs.sh`.

### 4.2 Backup (dual-repo pgBackRest)

```
                 repo central /backup/pgbackrest  (usuario OS: pgbackrest)
        backup pull ─────►  dev-1 (149.50.148.198)  ◄───── archive-push (WAL)
                                    │ SSH
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                            ▼
   axioma (PG14)              clubix (PG14, :2222)        axiodemo (PG16)
   stanza AxiomaCloudProd     stanza clubix               stanza axiodemo
   dev-1 respalda su propia DB vía SSH loopback → stanza dev-1
   + en cada operación escribe TAMBIÉN a repo2 → Cloudflare R2 (S3, off-site, CIFRADO)
```

- **repo1** — central en dev-1 (`/backup/pgbackrest`), transporte SSH, **sin cifrado en reposo** (tránsito cifrado por SSH).
- **repo2** — Cloudflare R2 (bucket `axiomacloud-pgbackrest`), **cifrado AES-256-CBC en reposo** (`repo2-bundle=y`). Elimina el single-point-of-failure de dev-1.
- **Retención:** full=4, diff=7 en ambos repos.
- **Cron (dev-1):** full domingos, diff lun-sáb, incr cada 4h, check semanal; stanzas escalonadas de a 15 min.
- **RPO efectivo:** 4 horas (frecuencia del incr). El drill valida WAL replay hasta <30 min antes del evento.
- **Confianza SSH bidireccional por stanza** (archive-push + backup pull); las 4 IPs internas en `ignoreip` de fail2ban.

---

## 5. Dominios de control mapeados a CIS Controls v8

> Estado: ✅ implementado y verificado · 🟡 parcial / con pendientes · 🔴 gap · ⬜ no aplica

| CIS v8 | Control | Qué implementa la infra | Evidencia (archivo/config) | Estado |
|---|---|---|---|---|
| **1** — Inventario de activos | Inventario de hardware/servidores y su rol | Inventario cerrado de 5 servers + apps + bases por stanza | `plan-estandarizacion-y-redespliegue.md` §2; DRP Apéndice A; `disaster-recovery-plan.md` §1.1 | ✅ |
| **2** — Inventario de software | Software autorizado, apps por server, runtime fijado | Inventario de apps + versión Node por app en manifiesto; PG/pgBackRest unificados | `estandar-despliegue.md` §10; plan §2 | 🟡 (manifiestos por app aún no completos, F7) |
| **3** — Protección de datos | Backups cifrados off-site; secretos cifrados; TLS | pgBackRest repo2 R2 cifrado AES-256; SOPS+age para `.env`; TLS Let's Encrypt en apps públicas | `pgbackrest-setup.md`; plan §3 (SOPS); `estandar-despliegue.md` §6,§8 | 🟡 (creds R2 en claro en los `.conf` vivos, protegidos por `640`+owner+fw; los `.bak` con credenciales pre-rotación fueron purgados — H03 cerrado 07-19) |
| **4** — Configuración segura | Hardening de host: SSH, firewall, servicios en loopback, permisos | SSH sin root/pass (5/5); ufw default-deny (5/5); `.env` 600; PG en loopback (mayoría); anti-scanner nginx; **regla de propiedad de archivos** (`/var/www/<app>` todo `<app>app:<app>app`, verificable con `find -not -user`) formalizada en el estándar | `hardening.md` (comparativa 5 servers); `nginx-anti-scanner.md`; `estandar-despliegue.md` §3 (owner de archivos) | 🟡 (pg_hba axioma — H01; 5 apps Next.js en `0.0.0.0` — H04 parcial; propiedad de archivos de mini/axioma — H06 parcial) |
| **5** — Gestión de cuentas | Cuentas de servicio dedicadas, sin cuentas ajenas activas; mínimo privilegio en DB | Usuario dedicado `<app>app` por app (no root); `linuxadmin` ajeno bloqueado en drp (`passwd -l`); **regla de propiedad en DB** (`<app>user` owner de la base y de todas las tablas/secuencias/tipos, no solo GRANT) formalizada en el estándar | `estandar-despliegue.md` §2, §9 (owner de DB); `hardening.md` (drp) | 🟡 (axio-ml corre como `axiomacloud`; falta matriz formal de cuentas) |
| **6** — Gestión de accesos | Acceso remoto solo por llave; MFA/CA; restricción por IP | SSH solo `axiomacloud` por pubkey (5/5); CA Smallstep en dev-1 (`80-step.conf`); pg_hba de axiodemo restringido a IP de dev-1 | `hardening.md` §3 + comparativa; `pgbackrest-setup.md` (confianza SSH) | ✅ (host); 🟡 (accesos de app fuera de alcance) |
| **8** — Gestión de logs de auditoría | Logs de acceso, detección de brute-force, retención | fail2ban en los 5 (backend=systemd/journald donde aplica); access.log nginx; anti-scanner filtra ruido; journald | `hardening.md` (fail2ban drp/dev-1); `nginx-anti-scanner.md` | 🟡 (sin agregación central de logs ni política de retención documentada) |
| **11** — Recuperación de datos | Backups probados, restore drills, DRP documentado | DRP de DB (4 escenarios, RPO/RTO); restore drill con WAL replay auto-evaluante + registro CSV; `pgbackrest verify` | `disaster-recovery-plan.md`; `restore-drill-procedure.md`; `drill-history.csv` | 🟢 (las **3 stanzas productivas en PASS** el 2026-07-19 — 1ª corrida registrada de AxiomaCloudProd y clubix; H07 cerrado. Pendiente: sostener la cadencia mensual en el tiempo) |
| **12** — Gestión de infra de red | Firewall, segmentación de puertos, servicios expuestos mínimos | ufw default-deny allowlist SSH/80/443 (5/5); snmpd acotado a IPs dattaweb en dev-1; puertos de monitoreo salientes | `hardening.md` §2 + comparativa + Pendientes dev-1 | 🟡 (rebindeo parcial 07-20: parse-front axioma → loopback, CUPS dev-1 deshabilitado, netdata → loopback en los 3. Quedan 5 apps Next.js en `0.0.0.0`, mitigadas por fw — H04) |
| **13** — Monitoreo y defensa de red | Monitoreo de recursos/servicios/disponibilidad + alertas | Netdata Cloud multicapa (5/5); alarmas custom apps_http + pgbackrest; notificación Telegram/Email | `README.md`; `setup-netdata-cloud.md`; `netdata/health.d/*` | 🟢 (alarma de antigüedad de backup verificada **desplegada y en CLEAR** desde 2026-05-26 — H08 cerrado) |
| **7** — Gestión de vulnerabilidades | Escaneo y remediación de vulnerabilidades | Remediación de hub **desplegada y verificada en producción** (2026-07-20): **61 → 11 vulnerabilidades, críticas 3 → 0**, sin `--force`, con 57/57 tests en PASS; health/login/mail/parseo-PDF OK, sin rollback. Sigue sin proceso periódico formal (escaneo calendarizado, umbrales, SLA de parcheo) | `plan-remediacion-hallazgos.md` (H13); `plan-trabajo-estandarizacion.md` | 🟡 remediación puntual de hub cerrada; el **proceso** periódico sigue como gap (ver G4) |
| **17** — Respuesta a incidentes | Plan formal, roles, comunicación | Flujo de comunicación por escenario en el DRP; sin plan de respuesta a incidentes formal e independiente | `disaster-recovery-plan.md` §3 (parcial) | 🔴 gap (ver §8) |

---

## 6. RPO/RTO y capacidad de recuperación

### 6.1 Objetivos (DRP de DB)

| Tier | Servicio | RPO | RTO |
|---|---|---|---|
| Crítico | AxiomaCloudProd, clubix | 4 h | 30 min |
| No crítico | axiodemo | 4 h | 60 min |
| Infraestructura | dev-1 (repo host) | 4 h | 45 min |

- **RPO efectivo:** 4 h (frecuencia del incr). **RTO referencia:** 15–30 min bases chicas (repo1 red local); 30–60 min desde R2 (egress WAN).

### 6.2 Escenarios de DRP de base de datos (`disaster-recovery-plan.md`)

| Escenario | Descripción | Fuente de restore | RTO |
|---|---|---|---|
| A | Corrupción de datos en un db host | repo1 (o repo2 si dev-1 caído) | 15–30 min |
| B | Pérdida total de un db host | repo1 → repo2 fallback | 30–45 min |
| C | Pérdida de dev-1 (repo host) | repo2 (R2) | 45–60 min |
| D | Pérdida simultánea dev-1 + db host (peor caso) | repo2 (R2) | 60–90 min |

### 6.3 DRP de aplicación (recuperación de app completa, en definición)

- Piloto en curso: **restaurar hub en axioma-drp** (código + build + PM2/systemd + vhost nginx + `hub_db` desde backup) como ensayo de disaster recovery de aplicación. Runbook mapeado a los 9 pasos del `lib-redeploy`.
- **Matriz de 4 escenarios de recuperación** formalizada, de menor a mayor alcance: (1) solo la base — restore quirúrgico sin tocar el binario; (2) solo la app — redeploy con base sana; (3) app entera = app + base (composición de 1 y 2, **este drill**); (4) servidor entero (repite el escenario 3 por app + un restore único del cluster). Los escenarios 1 y 2 tienen **runbooks propios** (secciones E y F del drill), reutilizables por cualquier app.
- Estado del drill: **relevamiento in-situ completo** (destino axioma-drp mapeado — PG14 + pgBackRest ya ven la stanza `AxiomaCloudProd` en R2; faltan Node/PM2/nginx y el usuario `hubapp`) + **plan de 9 pasos con red de seguridad y decisiones abiertas** (G3: restore a PGDATA aislado→pg_dump vs. sobre el PG principal; G4: `/etc/hosts`+cert self-signed para no reemitir el cert LE de producción; G8: crear el rol `hubuser` en drp, que el `pg_dump` no trae). **Aún NO ejecutado** — todos los pasos invasivos siguen `[ ]`, pendiente de OK del usuario y de acordar las decisiones G3/G4.
- Evidencia y estado: `docs/drp-app-hub-drill.md` (estado global `[~] relevamiento hecho — pendiente OK para ejecutar`; el drill aún no aparece en `drill-history.csv`).

### 6.4 Evidencia de drills ejecutados

| Fecha | Stanza | Repo | Restore | WAL lag | Resultado |
|---|---|---|---|---|---|
| 2026-05-29 | axiodemo | repo2 | 14s | 1 min | PASS |
| 2026-07-04 | axiodemo | R2 (repo1 local) | 15s | 0 min | PASS |
| 2026-07-04 (x2) | axiodemo | R2 | 13–15s | 0 min | PASS |
| 2026-07-19 12:26 / 12:51 | AxiomaCloudProd, clubix | R2 | 49–79s | — | **FAIL** (bug del drill — ver nota) |
| 2026-07-19 20:08 | **AxiomaCloudProd** | R2 | 71s | 0 min | **PASS** (1ª corrida registrada) |
| 2026-07-19 20:08 | **clubix** | R2 | 44s | 1 min | **PASS** (1ª corrida registrada) |
| 2026-07-19 20:08 | axiodemo | R2 | 11s | 1 min | PASS |

- El drill valida end-to-end: descarga R2 → descifrado AES → descompresión → **WAL replay completo** → promoción, con umbral de frescura de WAL de 30 min. Auto-evaluante (`exit 0/1`), registro automático en `drill-history.csv`.
- **Sobre los FAIL del 2026-07-19 (transparencia).** Las 4 corridas en FAIL de las 12:26 y 12:51 quedan deliberadamente en el registro. La causa fue diagnosticada como un **defecto del script de drill, no de los backups**: el `pg_hba` del entorno de restore se copiaba del cluster local (con `scram`), provocando rechazo por autenticación, y la comprobación de conectividad no esperaba al WAL replay. Corregido `scripts/70-restore-drill.sh` y re-ejecutado a las 20:08 con las **3 stanzas en PASS**. Los backups nunca estuvieron comprometidos; lo que falló fue el instrumento de verificación.
- **Estado de H07 (cerrado 2026-07-19):** AxiomaCloudProd y clubix tienen ahora su **primera corrida registrada en PASS** (585 y 178 tablas restauradas, WAL al día), junto a axiodemo (34 tablas). Queda como compromiso vivo **sostener la cadencia mensual** — un solo ciclo cumplido no constituye todavía evidencia de cadencia.

---

## 7. Registro de hallazgos y remediación

> Severidad: 🔴 alta · 🟡 media · 🟢 baja. Estado: pendiente / en curso / ⚠ reabierto / ✅ corregido (fecha).
> **Estado consolidado al 2026-07-20:** 9 cerrados · 2 parciales (H04, H06) · 1 bloqueado por tercero (H09) · 2 pendientes (H01, H11).
> Owner por defecto: mfourgeaux@axiomacloud.com (responsable técnico único actual — ver gap G2 en §8).

| # | Hallazgo | Server(s) | Dominio CIS | Sev | Estado | Owner |
|---|---|---|---|---|---|---|
| H01 | `pg_hba.conf`: `host all all 0.0.0.0/0 md5` (cualquier IP puede intentar conectar; md5 en vez de scram) | axioma | CIS 3, 4, 6 | 🔴→🟡 | **pendiente** (mitigado en la práctica: PG bindea a `127.0.0.1` + ufw bloquea 5432; falta corregir a nivel config y migrar a scram-sha-256) | martin4yo |
| H02 | Firewall ausente (ufw inactive) | axioma, clubix, dev-1, axioma-drp | CIS 4, 12 | 🔴 | ✅ **corregido 2026-07-17** (ufw default-deny + allowlist en los 5; axiodemo ya lo tenía) | martin4yo |
| H03 | Credenciales R2 (`s3-key-secret`, `cipher-pass`) en texto plano en `pgbackrest.conf` + expuestas en sesión | dev-1, axioma, clubix, axiodemo (+drp) | CIS 3 | 🟡 | ✅ **cerrado 2026-07-19** — token rotado 07-17 (viejo borrado en Cloudflare, nuevo en 5 archivos, verificado con `pgbackrest check`; custodia SOPS). El relevamiento del 07-19 mostró que los `.conf` vivos ya estaban en `640`+owner correcto y que la superficie real eran **4 `.bak` con credenciales pre-rotación**: respaldados en un tar `600` root-only y **borrados los 4** (+2 residuos). Resultado: 0 `.bak` en los 5 servers, `check` OK en las 4 stanzas, ningún `.conf` vivo tocado. **Residual aceptado:** las credenciales siguen en claro en los `.conf` que pgBackRest debe leer (limitación del producto), mitigado por `640` + owner + firewall | martin4yo |
| H04 | Puertos de app escuchando en `0.0.0.0` en vez de `127.0.0.1` (salteando nginx/TLS/headers) | axioma (`:8087` parse-front), dev-1 (`:3000/5000/8086/8087/8089`, CUPS `:631`, netdata `:19999`), axiodemo (`:5300`) | CIS 4, 12 | 🟡 | **parcial 2026-07-20** — el relevamiento confirmó que **todos los `proxy_pass` ya apuntan a loopback** (el riesgo principal no existía). Rebindeados en verde: `:8087` parse-front (axioma), **CUPS `:631` deshabilitado** en dev-1 (nadie imprime), netdata `:19999` → `bind to = 127.0.0.1` en los 3 (ACLK intacto). **Bloqueadas 5 apps Next.js:** el flag `-H` bindea pero hace que Next redirija el login a `https://localhost:<port>` → revertido de inmediato en producción; `HOSTNAME` es inerte fuera de standalone. Sigue **mitigado por ufw**, que tapa esos puertos desde afuera | martin4yo |
| H05 | SSH con `PermitRootLogin yes` + `PasswordAuthentication yes` (root por fuerza bruta) | axioma, clubix, dev-1 (custom.conf); axiodemo (50-cloud-init) | CIS 4, 6 | 🔴 | ✅ **corregido 2026-07-17** (root+pass `no`, solo pubkey, en los 5; drop-in `00-hardening`) | martin4yo |
| H06 | `.env` con permisos laxos (777/664/644/755) en vez de 600 | axioma, dev-1, axiodemo | CIS 3, 4 | 🟡 | ⚠ **REABIERTO 2026-07-20** — el cierre del 07-18 fue un **falso verde** (ver §7.1). Re-auditado en los 5 servers. **Cerrado desde entonces:** `axio/.env` en dev-1 (7 archivos en `664` world-readable → `600 axioapp:axioapp`; los leían los 8 usuarios de apps del server — control negativo `hubapp` NO_LEE); **mini/dev-1 migrada a `miniapp`** con ~90 directorios en `777` → `750`/`755`, `find -not -user miniapp` vacío, health 200; mini/axioma backend `.env` → `600 miniapp:miniapp`. **Pendiente:** el `chown -R` del árbol de mini en axioma **requiere ventana** (server productivo) | mfourgeaux |
| H07 | Cadencia mensual de restore drills no sostenida; solo stanza axiodemo con corridas registradas (AxiomaCloudProd/clubix sin drill registrado) | infra (backup) | CIS 11 | 🟡 | ✅ **cerrado 2026-07-19** — las **3 stanzas productivas en PASS** (585/178/34 tablas, WAL al día); 1ª corrida registrada de AxiomaCloudProd y clubix. Los FAIL previos del mismo día se diagnosticaron como **bug del drill, no de los backups** (`pg_hba` con `scram` copiado del cluster local + chequeo que no esperaba el replay); `70-restore-drill.sh` corregido. **Compromiso vivo:** sostener la cadencia mensual | martin4yo |
| H08 | Alarma de antigüedad de backup pgBackRest (colector statsd custom) documentada pero **no desplegada** | dev-1 (repo host) | CIS 11, 13 | 🟡 | ✅ **cerrado 2026-07-18** — el hallazgo era **incorrecto**: el monitoreo ya estaba desplegado en dev-1 desde el **2026-05-26** (colector `pgbackrest-collect.py` + cron 15 min + `health.d` + `statsd.d`), con charts poblados y alarmas en CLEAR. Solo se reconcilió el colector del repo con la versión multi-repo del server (md5 idéntica); **sin tocar dev-1** | martin4yo |
| H09 | snmpd con community `public` y `agentaddress` público en dev-1 | dev-1 | CIS 4, 12 | 🟡 | ⏸ **bloqueado por dependencia de tercero (2026-07-19)** — el relevamiento confirmó que la community `public` ya está acotada por `com2sec` a 2 IPs de dattaweb, y `tcpdump` probó que **el proveedor consulta cada ~1s y snmpd responde**: bindear a loopback o cambiar la community **cortaría el monitoreo contratado**. Requiere coordinar la nueva community con dattaweb. Mitigado por ufw (161 solo desde esas IPs) | martin4yo |
| H10 | Usuario ajeno de provisioning `linuxadmin` (password+sudo+llave de terceros) | axioma-drp | CIS 5, 6 | 🟡 | ✅ **mitigado 2026-07-17** (`passwd -l` bloquea password/brute-force; usuario+sudo conservados para emergencia, solo entra por llave) | martin4yo |
| H11 | `axio-ml` corre como `axiomacloud` (owner ≠ app), no usuario dedicado | axiodemo | CIS 5 | 🟢 | **pendiente** (normalizar a usuario dedicado + hook ollama, Fase 6) | martin4yo |
| H12 | Deploy de `axio` en axiodemo con `origin` mal apuntado (a ProHub, repo de hub) → un `deploy.sh` con credencial arreglada traería hub y rompería axio en prod | axiodemo | CIS 2 (integridad de deploy) | 🟡 | ✅ **corregido 2026-07-18** (`origin` re-apuntado a `github-axio:AxiomaCloud/axio.git` vía deploy key SSH; `fetch` verifica que trae axio, no hub; working tree intacto). Reconciliar los 3 cambios locales + `pull` queda para Fase 6 | mfourgeaux |
| H13 | Vulnerabilidades de dependencias sin escanear/remediar (`npm audit` hub: 47 backend / 18 frontend) — sin proceso de gestión de vulnerabilidades | apps (axioma) | CIS 7 | 🟡 | ✅ **desplegado y verificado 2026-07-20** — **61 → 11 vulnerabilidades, críticas 3 → 0**, sin `--force` (todo dentro de semver; `axios 1.13.2→1.18.1` cerró 23 advisories). El `audit fix` rompió el build (tipado de axios), corregido en 2 líneas, con **57/57 tests en PASS**. Desplegado a `/var/www/hub` como `hubapp` (commit `67a9d83`), **sin rollback**: `hub.axiomacloud.com` **200**, `api.hub.axiomacloud.com/health` **200**, login OK, `npm audit` en prod **0 críticas**, `find -not -user hubapp` vacío. Validado en vivo: **mail real (SMTP+sendMail OK)** y **parseo de PDF con mitigación de `pdfjs`** (`disableEval`), que cierra la única cadena de explotación real (facturas del portal de proveedores). Hallazgos colaterales: AWS SDK declarado pero **nunca importado** (peso muerto + creds AWS a revocar); `backend/.env` malformado (comentario pegado al `JWT_SECRET`). El **proceso periódico sigue ausente** — ver gap G4 | martin4yo |
| H14 | `stub_status` de nginx no devolvió métricas al probar (colector `go.d/nginx` podría no recibir datos) | los 3 con nginx | CIS 13 | 🟢 | ✅ **verificado 2026-07-18** (falsa alarma: el colector apunta a `:8088`, no `:80`; el bloque stub_status existe en los 3 y el chart `nginx_local.connections` tiene datos vivos). Sin intervención en servers | mfourgeaux |

### 7.1 Reapertura de H06 y corrección del criterio de verificación

> Se documenta en detalle porque afecta la **confiabilidad de los cierres declarados** en este
> registro, y porque la corrección del método es un control en sí mismo.

**Qué pasó.** H06 se declaró cerrado el 2026-07-18. La verificación tenía dos defectos:

1. **Cobertura parcial** — se validó en un solo server (dev-1) y se extrapoló al resto.
2. **Criterio equivocado** — se comprobó que el **proceso ya en ejecución** seguía funcionando
   después del `chmod`. Pero un proceso vivo ya tiene el `.env` leído en memoria: el permiso
   restrictivo no lo afecta. Lo que un `chmod`/`chown` mal aplicado rompe es el **próximo
   arranque**, que en ese momento no se probó.

**Consecuencia.** Un cierre posterior derivado del mismo criterio provocó un **incidente en
producción** (2026-07-20), con una caída de aproximadamente 1 minuto en la app afectada, resuelta
por rollback inmediato.

**Correcciones aplicadas al método** — hoy vigentes para todo cierre de hallazgo:

- Verificar contra el **usuario configurado para el próximo arranque** (ecosystem/unit), no contra
  el proceso vivo; y confirmar reinicio efectivo (`restart_time` estable).
- Ejecutar la comprobación en los **5 servers**, sin extrapolar.
- Usar **control negativo**: probar explícitamente que un usuario ajeno **no puede** leer el
  secreto (p. ej. `hubapp` → NO_LEE), en vez de solo confirmar que el dueño sí puede.
- Para cambios sobre HTTP, ampliar el criterio al **`Location` de las respuestas 3xx**: un
  `curl → 200` no detecta que un redirect apunte a un host equivocado (así se detectó el fallo de
  H04 en las apps Next.js).
- Relevar **antes** de actuar: el relevamiento previo evitó una segunda caída al detectar
  `/var/log/mini`, fuera de `/var/www`, sin el cual PM2 no arranca.

**Hallazgos que la re-auditoría encontró y el cierre original no había visto:** 7 archivos `.env`
en `664` world-readable en dev-1 (legibles por los 8 usuarios de apps del server), ~90 directorios
en `777` en mini, y 2 configuraciones de owner divergentes en axioma. Todos cerrados salvo el
`chown -R` de mini/axioma, que requiere ventana.

**Efecto sobre este dossier.** Los cierres marcados ✅ con fecha **2026-07-19 o posterior** fueron
verificados con el criterio corregido. Los anteriores se re-verificaron o se anotaron
explícitamente cuando no fue posible.

---

## 8. Gaps de gobierno (documentos que un auditor pediría y HOY no existen)

> Estos NO son fallas técnicas: son **artefactos de gobierno ausentes**. Se listan honestamente
> como brechas a cubrir. Su ausencia es la razón del semáforo 🔴 del dominio Gobierno (§1).

- [ ] **G1 — Política de seguridad formal.** No existe un documento de política (uso aceptable, clasificación de datos, requisitos de acceso, cifrado, retención). Hoy las prácticas están dispersas en docs técnicos (`hardening.md`, `estandar-despliegue.md`) pero no consolidadas en una política aprobada.
- [ ] **G2 — Matriz de roles y responsabilidades (RACI).** Responsable técnico único (`mfourgeaux@axiomacloud.com`) para todos los dominios y todos los hallazgos → **riesgo de bus factor = 1** y sin segregación de funciones. No hay backup de responsable ni escalamiento definido.
- [ ] **G3 — Gestión de riesgos.** No existe un registro de riesgos formal (identificación, probabilidad/impacto, tratamiento, aceptación). El DRP cubre escenarios de desastre pero no un análisis de riesgos del negocio.
- [ ] **G4 — Gestión de vulnerabilidades y parches (CIS 7).** No hay proceso de escaneo periódico de vulnerabilidades ni política de parcheo (SO, PostgreSQL, Node, dependencias npm). La remediación puntual de hub se ejecutó, validó y **desplegó a producción** el 2026-07-20 (61 → 11 vulnerabilidades, críticas 3 → 0, 57/57 tests en PASS, sin rollback), pero fue una acción reactiva y única: no hay escaneo calendarizado, umbrales de severidad para actuar, ni SLA de parcheo (H13).
- [ ] **G5 — Plan de respuesta a incidentes formal (CIS 17).** El DRP incluye flujos de comunicación por escenario, pero no existe un IR plan independiente (detección, clasificación de severidad, contención, erradicación, recuperación, lecciones aprendidas, contactos, plantillas de post-mortem).
- [ ] **G6 — Evidencia de revisión periódica.** El DRP declara "revisión trimestral obligatoria" (próxima 2026-08-29) pero no hay registro de revisiones ejecutadas. No hay cadencia documentada de auditoría de accesos ni de verificación mensual de acceso SSH de emergencia (el DRP §5.3 la pide, sin evidencia de ejecución). **Avance parcial:** la cadencia de restore drills tiene ahora su primer ciclo completo con las 3 stanzas en PASS (2026-07-19), pero un ciclo no constituye cadencia sostenida.
- [ ] **G10 — Criterio formal de verificación de remediaciones.** La reapertura de H06 (§7.1) mostró que no existía un estándar escrito de qué evidencia hace válido el cierre de un hallazgo. El criterio corregido (próximo arranque, cobertura total, control negativo, `Location` en 3xx) **está aplicado en la práctica pero aún no formalizado** como procedimiento aprobado con checklist de cierre.
- [ ] **G7 — Gestión formal de secretos y rotación.** SOPS+age está implementado, pero no hay **política de rotación** de credenciales (el token R2 se rotó reactivamente por exposición, no por calendario) ni inventario formal de secretos con owner y frecuencia de rotación.
- [ ] **G8 — Clasificación de datos y cumplimiento.** No hay clasificación de las bases (qué contiene datos personales/sensibles) ni evaluación de cumplimiento regulatorio aplicable.
- [ ] **G9 — Continuidad de negocio (BCP) más allá del DRP técnico.** El DRP cubre recuperación técnica de DB/apps; no hay un BCP que cubra continuidad operativa, dependencias de terceros (Cloudflare R2, Netdata Cloud, proveedores VPS) ni acuerdos de nivel de servicio.

---

## Registro de compilación

| Fecha | Acción | Resultado |
|---|---|---|
| 2026-07-18 | Compilación del dossier a partir de las fuentes del repo (solo lectura, sin tocar servers) | ✅ 14 hallazgos consolidados + 9 gaps de gobierno + mapeo CIS v8 de 11 controles |
| 2026-07-18 | Revisión de deltas post-compilación (solo lectura de repo, sin tocar servers) | Sin cambios de estado en H01-H14 (el único commit posterior fue de memorias; los diffs de docs formalizan reglas, no aplican fixes a servers). Precisiones aplicadas: CIS 4/5 reflejan las **2 reglas de propiedad formalizadas en el estándar** (archivos `/var/www/<app>` todo `<app>app`; DB con `<app>user` owner de todos los objetos, no solo GRANT — aprendizaje del drill de hub); §6.3 enriquecida con la matriz de 4 escenarios + runbooks E/F + decisiones abiertas G3/G4/G8 del drill de app. **Drill DRP de app confirmado NO ejecutado** (sigue en relevamiento/pendiente de OK; no figura en `drill-history.csv`). §6.4 verificada exacta (fila 2026-05-29 viene de `restore-drill-procedure.md`; las 2 de 2026-07-04 del CSV auto-registrado). |
| 2026-07-20 | **Actualización de estado al 2026-07-20** tras la pasada de remediación del 19–20 de julio (solo lectura de repo; fuente: `plan-remediacion-hallazgos.md` §registro de ejecución + `drill-history.csv` + log de commits) | Cambios de estado: **H03, H07, H08 → ✅ cerrados**; **H04 → parcial** (5 ítems en verde, 5 apps Next.js bloqueadas por el patrón `-H`/redirects); **H06 → ⚠ reabierto** (falso verde del 07-18 + incidente en prod) con 3 sub-ítems cerrados y el `chown -R` de mini/axioma pendiente de ventana; **H09 → ⏸ bloqueado** por dependencia de dattaweb; **H13 → ⏸ remediado sin desplegar**. Secciones tocadas: §1 (resumen + nota de transparencia + tabla de madurez), §5 (CIS 3, 4, 7, 11, 12, 13), §6.4 (6 corridas nuevas, incluidos los 4 FAIL diagnosticados), §7 (tabla de hallazgos + estado consolidado), **§7.1 nueva** (reapertura de H06 y criterio de verificación corregido), §8 (G4 actualizado, **G10 nuevo**). Sin intervención sobre servers. |
| 2026-07-22 | **Cierre de H13**: el despliegue de la remediación de hub a producción (commit `67a9d83`, 2026-07-20) se sincronizó al dossier (había quedado como "remediado sin desplegar"). | **H13 → ✅ desplegado y verificado** (health/login/mail/parseo-PDF OK, 0 críticas en prod, sin rollback). Estado consolidado: **9 cerrados · 2 parciales · 1 bloqueado · 2 pendientes (H01, H11)**. Secciones tocadas: §5 (CIS 7 → 🟡), §7 (consolidado + fila H13), §8 (G4). El **proceso** periódico sigue como gap G4. Sin intervención sobre servers. |
