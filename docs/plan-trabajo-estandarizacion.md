# Plan de Trabajo — Estandarización + Redespliegue (tracker de ejecución)

> **Tracker accionable** del plan definido en [`plan-estandarizacion-y-redespliegue.md`](./plan-estandarizacion-y-redespliegue.md).
> Aquí se tilda tarea por tarea a medida que se ejecuta. Regla transversal:
> **una app a la vez, con backup y rollback, cada fase aprobada antes de ejecutar.**
>
> Convención de estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho · `[!]` bloqueado
> Fecha de arranque: 2026-07-04.

## Leyenda de progreso por fase

| Fase | Descripción | Riesgo | Estado |
|---|---|---|---|
| 0 | Cerrar inventario | Nulo (solo lectura) | [x] hecho (2026-07-04) |
| 1 | Bajas (AxiomaWeb, rendiciones) | Bajo | [x] hecho (2026-07-05) |
| 2 | Documento del estándar | Nulo | [x] hecho (2026-07-05) |
| 3 | Secretos SOPS+age | Nulo (no toca servers) | [x] hecho (2026-07-05) |
| 4 | Migración piloto (mini) | Medio | [ ] |
| 5 | Migración del resto | Medio | [ ] |
| 6 | Hooks especiales + tercero | Medio | [ ] |
| 7 | Construir redespliegue | Bajo (solo scripts) | [ ] |
| 8 | PoC end-to-end | Bajo (server de prueba) | [ ] |

---

## Fase 0 — Cerrar inventario (solo lectura, cero riesgo)

**Objetivo:** completar la tabla del §2 del plan sin ningún `?` ni "(por confirmar)".

Por cada app confirmar: **repo git exacto + método de auth**, **base de datos**, **puerto**,
**dominio**, **versión de Node**, **dependencias externas** (redis, ollama/modelos, venv, etc.).

### Apps relevadas (in-situ, solo lectura, 2026-07-04)

- [x] **axioma-corporate** — estático (vhost `default`) + backend node **3005** (`prd.axiomacloud.com`); DB `axiomadocs`; Node 20
- [x] **checkpoint** — **NO es app root**: sitio **estático** (nginx `root`/`try_files`); DB `checkpoint_db` (verificar uso); sin node
- [x] **elore** — Next.js, puerto 3700, DB `elore_db`, `elore.com.ar`, ecosystem `.js`; **⚠ sin remote git** (código local)
- [x] **evolution-api** — tercero, puerto 8080, DB `evolution`, tsx/TS, `evolution.axiomacloud.com`, Node 20
- [x] **hub** — back 5200 + front 8089, DB `hub_db`, ecosystem `.js`; **⚠ sin remote git** (código local)
- [x] **mediflow** — puerto 5300, DB `mediflow_db`, repo `martin4yo/mediflow` (SSH), sirve **alvera.axiomacloud.com / alvera.com.ar**, Node 20
- [x] **mini** — puerto 8095, DB `mini_db`, repo `martin4yo/AxiomaWeb` (SSH), **⚠ ya corre como `miniapp`**, ecosystem `.cjs`, Node 20
- [x] **parse** — back 5100 + front 8087, DB `parse_db`, repo `martin4yo/parse` (SSH), `parse.axiomacloud.com`, Node 20
- [x] **clubix** — puerto 5400, DB `clubix_db`, repo `martin4yo/rojoplus`, ecosystem `.js`, clubix.com.ar + sportivopilar.com.ar, Node 20
- [x] **axio-backend** — puerto 3001, DB `axiodemo`, repo `AxiomaCloud/ProHub`, `axiodemo.axiomacloud.com`, **Node 22**
- [x] **axio-ml** — puerto 8001, `/opt/axio-ml-service` (uvicorn+ollama, 8 modelos ~31 GB), **⚠ corre como `axiomacloud`** (owner a normalizar)

### Cierre de Fase 0

- [x] Volcar todos los datos confirmados en la tabla del §2 de `plan-estandarizacion-y-redespliegue.md`
- [x] Marcar §2 sin huecos (`?` / "por confirmar" = 0)
- [x] Registrar versión de Node objetivo por app (axioma/clubix v20, axiodemo v22)
- [x] **Entregable:** tabla del §2 completa ✅

### Hallazgos que ajustan fases siguientes

- [ ] **Fase 4 (mini):** owner ya es `miniapp` → la migración de owner **ya está hecha**; queda solo `.cjs`→`.js` y decidir el repo
- [ ] **Fase 5 (checkpoint/corporate):** ambos son estáticos (+ backend 3005 en corporate) → "sacar de root" es trivial, no requiere migrar app node completa
- [ ] **Fase 6/7 (elore, hub):** **crean/confirman repo remoto** antes de poder redesplegar (hoy sin remote) — bloqueante para Fase 7
- [ ] **Fase 1 (rendiciones):** tiene DB `rendiciones_db` → respaldar esa base antes de la baja, no solo el código
- [ ] **Fase 6 (axio-ml):** normalizar owner `axiomacloud` → usuario dedicado, además del hook ollama

---

## Fase 1 — Bajas (decomisionar lo muerto)

**Procedimiento probado con clubix:** verificar desuso → backup código (git) + DB si tuviera →
parar PM2/servicio → quitar vhost → borrar cert si aplica → limpiar. Reduce de 4 a 2 las apps root.

### AxiomaWeb (puerto 3150, sin DB)

- [x] Verificar desuso: no escucha en 3150 / sin proceso / sin hits en access.log
- [x] Backup del código: HEAD local `eee1458` pusheado a origin ✅ + tarball `AxiomaWeb-decom-20260704.tar.gz` (100M, gzip OK)
- [x] Confirmar que no tiene base de datos propia → **no tiene DB**
- [x] Parar PM2/servicio → no había proceso activo
- [x] Quitar vhost nginx (era archivo regular en sites-enabled, no symlink) + `nginx -t` + reload sin corte
- [x] Borrar cert Let's Encrypt `axiomaweb.axiomacloud.com` (`certbot delete`)
- [x] Mover directorio a `/var/backups/AxiomaWeb-decom-20260704.dir` (reversible, no rm)
- [x] Registrar la baja (2026-07-05)

### rendiciones (puerto 5050, con DB `rendiciones_db`)

- [x] Verificar desuso: no escucha en 5050 / sin proceso / sin vhost / sin cert
- [x] Backup del código: HEAD local `af17c79` pusheado a origin ✅ + tarball `rendiciones-decom-20260704.tar.gz` (459M, gzip OK)
- [x] **Respaldar DB** `rendiciones_db` (12 MB) → `pg_dump -Fc` → `rendiciones_db-decom-20260704.dump` (178K, pg_restore listable OK)
- [x] Parar PM2/servicio → no había proceso activo
- [x] Vhost / cert → no tenía
- [x] Mover directorio a `/var/backups/rendiciones-decom-20260704.dir` (reversible, no rm)
- [x] **DROP DATABASE `rendiciones_db`** (aprobado por el usuario; dump de respaldo intacto)
- [x] Registrar la baja (2026-07-05)

### Cierre de Fase 1

- [x] Apps root remanentes: solo **corporate** (backend node 3005) — `checkpoint` resultó estático (no root); AxiomaWeb dado de baja
- [x] Actualizar inventario §2 (marcar AxiomaWeb y rendiciones como dadas de baja)
- [x] Actualizar DRP Apéndice A (quitar `rendiciones_db` de axioma)

---

## Fase 2 — Documento del estándar (aprobación)

- [x] Formalizar el §3 como estándar oficial (convención de usuario, paths, ecosystem, systemd, nginx, TLS, DB) → [`estandar-despliegue.md`](./estandar-despliegue.md) v1
- [x] Revisión y OK explícito antes de migrar cualquier app viva (aprobado 2026-07-05)
- [x] Publicar el estándar como referencia versionada en `docs/` (con plantillas y checklist de conformidad)

---

## Fase 3 — Secretos SOPS+age (base para el redespliegue)

> No cambia nada en los servers — solo respalda secretos cifrados. Va **antes** de toda migración.

- [x] Instalar `sops` + `age` en la máquina de trabajo (`~/.local/bin`: age v1.3.1, sops 3.13.2)
- [x] Generar clave age (`~/.config/sops/age/keys.txt`, chmod 600) — **custodia fuera de banda pendiente de confirmar por el usuario**
- [x] Crear repo git privado de secrets `~/Desarrollos/infra-secrets` con `.sops.yaml` (recipient = clave age pública)
- [x] Definir regla SOPS (cifrado **por-valor** vía `encrypted_regex`, las claves quedan legibles)
- [x] Cifrar y commitear el `.env` de cada app viva → **15 `.env` cifrados** (commit `970e2ee`):
  - [x] elore · evolution-api (tercero, respaldado) · hub (backend+frontend) · mediflow (backend)
  - [x] mini (backend+frontend+print-agent) · parse (backend+frontend) · clubix (server/.env)
  - [x] axio (raíz+backend) · axio-ml (`/opt/axio-ml-service`) · **axio-db-agent** (`/opt`, nuevo hallazgo)
  - [~] axioma-corporate · checkpoint → **estáticos, sin `.env` de app**; se confirma al migrarlos (Fase 5)
- [x] Verificar descifrado en máquina limpia (roundtrip con solo la clave age): **15/15 OK**
- [x] Documentar el procedimiento de descifrado para el redespliegue (`infra-secrets/README.md`)
- [x] **Remote git privado + `git push`** → `martin4yo/infra-secrets` (GitHub, isPrivate=true)
- [x] **Clave age guardada en el gestor de contraseñas** (custodia fuera de banda confirmada por el usuario)

---

## Fase 4 — Migración piloto: mini (owner axiomacloud → miniapp)

> App elegida por bajo riesgo. Ventana de bajo tráfico + rollback listo antes de tocar.

### Preparación

- [ ] Acordar ventana de bajo tráfico
- [ ] Backup de código (git al día)
- [ ] Backup de DB `mini_db` (verificar stanza pgBackRest)
- [ ] Backup del `.env` (ya cifrado en Fase 3)
- [ ] Backup de ecosystem PM2 + `pm2 save` (`dump.pm2`) para rollback en segundos

### Ejecución (normalización in-situ)

- [ ] Crear usuario dedicado `miniapp` (sin shell de login)
- [ ] Reasignar owner del código a `miniapp:miniapp` en `/var/www/mini/`
- [ ] Normalizar ecosystem a `ecosystem.config.js` (nombre y formato fijos)
- [ ] Normalizar estructura de directorios (frontend → `frontend/dist` si aplica)
- [ ] Parar PM2 bajo `axiomacloud`, arrancar bajo `miniapp`
- [ ] `pm2 save` + `systemctl enable pm2-miniapp.service`
- [ ] Ajustar vhost nginx si el path cambió + `nginx reload`

### Verificación

- [ ] Health HTTP OK
- [ ] App conecta a `mini_db`
- [ ] Boot test: reinicio del servicio arranca la app bajo `miniapp`
- [ ] Sin residuos del usuario `axiomacloud` para esta app

### Cierre

- [ ] Documentar lo aprendido y ajustar el procedimiento antes de replicar
- [ ] Actualizar inventario §2 (mini → owner miniapp)

---

## Fase 5 — Migración del resto (app por app)

> Repetir el patrón de la Fase 4 (preparación → ejecución → verificación → cierre) por cada app.
> Marcar el checkbox cuando la app quedó 100% en el estándar.

### Sacar de root

- [ ] **axioma-corporate** — crear usuario dedicado, sacar de root, normalizar, verificar
- [ ] **checkpoint** — crear usuario dedicado, sacar de root, normalizar, verificar

### Ajustes menores (ya casi estándar)

- [ ] **elore** — normalizar ecosystem/paths/usuario según desvíos detectados en Fase 0
- [ ] **hub** — normalizar según desvíos detectados en Fase 0
- [ ] **mediflow** — cerrar los últimos ajustes al molde (ya casi estándar)
- [ ] **clubix** — cerrar los últimos ajustes al molde (ya casi estándar)

### Cierre de Fase 5

- [ ] Todas las apps propias (excepto axio/parse de Fase 6) en el estándar
- [ ] Cero apps corriendo como root
- [ ] Inventario §2 actualizado

---

## Fase 6 — Hooks especiales y tercero

### parse (propia, sin hook)

- [ ] Migrar al molde común como app Node estándar (confirmado sin redis/mongo)
- [ ] Verificar (health + DB `parse_db`)
- [ ] Aclarar/documentar el doble puerto 5100/8087

### axio (propia, con hook axio-ml)

- [ ] Migrar `axio-backend` (Node/PM2) al molde común
- [ ] Definir el **hook axio-ml** en el manifiesto:
  - [ ] Instalar ollama
  - [ ] `ollama pull` de modelos (mistral-nemo, gemma2, llama3.1, qwen2.5…)
  - [ ] Levantar venv Python/uvicorn de `/opt/axio-ml-service` (puerto 8001)
- [ ] Confirmar que los 30 GB de modelos NO se respaldan (se re-descargan, reproducible)
- [ ] Verificar (backend health + DB `axiodemo` + axio-ml responde en 8001)

### evolution-api (tercero, setup separado)

- [ ] Escribir runbook de reinstalación propio (dependencias + esquema)
- [ ] Documentar sus deps externas (confirmadas en Fase 0)
- [ ] NO forzar al molde común

---

## Fase 7 — Construir el redespliegue

> Sobre el entorno ya estandarizado. Estructura: `scripts/redeploy/`.

- [ ] Escribir `lib-redeploy.sh` (lógica compartida) con los 9 pasos:
  - [ ] 1. Crear usuario `<app>app` en server destino
  - [ ] 2. Instalar runtime (Node del manifiesto + PM2 global)
  - [ ] 3. `git clone` con credencial correcta (deploy key SSH)
  - [ ] 4. Restaurar DB desde pgBackRest (reusar lógica de `70-restore-drill.sh`)
  - [ ] 5. Descifrar y colocar `.env` (SOPS)
  - [ ] 6. `npm install` + build de frontend si aplica
  - [ ] 7. PM2 + ecosystem, `pm2 save`, `systemctl enable pm2-<app>app`
  - [ ] 8. Desplegar vhost nginx + emitir cert Let's Encrypt
  - [ ] 9. Verificar (health HTTP + app conecta a DB)
- [ ] Escribir manifiestos por app (`manifests/<app>.manifest.sh`, ~15 líneas):
  - [ ] mini
  - [ ] parse
  - [ ] clubix
  - [ ] axio (con hook axio-ml)
  - [ ] mediflow
  - [ ] elore
  - [ ] hub
  - [ ] axioma-corporate
  - [ ] checkpoint
- [ ] Escribir orquestador `redeploy.sh <app> <server-destino>`
- [ ] Documentar el hook de tercero para evolution-api (runbook aparte, invocable)

---

## Fase 8 — PoC end-to-end

- [ ] Elegir server destino de prueba
- [ ] Reinstalar una app completa: DB + app + vhost + cert
- [ ] Medir tiempo de recuperación (RTO real)
- [ ] Ajustar lib/manifiesto según lo aprendido
- [ ] Documentar el resultado como parte del DRP
- [ ] (Opcional) Repetir con una segunda app para validar el molde

---

## Registro de ejecución

> Bitácora corta: fecha · fase/app · qué se hizo · resultado. Se completa a medida que se avanza.

| Fecha | Fase / App | Acción | Resultado |
|---|---|---|---|
| 2026-07-04 | 0 | Relevamiento in-situ de los 3 servers (PM2, puertos, git, nginx, DBs, Node, ollama) | ✅ inventario §2 cerrado; 5 hallazgos que ajustan fases 1/4/5/6/7 |
| 2026-07-05 | 1 · AxiomaWeb | Backup (git+tar 100M) → quitar vhost + reload → borrar cert → mover dir a backup | ✅ baja completa (sin DB) |
| 2026-07-05 | 1 · rendiciones | Backup (git+tar 459M) + pg_dump DB (178K) → mover dir → DROP rendiciones_db | ✅ baja completa (DB eliminada, dump intacto) |
| 2026-07-05 | 2 | Formalizar el estándar como `estandar-despliegue.md` v1 (nombres, usuario, dirs, ecosystem, systemd, .env/SOPS, nginx, TLS, DB, hooks, checklist + línea base de conformidad) | ✅ aprobado y cerrado |
| 2026-07-05 | 2 · clubix | Decisión de layout: server/+client/dist se declara en manifiesto (no se renombra); PM2 admite `<app>-backend`/`<app>-web` | ✅ clubix conforme sin tocar el server |
| 2026-07-05 | 3 | Instalar age/sops (local) + generar clave age + repo `infra-secrets` con `.sops.yaml` (cifrado por-valor) | ✅ tooling y repo listos; clave age generada (custodia a confirmar) |
| 2026-07-05 | 3 | Traer y cifrar 15 `.env` de los 3 servers (sudo para los chmod 600) + README de descifrado | ✅ commit `970e2ee`; roundtrip máquina limpia 15/15 |
| 2026-07-05 | 3 | Crear repo privado `martin4yo/infra-secrets` + push; clave age custodiada en gestor | ✅ Fase 3 cerrada (isPrivate=true) |
