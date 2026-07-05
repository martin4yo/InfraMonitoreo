# Plan de Estandarización de Despliegues + Redespliegue Automatizado

> **Estado: BORRADOR PARA REVISIÓN — nada ejecutado.** Este documento es el plan de
> trabajo. No se toca ningún servidor hasta aprobación explícita, app por app.
> Fecha: 2026-07-04.

## 1. Objetivo

Poder **reinstalar cualquier app del entorno en otro servidor** (base de datos + aplicación)
en el menor tiempo posible y de forma automatizada. Para lograrlo con un script simple y
confiable, primero se **estandariza** cómo están instaladas las apps (hoy divergen mucho), y
recién después se construye el redespliegue sobre un molde uniforme.

**Alcance:** apps de `axioma`, `clubix` y `axiodemo`. `dev-1` queda fuera (es test).

**Decisión de runtime:** se mantiene **Node + PM2 nativo** (lo que ya se usa). **No se migra a
Docker** — no está instalado, no aporta a los problemas reales (owners, secretos), y sería un
proyecto aparte. Los `docker-compose.yml` que quedaron en algunos repos son restos sin uso.

---

## 2. Situación actual (inventario)

### Apps por servidor

> **Inventario cerrado en Fase 0 (relevamiento in-situ, 2026-07-04).** Node por server:
> axioma **v20.20.2**, clubix **v20.20.2**, axiodemo **v22.22.2**. Ver notas debajo de la tabla.

| Servidor | App | Owner hoy | Puerto | Base de datos | Repo git | Node | Estado |
|---|---|---|---|---|---|---|---|
| axioma | axioma-corporate | 🟡 estático + backend root | 3005 (prd) + estático (default) | axiomadocs | rodrigomnaranjo/axioma-corporate | 20 | migrar (frontend estático + backend node en 3005) |
| axioma | **AxiomaWeb** | 🔴 root | 3150 | — | martin4yo/AxiomaWeb | 20 | **DAR DE BAJA** (vhost axiomaweb.axiomacloud.com) |
| axioma | checkpoint | 🟡 estático (nginx `root`) | — (estático) | checkpoint_db (¿en uso?) | AxiomaCloud/checkpointsite | — | **NO es app root** — sitio estático servido por nginx |
| axioma | **rendiciones** | 🔴 root | 5050 | rendiciones_db | martin4yo/Rendiciones | 20 | **DAR DE BAJA** |
| axioma | elore | eloreapp | 3700 | elore_db | (repo local — remote no configurado) | 20 | menor · Next.js · elore.com.ar · **ecosystem.config.js ✅** |
| axioma | evolution-api | evolutionapp | 8080 | evolution | EvolutionAPI/evolution-api | 20 | **TERCERO → setup separado** · tsx/TypeScript · evolution.axiomacloud.com |
| axioma | hub | hubapp | 5200 (back) + 8089 (front) | hub_db | (repo local — remote no configurado) | 20 | revisar · back `dist/server.js` + front Next · **ecosystem.config.js ✅** |
| axioma | mediflow | mediflowapp | 5300 | mediflow_db | martin4yo/mediflow (SSH) | 20 | casi estándar ✅ · sirve **alvera.axiomacloud.com / alvera.com.ar** |
| axioma | mini | 🟢 **miniapp (ya migrado)** | 8095 | mini_db | martin4yo/AxiomaWeb (SSH) | 20 | owner ✅ · **falta**: ecosystem `.cjs`→`.js`, repo raro (AxiomaWeb) |
| axioma | parse | parseapp | 5100 (back) + 8087 (front) | parse_db | martin4yo/parse (SSH) | 20 | estándar ✅ · back `src/index.js` (5100) + front Next standalone (8087) |
| clubix | clubix | clubixapp | 5400 | clubix_db | martin4yo/rojoplus | 20 | casi estándar ✅ · **ecosystem.config.js ✅** · clubix.com.ar + sportivopilar.com.ar |
| axiodemo | axio-backend | axioapp | 3001 | axiodemo | AxiomaCloud/ProHub | 22 | estándar · `dist/server.js` · axiodemo.axiomacloud.com |
| axiodemo | axio-ml | 🟡 **axiomacloud** | 8001 | — | (parte de ProHub / `/opt/axio-ml-service`) | py | hook · **owner a normalizar** · uvicorn + ollama (8 modelos ~31 GB) |

**Aclaración de propiedad y estandarización:**

- **`parse` y `axio` son propias** → van al **estándar común**. El nombre "parse" no es Parse
  Server: es una app Node tuya (backend + frontend Next.js), solo Postgres, sin redis/mongo.
- **`axio`** son en realidad **dos componentes**: `axio-backend` (Node/PM2, estándar) **+
  `axio-ml`** — un servicio **Python/uvicorn** en `/opt/axio-ml-service` (puerto 8001) que usa
  **ollama con ~30 GB de modelos** (mistral-nemo, gemma2, llama3.1, qwen2.5…). `axio-ml` se
  estandariza con un **hook extra en su manifiesto**: instalar ollama + `ollama pull` de los
  modelos (reproducible, NO hay que respaldar los 30 GB) + levantar el venv de Python. No es un
  setup separado, es el molde común con un paso adicional declarado.
- **`evolution-api` es de un tercero** (EvolutionAPI) → **setup separado** documentado aparte,
  fuera del molde común.

> Puertos, DBs y repos marcados con `?` o "(por confirmar)" se cierran en la Fase 0. **Cerrado ✅.**

**Hallazgos de la Fase 0 que ajustan el plan:**

1. **`mini` YA corre como `miniapp`** (no `axiomacloud`). La migración de owner de la Fase 4
   está de hecho **hecha**. Lo que resta en `mini` es cosmético: ecosystem `.cjs`→`.js` y decidir
   qué hacer con el repo (apunta a `martin4yo/AxiomaWeb`, no a un repo "mini" propio).
2. **`checkpoint` y `axioma-corporate` NO son apps node corriendo como root.** `checkpoint` es un
   **sitio estático** (nginx `root` + `try_files`). `axioma-corporate` es **estático (vhost `default`)
   + un backend node en el puerto 3005** (vhost `prd.axiomacloud.com`). Sacarlos de root es mucho
   más simple de lo previsto (el estático lo sirve nginx; solo el backend 3005 necesita usuario).
3. **`axio-ml` corre como `axiomacloud`**, no como usuario dedicado → **inconsistencia nueva**
   (owner ≠ app), sumar a la lista. Confirmados **8 modelos ollama (~31 GB)**: mistral-nemo:12b,
   gemma2:9b, llama3.1:8b, qwen2.5-coder:7b, qwen2.5:7b, nomic-embed-text, llama3.2:3b, phi3:mini.
4. **Repos de `elore` y `hub` no tienen remote git configurado** en el server (código local).
   Antes de poder redesplegarlos hay que **crear/confirmar su repo remoto** (bloqueante para Fase 7).
5. **`rendiciones` sí tiene DB** (`rendiciones_db` en axioma PG14) — contemplar backup de esa base
   antes de darla de baja (no solo el código).
6. **`mediflow` sirve el dominio `alvera`** (alvera.axiomacloud.com / alvera.com.ar), no un dominio
   "mediflow" — dato para el vhost del manifiesto.
7. **Ecosystem ya estándar (`.js`)** en: elore, hub, parse, clubix. Solo **`mini` está en `.cjs`**.
8. **Node diverge por server**: axioma/clubix v20.20.2, axiodemo v22.22.2 — fijar versión por app
   en el manifiesto (axio necesita v22).

### Inconsistencias detectadas (lo que hay que corregir)

1. **Apps corriendo como `root`** — axioma-corporate, AxiomaWeb, checkpoint, rendiciones.
   Inseguro y rompe el patrón de usuario dedicado. (2 de estas 4 se dan de baja.)
2. **Usuario ≠ nombre de app** — `mini` corre como `axiomacloud`, no `miniapp`.
3. **Ecosystem PM2 inconsistente** — `.js` vs `.cjs` vs sin archivo.
4. **Estructura de directorios variada** — frontend en `dist/`, `client/`, `web/` según la app.
5. **`.env` no versionados** — secretos (DB pass, JWT, API keys) solo viven en cada server.
   Es el mayor riesgo de DR: un server destruido los pierde.
6. **Dependencias/runtime extra en apps propias** — `axio` incluye `axio-ml` (Python/uvicorn +
   ollama con ~30 GB de modelos). Se estandariza con un hook extra, no queda fuera del molde.
7. **Una app de tercero** — `evolution-api` (EvolutionAPI). No es propia → setup separado.

---

## 3. Estándar de despliegue objetivo

Toda app propia converge a esta convención, sin excepción:

```
Usuario:      <app>app         (dedicado, sin shell de login, dueño de todo lo suyo)
Código:       /var/www/<app>/  (git clone, owner <app>app:<app>app)
Runtime:      Node (versión fijada por app en el manifiesto) + PM2
Arranque:     ecosystem.config.js   (nombre y formato fijos)
Boot:         systemd  pm2-<app>app.service  (enabled)
Config:       /var/www/<app>/.env   (versionado CIFRADO con SOPS+age)
Frontend:     /var/www/<app>/frontend/dist   (convención fija; si aplica)
Web:          /etc/nginx/sites-available/<app>  + symlink en sites-enabled
TLS:          cert Let's Encrypt (auth=webroot con /var/www/certbot, o nginx)
Puerto:       asignado y documentado en el manifiesto de la app
Base:         una stanza pgBackRest (ya existe el backup + restore drill)
```

Las apps **propias** (incluidas parse y axio) van a este molde. Cuando una tiene una dependencia
o runtime extra (ej. `axio-ml`: Python/uvicorn + ollama), se agrega un **hook** en su manifiesto,
sin salir del molde. Solo la app de **tercero** (`evolution-api`) va a un **setup separado**.

### Estrategia de secretos (best-practice): **SOPS + age**

- Repo git privado con los `.env` de todas las apps, **cifrados por-valor** con SOPS+age.
- Se pueden commitear sin exponer secretos; el diff muestra *qué* variable cambió, no el valor.
- Una sola **clave age** descifra, custodiada **fuera de banda** (gestor de contraseñas).
- El script de redespliegue descifra el `.env` de la app al reinstalar.
- Descartado: backup crudo a R2 (sin versión, cifrado casero) y edición manual (no es DR real).

---

## 4. Arquitectura del redespliegue

**Librería común + manifiesto por app + orquestador.** No un mega-script ni 12 scripts repetidos.

```
scripts/redeploy/
  lib-redeploy.sh          # lógica compartida (una sola vez)
  manifests/
    mini.manifest.sh       # ~15 líneas declarativas por app
    parse.manifest.sh
    clubix.manifest.sh
    ...
  redeploy.sh <app> <server-destino>   # orquesta: lee manifiesto → invoca lib
```

**Qué hace `lib-redeploy.sh` (pasos del redespliegue de una app):**
1. Crear usuario `<app>app` en el server destino.
2. Instalar runtime (Node versión del manifiesto, PM2 global).
3. `git clone` del repo (con la credencial correcta — deploy key para SSH).
4. Restaurar la base desde pgBackRest (reutiliza la lógica de `70-restore-drill.sh`).
5. Descifrar y colocar el `.env` (SOPS).
6. `npm install` + build del frontend si aplica.
7. Levantar con PM2 + ecosystem, registrar `pm2 save` + `systemctl enable pm2-<app>app`.
8. Desplegar vhost nginx + emitir cert Let's Encrypt.
9. Verificar: health HTTP + app conecta a su DB.

**El manifiesto de cada app** declara solo sus diferencias: nombre, repo+método de auth,
stanza de DB, puerto, dominio, versión de Node, y (para terceros) hooks de pasos extra.

---

## 5. Plan de trabajo por fases

> Regla transversal: **una app a la vez, con respaldo y rollback, sin tocar varias juntas.**
> Cada fase se aprueba antes de ejecutar.

### Fase 0 — Cerrar inventario (solo lectura, cero riesgo)
- Confirmar por app los `?`: repo git exacto + método auth, base de datos, puerto, dominio,
  versión de Node, dependencias externas (redis, ollama/modelos, etc.).
- Entregable: tabla del §2 completa, sin huecos.

### Fase 1 — Bajas (decomisionar lo muerto)
- **AxiomaWeb** y **rendiciones** (ambas ya no escuchan, sin tráfico).
- Procedimiento seguro ya probado con clubix: verificar desuso → backup de código (git) y de
  DB si tuvieran → parar PM2/servicio → quitar vhost → borrar cert si aplica → limpiar.
- Reduce de 4 a 2 las apps que corren como root.

### Fase 2 — Documento del estándar (aprobación)
- Formalizar el §3 como el estándar oficial. Revisión y OK antes de migrar apps vivas.

### Fase 3 — Secretos SOPS+age (base para el redespliegue)
- Generar clave age (custodia fuera de banda), crear repo de secrets, cifrar los `.env`
  actuales de cada app. No cambia nada en los servers todavía; solo respalda secretos.

### Fase 4 — Migración piloto (1 app de bajo riesgo)
- Candidata: **mini** (migrar owner `axiomacloud`→`miniapp`) o una app ya casi estándar.
- Ejecutar la normalización con ventana + rollback listo. Validar que la app sigue igual.
- Aprender y ajustar el procedimiento antes de replicar.

### Fase 5 — Migración del resto (app por app)
- Aplicar el estándar a: axioma-corporate, checkpoint (sacar de root), y ajustes menores en
  elore, hub, mediflow. Cada una con su ventana y verificación.

### Fase 6 — Hooks especiales y tercero
- **axio-ml** (propia, hook extra): manifiesto de `axio` con paso adicional — instalar ollama,
  `ollama pull` de los modelos (mistral-nemo, gemma2, llama3.1, qwen2.5…), y levantar el
  servicio Python/uvicorn de `/opt/axio-ml-service`. Los 30 GB de modelos NO se respaldan: se
  re-descargan (reproducible). El resto de `axio` (backend Node) va por el molde común.
- **parse** (propia, sin hook): entra al molde común como cualquier app Node — no necesita nada
  especial (confirmado sin redis/mongo).
- **evolution-api** (tercero): **setup separado** documentado — no se fuerza al molde común.
  Se escribe su propio runbook de reinstalación con sus dependencias y esquema.

### Fase 7 — Construir el redespliegue
- Escribir `lib-redeploy.sh` + manifiestos + `redeploy.sh` sobre el entorno ya estandarizado.

### Fase 8 — PoC end-to-end
- Reinstalar una app completa en un server destino de prueba: DB + app + vhost + cert.
- Medir tiempo de recuperación. Ajustar. Documentar como parte del DRP.

---

## 6. Orden recomendado y por qué

1. **Fase 0 + Fase 1 primero** — cerrar inventario y sacar lo muerto: cero/bajo riesgo, y
   limpian el terreno (menos apps, menos ruido).
2. **Fase 2 + 3** — acordar el estándar y respaldar secretos antes de tocar apps vivas.
3. **Fase 4 piloto** — probar la migración en una app controlada antes de generalizar.
4. **Fases 5–8** — replicar y construir el automatismo sobre base sólida.

El principio rector: **estandarizar sobre orden, no sobre caos**. Cada paso deja el entorno
igual o mejor que antes, nunca peor, y siempre con vuelta atrás.

---

## 7. Downtime de la estandarización

La estandarización se hace **in-situ** (en el mismo server donde ya corre la app); NO reinstala
ni migra datos. La base de datos **no se toca**. El único corte es el reinicio de PM2 al aplicar
el cambio: **segundos por app**, nunca minutos.

| Cambio | ¿Downtime? | Duración típica | Motivo |
|---|---|---|---|
| Migrar owner (ej. mini → miniapp) | Sí, breve | ~5–15 s | Parar PM2 del usuario viejo, arrancar con el nuevo |
| Sacar app de root → usuario dedicado | Sí, breve | ~10–20 s | Reproceso bajo el nuevo usuario |
| Normalizar ecosystem (`.cjs`→`.js`, nombre) | Sí, breve | ~5 s | `pm2 reload`/`restart` toma el nuevo ecosystem |
| Mover/normalizar directorios | Sí, breve | ~10 s | Reapuntar path y reiniciar |
| Versionar `.env` con SOPS | **No** | 0 | Solo se copia (cifrado) al repo; el server no cambia |
| Ajustar vhost nginx | **No** | 0 | `nginx reload` es sin corte (mantiene conexiones) |
| Emitir/renovar cert TLS | **No** | 0 | No toca el servicio |

**Cómo se minimiza:**
1. **Ventana de bajo tráfico** por app (horario tranquilo).
2. **`pm2 reload`** (recarga con solapamiento, ~0 corte) en vez de `restart` donde la app lo soporte.
3. **Rollback listo** — backup de ecosystem + `dump.pm2` para volver en segundos.
4. **Una app a la vez** — un problema afecta solo a esa app.

> **Nota sobre axio-ml y el redespliegue:** el downtime largo (reinstalar ollama, re-bajar 30 GB
> de modelos) aplica solo al **redespliegue en OTRO server** (Fase 7–8), no a la estandarización
> in-situ. Estandarizar axio-ml donde ya está es solo normalizar cómo arranca (~segundos).

**Resumen:** estandarizar el entorno cuesta **segundos de corte por app**, planificables en
ventana. No hay downtime prolongado en ninguna app propia.

---

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Romper una app en producción al migrarla | Una app a la vez, ventana acordada, backup de código+DB+.env y rollback probado antes de tocar |
| Perder secretos al mover apps | Fase 3 (SOPS) va **antes** de cualquier migración |
| App de tercero (evolution) que no encaja en el molde | Setup separado documentado, no forzarla al molde común |
| Dar de baja algo que sí se usaba | Verificación de desuso (puerto/tráfico/DNS) + backup antes de borrar, como se hizo con clubix |
| Dependencias/runtime extra olvidados (ollama/modelos, venv Python) | Fase 0 los inventaría explícitamente por app; hook en el manifiesto |
| Downtime inesperado al reiniciar PM2 | Ventana de bajo tráfico + `pm2 reload` + rollback en segundos (§7) |

---

## 9. Decisiones aprobadas (2026-07-04)

- [x] El estándar del §3 se adopta como convención oficial. ✅
- [x] Se confirma dar de baja **AxiomaWeb** y **rendiciones**. ✅
- [x] Se adopta **SOPS+age** para secretos. ✅
- [x] Se arranca por **Fase 0** (cerrar inventario, solo lectura). ✅ **cerrada 2026-07-04**
- [x] App piloto para la Fase 4: **mini**. ✅

*Plan aprobado — 2026-07-04. Ejecución por fase, una app a la vez, con backup y rollback.*
