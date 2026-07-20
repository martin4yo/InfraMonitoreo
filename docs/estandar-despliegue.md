# Estándar de Despliegue de Aplicaciones (v1)

> **Estado: OFICIAL — adoptado 2026-07-05 (Fase 2).** Formaliza el §3 del
> [plan de estandarización](./plan-estandarizacion-y-redespliegue.md) como la convención
> normativa contra la cual se migran (Fases 4–6) y redespliegan (Fases 7–8) todas las apps propias.
>
> Regla de oro: **toda app propia converge a este molde, sin excepción.** Cuando una app necesita
> algo extra (runtime adicional, dependencia externa), se agrega un **hook declarado en su
> manifiesto** — no se sale del molde. Solo apps de **tercero** (evolution-api) quedan fuera, con
> setup separado documentado.
>
> Lenguaje normativo: **DEBE** = obligatorio · **DEBERÍA** = recomendado salvo justificación
> registrada · **PUEDE** = opcional.

## 0. Alcance y no-alcance

- **Aplica a:** apps propias de los servers `axioma`, `clubix`, `axiodemo`.
- **No aplica a:** `dev-1` (entorno de test) y `evolution-api` (tercero → runbook aparte).
- **Runtime fijo del entorno:** **Node + PM2 nativo**. No se usa Docker (decisión del plan §1).

---

## 1. Convención de nombres

Sea `<app>` el nombre canónico de la app en minúsculas, sin espacios ni guiones bajos
(ej. `mini`, `parse`, `clubix`, `mediflow`).

| Elemento | Valor | Ejemplo (`mini`) |
|---|---|---|
| Usuario del sistema | `<app>app` | `miniapp` |
| Grupo | `<app>app` | `miniapp` |
| Directorio de código | `/var/www/<app>/` | `/var/www/mini/` |
| Proceso PM2 (`name`) | `<app>` (o `<app>-backend`/`<app>-web` si hay varios) | `mini` · `clubix-backend` |
| Servicio systemd | `pm2-<app>app.service` | `pm2-miniapp.service` |
| Vhost nginx | `/etc/nginx/sites-available/<app>` | `/etc/nginx/sites-available/mini` |
| Stanza pgBackRest | nombre de la DB / stanza existente | `mini_db` |

**Reglas:**
- El nombre del proceso PM2 **DEBE** ser `<app>` (sin sufijo `app`), para que `pm2 list` sea legible.
  Apps con varios procesos **PUEDEN** usar `<app>-backend` / `<app>-web` (ej. clubix ya usa
  `clubix-backend`) — el patrón es igual de legible y no requiere renombrar procesos existentes.
- El usuario **DEBE** ser `<app>app`. El usuario **NUNCA** debe ser `root`, `axiomacloud` ni
  compartido entre apps.

---

## 2. Usuario dedicado

Cada app **DEBE** correr bajo su propio usuario `<app>app`:

- Sin shell de login (`--shell /usr/sbin/nologin`) y sin contraseña.
- Home = el directorio de código o `/var/www/<app>` (para que PM2 escriba `~/.pm2` ahí).
- Dueño de **todo lo suyo**: código, `.env`, `node_modules`, logs de PM2.
- **NO** pertenece a `sudo` ni a grupos con privilegios.

```bash
# Crear usuario dedicado (idempotente)
id miniapp &>/dev/null || useradd --system --create-home \
  --home-dir /var/www/mini --shell /usr/sbin/nologin miniapp
```

**Prohibido:** correr una app como `root`. (Estado inicial: corporate-backend, checkpoint las
únicas remanentes tras la Fase 1; se corrigen en Fase 5.)

### 2.1 Migrar una app existente a su usuario dedicado

> Reglas destiladas de dos incidentes reales (2026-07-20): mini en axioma dio **500 en producción** al
> reiniciarse, y **checkpoint-web estuvo 3 días en crash loop** (108k reinicios) por una migración
> abandonada en enero. En ambos casos la causa fue **la misma**: el `.env` quedó con el owner viejo.

1. **El `chown` del `.env` va en el MISMO paso que el cambio de usuario.** Nunca en pasos separados:
   un `.env` con owner viejo **no rompe el proceso vivo** (el descriptor ya está abierto) — rompe el
   **próximo arranque**. La bomba puede quedar latente días.
2. **El `chown` debe cubrir los paths de log declarados en el ecosystem**, que suelen estar **fuera de
   `/var/www`** (p. ej. `/var/log/<app>` en `out_file`/`error_file`). Si el usuario nuevo no puede
   escribir ahí, **PM2 falla al arrancar**. Revisar el ecosystem, no solo el árbol de la app.
3. **Verificar contra el usuario CONFIGURADO, no contra el proceso vivo**: `pm2 jlist` del PM2_HOME
   correcto y `User=` de la unit systemd. `sudo -u <usuario> test -r <.env>` debe dar OK.
4. **Criterio de cierre: `restart_time` estable tras 60 s.** Que la app "esté online" no alcanza —
   un crash loop también reporta `online` entre reinicios. Este chequeo es el que habría cazado
   checkpoint-web en enero. Ojo: `restart_time`/`pm_uptime` describen el **proceso actual**, no la
   historia de arranques (un `pm2 delete`+`start` reinicia el contador).
5. **nginx necesita traverse**: las rutas que sirve como estáticos (`/var/www/<app>`, `frontend/`,
   `frontend/dist/`) van en **`755`**, no `750`, o `www-data` queda afuera y **se cae el sitio**.
   Verificar con `sudo -u www-data test -r .../index.html` en la misma pasada del `chmod`.
6. **Correr los comandos PM2 desde un cwd neutro** (`/tmp`). Parado en el home del usuario viejo, el
   `pm2 start` falla con `spawn EACCES` — engañoso, porque parece un problema del binario de node.
7. **`chown -R` no sigue symlinks**: normalizar aparte con `chown -h` (típicamente
   `node_modules/.bin/*`).
8. **Si el deploy es por git**, verificar que el usuario nuevo pueda autenticar contra el remoto
   (deploy key propia en su `~/.ssh`, no en el home del usuario viejo) y configurar `safe.directory`.
   Un árbol migrado con `.git` del owner viejo **bloquea el deploy** (la app sigue corriendo con
   código viejo); al revés, un `pull` del usuario viejo sobre árbol nuevo **rompe la app en el
   próximo restart**.
9. **Sacar del working tree los datos de runtime** (uploads de usuarios): si viven dentro del repo,
   un `git clean -fd` los borra.
10. **Los uid pueden diferir entre servers** para el mismo `<app>app` (p. ej. `miniapp` es 1002 en
    axioma y 1005 en dev-1) → un `rsync -a`/restore cruzado asigna owners equivocados.

---

## 3. Estructura de directorios

```
/var/www/<app>/
  .env                    # config CIFRADA en repo de secrets (SOPS); en claro solo en el server
  ecosystem.config.js     # arranque PM2 (formato fijo, ver §4)
  <código de la app>      # git clone del repo
  frontend/dist/          # build del frontend, SI la app tiene frontend (default apps nuevas)
  node_modules/           # generado por npm install (no versionado)
```

- El código **DEBE** ser un `git clone` de un repo remoto con credencial conocida (deploy key SSH
  o HTTPS con token). Apps sin remote configurado (elore, hub) **DEBEN** resolver esto antes de
  ser redesplegables (bloqueante de Fase 7).
- **Layout de código.** Lo que el estándar exige NO es un nombre de carpeta fijo, sino que el
  layout esté **declarado en el manifiesto** y sea reproducible por el redespliegue. Concretamente:
  - **Apps nuevas** **DEBERÍAN** usar `frontend/dist` para el build y una carpeta de backend clara.
  - **Apps existentes** con otro layout (ej. clubix: `server/` + `client/dist`) son **conformes**
    tal cual, siempre que declaren su layout real en el manifiesto:
    `BACKEND_DIR`, `FRONTEND_DIST` y, si aplica, la ruta de `uploads`/datos de usuario. **No se
    renombra en disco** (evita tocar ecosystem + vhosts + rutas de código sin beneficio funcional).
  - El manifiesto es la fuente de verdad del layout; el redespliegue lo lee de ahí.
- Owner recursivo: `chown -R <app>app:<app>app /var/www/<app>`.
- **TODO el árbol `/var/www/<app>` DEBE ser `<app>app:<app>app`, sin excepción.** Es común que un
  `git`, `npm install` o `prisma generate` corrido como `root` (o por otro usuario en un deploy
  previo) deje archivos con owner `root` mezclados → la app **no puede leerlos/escribirlos** y falla
  de formas confusas (build a medias, cliente Prisma que no se regenera, `EACCES`). **Como último
  paso del deploy/redeploy, SIEMPRE re-aplicar el `chown -R` y verificar que quede en cero:**
  ```sh
  chown -R <app>app:<app>app /var/www/<app>
  find /var/www/<app> -not -user <app>app | head    # DEBE no imprimir nada
  ```
  Regla de oro: **nunca correr `git`/`npm`/`prisma` como root** dentro de `/var/www/<app>`; usar
  siempre `sudo -u <app>app`. Si igual pasó, el `chown` final lo corrige.

Ejemplo de declaración de layout en el manifiesto:

```sh
# clubix.manifest.sh (extracto — layout histórico, conforme por declaración)
BACKEND_DIR="server"              # cwd del proceso PM2  → /var/www/clubix/server
FRONTEND_DIST="client/dist"       # root de nginx        → /var/www/clubix/client/dist
UPLOADS_DIR="server/uploads"      # datos de usuario servidos por nginx (alias)
```

---

## 4. Arranque: PM2 + ecosystem

- El arranque **DEBE** definirse en `ecosystem.config.js` (extensión **`.js`**, no `.cjs`).
- El archivo **DEBE** vivir en `/var/www/<app>/ecosystem.config.js`.
- El `name` del proceso **DEBE** ser `<app>` (§1).

Plantilla mínima (ajustar `script`, `cwd`, puerto por app):

```js
// /var/www/<app>/ecosystem.config.js
module.exports = {
  apps: [
    {
      name: '<app>',
      script: './dist/server.js',      // o 'src/index.js', 'npm', etc. según la app
      cwd: '/var/www/<app>',
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'production',
        PORT: 5300,                     // puerto documentado en el manifiesto
      },
      max_memory_restart: '512M',
    },
  ],
}
```

Apps con **frontend + backend separados** (parse, hub) **PUEDEN** declarar dos entradas en `apps[]`
(ej. `parse` backend `5100` + `parse-web` front `8087`), documentando ambos puertos en el manifiesto.

---

## 5. Boot: systemd

El arranque en boot **DEBE** ir por systemd, generado con el helper de PM2:

```bash
# Como el usuario de la app (genera pm2-<app>app.service y lo habilita)
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u miniapp --hp /var/www/mini
# Tras dejar la app corriendo bajo su usuario:
sudo -u miniapp pm2 save         # persiste la lista → ~miniapp/.pm2/dump.pm2
sudo systemctl enable pm2-miniapp.service
```

**Verificación de conformidad:** `systemctl is-enabled pm2-<app>app.service` → `enabled`, y un
reinicio del servicio **DEBE** levantar la app bajo `<app>app` (no bajo otro usuario).

---

## 6. Configuración: `.env` + secretos

- La config de runtime **DEBE** vivir en `/var/www/<app>/.env` (leída por la app o por PM2).
- El `.env` **DEBE** estar versionado **CIFRADO con SOPS+age** en el repo de secrets (Fase 3).
  Nunca se commitea en claro. El diff muestra *qué* variable cambió, no su valor.
- La **clave age** se custodia **fuera de banda** (gestor de contraseñas), nunca en el repo.
- En el server, el `.env` en claro **DEBE** ser `chmod 600`, owner `<app>app`.
- El redespliegue (Fase 7) descifra el `.env` con SOPS al reinstalar.

> Detalle operativo del cifrado/descifrado y estructura del repo de secrets: se define en la
> **Fase 3**. Este estándar solo fija que **el `.env` va cifrado en repo, con clave age fuera de banda**.

---

## 7. Web: nginx

- Cada app con dominio propio **DEBE** tener un vhost en `/etc/nginx/sites-available/<app>` con
  **symlink** en `sites-enabled` (nunca un archivo regular suelto en `sites-enabled`).
- El backend se expone por `proxy_pass` al puerto local documentado; el frontend estático se sirve
  por `root` + `try_files`.
- Un cambio de vhost se aplica con `nginx -t && systemctl reload nginx` (**sin corte**).

Plantilla mínima (backend Node tras nginx):

```nginx
# /etc/nginx/sites-available/<app>
server {
    server_name <dominio>;

    location / {
        proxy_pass http://127.0.0.1:<puerto>;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # TLS gestionado por certbot (§8)
    listen 443 ssl;
    # ssl_certificate / ssl_certificate_key insertados por certbot
}
```

Frontend estático (checkpoint, corporate): `root /var/www/<app>/frontend/dist;` +
`try_files $uri $uri/ /index.html;`, sin `proxy_pass`.

---

## 8. TLS

- El certificado **DEBE** ser Let's Encrypt, emitido y renovado con `certbot`.
- Método preferido: `--webroot` con `/var/www/certbot`, o el plugin nginx.
- La renovación automática **DEBE** estar activa (timer de certbot). Emitir/renovar **no** produce
  downtime de la app.

---

## 9. Base de datos

- El rol de conexión de la app **DEBE** ser `<app>user` (el del `DATABASE_URL`), y **DEBE ser
  OWNER de la base y de todos sus objetos** (tablas, secuencias, tipos, schema) — no basta con
  `GRANT`. Full ownership evita el bug recurrente: cuando un `prisma migrate`/`db push` se corre
  como otro rol (ej. `postgres`), las tablas creadas quedan con ese owner y `<app>user` pierde
  acceso → `permission denied for table X` en runtime. Con ownership, `<app>user` puede correr
  migraciones y DDL sin depender de re-otorgar grants.

  ```sql
  -- Estándar: <app>user dueño de todo (idempotente, correr como postgres)
  ALTER DATABASE <app>_db OWNER TO <app>user;
  ALTER SCHEMA public OWNER TO <app>user;
  DO $$ DECLARE r RECORD; BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
      EXECUTE format('ALTER TABLE public.%I OWNER TO <app>user', r.tablename); END LOOP;
    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema='public' LOOP
      EXECUTE format('ALTER SEQUENCE public.%I OWNER TO <app>user', r.sequence_name); END LOOP;
    FOR r IN SELECT t.typname FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
             WHERE n.nspname='public' AND t.typtype='e' LOOP
      EXECUTE format('ALTER TYPE public.%I OWNER TO <app>user', r.typname); END LOOP;
  END $$;
  ```
  > **Regla operativa:** correr migraciones/`db push` **como `<app>user`** (no como `postgres`).
  > Si por permisos hubo que correrlas como `postgres`, re-aplicar el bloque de arriba después.

- Cada app con DB propia **DEBE** tener su base respaldada por **una stanza pgBackRest** (ya
  existe el backup + el restore drill; ver [DRP](./disaster-recovery-plan.md) y
  [restore-drill-procedure](./restore-drill-procedure.md)).
- El redespliegue restaura la DB desde pgBackRest reutilizando la lógica de `70-restore-drill.sh`.
- La versión de Postgres y la stanza se documentan en el manifiesto de la app.

---

## 10. Runtime Node

- La **versión de Node se fija por app** en su manifiesto (no se asume la global del server).
- Divergencia actual conocida: axioma/clubix **v20.20.2**, axiodemo **v22.22.2** (axio necesita v22).
- El redespliegue instala la versión declarada (nvm/nodesource) antes del `npm install`.

---

## 11. Hooks (dependencias/runtime extra)

Cuando una app propia necesita algo más que Node+PM2, se declara un **hook** en su manifiesto —
**no** se saca del molde. Ejemplo canónico: **axio-ml**.

- `axio-ml` (parte de `axio`): servicio **Python/uvicorn** en `/opt/axio-ml-service` (puerto 8001)
  con **ollama** (~31 GB en 8 modelos). Hook = instalar ollama + `ollama pull` de los modelos +
  levantar el venv Python. Los modelos **NO** se respaldan: se re-descargan (reproducible).
- El backend Node de `axio` va por el molde común; solo `axio-ml` agrega el hook.
- Su owner (`axiomacloud` hoy) se normaliza a un usuario dedicado en la Fase 6.

---

## 12. Tercero: evolution-api (fuera del molde)

- `evolution-api` (EvolutionAPI) **NO** se fuerza al molde común.
- Tiene su propio **runbook de reinstalación** con sus dependencias y esquema (Fase 6).
- Se documenta como hook invocable desde el redespliegue, pero con procedimiento separado.

---

## 13. Checklist de conformidad (por app)

Una app está "en el estándar" cuando **todo** esto es verdadero:

- [ ] Corre bajo usuario dedicado `<app>app` (no root, no compartido) — `ps -o user= -C node`
- [ ] Código en `/var/www/<app>/`, **todo** owner `<app>app:<app>app` — `find /var/www/<app> -not -user <app>app` no imprime nada
- [ ] DB: rol `<app>user` es **owner** de la base y de todas las tablas/secuencias/tipos — `SELECT tableowner FROM pg_tables WHERE schemaname='public'` todo `<app>user`
- [ ] Repo git remoto configurado con credencial conocida — `git -C /var/www/<app> remote -v`
- [ ] `ecosystem.config.js` (`.js`) con `name: '<app>'`
- [ ] `systemctl is-enabled pm2-<app>app.service` → `enabled`
- [ ] Reinicio del servicio levanta la app bajo `<app>app` (boot test)
- [ ] `.env` en `/var/www/<app>/.env` (`chmod 600`, owner `<app>app`) y **cifrado en repo de secrets**
- [ ] Layout de código declarado en el manifiesto (`frontend/dist` por defecto, o `BACKEND_DIR`/`FRONTEND_DIST` reales)
- [ ] Vhost en `sites-available/<app>` + symlink en `sites-enabled`
- [ ] Cert Let's Encrypt activo con renovación automática (si tiene dominio)
- [ ] DB respaldada por stanza pgBackRest
- [ ] Versión de Node fijada en el manifiesto
- [ ] Hooks extra (si aplica) declarados en el manifiesto

---

## 14. Estado de conformidad inicial (línea base 2026-07-05)

Referencia rápida de cuán lejos está cada app del molde (detalle en §2 del plan). Se actualiza a
medida que avanzan las Fases 4–6.

| App | Owner OK | ecosystem `.js` | Remote git | Desvío principal |
|---|---|---|---|---|
| parse | ✅ | ✅ | ✅ | doble puerto a documentar |
| clubix | ✅ | ✅ | ✅ | conforme · layout `server/`+`client/dist` declarado en manifiesto (no se renombra) |
| mediflow | ✅ | ✅ | ✅ | ajustes menores |
| axio-backend | ✅ | — | ✅ | molde común (Fase 6) |
| elore | ✅ | ✅ | ⚠ sin remote | crear repo remoto (bloqueante F7) |
| hub | ✅ | ✅ | ⚠ sin remote | crear repo remoto (bloqueante F7) |
| mini | ✅ | ⚠ `.cjs` | ⚠ repo = AxiomaWeb | `.cjs`→`.js` + repo propio (piloto F4) |
| axio-ml | ⚠ `axiomacloud` | n/a (Python) | ✅ | owner + hook ollama (F6) |
| axioma-corporate | ⚠ backend root | — | ✅ | sacar de root (F5) |
| checkpoint | ⚠ estático root | n/a (estático) | ✅ | sacar de root (F5) |

---

*Estándar v1 — Fase 2 del plan de estandarización. Cambios al molde se versionan aquí
(v1 → v2 …) y se registran en el tracker.*
