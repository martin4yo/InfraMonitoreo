# DRP de Aplicación — Drill: restaurar hub en axioma-drp

> **Encuadre (el "qué recuperamos" vs el "cómo lo validamos").**
> El objetivo del DRP de aplicaciones es **recuperar un servidor entero** — cuando cae un host
> (p.ej. axioma), hay que levantar **todas sus apps + el cluster PG completo + nginx + PM2** en
> hardware nuevo. Ese es el desastre real (ver escenarios B/C del [DRP de DB](./disaster-recovery-plan.md)):
> nadie pierde una sola app y deja el resto sano.
>
> Pero **construimos y validamos app por app.** Cada app se prueba como una unidad reusable de
> restore (código + build + PM2/systemd + vhost nginx + su base recortada del cluster). **hub es el
> primer drill** y define el procedimiento por-app que luego se repite para las demás. En resumen:
> **se recupera servidor-entero, se valida app-por-app.** El trabajo de hub es el ladrillo; el DRP
> por-servidor es la pared. Ver la **matriz de escenarios** más abajo para saber qué cubre cada nivel.
>
> **Qué es este drill puntual.** Checklist marcable y **fuente de verdad del avance** del primer
> drill: recuperar hub **completa** en un server distinto del suyo (**axioma-drp**), como si hub se
> hubiera perdido y hubiera que reinstalarla de cero.
>
> **Cómo se usa.** Cada paso tiene estado marcable. Se tilda a medida que se ejecuta y **nunca se
> rehace una tarea ya `[x]`**. Al retomar en otra sesión, este doc dice qué está hecho, qué está en
> curso y qué falta. Convención: `[ ]` pendiente · `[~]` en curso · `[x]` hecho · `[!]` bloqueado.
>
> **Regla de oro.** Cada paso marcado **⚠ INVASIVO** modifica axioma-drp y **requiere OK explícito
> del usuario antes de ejecutar**. Aprobar un paso NO aprueba el siguiente. Una cosa a la vez.
> axioma-drp es NO productivo → el riesgo es solo sobre el drill, no sobre producción; aun así se
> respeta el freno paso a paso.
>
> Relacionado: [disaster-recovery-plan.md](./disaster-recovery-plan.md) (DRP de DB),
> [estandar-despliegue.md](./estandar-despliegue.md) (9 pasos del molde),
> [plan-trabajo-estandarizacion.md](./plan-trabajo-estandarizacion.md) (Fase 4 — hub revivida).

---

## Matriz de escenarios de recuperación — qué nivel aplica

> Cuatro escenarios, clasificados por **qué componente se rompió** (base / app / ambos / host entero),
> de menor a mayor alcance. **Este drill prueba el escenario 3 (app + base de una app)**, que es la
> composición de los escenarios 1 y 2 sobre una misma app. El escenario 4 (servidor entero) se compone
> repitiendo el escenario 3 por cada app + un restore único del cluster.

| # | Qué se rompió | Qué se recupera | NO se toca | Fuente | Procedimiento |
|---|---|---|---|---|---|
| **1 — Solo la base** | La DB de una app se corrompió/borró; **el código, PM2 y nginx están sanos** y el resto de las apps del host siguen andando | **Solo esa base** (p.ej. `hub_db`) | Código, build, PM2, nginx, y las otras 10 bases del cluster | pgBackRest (repo1/R2) | **Restore quirúrgico de base** — sección E. Restore a PGDATA aislado → `pg_dump <base>` → `pg_restore` sobre el PG vivo. La app sigue con su binario; solo se le repone la data. |
| **2 — Solo la app** | Se corrompió/perdió el **código o el servicio** de una app (deploy roto, binarios dañados, PM2/nginx caídos), pero **la base está intacta y con datos vigentes** | Código + build + PM2/systemd + vhost nginx | **La base** (se conecta a la que ya existe, sana) | Git (código) + SOPS (.env) | **Redeploy de app** — sección F. Es el lib-redeploy sin el paso 4 (restore de DB): clone/build/env/PM2/nginx apuntando a la base viva existente. Equivale a la Fase 4 de estandarización. |
| **3 — App entera (app + base)** | Se perdió la app **completa** — código y base — pero el server sigue en pie, o se reinstala de cero en otro host | Código + build + PM2/systemd + vhost nginx **+ su base** | Las otras apps y bases del host | Git + SOPS + pgBackRest | **Este drill** (secciones A–D, los 9 pasos completos). Es escenario 2 **+** escenario 1 sobre la misma app. hub es el piloto. |
| **4 — Servidor entero** | Cae el host completo (escenarios B/C del DRP de DB): se pierden **todas** sus apps y su cluster PG | Todas las apps del host + el **cluster PG completo** (todas las bases, no recortadas) + nginx + PM2 | — (se recupera todo) | Git + SOPS + pgBackRest (restore del cluster una sola vez) | Repetir el escenario 3 por cada app, pero restaurando el **cluster completo una vez** (sin el recorte pg_dump de G3) y saltando la creación individual de bases. Drill propio, más pesado — pendiente, posterior a validar varias apps a escenario 3. |

**Cómo se componen los escenarios:**
- **1 y 2 son las dos mitades independientes de una app:** el escenario 1 repone *datos* (base) sin tocar el binario; el escenario 2 repone el *binario* (código+servicio) sin tocar la base. Cada uno se puede necesitar por separado, y por eso cada uno tiene su runbook (E y F).
- El **escenario 3 (este drill) = escenario 2 + escenario 1** sobre la misma app: los pasos 1–3, 5–9 son el redeploy de app (escenario 2, sección F) y los pasos 4.1–4.6 son el restore de base (escenario 1, sección E). Validar hub a escenario 3 valida también los dos sub-casos por separado.
- El **escenario 4 reutiliza el escenario 3:** mismo procedimiento de app por cada una, cambiando solo el paso 4 por un restore del cluster completo **una vez** para todo el host en lugar del recorte por-base. Lo que se prueba de nuevo en el 4 es el restore del cluster entero (las 11 bases) y la orquestación de N apps.

**Estado global del drill:** `[~] relevamiento hecho — pendiente OK para ejecutar` · Arranque: 2026-07-18

---

## A. Estado de axioma-drp como destino (relevado 2026-07-18, solo lectura)

| Componente | Estado en axioma-drp | ¿Sirve para el drill? |
|---|---|---|
| SSH / usuario | `axiomacloud`, puerto **22**, `sudo -n` OK | ✅ |
| OS | Ubuntu **22.04.5 LTS**, kernel 5.15 | ✅ (axioma es la misma familia) |
| Disco | LVM 64 G, **52 G libres** (15 % usado) | ✅ sobra (hub_db ~15 MB + build) |
| **PostgreSQL** | **14.23** (PGDG), `active`, listen `localhost`, solo base `postgres` | ✅ **matchea PG14 de AxiomaCloudProd** |
| **pgBackRest** | **2.58.0**, `/etc/pgbackrest.conf` con `[global]` repo1=**S3/R2** + `[AxiomaCloudProd]` (`pg1-path=/var/lib/postgresql/14/main`) | ✅ **ya ve la stanza en R2** (`pgbackrest info --stanza=AxiomaCloudProd` → status ok, full 20260621 + incrementales) |
| **Node / npm / PM2** | **ausentes** (`node: command not found`) | ❌ **falta instalar** (Node 20.20.2 + PM2) |
| repo apt nodesource | **no presente** (solo `netdata.sources`, `pgdg.list`) | ❌ agregar antes de instalar Node |
| **nginx / certbot** | **ausentes** (`nginx: command not found`, `inactive`) | ❌ **falta instalar** |
| ufw | active, default-deny; abiertos **22, 80, 443** (v4+v6) | ✅ 80/443 ya abiertos para nginx |
| Netdata | v2.10.4 claimed, `:19999` local | ✅ (no afecta el drill) |
| Residuos hub/axioma | **ninguno** — no hay `/var/www`, no existe `hubapp`, sin procesos PM2 | ✅ server limpio |

**Lectura clave:** axioma-drp ya trae la mitad pesada resuelta — **PG14 + pgBackRest apuntando a
la stanza correcta en R2**. El restore de `hub_db` es directo. Falta la capa de app (Node/PM2,
nginx/certbot) y el usuario `hubapp`.

> **Ojo — el restore de pgBackRest trae el CLUSTER COMPLETO de AxiomaCloudProd (11 bases, ~547 MB),
> no solo `hub_db`.** Para un DRP *de aplicación* querés solo `hub_db`. Dos caminos (se decide en el
> paso 4): **(4a)** restore del cluster completo a un `PGDATA` temporal aislado → `pg_dump hub_db` →
> `pg_restore` en el PG14 principal de drp (recomendado, deja el PG de drp limpio con solo hub_db);
> **(4b)** restore del cluster completo *sobre* el PG14 principal de drp (más simple pero deja las 11
> bases; aceptable en un server de drill descartable). Recomendado: **4a**.

---

## B. Despliegue de hub a replicar (fuente de verdad — relevado 2026-07-18 en axioma)

| Aspecto | Valor real en axioma |
|---|---|
| Repo git | `git@github.com:AxiomaCloud/ProHub.git` (SSH), branch **`main`**, HEAD `311a6ed` |
| ⚠ Nota repo | `package.json` declara `url: github.com/AxiomaCloud/Hub.git` (metadato viejo); el **origin real es ProHub**. hub y axio comparten ProHub pero son proyectos distintos (`name: hub-monorepo`). |
| Layout | **monorepo npm workspaces** (`backend`, `frontend`, `shared`) — código en `/var/www/hub` |
| Node | **v20.20.2** (nodesource) — igual que axioma |
| Build | `npm ci` **desde la raíz** + `prisma generate` **desde la raíz** (Prisma 6.19 local; NO usar npx→Prisma 7) + `npm run build` (backend `tsc`→`backend/dist/server.js`, frontend `next build`→`frontend/.next`) |
| Arranque | `ecosystem.config.js` con **2 procesos**: `hub-backend` (cwd `backend`, `dist/server.js`, **:5200**) + `hub-frontend` (cwd `frontend`, `next start -p 8089`, **:8089**) |
| PM2 owner | usuario **`hubapp`** (uid 993), `PM2_HOME=/home/hubapp/.pm2` |
| systemd | `pm2-hubapp.service` **enabled + active** |
| Puertos | backend **5200** (127.0.0.1), frontend **8089** (0.0.0.0 vía next) |
| Logs | `/var/log/hub/{backend,frontend}-{out,error}.log` |
| Vhost nginx | `/etc/nginx/sites-available/hub` (symlink en enabled): `hub.axiomacloud.com`→:8089 (front) + `api.hub.axiomacloud.com`→:5200 (backend, incluye `wss://`); usa `snippets/block-scanners.conf` |
| Certs | Let's Encrypt `hub.axiomacloud.com` (SAN cubre api.hub) |
| `.env` | `backend/.env` (600, hubapp) + `frontend/.env` (600) — **cifrados en infra-secrets**: `env/axioma/hub-backend.env` (28 vars) + `hub-frontend.env` (2 vars), descifran OK |
| DB | `hub_db` en stanza **AxiomaCloudProd** (axioma, PG14), **15 MB**; rol **`hubuser`** = owner de la base + **87/87 tablas** ✅ |

**Variables `.env` que definen el drill (valores no sensibles):**
- backend: `DATABASE_URL=postgresql://<user>:<pass>@localhost:5432/hub_db`, `PORT=5200`, `NODE_ENV=production`, `FRONTEND_URL=https://hub.axiomacloud.com`
- frontend: `NEXT_PUBLIC_API_URL=https://api.hub.axiomacloud.com`, `NEXT_PUBLIC_WS_URL=wss://api.hub.axiomacloud.com`
- Otras (S3/AWS, Redis, Anthropic, Parse, WhatsApp/Twilio, SMTP, JWT): se colocan tal cual desde SOPS; **no hace falta que funcionen para probar el drill** (login + navegación + conexión a DB alcanzan como criterio de éxito).

---

## C. Gaps y riesgos para restaurar hub en axioma-drp

| # | Gap / Riesgo | Impacto | Mitigación en el plan |
|---|---|---|---|
| G1 | **Node/npm/PM2 ausentes** en drp | no arranca la app | Paso 2: instalar Node 20.20.2 (nodesource) + PM2 global |
| G2 | **nginx/certbot ausentes** | no hay reverse proxy ni TLS | Paso 8: instalar nginx (+ vhost); certbot **NO se usa en el drill** (ver G4) |
| G3 | **pgBackRest restore trae 11 bases**, no solo hub_db | pisaría/llenaría el PG de drp | Paso 4a: restore a `PGDATA` temporal aislado → `pg_dump hub_db` → `pg_restore` |
| **G4** | **DNS/certs: los `server_name` apuntan a la IP de axioma, no a drp.** El cert LE real no se puede reemitir para drp (validación ACME iría a axioma). Además **el frontend Next hornea `NEXT_PUBLIC_API_URL=https://api.hub.axiomacloud.com` en build-time** | el front pega a la api de **producción**, no a la de drp | **Decisión de drill (a confirmar con el usuario):** resolver `hub.axiomacloud.com` + `api.hub.axiomacloud.com` a la **IP de drp vía `/etc/hosts` del cliente que prueba** (no DNS público) + **cert self-signed** en drp para esos server_name. Así el build de front no cambia y la validación es realista. Alternativa: server_name `hub-drp.axiomacloud.com` + rebuild del front con esa API URL (más trabajo, cambia el artefacto). **Recomendado: /etc/hosts + self-signed.** |
| G5 | **Acceso a backups desde drp** | sin backup no hay restore | ✅ **ya resuelto** — drp ve la stanza en R2 (repo1=S3). Nada que hacer. |
| G6 | **Credenciales R2 en `/etc/pgbackrest.conf` de drp** | si el token viejo quedó, falla | ✅ verificado: config presente y `pgbackrest info` funciona → token vigente. (Recordatorio: si se rota el token R2, drp es un **6.º archivo** a actualizar además de los 5 conocidos.) |
| G7 | **`.env` desde SOPS** | la app no levanta sin config | Paso 5: descifrar con la clave age + colocar 600/hubapp. `DATABASE_URL` apunta a `localhost:5432/hub_db` → sirve tal cual en drp. |
| G8 | **hubuser (rol de la app) no existe en el PG de drp** | login/queries fallan por auth | El `pg_dump -Fc` de hub_db **no crea el rol**; hay que **crear `hubuser` en drp** con el password del `DATABASE_URL` + hacerlo owner (bloque §9 del estándar). Paso 4c. |
| G9 | **Desfase código↔DB conocido** (checkout más viejo que hub_db) | no rompe (Prisma ignora columnas extra) | mismo comportamiento que en axioma; no se toca el esquema salvo OK |
| G10 | **prisma migrate/db push** | podría alterar esquema | **NO se corre.** Solo `prisma generate`. `migrate status` (lectura) para diagnosticar. |

---

## D. Plan de restore paso a paso (mapeado a los 9 pasos del lib-redeploy)

> Orden estricto. Los pasos **⚠ INVASIVO** requieren **OK explícito** antes de ejecutar.
> Los pasos de **verificación/lectura** se hacen sin pedir permiso e informan resultado.
> Antes de empezar la tanda invasiva: acordar **ventana** (drp es no productivo → flexible).

### Fase 0 — Preparación / red de seguridad
- [ ] 0.1 (lectura) Snapshot del estado inicial de drp (`df -h`, `ss -tlnp`, lista de bases PG) para rollback/registro
- [ ] 0.2 (lectura) Confirmar con `pgbackrest info --stanza=AxiomaCloudProd` que el último backup es reciente y `status: ok`
- [ ] 0.3 Acordar con el usuario la **decisión G4** (hosts+self-signed vs server_name alternativo) y la **decisión G3** (4a vs 4b). Sin esto no se arranca la Fase 4/8.

### Paso 1 (lib-redeploy #1) — Usuario `hubapp`
- [ ] 1.1 ⚠ **INVASIVO** — crear usuario `hubapp` en drp: `useradd --system --create-home --home-dir /var/www/hub --shell /bin/bash hubapp` (home = code dir, para `~/.pm2`)

### Paso 2 (lib-redeploy #2) — Runtime Node + PM2
- [ ] 2.1 ⚠ **INVASIVO** — agregar repo nodesource 20.x + `apt install nodejs` (→ v20.20.2, igual que axioma)
- [ ] 2.2 ⚠ **INVASIVO** — `npm install -g pm2`
- [ ] 2.3 (lectura) verificar `node -v` = v20.20.2, `pm2 -v`

### Paso 3 (lib-redeploy #3) — Traer el código (git clone)
- [ ] 3.1 ⚠ **INVASIVO** — como `hubapp`: `git clone git@github.com:AxiomaCloud/ProHub.git /var/www/hub` branch `main` (requiere **deploy key SSH** con acceso a ProHub en drp — **verificar/instalar antes**; si no hay, alternativa: `rsync` del árbol de axioma sin `node_modules`/`dist`/`.next`, documentándolo como gap del redeploy)
- [ ] 3.2 (lectura) confirmar HEAD y que `origin` = ProHub

### Paso 4 (lib-redeploy #4) — Restaurar `hub_db` desde pgBackRest ⚠ el corazón del drill
- [ ] 4.1 ⚠ **INVASIVO** — restore del cluster AxiomaCloudProd desde **repo1 (R2)** a un **PGDATA temporal aislado** (ej. `/var/lib/postgresql/drill-restore`), levantar una instancia PG14 efímera en un puerto alterno (5433) con WAL replay hasta consistencia [decisión 4a]
- [ ] 4.2 (lectura) verificar en la instancia efímera: `\l` lista `hub_db`, `SELECT count(*)` en tablas críticas
- [ ] 4.3 ⚠ **INVASIVO** — `pg_dump -Fc hub_db` desde la efímera → `pg_restore` a la instancia PG14 **principal** de drp (crea `hub_db` ahí)
- [ ] 4.4 ⚠ **INVASIVO** — crear rol **`hubuser`** en el PG principal de drp con el password del `DATABASE_URL` (de SOPS) + `ALTER DATABASE hub_db OWNER TO hubuser` + bloque de ownership de tablas/secuencias/tipos (§9 estándar) [gap G8]
- [ ] 4.5 ⚠ **INVASIVO** — parar y borrar la instancia efímera + su PGDATA temporal (limpieza)
- [ ] 4.6 (lectura) `psql -U hubuser -d hub_db -c "SELECT 1"` conecta OK

### Paso 5 (lib-redeploy #5) — `.env` desde SOPS
- [ ] 5.1 ⚠ **INVASIVO** — descifrar `hub-backend.env` + `hub-frontend.env` (clave age) y colocarlos en `/var/www/hub/backend/.env` y `/var/www/hub/frontend/.env`, `chmod 600`, owner `hubapp` (`DATABASE_URL` ya apunta a `localhost/hub_db` → sirve)

### Paso 6 (lib-redeploy #6) — Instalar deps + build
- [ ] 6.1 ⚠ **INVASIVO** — como `hubapp`, **desde la raíz**: `npm ci` (workspaces) [aprendizaje Fase 4: NO por-workspace]
- [ ] 6.2 ⚠ **INVASIVO** — **desde la raíz**: `npx prisma generate` con Prisma **6.19 local** (NO npx→7) o `npm run build`-equivalente que dispare el generate
- [ ] 6.3 ⚠ **INVASIVO** — `npm run build` (backend `tsc`→`backend/dist`, frontend `next build`→`frontend/.next`)
  - > Si se optó por server_name alternativo (G4 alternativa), acá el front hay que buildearlo con `NEXT_PUBLIC_API_URL` de drp. Si se optó por /etc/hosts+self-signed (recomendado), el build es idéntico al de axioma.
- [ ] 6.4 (lectura) confirmar `backend/dist/server.js` y `frontend/.next` existen

### Paso 7 (lib-redeploy #7) — PM2 + ecosystem + systemd
- [ ] 7.1 ⚠ **INVASIVO** — colocar/usar `ecosystem.config.js` (idéntico al de axioma: hub-backend :5200 + hub-frontend :8089) y `sudo -u hubapp pm2 start ecosystem.config.js`
- [ ] 7.2 ⚠ **INVASIVO** — `pm2 save` + `pm2 startup systemd -u hubapp --hp /var/www/hub` → `systemctl enable pm2-hubapp.service`
- [ ] 7.3 ⚠ **INVASIVO** — crear `/var/log/hub/` (owner hubapp) para los logs del ecosystem

### Paso 8 (lib-redeploy #8) — nginx + TLS
- [ ] 8.1 ⚠ **INVASIVO** — `apt install nginx`
- [ ] 8.2 ⚠ **INVASIVO** — generar **cert self-signed** para `hub.axiomacloud.com` + `api.hub.axiomacloud.com` en drp [decisión G4] (o certbot con server_name alternativo si se eligió esa vía)
- [ ] 8.3 ⚠ **INVASIVO** — colocar el vhost de hub adaptado (mismo del de axioma, apuntando al cert self-signed; sin `snippets/block-scanners.conf` si no se copia el snippet, o copiarlo) + `nginx -t` + `systemctl reload/enable nginx`

### Paso 9 (lib-redeploy #9) — Verificación (criterio de éxito del drill)
- [ ] 9.1 (lectura) `curl 127.0.0.1:5200/health` → 200 y `curl 127.0.0.1:8089/` → 200
- [ ] 9.2 (lectura) desde el cliente con `/etc/hosts`→IP drp: `https://hub.axiomacloud.com` (front) y `https://api.hub.axiomacloud.com/health` (backend) responden (cert self-signed → `-k`)
- [ ] 9.3 (lectura) **hub conecta a hub_db restaurada**: rutas que pegan a DB responden 400/401 (no 500); `POST /api/auth/login` con credencial inválida → 401 (no 500)
- [ ] 9.4 (lectura) **boot test**: `pm2 kill` + `systemctl start pm2-hubapp` → app online + health 200
- [ ] 9.5 (lectura) `find /var/www/hub -not -user hubapp` vacío (regla de owner)
- [ ] 9.6 (lectura) **medir RTO real** del drill (insumo para Fase 8 del plan de estandarización)

### Cierre
- [ ] C.1 Registrar el resultado en [drill-history.csv](./drill-history.csv) y en el DRP §7.3 (tipo "DRP-app", stanza AxiomaCloudProd, RTO real)
- [ ] C.2 Volcar aprendizajes al `lib-redeploy` / manifiesto de hub (Fase 7)
- [ ] C.3 (opcional) **teardown** de drp: parar hub, borrar `/var/www/hub`, dropear `hub_db`, remover nginx/vhost — dejar drp listo para el próximo drill de otra app
- [ ] C.4 Actualizar el estado global de este doc a `[x] drill completado`

---

## E. Runbook nivel 1 — Restore quirúrgico de una sola base (app viva, resto sano)

> **Cuándo.** Se corrompió/borró la base de UNA app (p.ej. `hub_db`) pero el servidor, el código,
> PM2 y nginx están OK, y las **otras bases del cluster siguen sirviendo tráfico real**. NO es un
> desastre de server; es cirugía sobre una base. Corresponde al **nivel 1** de la matriz.
>
> **Principio rector (del Apéndice A del [DRP de DB](./disaster-recovery-plan.md)):** `pgbackrest
> restore --stanza=<X>` trae el **cluster completo con TODAS las bases juntas**. Por eso **NUNCA se
> restaura la stanza directamente sobre el PG de producción** para arreglar una sola base — pisaría
> las otras 10, que están sanas. Se restaura a un host/instancia **aislado** y de ahí se extrae solo
> la base afectada. Estos son los mismos pasos 4.1–4.6 de este drill, pero el destino es el **PG vivo**.

- [ ] E.1 (lectura) Confirmar el daño y el **punto de restauración objetivo** (último incr previo al
      evento, o timestamp para PITR). `pgbackrest info --stanza=AxiomaCloudProd` para ver backups disponibles.
- [ ] E.2 (lectura) Anunciar ventana: **solo la app afectada** para de servir; el resto del host sigue vivo.
- [ ] E.3 ⚠ **INVASIVO (host aislado, NO el de producción)** — restore del cluster a un **PGDATA
      temporal aislado** en puerto alterno, con `--type=time`/`--target` si se necesita PITR. Puede ser
      en un host aparte (drp) o en el mismo server en un PGDATA/puerto separado — **jamás sobre el
      cluster productivo**.
- [ ] E.4 (lectura) Verificar en la instancia aislada que `<base>` tiene los datos correctos al punto objetivo.
- [ ] E.5 ⚠ **INVASIVO (producción)** — parar la app afectada; en el PG productivo, respaldar la base
      dañada (`pg_dump -Fc` a un `.dump` fechado, por si hay que revertir) y luego `DROP DATABASE` +
      `CREATE` (o restaurar a una base con sufijo y renombrar). **Solo esa base — las demás no se tocan.**
- [ ] E.6 ⚠ **INVASIVO (producción)** — `pg_dump -Fc <base>` desde la instancia aislada → `pg_restore`
      sobre el PG productivo. Reponer el rol owner si hiciera falta (nivel 1 normalmente ya lo tiene).
- [ ] E.7 ⚠ **INVASIVO** — parar y borrar la instancia aislada + su PGDATA temporal (limpieza).
- [ ] E.8 (lectura) Levantar la app; checklist post-restore del [DRP de DB §6](./disaster-recovery-plan.md)
      (conecta, tablas con filas, sin 500). Registrar RTO real.

> **Diferencia con el drill (escenario 3):** acá NO se reinstala código/PM2/nginx (están sanos) y el
> destino del pg_restore es el **PG de producción vivo**, con el recaudo extra de respaldar la base
> dañada antes de reemplazarla (E.5) y de **no rozar las otras bases**. En el drill, en cambio, el
> destino es un PG limpio en drp y se monta la app entera alrededor.

---

## F. Runbook escenario 2 — Redeploy de app con base sana (solo el binario)

> **Cuándo.** Se rompió el **código o el servicio** de una app (deploy inconcluso, build corrupto,
> PM2/nginx caídos, o hay que reinstalarla en otro host) pero **la base está intacta y con datos
> vigentes**. NO hay que restaurar datos — la app se reconecta a la base viva. Corresponde al
> **escenario 2** de la matriz. Es exactamente el **lib-redeploy sin el paso 4** (restore de DB), y
> equivale a lo que se hizo en la Fase 4 de estandarización con hub.
>
> **Principio rector:** el `.env` (`DATABASE_URL`) ya apunta a la base existente. **No se corre
> `prisma migrate` ni `db push`** — la base sana manda; el código se adapta a ella (Prisma ignora
> columnas extra). Si el desfase esquema↔código fuera real y bloqueante, es una decisión aparte, con OK.

- [ ] F.1 (lectura) Confirmar que **la base está sana**: conecta, tablas con filas, la app fallaba por
      el binario/servicio y no por datos. Si hay duda sobre los datos → esto es escenario 1 o 3, no 2.
- [ ] F.2 ⚠ **INVASIVO** — Traer el código: `git clone`/`git pull` de la rama productiva (o redeploy
      del artefacto). Requiere la deploy key con acceso al repo.
- [ ] F.3 ⚠ **INVASIVO** — Colocar `.env` desde SOPS (600, owner de la app). El `DATABASE_URL`
      apunta a la **base existente** — no se toca la DB.
- [ ] F.4 ⚠ **INVASIVO** — `npm ci` + `prisma generate` (solo generate, NO migrate) + `npm run build`,
      desde la raíz (aprendizaje Fase 4).
- [ ] F.5 ⚠ **INVASIVO** — PM2 + ecosystem + `pm2 save` + systemd enable (reponer el servicio).
- [ ] F.6 ⚠ **INVASIVO** — nginx: reponer/validar el vhost + reload.
- [ ] F.7 (lectura) Verificación: health 200, la app conecta a la base sana (queries responden, no 500),
      boot test. Registrar RTO real.

> **Diferencia con el drill (escenario 3):** acá se **saltan por completo los pasos 4.1–4.6** (todo
> el restore de base). La base ya está y con datos buenos; solo se repone el binario alrededor de ella.

---

## Registro de ejecución del drill

| Fecha | Paso | Acción | Resultado |
|---|---|---|---|
| 2026-07-18 | A/B/C | Relevamiento in-situ (drp + hub en axioma), solo lectura | ✅ estado A/B/C + gaps documentados; pendiente OK para ejecutar |
