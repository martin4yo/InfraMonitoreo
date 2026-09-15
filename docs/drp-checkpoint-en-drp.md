# DRP — Checkpoint (dev-1 → axioma-drp) · Runbook y registro del simulacro

> **Escenario que cubre:** se pierde **dev-1** (o solo checkpoint en dev-1) y hay que levantar
> **Checkpoint** en **axioma-drp** desde fuentes que **no dependen de dev-1**: código de GitHub, base de
> pgBackRest en **R2**, `.env` de **infra-secrets** (SOPS).
>
> **Cómo se usa:** las §2 a §8 son el paso a paso para hacerlo **a mano**, con los comandos listos para
> copiar. Cada paso dice **dónde** se corre (💻 equipo del operador · 🛟 axioma-drp) y con qué se
> verifica. La §12 registra la ejecución real del 2026-09-15.
>
> **Estado:** ✅ **EJECUTADO 2026-09-15 — PASS.** Checkpoint sirvió en `https://checkpointdrp.axiomacloud.com`
> desde R2 + GitHub + infra-secrets, sin tocar dev-1. Login real verificado; **teardown hecho el mismo día**.
>
> | Métrica | Valor medido |
> |---|---|
> | **RPO** | **≈ 2 min** (última transacción recuperada 08:55:11 -03, restore iniciado 08:56) |
> | **RTO de manos** (suma de pasos, sin esperas) | **≈ 20 min** — base 1 min · deps 1,5 min · build 5 min · arranque/nginx/TLS 2 min · verificación 5 min |
> | **RTO de pared** del simulacro | 41 min (08:37 → 09:18), incluye un build local fallido por la red del operador (H-7) |
> | Datos cifrados | ✅ 2/2 registros biométricos descifrados con la clave restaurada |
>
> Relacionado: [runbook general](./drp-recuperacion-axioma-en-drp.md) (axioma → drp) ·
> [drill de hub](./drp-app-hub-drill.md) (matriz de escenarios) · [DRP de DB](./disaster-recovery-plan.md) ·
> [estándar de despliegue](./estandar-despliegue.md).

---

## 0. Lo que hay que saber antes de empezar

> ⚠️ **No confundir las dos "checkpoint".** En **axioma**, `checkpoint.axiomacloud.com` es un **sitio
> estático** (vhost `checkpoint`, `/var/www/checkpoint/checkpoint`, repo `AxiomaCloud/checkpointsite`) —
> es el que figura en las [fichas de axioma](./drp-fichas-apps-axioma.md). **Este runbook es la
> aplicación Checkpoint** (RRHH / control de presencia), que corre en **dev-1** como
> `checkpointdemo.axiomacloud.com`. Son cosas distintas.

### 0.1 Ficha de la app (relevada en vivo en dev-1 el 2026-09-15)

| | dev-1 (origen) | axioma-drp (destino del simulacro) |
|---|---|---|
| **Dominio** | `checkpointdemo.axiomacloud.com` | `checkpointdrp.axiomacloud.com` |
| **Stack** | Next.js 15 con servidor custom (`tsx server.ts`), Node **20.20.2** | ídem |
| **Path** | `/var/www/checkpoint-web` (monolito, sin `backend/`/`frontend/`) | ídem |
| **Usuario** | `checkpointapp` (uid 1008, grupo suplementario `www-data`) | `checkpointapp` (uid 991) |
| **Puerto** | `127.0.0.1:8086` (loopback, detrás de nginx) | ídem |
| **PM2** | `checkpoint-web` · `npm start` · `PM2_HOME=/home/checkpointapp/.pm2` · `pm2-checkpointapp.service` | ídem |
| **Base / rol** | `checkpoint_db` (18 MB) / `checkpointuser` · `localhost:5432` directo (sin pgbouncer) | ídem |
| **Stanza pgBackRest** | **`dev-1`** (PG14) — la base vive en el cluster de dev-1, junto a otras 15 | se lee de **R2** |
| **Repo** | `git@github.com:martin4yo/checkpoint-web.git` · rama `master` | ídem |
| **Prisma** | ✅ `prisma generate` (6.x local, **no** `npx` suelto) · 5 migraciones | ídem |
| **Secretos** | `infra-secrets` → `env/dev-1/checkpoint-web.env` | ídem |
| **Nativos** | `@tensorflow/tfjs-node`, motor de Prisma, `sharp`, `lightningcss`, `@next/swc` | se instalan **en destino** |
| **Extensiones PG** | `plpgsql`, `unaccent` | ídem |

### 0.2 🔴 Tres cosas que hacen fallar la recuperación en silencio

1. **`BIOMETRIC_ENCRYPTION_KEY`.** Los embeddings faciales (`biometric_data.faceEmbeddings`) están
   cifrados por la app con AES-256-GCM. Un restore de la base devuelve **bytes cifrados**: sin esa clave
   exacta, el reconocimiento facial queda **permanentemente roto** y ningún backup lo arregla. Es el
   mismo patrón que `ENCRYPTION_MASTER_KEY` de alvera (R15).
2. **El `.env` de infra-secrets tiene que estar al día.** `src/lib/env.ts` **aborta el arranque** si
   `JWT_SECRET` tiene menos de 32 caracteres o es un valor de ejemplo. Hasta el 2026-09-15 la copia
   cifrada tenía justamente el valor de ejemplo → **la app no hubiera arrancado**. Ver hallazgo H-1.
3. **Los archivos subidos (`UPLOAD_DIR`) no están en ningún backup.** pgBackRest respalda la base, no el
   filesystem. Las filas que apuntan a archivos se restauran; los archivos no. Ver §9.

### 0.3 🔴 Regla de no-contaminación de los backups

El cluster de dev-1 tiene en su `postgresql.auto.conf`:

```
archive_mode = 'on'
archive_command = 'pgbackrest --config=/etc/pgbackrest/db.conf --stanza=dev-1 archive-push %p'
```

Un restore **hereda eso**. Si la instancia restaurada arrancara archivando, empujaría WAL de una línea
de tiempo nueva **a la stanza productiva de dev-1**. Por eso el restore se hace **siempre** con
`--archive-mode=off`, y se verifica `show archive_mode` → `off` antes de seguir.

Desde drp: **solo `restore` e `info`**. Nunca `backup`, `expire` ni `stanza-*` — el repositorio R2 es
el de producción.

### 0.4 De dónde sale cada cosa (nada depende de dev-1)

| Qué | Fuente | Acceso necesario |
|---|---|---|
| Código | GitHub `martin4yo/checkpoint-web` | llave SSH con acceso al repo (en el equipo del operador) |
| Build (`.next`) | se compila **en drp** (medido: 298 s, sin afectar las otras apps) o en el equipo del operador (§4.5) | — |
| Base | pgBackRest, stanza `dev-1`, **R2** | ya configurado en drp (`/etc/pgbackrest/pgbackrest.conf`) |
| `.env` | `infra-secrets` (SOPS + age) | clave age (`~/.config/sops/age/keys.txt`) |
| DNS | Cloudflare / DNS de `axiomacloud.com` | cuenta con permiso de edición |
| TLS | Let's Encrypt (certbot en drp) | 80/tcp alcanzable desde internet |
| Uploads | ❌ **sin fuente hoy** | ver §9 |

---

## 1. Prerrequisitos

- [x] 💻 Acceso SSH a drp: `ssh axiomacloud@170.78.75.249` y `sudo -n true` OK.
- [x] 🛟 drp con Node 20.20.2, PM2 6, nginx, certbot, PostgreSQL 14 y pgBackRest 2.59 (Fase 1 del
      [runbook general](./drp-recuperacion-axioma-en-drp.md#1-fase-1--preparar-el-stack-base-en-drp)).
- [x] 🛟 drp ve la stanza: `sudo -u postgres pgbackrest --stanza=dev-1 info` → `status: ok`.
- [x] 💻 Clave age restaurada y `infra-secrets` clonado.
- [x] 💻 Node 20 y llave SSH de GitHub en el equipo del operador.
- [x] Registro DNS `A checkpointdrp.axiomacloud.com → 170.78.75.249` (sin proxy).
- [x] 🛟 Puertos libres en drp: `ss -tln | grep -E ':(5445|8086) '` → vacío.

---

## 2. Fase 1 — Restaurar `checkpoint_db` desde R2 (instancia temporal aislada)

> **Por qué no se restaura directo sobre el PG de drp:** la stanza `dev-1` trae **16 bases**, entre ellas
> `alvera_db` (datos de salud). `--db-include=checkpoint_db` hace que pgBackRest **solo materialice esa
> base** (las demás quedan como archivos vacíos, inservibles): menos datos sensibles copiados, menos
> disco, menos tiempo. Se restaura a un PGDATA temporal en el puerto **5445**, se extrae un dump y se
> borra.

🛟 **En drp, como `axiomacloud`:**

```bash
BASE=/var/lib/postgresql/drp-checkpoint
PGDATA=$BASE/pgdata
PORT=5445
BIN=/usr/lib/postgresql/14/bin

# 1.1 PGDATA temporal vacío
sudo -u postgres mkdir -p $BASE
sudo -u postgres install -d -m 700 $PGDATA

# 1.2 Restore: SOLO checkpoint_db, archivado APAGADO (§0.3)
#     Para un punto en el tiempo: agregar --type=time --target="2026-09-15 11:00:00-03"
sudo -u postgres pgbackrest --stanza=dev-1 --pg1-path=$PGDATA \
  --db-include=checkpoint_db --archive-mode=off restore

# 1.3 Config mínima (en Ubuntu el postgresql.conf NO viaja en el PGDATA)
echo "local all postgres peer" | sudo -u postgres tee $PGDATA/pg_hba.conf
sudo -u postgres touch $PGDATA/pg_ident.conf
sudo -u postgres tee $PGDATA/postgresql.conf <<EOF
port = $PORT
listen_addresses = ''
unix_socket_directories = '/var/run/postgresql'
hba_file = '$PGDATA/pg_hba.conf'
ident_file = '$PGDATA/pg_ident.conf'
max_connections = 300      # >= al de dev-1, si no el recovery no arranca
archive_mode = off
EOF

# 1.4 Arrancar: aplica el WAL de R2 hasta el final y promueve solo
sudo -u postgres $BIN/pg_ctl start -D $PGDATA -l $BASE/pg.log -w -t 600
until [ "$(sudo -u postgres psql -p $PORT -tAc 'select pg_is_in_recovery()')" = "f" ]; do sleep 5; done
```

**Verificar (obligatorio antes de seguir):**

```bash
sudo -u postgres psql -p $PORT -tAc "show archive_mode"                         # → off
sudo -u postgres psql -p $PORT -d checkpoint_db -tAc \
  "select count(*) from pg_tables where schemaname='public'"                     # → 103 (a 2026-09-15)
sudo -u postgres psql -p $PORT -d checkpoint_db -tAc \
  "select count(*), max(migration_name) from _prisma_migrations"                 # → 5 | ..._login_con_google
grep "last completed transaction" $BASE/pg.log                                   # → define el RPO real
```

```bash
# 1.5 Dump y limpieza de la instancia temporal
sudo -u postgres $BIN/pg_dump -p $PORT -Fc -f $BASE/checkpoint_db.dump checkpoint_db
sudo -u postgres $BIN/pg_ctl stop -D $PGDATA -m fast
sudo -u postgres rm -rf $PGDATA
```

---

## 3. Fase 2 — Rol y base en el PostgreSQL de drp

El password de `checkpointuser` es el del `DATABASE_URL` del `.env` (infra-secrets). **No** escribirlo en
la línea de comandos (queda en el historial y en `ps`): usar `\password` o mandarlo por stdin.

🛟 **En drp:**

```bash
sudo -u postgres psql <<'SQL'
CREATE ROLE checkpointuser LOGIN;
\password checkpointuser
CREATE DATABASE checkpoint_db OWNER checkpointuser;
SQL

# Restore FIEL: conserva owners, triggers y grants tal como estaban en dev-1.
# NO usar --no-owner: los triggers de auditoría (solo-agregar) y los owners mixtos
# son parte del estado a recuperar, no algo a "normalizar" durante un DR.
sudo -u postgres pg_restore -d checkpoint_db --exit-on-error \
  /var/lib/postgresql/drp-checkpoint/checkpoint_db.dump
```

**Verificar:**

```bash
sudo -u postgres psql -d checkpoint_db -tAc "select tableowner, count(*) from pg_tables where schemaname='public' group by 1"
#   → checkpointuser|71  y  postgres|32   (idéntico a dev-1 al 2026-09-15; ver hallazgo H-4)
sudo -u postgres psql -d checkpoint_db -tAc "select count(*) from pg_trigger where not tgisinternal"   # → 4
# Login con la credencial REAL de la app, por TCP (prueba pg_hba + scram + password):
psql "postgresql://checkpointuser@localhost:5432/checkpoint_db" -c "select count(*) from users"
```

---

## 4. Fase 3 — Código, dependencias y build

### 4.1 🛟 Usuario y directorio

```bash
sudo useradd --system --create-home --home-dir /home/checkpointapp --shell /bin/bash checkpointapp
sudo usermod -aG www-data checkpointapp
sudo install -d -o checkpointapp -g checkpointapp -m 755 /var/www/checkpoint-web
```

### 4.2 💻 Clonar el commit a recuperar (en el equipo del operador)

```bash
mkdir -p ~/drp-build && cd ~/drp-build
git clone --branch master git@github.com:martin4yo/checkpoint-web.git
cd checkpoint-web && git log -1 --format='%h %ad %s'     # anotar el commit
```

### 4.3 💻→🛟 Subir el código fuente a drp

drp **no tiene git** ni llave de GitHub: el código viaja como tar del commit exacto.

```bash
git archive --format=tar HEAD | gzip -1 | \
  ssh axiomacloud@170.78.75.249 'sudo -u checkpointapp tar -xzf - -C /var/www/checkpoint-web'
```

### 4.4 🛟 Dependencias y Prisma **en drp** — ⏱ medido 86 s + 5 s

Se instalan **siempre en drp**: los binarios nativos (`tfjs-node`, motor de Prisma, `sharp`…) tienen que
corresponder a la glibc 2.35 del destino.

```bash
cd /tmp   # cwd neutro (estándar §2.1 regla 6)
sudo -u checkpointapp -H bash -c 'cd /var/www/checkpoint-web && npm ci --no-audit --no-fund'
sudo -u checkpointapp -H bash -c 'cd /var/www/checkpoint-web && ./node_modules/.bin/prisma generate'
```

⚠️ **No usar `npx prisma` sin `node_modules`**: baja la última Prisma (7.x) en vez de la del proyecto (6.19).
⚠️ **No correr `prisma migrate deploy` ni `db push`**: la base restaurada ya tiene el esquema del commit.
⚠️ `npm ci` completo (con devDependencies): el build las necesita (Tailwind, TypeScript).

**Verificar:**

```bash
sudo ls /var/www/checkpoint-web/node_modules/.prisma/client/ | grep '\.node$'        # → libquery_engine-debian-openssl-3.0.x.so.node
sudo ls /var/www/checkpoint-web/node_modules/@tensorflow/tfjs-node/lib/napi-v8/      # → tfjs_binding.node
```

### 4.5 Build — opción A (validada): **compilar en drp** — ⏱ medido 298 s

> ⚠️ **`NEXT_PUBLIC_APP_URL` se hornea en el build.** Tiene que ser la URL **pública final** del destino.
> Si después cambia el dominio, **hay que recompilar**.
>
> **Memoria (medido 2026-09-15, con hub, alvera y parse corriendo en drp):** mínimo **590 MB disponibles**,
> pico de swap **242 MB**, ninguna otra app reinició. El `--max-old-space-size=4096` del `package.json`
> es un techo, no una reserva. Igual, **vigilar la memoria** y cortar si baja de 300 MB:

```bash
cd /tmp
sudo -u checkpointapp -H bash -c \
  'cd /var/www/checkpoint-web && NEXT_PUBLIC_APP_URL=https://checkpointdrp.axiomacloud.com npm run build' &
while kill -0 $! 2>/dev/null; do free -m | awk '/Mem:/{print "disponible: " $7 " MB"}'; sleep 5; done
sudo ls /var/www/checkpoint-web/.next/BUILD_ID      # → debe existir
```

Si la memoria no alcanza: detener temporalmente otras apps de drp (`pm2 stop`) durante el build, o ir a la
opción B.

### 4.5-B Build — opción B: compilar en el equipo del operador y subir `.next`

> **Por qué es válido:** `.next` es JavaScript — **no contiene binarios `.node`** (verificado: 0). Los
> nativos viven en `node_modules`, que ya se instaló en drp (§4.4). Compilar con otra glibc no rompe nada.
> El build **no necesita secretos**: `env.ts` detecta `NEXT_PHASE=phase-production-build` y solo avisa.
>
> ⚠️ **Depende de la red del operador**: son ~1,8 GB de `node_modules`. En el simulacro esta vía **falló**
> por `ETIMEDOUT` tras 25 min (H-7). Por eso la opción A es la primera.

```bash
# 💻 en el clone de §4.2
npm ci --no-audit --no-fund
./node_modules/.bin/prisma generate
NEXT_PUBLIC_APP_URL=https://checkpointdrp.axiomacloud.com npm run build
find .next -name '*.node' | wc -l      # → 0
tar --exclude=.next/cache -czf - .next | \
  ssh axiomacloud@170.78.75.249 'sudo -u checkpointapp tar -xzf - -C /var/www/checkpoint-web'
```

**Verificar (cualquiera de las dos):**

```bash
sudo find /var/www/checkpoint-web -not -user checkpointapp | head               # → vacío
```

---

## 5. Fase 4 — `.env` desde SOPS

💻 **En el equipo del operador** (el `.env` descifrado **nunca toca el disco local**):

```bash
cd ~/Desarrollos/infra-secrets && git pull
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops --decrypt env/dev-1/checkpoint-web.env | \
  ssh axiomacloud@170.78.75.249 'sudo install -o checkpointapp -g checkpointapp -m 600 /dev/stdin /var/www/checkpoint-web/.env'
```

🛟 **Ajustes en drp** (`sudo -u checkpointapp nano /var/www/checkpoint-web/.env`):

| Variable | En un DR real | En un simulacro |
|---|---|---|
| `NEXT_PUBLIC_APP_URL` | URL pública del destino (la misma del build) | `https://checkpointdrp.axiomacloud.com` |
| `GOOGLE_CALLBACK_URL` | `<URL>/api/auth/google/callback` — **y registrarla en Google Cloud Console** | ídem; si no se registra, el botón de Google falla con `redirect_uri_mismatch` (el ingreso con contraseña sigue) |
| `SMTP_*`, `FIREBASE_*` | se dejan como están | **comentarlas**: la base tiene personas y correos reales; un simulacro no debe mandarles mails ni push |
| `DATABASE_URL`, `JWT_SECRET`, `BIOMETRIC_ENCRYPTION_KEY` | **no tocar** | **no tocar** |

**Verificar:** `sudo -u checkpointapp test -r /var/www/checkpoint-web/.env && echo OK`

---

## 6. Fase 5 — PM2 y arranque al boot

🛟 **En drp, desde `/tmp`:**

```bash
cd /tmp
sudo -u checkpointapp -H bash -c 'cd /var/www/checkpoint-web && pm2 start ecosystem.config.js && pm2 save'
sudo env PATH=$PATH pm2 startup systemd -u checkpointapp --hp /home/checkpointapp
sudo systemctl enable pm2-checkpointapp
```

**Verificar — criterio del estándar: `restart_time` estable tras 60 s** (un crash loop también dice `online`):

```bash
sudo -u checkpointapp -H pm2 jlist | python3 -c "import json,sys;p=json.load(sys.stdin)[0]['pm2_env'];print(p['status'],p['restart_time'])"
sleep 60
sudo -u checkpointapp -H pm2 jlist | python3 -c "import json,sys;p=json.load(sys.stdin)[0]['pm2_env'];print(p['status'],p['restart_time'])"
curl -s http://127.0.0.1:8086/api/health        # → {"status":"ok","db":"ok",...}
```

Si no arranca: `sudo -u checkpointapp -H pm2 logs checkpoint-web --lines 50`. El mensaje
`Configuración inválida` / `Configuración insegura` viene de `env.ts` y dice qué variable falta.

---

## 7. Fase 6 — nginx y TLS

🛟 **En drp:**

```bash
sudo tee /etc/nginx/sites-available/checkpointdrp <<'EOF'
server {
    listen 80;
    server_name checkpointdrp.axiomacloud.com;
    access_log /var/log/nginx/checkpoint-access.log;
    error_log  /var/log/nginx/checkpoint-error.log;
    client_max_body_size 10M;
    location / {
        proxy_pass http://127.0.0.1:8086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 60s;
    }
}
EOF
sudo ln -sfn /etc/nginx/sites-available/checkpointdrp /etc/nginx/sites-enabled/checkpointdrp
sudo nginx -t && sudo systemctl reload nginx

# TLS — requiere que el DNS ya apunte a drp y que el 80 llegue desde internet
sudo certbot --nginx -d checkpointdrp.axiomacloud.com \
  --non-interactive --agree-tos --register-unsafely-without-email --redirect
```

> ⚠️ En un **DR real con el dominio productivo** (`checkpointdemo`), certbot recién después de mover el DNS
> (§7.1). En un **simulacro, nunca certbot contra el dominio productivo**: el cupo de Let's Encrypt
> (5 por semana) es compartido con dev-1.

### 7.1 DNS (solo DR real)

Cambiar el registro `A` de `checkpointdemo.axiomacloud.com` de `149.50.148.198` (dev-1) a
`170.78.75.249` (drp). Con el dominio productivo **no hace falta recompilar** si el build se hizo con
`NEXT_PUBLIC_APP_URL=https://checkpointdemo.axiomacloud.com`.

---

## 8. Fase 7 — Verificación (criterio de cierre)

💻 **Desde fuera de la red del proveedor** (G10 R8 — desde el propio drp su IP pública no sirve):

```bash
URL=https://checkpointdrp.axiomacloud.com
curl -s $URL/api/health                                   # → status ok, db ok
curl -sI $URL/ | grep -iE '^(HTTP|location)'              # → 307 a $URL/login — NUNCA a localhost
curl -s -o /dev/null -w '%{http_code}\n' -X POST $URL/api/auth/login \
  -H 'Content-Type: application/json' -H "Origin: $URL" \
  -d '{"email":"no-existe@example.com","password":"x"}'   # → 401 (no 500): backend + base
```

- [x] **Health, redirect, login inválido** — ✅ 2026-09-15: `ok/db ok` · 307 → `https://checkpointdrp…/login`
      (no localhost) · HTTP 301 → HTTPS con HSTS · `/login` 200 · login inválido **401**.
- [x] **Control negativo** (G10 R3) — ✅ desde afuera `8086`, `5432` y `19999` **cerrados**.
- [x] **Legibilidad de datos cifrados** — ✅ **2/2 registros de `biometric_data` descifrados** (9 embeddings
      de 128 dimensiones). AES-256-GCM valida un tag de autenticación: con una clave equivocada **falla**, no
      devuelve basura. Prueba sin exponer datos (solo conteos), 🛟 en drp:
      ```bash
      cat > /tmp/bio-check.js <<'EOF'
      const fs=require('fs'),c=require('crypto')
      const k=Buffer.from(fs.readFileSync('/var/www/checkpoint-web/.env','utf8').match(/^BIOMETRIC_ENCRYPTION_KEY="?([0-9a-fA-F]{64})/m)[1],'hex')
      let ok=0,fail=0
      for (const r of fs.readFileSync(0,'utf8').split('\n').filter(Boolean)) {
        try { const [iv,tag,enc]=r.split(':'); const d=c.createDecipheriv('aes-256-gcm',k,Buffer.from(iv,'hex'))
              d.setAuthTag(Buffer.from(tag,'hex')); JSON.parse(d.update(enc,'hex','utf8')+d.final('utf8')); ok++ } catch { fail++ }
      }
      console.log(`descifrados_ok=${ok} fallidos=${fail}`)
      EOF
      sudo -u postgres psql -d checkpoint_db -tAc \
        "select \"faceEmbeddings\" from biometric_data where coalesce(\"faceEmbeddings\",'')<>''" \
        | sudo -u checkpointapp node /tmp/bio-check.js; rm /tmp/bio-check.js     # → fallidos=0
      ```
- [x] **Login real** en la interfaz con un usuario existente — ✅ verificado por el RT el 2026-09-15.
- [x] **Boot test** — ✅ `pm2 kill` → health 000 → `systemctl restart pm2-checkpointapp` → `online`, 0 restarts, health ok.
- [x] **Estabilidad** — ✅ `restart_time` 0 → 0 tras 60 s.
- [x] **Owner** — ✅ `find -not -user checkpointapp` → 0.
- [x] **Memoria** — ✅ 2110 MB disponibles con las 4 apps de drp arriba; hub, alvera y parse sin reinicios.
- [x] **Uploads** — ⚠️ `/uploads/legajos/contrato-uds-1009.pdf` da **401** sin sesión (la ruta autorizada
      funciona); con sesión daría 404: el archivo **no existe** en drp. Esperado hoy (§9, H-2).

---

## 9. Política de backup de los uploads (propuesta)

### 9.1 Situación actual

- `UPLOAD_DIR="./public/uploads"` en dev-1 → **dentro** del árbol de la app, que el deploy reescribe.
  El propio código ya lo marca como desvío: `env.ts` defiende `./uploads` fuera del webroot (S4.5) y
  `next.config.ts` sirve `/uploads/*` por la ruta autorizada `/api/files`.
- Está en `.gitignore`, **no** lo cubre pgBackRest y **no hay ningún otro respaldo**.
- Volumen hoy: **1 archivo real** (`legajos/contrato-uds-1009.pdf`, 57 KB). Chico, pero es
  **documentación laboral con PII** (🟠 Confidencial en G8) y va a crecer.
- La base guarda **la referencia** al archivo: tras un restore, la fila existe y el archivo no.

### 9.2 Recomendación — dos etapas

**Etapa 1 (inmediata, sin tocar la app): restic → R2, cifrado, cada 15 min.**

| Decisión | Valor | Por qué |
|---|---|---|
| Herramienta | **restic** | Cifrado del lado cliente, deduplicación, snapshots incrementales baratos, `restic check` para verificar integridad. Un binario, sin servicio. |
| Destino | **R2, bucket propio** (`axiomacloud-uploads`), **no** el de pgBackRest | Off-site como la base; bucket separado para que un error de `forget/prune` no pueda tocar los backups de PostgreSQL. Token R2 con permiso **solo sobre ese bucket**. |
| Frecuencia | **cada 15 min** (timer systemd) | La base tiene RPO de minutos (WAL continuo). Con backup diario, un restore de la base referenciaría archivos subidos después del último snapshot → **huérfanos**. Con volumen chico, 15 min cuesta casi nada. |
| Retención | `--keep-within 48h --keep-daily 14 --keep-weekly 8 --keep-monthly 12` | 48 h de granularidad fina para errores recientes; 12 meses porque son legajos (borrado accidental descubierto tarde). Más larga que pgBackRest a propósito: un archivo borrado no se "reconstruye". |
| Clave | password de restic en **infra-secrets** (`env/pgbackrest/`-style, SOPS) | Misma custodia que `repo2-cipher-pass`. **Sin la clave, el backup es ilegible** — sumarla al kit de G9. |
| Previo al snapshot | mover `UPLOAD_DIR` a `/var/lib/checkpoint/uploads` (fuera de `/var/www`) | Un `rm -rf`/redeploy del árbol de la app no lo borra; separa datos de código. |
| Monitoreo | watchdog: alarma si el último snapshot tiene > 1 h | Mismo patrón que `pgbackrest_archive_push_failing`. Un backup sin alarma no es un control. |
| Verificación | `restic check --read-data-subset=10%` semanal + restore de prueba en el drill mensual de drp | Igual que C13 (verify semanal) y el restore drill. |
| Orden de restore en DR | **uploads primero, base después** con PITR a la hora del snapshot | Así no quedan filas que apunten a archivos inexistentes. |

**Etapa 2 (con el equipo de la app): object storage como fuente de verdad.** La app ya depende de
`@google-cloud/storage`. Subir los archivos directo a un bucket (R2/S3/GCS) **con versionado de objetos**
y lifecycle deja al servidor **sin estado**: el DR del filesystem desaparece, y un borrado o una
sobrescritura se recupera desde la versión anterior. La etapa 1 queda como red hasta completar la migración.

---

## 10. Vuelta atrás / teardown del simulacro

🛟 **En drp** — deja el server listo para el próximo drill:

```bash
cd /tmp
sudo -u checkpointapp -H pm2 delete checkpoint-web; sudo -u checkpointapp -H pm2 save --force
sudo systemctl disable --now pm2-checkpointapp
sudo rm -f /etc/nginx/sites-enabled/checkpointdrp && sudo nginx -t && sudo systemctl reload nginx
sudo certbot delete --cert-name checkpointdrp.axiomacloud.com --non-interactive
sudo -u postgres dropdb checkpoint_db && sudo -u postgres dropuser checkpointuser
sudo rm -rf /var/www/checkpoint-web /var/lib/postgresql/drp-checkpoint
sudo userdel -r checkpointapp
```

Y borrar el registro DNS `checkpointdrp`. En un **DR real**, la vuelta a dev-1 sigue la §11 del
[runbook general](./drp-recuperacion-axioma-en-drp.md#11-vuelta-atrás): **nunca dos instancias
escribiendo a la vez**.

---

## 11. Hallazgos del simulacro

| # | Hallazgo | Severidad | Estado |
|---|---|---|---|
| **H-1** | **La copia de infra-secrets no arrancaba la app**: `JWT_SECRET` = valor de ejemplo (30 caracteres), rechazado por `env.ts`. En dev-1 se rotó el 2026-09-12 y se agregó Google OAuth el 2026-09-14 sin reflejarlo en SOPS. Un DR real se hubiera detenido en la Fase 5. | 🔴 | ✅ Corregido 2026-09-15 (`infra-secrets` `7fa78f2`, verificado 22/22 claves == vivo). **Causa de fondo abierta:** cambiar un `.env` en un server no dispara actualizar SOPS → falta un control (C-: comparar hash de claves vivo vs SOPS en el selfcheck). |
| **H-2** | **Uploads sin backup** (`public/uploads`, fuera de git y de pgBackRest). | 🟠 | Abierto — propuesta en §9. |
| **H-3** | **`UPLOAD_DIR` dentro del árbol de la app** en dev-1, contra lo que pide el propio código (S4.5). | 🟡 | Abierto — se resuelve con la etapa 1 de §9. |
| **H-4** | **32 de 103 tablas de `checkpoint_db` son de `postgres`** (migraciones corridas como superusuario — estándar §9). `checkpointuser` igual tiene todos los privilegios. Además, como owner de `audit_logs`, `checkpointuser` puede `DISABLE TRIGGER` y saltear el control de auditoría solo-agregar. | 🟡 | Abierto — normalizar ownership en dev-1 y evaluar mover `audit_logs`/`auth_events` a un owner distinto del de la app. |
| **H-5** | **Docs desactualizados**: el runbook general §8.1 sigue dando R21 como bloqueante (cerrado en G3 el 2026-08-12; certbot HTTP-01 validó hoy desde internet); G6 dice que `checkpoint-web` corre como `axiomacloud` (hoy `checkpointapp`); las fichas no distinguían la app Checkpoint del sitio estático. | 🟢 | Ver commit del simulacro. |
| **H-6** | **Versión reportada ≠ código desplegado en dev-1**: `/api/health` dice `deployed-prev-10-ga4bf0c38c`, pero el HEAD y el `.next` son de `eff60f3`. El `APP_VERSION` quedó del último `pm2 reload --update-env`. No afecta el DR, sí confunde al elegir qué commit recuperar. | 🟢 | Informativo. |
| **H-7** | **Compilar "afuera" depende de la red del operador.** El build local falló por `ETIMEDOUT` de npm tras 25 min, mientras el mismo `npm ci` en drp tardó 86 s. Compilar **en drp** funcionó (298 s, 590 MB mínimos libres). Corrige la premisa de que en drp "no se compila" para esta app. | 🟢 | Incorporado: §4.5 opción A primero. Mejora de fondo: artefacto pre-compilado en R2 (runbook general §10.1). |

---

## 12. Registro de ejecución — simulacro 2026-09-15

| Hora (-03) | Fase | Acción | Resultado | Duración |
|---|---|---|---|---|
| < 08:37 | 0 | Relevamiento en vivo de dev-1 y drp (solo lectura) | Ficha §0.1; H-1…H-6 | — |
| 08:37 | 0 | `infra-secrets`: `.env` vivo → SOPS, commit `7fa78f2` | ✅ 22/22 claves idénticas | — |
| 08:38 | 3 | Build local: clone de GitHub + `npm ci` | ❌ `ETIMEDOUT` de la red del operador tras ~25 min | — |
| 08:56 | 1 | `pgbackrest restore --db-include=checkpoint_db --archive-mode=off` desde R2 | ✅ | **28 s** |
| 08:57 | 1 | Replay de WAL + promoción | ✅ última transacción **11:55:11 UTC** (RPO ≈ 2 min) · `archive_mode=off` · 103 tablas · 5 migraciones | **29 s** |
| 08:57 | 1 | `pg_dump` + borrar instancia temporal | ✅ dump 442 KB | 2 s |
| ~09:00 | 2 | Rol + base + `pg_restore` fiel | ✅ owners 71/32 · 4 triggers · login app por TCP OK (29 usuarios) | 2 s |
| 09:01 | 3 | Usuario `checkpointapp` (uid 991) + `/var/www/checkpoint-web` | ✅ | — |
| 09:02 | 4 | `.env` desde SOPS + ajustes drp (URL, SMTP/Firebase comentados) | ✅ 600 `checkpointapp` | — |
| 09:03 | 6 | vhost `checkpointdrp` + certbot | ✅ cert hasta 2026-12-14 (HTTP-01 validó desde internet) | — |
| ~09:04 | 3 | Código de `eff60f3` subido por `git archive` | ✅ 25 MB | — |
| 09:07 | 3 | `npm ci` + `prisma generate` **en drp** | ✅ 951 paquetes · motor Prisma 6.19.3 y `tfjs_binding.node` para glibc 2.35 | **86 s + 5 s** |
| 09:09 | 3 | Build **en drp** (el reintento local seguía lento → se descartó) | ✅ exit 0 · mín. 590 MB libres · swap 242 MB · 0 `.node` en `.next` | **298 s** |
| 09:15 | 5 | `pm2 start` + `pm2 save` | ✅ health ok a los 14 s · 0 restarts tras 60 s | 14 s |
| 09:16 | 5 | `pm2 startup` + boot test | ✅ `pm2-checkpointapp` enabled · vuelve sola tras kill | — |
| 09:17 | 7 | Verificación externa + control negativo | ✅ ver §8 | — |
| 09:18 | 7 | Legibilidad biométrica | ✅ 2/2 descifrados | — |
| 09:18 | — | Limpieza: dump y PGDATA temporal borrados; build local borrado | ✅ | — |
| tarde | 7 | Login real con usuario (RT) | ✅ | — |
| ~17:10 | 10 | **Teardown** (PM2, unit, vhost, cert, `checkpoint_db`, rol, usuario, directorio, logs nginx) | ✅ drp sin rastros; hub y parse intactos | — |

**Resultado: PASS.** Login real verificado y **teardown ejecutado el mismo día** — drp no conserva datos de Checkpoint.

*Documento creado el 2026-09-15 durante el primer simulacro de Checkpoint.*
