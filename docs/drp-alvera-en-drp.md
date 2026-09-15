# DRP — Alvera (axioma → axioma-drp) · Runbook y registro del simulacro

> **Escenario que cubre:** se pierde **axioma** (o solo alvera en axioma) y hay que levantar **Alvera
> producción** en **axioma-drp** desde fuentes que **no dependen de axioma**: código de GitHub, base de
> pgBackRest en **R2**, `.env` de **infra-secrets**, configuración de [`config/axioma/`](../config/axioma/)
> y adjuntos del backup en dev-1.
>
> **Cómo se usa:** §2 a §9 son el paso a paso **a mano**. 💻 = equipo del operador · 🛟 = axioma-drp.
> §12 registra la ejecución del 2026-09-15. Se lee junto a la
> [ficha de alvera](./drp-fichas-apps-axioma.md#-alvera-ex-mediflow--prioridad-1) y al
> [runbook general](./drp-recuperacion-axioma-en-drp.md).
>
> **Estado:** ✅ **EJECUTADO 2026-09-15 — PASS.** Alvera quedó sirviendo en
> `https://alveradrp.axiomacloud.com`, reemplazando al simulacro del 2026-08-12 (nombres `mediflow`).
>
> | Métrica | Valor medido |
> |---|---|
> | **RPO** | **≈ 0** — la última transacción recuperada (09:38:13 -03) es de **durante** el replay: pgBackRest trajo el WAL que axioma seguía archivando |
> | **RTO de manos** | **≈ 13 min** — base 4 min · deps+build 2,5 min · rol/neutralización/env/adjuntos 2 min · PM2+nginx+TLS 1,5 min · verificación 3 min |
> | **RTO de pared** | 16 min (09:33 → 09:49), incluye un rebuild por un error de `VITE_API_URL` (A-6) |
> | **Datos cifrados (PHI)** | ✅ **2993 valores descifrados, 0 fallidos**, en 18 columnas (pacientes, consultas, recetas, HC importadas) |
> | **Adjuntos** | ✅ 6/6 archivos con sha256 idéntico a producción |

---

## 0. Lo que hay que saber antes de empezar

### 0.1 Ficha (relevada en vivo en axioma el 2026-09-15)

| | axioma (origen) | axioma-drp (simulacro) |
|---|---|---|
| **Dominio** | `alvera.axiomacloud.com` (+ `alvera.com.ar`, `api.alvera` sin DNS) | `alveradrp.axiomacloud.com` |
| **Commit** | `f36c138` (2026-09-09) · repo `AxiomaCloud/Alvera` rama `master` | ídem |
| **Layout** | `/var/www/alvera/{backend,frontend,web}` — sin workspaces, `npm ci` por carpeta | ídem |
| **Usuario** | `alveraapp` (grupo suplementario `www-data`) | `alveraapp` (uid 998) |
| **Backend** | `server.js`, PM2 `alvera-backend` **cluster ×2**, `--env production`, puerto **5300** | ídem |
| **Frontend** | Vite → `frontend/dist`, servido por nginx; API por **`/api/`** del mismo dominio | ídem |
| **Base / rol** | `alvera_db` (50 MB) / `alverauser` (owner de 88 de 89 tablas) · `uuid-ossp` · **:6432 pgbouncer** | `:5432` directo (drp no tiene pgbouncer) |
| **Stanza** | `AxiomaCloudProd` (PG14) | se lee de **R2** |
| **Prisma** | `postinstall` del backend corre `prisma generate` (6.14) · 84 migraciones | ídem |
| **Secretos** | `infra-secrets` → **`env/axioma/alvera-backend.env`** *(renombrado 2026-09-15)* | ídem |
| **Frontend env** | [`config/axioma/frontend-env/alvera-frontend.env.production`](../config/axioma/frontend-env/) | con la URL de drp |
| **Adjuntos** | `backend/uploads` → rsync diario a dev-1 `/backup/alvera-adjuntos` | copiados desde dev-1 |

### 0.2 🔴 Cuatro cosas que hacen fallar la recuperación en silencio

1. **`ENCRYPTION_MASTER_KEY` / `SEARCH_HASH_SALT`.** Nombre, DNI, domicilio, motivo de consulta,
   diagnóstico y tratamiento están cifrados por la app (AES-256-GCM). Sin la clave exacta la base
   restaurada es **ilegible para siempre** y la app no muestra ningún error. La prueba de §9.2 es obligatoria.
2. **`VITE_API_URL` termina en `/api`.** Se hornea en el build. `https://<dominio>` sin `/api` → la app
   carga y **el login falla**. Pasó en este simulacro (A-6).
3. **pgbouncer.** El `DATABASE_URL` de producción va a `:6432?pgbouncer=true`. drp no tiene pgbouncer: cambiar
   a `:5432` y quitar `pgbouncer=true`, o la app arranca y falla al primer query.
4. **El `.env` de infra-secrets tiene que estar al día.** Hasta el 2026-09-15 apuntaba a
   `mediflowuser`/`mediflow_db`, que no existen desde el rename → no conectaba (A-2).

### 0.3 🔴 Regla de no-contaminación — y **regla de no-mensajear a pacientes**

- **Backups:** el restore va **siempre** con `--archive-mode=off` (§2). Desde drp solo `restore` e `info`.
- **Pacientes (solo simulacros):** la configuración de WhatsApp (Evolution) y del email **vive en la base**
  (tabla `configurations`), no en el `.env`. Un restore trae `WHATSAPP_ENABLED=true` con las credenciales
  productivas, y el backend tiene un **cron de recordatorios de turnos a las 09:00** más notificaciones por
  evento. **Un simulacro sin el paso §3.3 le escribe a pacientes reales desde drp.** Ver A-3.
  En un **DR real** ese paso **no** se hace: drp pasa a ser producción y los recordatorios tienen que salir.

### 0.4 De dónde sale cada cosa

| Qué | Fuente | ¿Depende de axioma? |
|---|---|---|
| Código | GitHub `AxiomaCloud/Alvera` @ `f36c138` | ❌ |
| Base | pgBackRest `AxiomaCloudProd` en **R2** | ❌ |
| `.env` backend | `infra-secrets` `env/axioma/alvera-backend.env` | ❌ |
| `.env.production` frontend, vhost, ecosystem, unit | [`config/axioma/`](../config/axioma/) *(recapturados 2026-09-15)* | ❌ |
| Adjuntos | dev-1 `/backup/alvera-adjuntos` (rsync diario 06:25) | ❌ — pero **sí de dev-1** (A-5) |
| Build | se compila **en drp** (Vite: 38 s, mín. 1063 MB libres) | ❌ |

---

## 1. Prerrequisitos

- [x] 🛟 drp con Node 20.20.2, PM2 6, nginx, certbot, PG14, pgBackRest 2.59 ([runbook general §1](./drp-recuperacion-axioma-en-drp.md#1-fase-1--preparar-el-stack-base-en-drp)).
- [x] 🛟 `sudo -u postgres pgbackrest --stanza=AxiomaCloudProd info` → `status: ok`.
- [x] 💻 Clave age + `infra-secrets` clonado · 💻 acceso a GitHub · 💻 SSH a dev-1 (adjuntos).
- [x] Registro DNS `A alveradrp.axiomacloud.com → 170.78.75.249` (sin proxy).
- [x] 🛟 Sin otra alvera en drp: `id alveraapp`, `ss -tln | grep :5300`, base `alvera_db` → nada.
      *(Si queda un simulacro anterior, bajarlo primero con §10.)*

---

## 2. Restaurar `alvera_db` desde R2 (instancia temporal) — ⏱ 50 s + 3 min de WAL

Mismo método que [Checkpoint §2](./drp-checkpoint-en-drp.md#2-fase-1--restaurar-checkpoint_db-desde-r2-instancia-temporal-aislada):
`--db-include` materializa **solo** `alvera_db` (la stanza trae las ~11 bases de axioma).

🛟 **En drp:**

```bash
BASE=/var/lib/postgresql/drp-alvera; PGDATA=$BASE/pgdata; PORT=5446; BIN=/usr/lib/postgresql/14/bin
sudo -u postgres mkdir -p $BASE && sudo -u postgres install -d -m 700 $PGDATA

# Para un punto en el tiempo: --type=time --target="2026-09-15 09:00:00-03"
sudo -u postgres pgbackrest --stanza=AxiomaCloudProd --pg1-path=$PGDATA \
  --db-include=alvera_db --archive-mode=off restore

echo "local all postgres peer" | sudo -u postgres tee $PGDATA/pg_hba.conf
sudo -u postgres touch $PGDATA/pg_ident.conf
sudo -u postgres tee $PGDATA/postgresql.conf <<EOF
port = $PORT
listen_addresses = ''
unix_socket_directories = '/var/run/postgresql'
hba_file = '$PGDATA/pg_hba.conf'
ident_file = '$PGDATA/pg_ident.conf'
hot_standby = off          # evita exigir max_connections/etc. >= a los de axioma durante el recovery
archive_mode = off
EOF

sudo -u postgres $BIN/pg_ctl start -D $PGDATA -l $BASE/pg.log -w -t 600
until [ "$(sudo -u postgres psql -p $PORT -tAc 'select pg_is_in_recovery()' 2>/dev/null)" = "f" ]; do sleep 5; done
```

**Verificar:**

```bash
sudo -u postgres psql -p $PORT -tAc "show archive_mode"                                         # → off
sudo -u postgres psql -p $PORT -d alvera_db -tAc "select count(*) from pg_tables where schemaname='public'"   # → 89
sudo -u postgres psql -p $PORT -d alvera_db -tAc "select count(*), max(migration_name) from _prisma_migrations"  # → 84 | 20260909150000_consultation_notes
grep "last completed transaction" $BASE/pg.log                                                  # → RPO
```

```bash
sudo -u postgres $BIN/pg_dump -p $PORT -Fc -f $BASE/alvera_db.dump alvera_db
sudo -u postgres $BIN/pg_ctl stop -D $PGDATA -m fast && sudo -u postgres rm -rf $PGDATA
```

---

## 3. Rol, base y canales de notificación

### 3.1 🛟 Rol y base

Password de `alverauser` = el del `DATABASE_URL` en infra-secrets. Nunca en la línea de comandos.

```bash
sudo -u postgres psql <<'SQL'
CREATE ROLE alverauser LOGIN;
\password alverauser
CREATE DATABASE alvera_db OWNER alverauser;
SQL
```

### 3.2 🛟 Restore fiel (conserva owners y grants)

```bash
sudo -u postgres pg_restore -d alvera_db --exit-on-error $BASE/alvera_db.dump && sudo rm -rf $BASE
sudo -u postgres psql -d alvera_db -tAc "select tableowner, count(*) from pg_tables where schemaname='public' group by 1"
#   → alverauser|88 · postgres|1   (igual que axioma al 2026-09-15)
```

### 3.3 🔴 🛟 SOLO SIMULACRO — neutralizar WhatsApp, email y SMS **antes de arrancar la app**

```bash
sudo -u postgres psql -d alvera_db -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
UPDATE configurations SET value='false', "updatedAt"=now() WHERE key IN ('WHATSAPP_ENABLED','WHATSAPP_CLOUD_ENABLED');
UPDATE configurations SET value='http://127.0.0.1:9', "updatedAt"=now() WHERE key='WHATSAPP_API_URL';
UPDATE configurations SET value=jsonb_set(jsonb_set(value::jsonb,'{enabled}','false'),'{smtpHost}','"127.0.0.1"')::text,
       "updatedAt"=now() WHERE key='email_config';
UPDATE configurations SET value=jsonb_set(value::jsonb,'{enabled}','false')::text, "updatedAt"=now()
       WHERE key IN ('sms_config','whatsapp_config');
COMMIT;
SQL
```

Además del flag, la URL de Evolution y el host SMTP apuntan a un destino muerto: si algún camino del
código ignora `enabled`, **falla cerrado**. Verificar que no haya overrides por tenant:

```bash
sudo -u postgres psql -d alvera_db -tAc "select key, coalesce(\"tenantId\"::text,'global') from configurations
  where key ilike any(array['%whatsapp%','%email%','%sms%']) and \"tenantId\" is not null"   # → vacío
```

---

## 4. Código

### 4.1 🛟 Usuario y directorio

```bash
sudo useradd --system --create-home --home-dir /home/alveraapp --shell /bin/bash alveraapp
sudo usermod -aG www-data alveraapp
sudo install -d -o alveraapp -g alveraapp -m 755 /var/www/alvera
```

### 4.2 💻→🛟 El commit **de producción**, no el último de master

Anotar en axioma (si existe) o en el último registro de deploy qué commit corría. Al 2026-09-15:
`f36c138` (`master` ya tenía 36 commits más, no desplegados).

```bash
git clone git@github.com:AxiomaCloud/Alvera.git && cd Alvera
git archive --format=tar f36c138 | gzip -1 | \
  ssh axiomacloud@170.78.75.249 'sudo -u alveraapp tar -xzf - -C /var/www/alvera'
```

---

## 5. Configuración

### 5.1 💻 `.env` del backend desde SOPS

```bash
cd ~/Desarrollos/infra-secrets && git pull
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops --decrypt env/axioma/alvera-backend.env | \
  ssh axiomacloud@170.78.75.249 'sudo install -o alveraapp -g alveraapp -m 600 /dev/stdin /var/www/alvera/backend/.env'
```

🛟 Ajustes (`sudo -u alveraapp nano /var/www/alvera/backend/.env`):

| Variable | DR real | Simulacro |
|---|---|---|
| `DATABASE_URL` | `:6432` → **`:5432`** y quitar `pgbouncer=true` (o instalar pgbouncer) | ídem |
| `ALLOWED_ORIGINS` | dominio público final | `https://alveradrp.axiomacloud.com` |
| `EMAIL_*`, `TWILIO_*` | no tocar | **comentar** |
| `AXIO_*` | no tocar | **comentar** (el chat de IA habla con Hub productivo) |
| `ENCRYPTION_MASTER_KEY`, `SEARCH_HASH_SALT`, `JWT_SECRET` | **no tocar** | **no tocar** |

### 5.2 🛟 `.env.production` del frontend

```bash
echo 'VITE_API_URL=https://alveradrp.axiomacloud.com/api' | \
  sudo -u alveraapp tee /var/www/alvera/frontend/.env.production        # ⚠️ con /api al final
```

En un DR real con el dominio productivo: copiar tal cual
[`alvera-frontend.env.production`](../config/axioma/frontend-env/alvera-frontend.env.production).

---

## 6. Dependencias y build 🛟 — ⏱ 73 s + 38 s + 38 s

```bash
cd /tmp
sudo -u alveraapp -H bash -c 'cd /var/www/alvera/backend  && npm ci --legacy-peer-deps --no-audit --no-fund'   # postinstall → prisma generate
sudo -u alveraapp -H bash -c 'cd /var/www/alvera/frontend && npm ci --legacy-peer-deps --no-audit --no-fund'
sudo -u alveraapp -H bash -c 'cd /var/www/alvera/frontend && npm run build'
```

`--legacy-peer-deps` es el que usa `deploy-update.sh` en producción. **No** correr `prisma migrate deploy`.

**Verificar el build — la URL completa, no la ausencia de `localhost`:**

```bash
cd /var/www/alvera/frontend/dist/assets
sudo grep -l "alveradrp.axiomacloud.com/api" *.js | wc -l      # → 3  (producción: 3 con su dominio)
sudo grep -o '"https://alveradrp.axiomacloud.com"' *.js | wc -l  # → 0  (sin /api = login roto)
```

> ⚠️ `grep localhost:5000` **siempre da 1**, también en producción: es un fallback inerte de
> `websocketService.js` (`URL || "http://localhost:5000"`). El chequeo "debe dar 0" del runbook general
> §4.2.1 no sirve para esta versión.

---

## 7. Adjuntos 💻 (dev-1 → drp, el operador hace de puente)

drp no tiene acceso a dev-1. Si axioma no existe, el backup de dev-1 es la única copia:

```bash
ssh dev-1 'sudo tar -C /backup/alvera-adjuntos -czf - .' | \
  ssh axiomacloud@170.78.75.249 'sudo install -d -o alveraapp -g alveraapp -m 750 /var/www/alvera/backend/uploads &&
    sudo tar -C /var/www/alvera/backend/uploads -xzf - --no-same-owner &&
    sudo chown -R alveraapp:alveraapp /var/www/alvera/backend/uploads'
```

**Verificar** (si axioma vive): comparar `find uploads -type f -exec sha256sum {} + | sort -k2` en ambos lados.
Si axioma no existe: la copia tiene hasta **24 h** de atraso (corre 06:25) — los adjuntos subidos después se
perdieron; las filas que los referencian quedan huérfanas.

---

## 8. PM2, systemd, nginx y TLS 🛟

```bash
cd /tmp
sudo -u alveraapp -H bash -c 'cd /var/www/alvera/backend && pm2 start ecosystem.config.js --env production && pm2 save'
sudo env PATH=$PATH pm2 startup systemd -u alveraapp --hp /home/alveraapp
```

⚠️ **`--env production`** — sin él el ecosystem arranca en `development` y en el puerto 5000.

**Estabilidad (60 s):** `sudo -u alveraapp -H pm2 jlist` → 2 procesos `online`, `restart_time` 0 antes y después.
En los logs deben aparecer `Email: … modo simulado` y `WhatsApp: sin credenciales Twilio — modo simulado` (simulacro).

**nginx:** partir del bloque *Frontend* de [`config/axioma/nginx/alvera.conf`](../config/axioma/nginx/alvera.conf)
(incluye las `limit_req_zone`), cambiar `server_name`, dejar solo `listen 80` y que certbot agregue el 443:

```bash
sudo nano /etc/nginx/sites-available/alveradrp          # server_name alveradrp.axiomacloud.com; root /var/www/alvera/frontend/dist; /api/ y /socket.io/ → 127.0.0.1:5300
sudo ln -sfn /etc/nginx/sites-available/alveradrp /etc/nginx/sites-enabled/alveradrp
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d alveradrp.axiomacloud.com --non-interactive --agree-tos --register-unsafely-without-email --redirect
```

**DR real:** mover los registros `A` de `alvera.axiomacloud.com`, `alvera.com.ar` y `www.alvera.com.ar` a
`170.78.75.249` y recién ahí `certbot` con esos dominios (el cupo de Let's Encrypt es compartido con axioma).
`alvera.com.ar` sirve `/var/www/alvera/web` (estático, en el mismo commit) — no cubierto por este simulacro.

---

## 9. Verificación

### 9.1 💻 Desde internet

```bash
URL=https://alveradrp.axiomacloud.com
curl -s $URL/ | grep -o "<title>[^<]*</title>"                       # → Alvera - Sistema de Gestión Médica
curl -s -o /dev/null -w '%{http_code}\n' http://alveradrp.axiomacloud.com/   # → 301
curl -s -w ' %{http_code}\n' -X POST $URL/api/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"no-existe-drp","password":"x"}'                    # → Credenciales incorrectas 401 (no 500)
curl -s -o /dev/null -w '%{http_code}\n' $URL/api/patients           # → 401
curl -s -o /dev/null -w '%{http_code}\n' "$URL/socket.io/?EIO=4&transport=polling"   # → 200
for p in 5300 5432; do timeout 5 bash -c "</dev/tcp/170.78.75.249/$p" && echo "$p ABIERTO" || echo "$p cerrado"; done
```

> `/api/health` **pide token** — no hay endpoint público de salud (A-10).

### 9.2 🔴 🛟 Legibilidad de PHI (obligatoria, sin exponer datos)

Recorre todas las columnas de texto con formato `iv:tag:dato` y descifra hasta 200 valores por columna.
Con una clave equivocada, GCM **falla** (no devuelve basura). Imprime solo conteos.

```bash
cat > /tmp/phi-check.js <<'EOF'
const fs=require('fs'),c=require('crypto')
const k=Buffer.from(fs.readFileSync('/var/www/alvera/backend/.env','utf8').match(/^ENCRYPTION_MASTER_KEY="?([0-9a-fA-F]{64})/m)[1],'hex')
const r={}
for (const l of fs.readFileSync(0,'utf8').split('\n')) { const t=l.indexOf('\t'); if(t<0) continue
  const col=l.slice(0,t), x=(r[col]||={ok:0,fail:0})
  try { const [iv,tag,e]=l.slice(t+1).split(':'); const d=c.createDecipheriv('aes-256-gcm',k,Buffer.from(iv,'hex'))
        d.setAuthTag(Buffer.from(tag,'hex')); d.update(e,'hex','utf8'); d.final('utf8'); x.ok++ } catch { x.fail++ } }
for (const [col,x] of Object.entries(r)) console.log(col, 'ok='+x.ok, 'fail='+x.fail)
EOF
cat > /tmp/phi-sample.sql <<'EOF'
\pset format unaligned
\pset tuples_only on
\pset fieldsep '\t'
SELECT format('SELECT %L, %I FROM public.%I WHERE %I ~ ''^[0-9a-f]{32}:[0-9a-f]{32}:[0-9a-f]+$'' LIMIT 200',
       table_name||'.'||column_name, column_name, table_name, column_name)
FROM information_schema.columns WHERE table_schema='public' AND data_type IN ('text','character varying')
\gexec
EOF
chmod 644 /tmp/phi-check.js /tmp/phi-sample.sql
sudo -u postgres psql -d alvera_db -q -f /tmp/phi-sample.sql | sudo -u alveraapp node /tmp/phi-check.js
rm /tmp/phi-check.js /tmp/phi-sample.sql
# → 2026-09-15: 18 columnas, 2993 ok, 0 fail
```

### 9.3 Checklist

- [x] Título real, 301→HTTPS, cert Let's Encrypt, `socket.io` 200.
- [x] Login inválido **401**; ruta protegida sin token **401**.
- [x] Control negativo: 5300, 5432, 8086, 19999 **cerrados** desde afuera.
- [x] PHI legible: **2993/2993**.
- [x] Adjuntos: **6/6** sha256 == producción.
- [x] Estabilidad: 2 instancias, 0 restarts tras 60 s.
- [x] Boot test: `pm2 kill` → `systemctl restart pm2-alveraapp` → vuelven solas, 0 restarts.
- [x] Owner: `find /var/www/alvera -not -user alveraapp` → 0.
- [x] Canales neutralizados (logs: email y Twilio "modo simulado"; `WHATSAPP_ENABLED=false`).
- [x] Resto de drp intacto: hub, parse, checkpoint `online`, 0 restarts; 2129 MB disponibles.
- [ ] **Login real y abrir una ficha de paciente** — pendiente, lo hace una persona.

---

## 10. Teardown del simulacro 🛟

```bash
cd /tmp
sudo -u alveraapp -H pm2 delete all; sudo -u alveraapp -H pm2 kill
sudo systemctl disable --now pm2-alveraapp && sudo rm -f /etc/systemd/system/pm2-alveraapp.service && sudo systemctl daemon-reload
sudo rm -f /etc/nginx/sites-enabled/alveradrp /etc/nginx/sites-available/alveradrp && sudo nginx -t && sudo systemctl reload nginx
sudo certbot delete --cert-name alveradrp.axiomacloud.com --non-interactive
sudo -u postgres psql -c "DROP DATABASE alvera_db;" -c "DROP ROLE alverauser;"
sudo userdel -r alveraapp; sudo rm -rf /var/www/alvera
```

Y borrar el registro DNS `alveradrp`. Con datos de salud reales en un server de pruebas, **no dejarlo vivo
más de lo necesario** (el simulacro del 2026-08-12 quedó 34 días corriendo).

---

## 11. Hallazgos

| # | Hallazgo | Sev. | Estado |
|---|---|---|---|
| **A-1** | **dev-1 (demo) usa la MISMA `ENCRYPTION_MASTER_KEY` que producción**, y la copia de `infra-secrets` (`env/dev-1/mediflow-backend.env`) tiene otra clave, vieja. Verificado por hash el 2026-09-15: axioma vivo = axioma SOPS = **dev-1 vivo** (`8ef0e6…`) ≠ dev-1 SOPS (`29ea4b…`); `SEARCH_HASH_SALT` sí es propio de dev-1. Con su clave viva, dev-1 descifra 200/200 apellidos de su `alvera_db`. **No afecta la operación de producción**, pero: (1) quien obtenga el `.env` de dev-1 —el server menos controlado y con más usuarios— tiene la llave de los datos de salud de producción, incluidos sus backups en R2; (2) un DR de la demo desde SOPS dejaría sus datos ilegibles. Refuerza R13/R20 (datos productivos en dev-1). | 🔴 | **Abierto — decisión, no mecánico.** Recapturar el `.env` vivo a SOPS cerraría (2) pero **consagraría la clave de producción en el secreto de un entorno de desarrollo**. Lo correcto es darle a dev-1 una clave propia, lo que exige recifrar sus datos o recargarlos sin datos reales. Va con la decisión de R13/R20. |
| **A-2** | **axioma: el `.env` de SOPS apuntaba a `mediflowuser`/`mediflow_db`** (anterior al rename). Las claves de cifrado sí coincidían. | 🟠 | ✅ `infra-secrets` `e29ea3e`: renombrado a `alvera-backend.env`, 23/23 == vivo. |
| **A-3** | **Los canales de notificación viven en la base.** Un restore trae WhatsApp (Evolution) habilitado con credenciales productivas; el backend tiene cron de recordatorios 09:00 y alertas 07:30. Un simulacro sin §3.3 mensajea a pacientes reales. El drill del 2026-08-12 corrió **34 días con `WHATSAPP_ENABLED=true`** — sin evidencia de envíos (su código no tenía aún el cron de recordatorios y los logs no muestran envíos). | 🔴 | ✅ Mitigado en el procedimiento (§0.3, §3.3). Mejora de fondo sugerida: un flag de entorno (`NOTIFICATIONS_DISABLED`) que la app respete antes que la base. |
| **A-4** | **El rate limit de login no protege la ruta que usa el frontend.** `limit_req zone=alvera_login` (5/min) está solo en el server `api.alvera.axiomacloud.com` (sin DNS); el frontend llama a `alvera.axiomacloud.com/api/auth/login`, que solo tiene el límite general (30/s). Verificado en la réplica de drp: 7 intentos seguidos → 7×401, ningún 429. | 🟠 | **Abierto** — agregar en el server del frontend de axioma `location ~* ^/api/(auth/login|users/login)` con `alvera_login`. Toca producción: requiere OK y ventana. |
| **A-5** | **Los adjuntos solo se respaldan en dev-1** (rsync diario 06:25). No hay copia off-site ni en R2, RPO 24 h. Si caen axioma **y** dev-1, se pierden. Además el destino quedó `755` (el script dice `700`) y son documentos de salud. | 🟡 | **Abierto** — misma política propuesta para Checkpoint ([§9](./drp-checkpoint-en-drp.md#9-política-de-backup-de-los-uploads-propuesta)): restic → R2 cada 15 min; `chmod 700` el destino en dev-1. |
| **A-6** | **`VITE_API_URL` sin `/api` rompe el login en silencio**, y el chequeo del runbook general (`localhost:5000` → 0) no lo detecta: esa cadena aparece siempre como fallback inerte. En el simulacro se compiló primero sin `/api` (error del operador al relevar con un `sed` que recortaba la ruta) y se detectó comparando el bundle contra producción. | 🟡 | ✅ Chequeo corregido (§6); comentario en `alvera-frontend.env.production`. |
| **A-7** | **El backend escucha en `*:5300`**, no en loopback, en axioma y en drp (PM2 cluster ignora `HOST`). Hoy lo cierra ufw (verificado desde afuera). | 🟢 | Informativo — depende de un solo control (el firewall). |
| **A-8** | **`config/axioma/` desactualizado para alvera**: ecosystem, vhost, unit y frontend-env seguían con nombres/rutas `mediflow`. | 🟢 | ✅ Recapturados del vivo 2026-09-15 con nombres `alvera` (sin secretos). |
| **A-9** | El cron `dbBackup` del backend ejecuta `scripts/backup-db.sh`, que **no está en el repo** → en drp falla cada noche (inofensivo). No verificado en axioma. | 🟢 | Informativo. |
| **A-10** | **No hay endpoint público de salud** (`/api/health` pide token): el httpcheck de monitoreo tiene que usar otra ruta. | 🟢 | Informativo. |

---

## 12. Registro de ejecución — 2026-09-15

Horas -03. Las de drp salen de sus logs (UTC −3).

| Hora | Paso | Acción | Resultado | Duración |
|---|---|---|---|---|
| < 09:30 | 0 | Relevamiento axioma/dev-1/drp (solo lectura) | Dos alvera (prod/demo), drill viejo en drp, A-1…A-3 | — |
| 09:33 | 0 | `infra-secrets`: `mediflow-backend.env` → `alvera-backend.env` con el vivo, commit `e29ea3e` | ✅ 23/23 claves | — |
| ~09:34 | 10 | Teardown del simulacro 2026-08-12 (`mediflowapp`, `mediflow_db`, vhost `alvera-drill`, unit) | ✅ checkpoint siguió 200 · +355 MB libres | ~1 min |
| 09:34:55 | 2 | `pgbackrest restore --db-include=alvera_db --archive-mode=off` | ✅ | **50 s** |
| 09:35:46 | 2 | Replay de WAL + promoción | ✅ última transacción **09:38:13** · 89 tablas · 84 migraciones · `archive_mode=off` | **3 min 6 s** |
| 09:38:55 | 2 | `pg_dump` + borrar temporal | ✅ 5,5 MB | 2 s |
| ~09:39 | 3 | Rol + base + `pg_restore` fiel | ✅ owners 88/1 · `uuid-ossp` | 2 s |
| ~09:40 | 3.3 | Neutralización de canales (1.er intento revertido por un INSERT de marcador inválido; transacción íntegra) | ✅ WhatsApp/email/SMS `enabled=false` | — |
| ~09:41 | 4–5 | Usuario `alveraapp`, código `f36c138` (46 MB), `.env` backend y frontend | ✅ | — |
| 09:41–09:44 | 6 | `npm ci` backend · `npm ci` frontend · `vite build` | ✅ | **73 s · 38 s · 38 s** |
| ~09:42 | 7 | Adjuntos dev-1 → drp | ✅ 6/6 sha256 == prod | 1 s |
| ~09:42 | 8 | vhost `alveradrp` + certbot | ✅ cert hasta 2026-12-14 | — |
| ~09:44 | 9.2 | Legibilidad PHI | ✅ **2993 ok / 0 fail** en 18 columnas | — |
| ~09:45 | 6 | ❌ bundle sin `/api` detectado → `.env.production` corregido y rebuild | ✅ 3 archivos con `/api`, igual que prod | 37 s |
| 09:46:17 | 8 | `pm2 start --env production` | ✅ 2 instancias, health a los 8 s, 0 restarts tras 60 s | 8 s |
| ~09:48 | 8–9 | systemd + boot test + verificación externa | ✅ ver §9.3 | — |
| 09:49 | — | Estado final drp | ✅ 4 apps `online`, 0 restarts, 2129 MB disponibles | — |
| — | 9.3 | Login real + ficha de paciente | ⏳ pendiente (persona) | — |

**Resultado: PASS.** Alvera **queda levantada en drp** para el login manual. Después: §10.

*Documento creado el 2026-09-15 durante el simulacro. Reemplaza como procedimiento ejecutado a las secciones
de alvera del runbook general, que siguen valiendo como contexto.*
