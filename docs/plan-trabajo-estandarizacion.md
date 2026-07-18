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
- [ ] **Fase 6/7 (elore):** **crear/confirmar repo remoto** antes de poder redesplegar (hoy sin remote) — bloqueante para Fase 7
- [x] **hub:** SÍ tiene remote → `AxiomaCloud/ProHub` (SSH), branch `main`, `name: hub-monorepo`. El "sin remote" de Fase 0 fue falso negativo por `safe.directory`.
- [ ] **⚠ Fase 6 (axio) — DEPLOY CON `origin` MAL APUNTADO (hallazgo 2026-07-17):** el checkout desplegado `/var/www/axio` (`name: axio`, con backend/frontend Vite/`ml-service/`+`db-agent/`) tiene `origin = AxiomaCloud/ProHub` (HTTPS) — **pero ProHub es el repo de hub** (`hub-monorepo`). **El repo propio de axio SÍ existe y es correcto:** `github.com/AxiomaCloud/axio.git`, clonado local en `~/Desarrollos/cuthulu` (`name: axio`, mismo árbol). O sea: dos repos correctos y separados (ProHub=hub, axio=axio); lo único mal es el `origin` del deploy de axio en axiodemo. **✅ ProHub NO fue ensuciado (verificado 2026-07-17):** `origin/main` de ProHub es 100% hub (`name: hub-monorepo`, marcadores `shared`/`prototypes`/`pricing_hub.html` presentes; `ml-service`/`db-agent`/`CONEXION_ERP.md` ausentes); ningún commit de axio en el historial; ramas solo `main` + `feat/udesa-demo` (ambas de hub). Los commits de axio del server (`22eaff3`, etc.) **nunca se pushearon** → el enredo fue solo de config (`origin` mal), sin daño de datos.
**Corrección (Fase 6):** (1) re-apuntar `origin` de `/var/www/axio` a `axio.git`; (2) reconciliar los cambios locales sin commitear del server (`ml-service/main.py`, `kb_repo.py`, `frontend/.env.production`) y el HEAD `22eaff3` con `axio.git`; (3) NO tocar ProHub (es de hub).

**Estado de repos axio (verificado 2026-07-17):**
- Repo canónico: `github.com/AxiomaCloud/axio.git`. Clon local en `~/Desarrollos/cuthulu`, **actualizado a `afa7461`** (pull ff-only limpio, 127 archivos vs el viejo `1ad60fb`).
- **Método de deploy real (reconstruido por reflog + bash_history):** se corre **en el server** `sudo bash /var/www/axio/scripts/deploy.sh`, que hace `git -C /var/www/axio fetch origin main` + `pull origin main` como `axioapp` + build + restart. NO es copia de archivos desde local. El reflog muestra ~15 `pull origin main` (ff) entre 15–23 may.
- **Se congeló el 23-may** en `22eaff3` (último pull OK). `axio.git` canónico ya está en `afa7461` (~5 commits más) que el server nunca recibió.
- **⚠ BOMBA EN EL DEPLOY:** hoy `origin` de `/var/www/axio` = `ProHub` (repo de hub). En mayo ese origin *era axio* (por eso los pulls traían axio); cambió a ProHub **después** del 23-may → desde entonces `deploy.sh` falla en el `fetch` por falta de credencial HTTPS. **Si se arregla la credencial SIN re-apuntar el origin primero, el próximo `deploy.sh` haría `pull origin main` desde ProHub → traería hub → rompe axio en prod.** Corrección obligatoria antes de volver a deployar axio: `git remote set-url origin git@github.com:AxiomaCloud/axio.git` en `/var/www/axio`, reconciliar los 3 cambios locales (`ml-service/main.py`, `kb_repo.py`, `frontend/.env.production`), recién ahí pull.
- **axio también tiene CI/CD** (`.github/workflows/deploy-axio.yml` + `deploy-db-agent.yml`) — coexiste con el `deploy.sh`; aclarar cuál es el método vigente en Fase 6.
- `db-agent/` es un subproyecto de axio (Node) con su `.service` + `DEPLOY_CLUBIX.md` → es el proceso `:3005` de axioma (`/opt/axio-db-agent`); se despliega en varios servers. **Nota:** el `db-agent/` de axio (con `DEPLOY_CLUBIX.md` + `.service`) es el proceso `:3005` de axioma (`/opt/axio-db-agent`) — parte del monorepo de axio, contemplarlo en el manifiesto.
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

## Fase 4 — Migración piloto

> **Cambio de piloto (2026-07-17):** mini quedó descartado como piloto por estar **en
> producción**. Se elige **hub**, que está **caída** (bajo riesgo: no hay servicio vivo que
> romper) y ejercita un redespliegue realista.

> **Encuadre (2026-07-17):** revivir hub se trata como un **ensayo del procedimiento de
> redeploy** — como si hub se hubiera perdido y tuviéramos que reinstalarla de cero. Cada
> paso se mapea a los 9 del `lib-redeploy.sh` (plan §4), así hub adelanta el PoC de la Fase 8
> y lo aprendido se vuelca en la librería + el manifiesto de hub. Diferencia con un redeploy
> puro: el código ya está en disco (hub no tiene remote git) y la DB `hub_db` ya existe; esos
> dos huecos son, de hecho, hallazgos del ensayo (ver "Aprendizajes" al cierre).

### Piloto elegido: hub (redeploy-drill: reinstalar + estandarizar)

**Mapa a los 9 pasos del redeploy (lib-redeploy §4):**
| Paso lib-redeploy | En este ensayo de hub |
|---|---|
| 1. crear usuario `<app>app` | ya existe `hubapp` (uid 993) → se reusa |
| 2. instalar runtime | Node v20.20.2 ya presente + PM2 |
| 3. `git clone` | ✅ remote real: `AxiomaCloud/ProHub` (SSH), branch `main`. El código en disco ya es ese repo (`safe.directory` requerido por owner `hubapp`) |
| 4. restaurar DB (pgBackRest) | `hub_db` ya existe y está sana → no se restaura; en un DR real vendría de repo1/R2 |
| 5. descifrar+colocar `.env` (SOPS) | `hub-backend.env` + `hub-frontend.env` desde infra-secrets |
| 6. `npm install` + build | backend `npm ci`+prisma+build, frontend `npm ci`+build |
| 7. PM2 + ecosystem + systemd | `pm2 start` + `pm2 save` + crear `pm2-hubapp.service` + enable |
| 8. vhost nginx + cert | revisar/ajustar vhost + `nginx -t` + reload; cert si aplica |
| 9. verificar (health + DB) | health :5200/:8089 + conecta a `hub_db` + boot test |

**Diagnóstico (relevado in-situ 2026-07-17, solo lectura):**
- hub está detenida desde ~13-jun por un **deploy inconcluso**: en `/var/www/hub` está el
  código fuente completo (backend `src/`+`server.ts`+`tsconfig`+`prisma/schema.prisma`;
  frontend `src/`+`next.config.js`) pero **sin `node_modules` ni build** (`dist/` en backend,
  `.next` en frontend) → PM2 no podía arrancar `dist/server.js`, no logueó nada, y sin servicio
  systemd nada lo reintentó. El server no rebooteó (uptime 27-jun).
- **No es un crash**: es una instalación a mitad de camino. Logs `/var/log/hub/` vacíos.
- **DB `hub_db` sana** (43 tablas). **`.env` recuperable** desde infra-secrets
  (`hub-backend.env` 28 vars + `hub-frontend.env` 2 vars, descifran OK); además hay un
  `backend/.env` en disco. **Node v20.20.2** correcto.
- **CORRECCIÓN (2026-07-17):** hub **SÍ tiene remote git** → `git@github.com:AxiomaCloud/ProHub.git`
  (SSH), branch `main`. El "sin remote" de la Fase 0 fue un falso negativo (git bloqueaba el
  repo por `safe.directory`, owner `hubapp`). hub y axio **comparten el repo ProHub** pero son
  proyectos distintos (`@hub/backend`/`@hub/frontend` vs axio). Copia local del repo también en
  `~/Desarrollos/hub`. → **hub SÍ es redesplegable** (paso 3 del lib-redeploy resuelto).
- **Desvíos al estándar a corregir de paso:** no existe `pm2-hubapp.service` (no arranca al
  reboot); vhost de hub a revisar.

**Plan de ejecución (pendiente de OK explícito, una acción a la vez):**

> **La DB `hub_db` NO se pisa.** El drill reinstala **solo la aplicación** (código+build+arranque).
> La causa de la caída fue un build faltante, no el esquema → la DB ya debería estar correcta.
> El único paso que tocaría el esquema es `prisma migrate deploy`, que **no se corre salvo OK
> explícito**; antes se chequea con `prisma migrate status` (solo lectura). Igual se hace `pg_dump`
> de respaldo como red de seguridad.

#### Preparación (backup + rollback)
- [ ] Backup del código actual de hub (tar de `/var/www/hub` a `/var/backups/`)
- [ ] Confirmar/colocar `.env` (comparar disco vs infra-secrets; usar el de SOPS si difiere)
- [ ] Dump de `hub_db` antes de tocar (por si el build corre migraciones Prisma)
- [ ] Registrar estado actual para rollback (hub caída = rollback = volver a caída)

#### Ejecución (completar deploy + estandarizar) — EJECUTADO 2026-07-17
- [x] Backup: tar `/var/backups/hub-predeploy-20260717.tar.gz` (11M) + `pg_dump` `hub_db-predeploy-20260717.dump` (176K, 314 objetos) ✅
- [x] `.env` confirmado idéntico a infra-secrets (28 vars, mismos valores) → no se tocó
- [x] **`npm ci` DESDE LA RAÍZ del monorepo** (workspaces backend/frontend/shared) — el `npm ci` por-workspace NO instala Prisma. **Aprendizaje clave.**
- [x] build backend (`tsc`→`dist/server.js`) + frontend (`next build`→`.next`) ✅
- [x] **`prisma generate` DESDE LA RAÍZ** (Prisma 6.19 local; el `npx` baja Prisma 7 que rompe el schema). Sin esto → crash `@prisma/client did not initialize`.
- [x] Migración pendiente `add_purchase_requests`: la DB ya la tenía aplicada (y MÁS: 25 cols vs 16) → `prisma migrate resolve --applied` (NO corre SQL) + limpieza de la fila fallida en `_prisma_migrations`. **DB intacta, sin `db push`.**
- [x] Arranque `pm2 start ecosystem.config.js` como `hubapp` ✅
- [x] `pm2 save` + **`pm2-hubapp.service` creado + enabled** (era el desvío que causó la caída original) ✅
- [x] **vhost nginx de hub creado + cert TLS emitido** (2026-07-17): hub NO tenía vhost ni cert (nunca se publicó). Creado `/etc/nginx/sites-available/hub` (molde parse): `hub.axiomacloud.com`→`:8089` (front Next) + `api.hub.axiomacloud.com`→`:5200` (backend, `/api/*` + `wss://`). Cert Let's Encrypt webroot para ambos SAN (exp 2026-10-15, autorenew). `nginx -t` OK + reload sin corte.

#### Verificación — EJECUTADA 2026-07-17
- [x] Backend `:5200/health` → HTTP 200 (`{"status":"ok","message":"Hub API is running"}`)
- [x] Frontend `:8089` → HTTP 200 (`<title>Axioma - Hub</title>`); **público**: `https://hub.axiomacloud.com` HTTP 200 + cert válido, `https://api.hub.axiomacloud.com/health` HTTP 200, redirect 80→443 OK
- [x] hub conecta a `hub_db`: rutas que pegan a la DB responden 400/401 (no 500) → Prisma consulta OK; **código viejo convive con DB nueva** (Prisma ignora las columnas extra)
- [x] **Boot test OK**: tras `pm2 kill` + `systemctl start pm2-hubapp` desde cero → `is-active: active`, ambos procesos online, health 200. hub sobrevive un reboot.
- [x] **Login funcional** (2026-07-17): tras resolver 2 problemas de DB encadenados, `POST /api/auth/login` responde 401 a credenciales inválidas (comportamiento correcto), ya no 500. Falta que el usuario pruebe con credenciales reales desde el browser.

  **Problemas de DB resueltos (post-arranque):**
  1. **`hub_db` desincronizada con el código** (no era productiva): al `User` le faltaban columnas que el código usa (`whatsappPhone`, `mustChangePassword`) → login daba 500 (`P2022 column does not exist`). Fix: **`prisma db push --accept-data-loss`** (como owner postgres) → DB sincronizada al `schema.prisma`. Autorizado porque la base NO estaba productiva.
  2. **Permisos**: el `db push` como postgres dejó las tablas con owner postgres; `hubuser` (rol de la app) perdió acceso → `42501 permission denied for table User`. Fix: `GRANT ALL ON ALL TABLES/SEQUENCES IN SCHEMA public TO hubuser` + `ALTER DEFAULT PRIVILEGES` (para futuros push/migrate). **Aprendizaje para el redeploy:** tras un `db push`/`migrate` ejecutado como owner distinto al de la app, re-otorgar grants al rol de la app.

#### Cierre — pendientes
- [x] hub → **online + systemd enabled** (actualizar inventario §2)
- [ ] **Desfase código↔DB:** el checkout (`32acd4c`) es más viejo que `hub_db` (PurchaseRequest 25 cols + FK `aprobadorId` que el código no conoce). No rompe (Prisma ignora extras) pero conviene **actualizar el código de hub** a una versión al día con la DB. NO se resuelve con `db push` (borraría columnas). Tema aparte.
- [ ] Vulnerabilidades npm audit (47 backend / 18 frontend) — higiene, no bloqueante.

#### Aprendizajes para el redeploy (Fases 7–8) — se completan al ejecutar
- [x] **hub SÍ tiene remote** (`AxiomaCloud/ProHub`, SSH) → redesplegable. El relevamiento de Fase 0 dio "sin remote" por `safe.directory`: **el redeploy debe setear `safe.directory` o clonar como el owner correcto**, no asumir "sin remote" cuando `git` falla por owner.
- [ ] **hub y axio comparten repo (ProHub)** → el manifiesto debe declarar qué proyecto/subdir/branch usa cada uno (monorepo con dos apps).
- [ ] Anotar tiempos reales de cada paso (build backend/frontend) → insumo para el RTO de la Fase 8.
- [ ] Todo comando ejecutado (npm/prisma/pm2/nginx) es candidato a línea del futuro `lib-redeploy.sh` — capturarlos.
- [ ] Confirmar orden seguro: ¿build antes o después de colocar `.env`? ¿migraciones idempotentes?

---

## Fase 4 (original) — Migración piloto: mini (owner axiomacloud → miniapp) — DESCARTADO como piloto

> mini quedó **en producción** → no es el piloto. Los ajustes de mini (ecosystem `.cjs`→`.js`,
> repo) se harán en Fase 5 con su propia ventana. Se conserva el checklist abajo como referencia.

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
