# Setup de Netdata Cloud + notificaciones + colectores

Guía paso a paso de lo que se hace **una sola vez** (cuenta, token, notificaciones)
y lo que hay que preparar en cada server para los colectores.

## 1. Cuenta y token de claim

1. Crear cuenta gratis en https://app.netdata.cloud
2. Crear un **Space** (ej. "Infra") y una **Room** (ej. "Servers").
3. En la Room → **Add Nodes** → pestaña Linux. Ahí ves el comando con
   `--claim-token XXXX --claim-rooms YYYY --claim-url https://app.netdata.cloud`.
4. Copiá esos valores a `secrets.sh` (este archivo está en `.gitignore`):

   ```bash
   # secrets.sh
   CLAIM_TOKEN="pegá-acá-el-token"
   CLAIM_ROOMS="pegá-acá-el-room-id"
   ```

   Luego `./scripts/10-install-and-claim.sh` los usa para instalar + reclamar.

## 2. Notificaciones: Telegram + Email (centralizado en la nube)

Se configuran en **Netdata Cloud**, una sola vez, y aplican a todos los nodos.
No hace falta configurar correo (MTA) en cada Linux.

**Email**
- Space → **Notifications** → Email → activar.
- Por defecto manda a los miembros del Space. Agregá `martin4yo@gmail.com`.

**Telegram**
1. En Telegram hablá con **@BotFather** → `/newbot` → te da un **bot token**.
2. Creá un grupo (o usá tu chat), agregá el bot, y obtené el **chat id**:
   - mandá un mensaje al bot/grupo y abrí
     `https://api.telegram.org/bot<TOKEN>/getUpdates` → mirá `chat.id`.
3. En Netdata Cloud → **Notifications** → Telegram → pegá bot token + chat id.
4. Mandá una notificación de prueba desde la UI.

> Tip: configurá la **severidad** por canal. Ej. Telegram para `critical` y
> `warning`; Email para `critical` solamente (o resúmenes), así no te satura.

## 3. PostgreSQL: usuario read-only para el colector

En **cada** server con PostgreSQL, una vez:

```sql
CREATE USER netdata PASSWORD 'una-clave-fuerte';
GRANT pg_monitor TO netdata;   -- rol de solo-lectura para monitoreo (PG 10+)
```

Luego poné esa clave en `netdata/go.d/postgres.conf` (campo `dsn`) antes de
desplegar, o configurá auth por socket (peer) y usá el DSN por socket comentado
en ese archivo.

## 4. nginx: habilitar stub_status

En **cada** server con nginx, agregá un server interno y recargá:

```nginx
server {
    listen 127.0.0.1:80;
    server_name _;
    location /stub_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## 5. pgBackRest: alarma de antigüedad de backup (fase 2)

`prod-1` y `dev-1` usan pgBackRest. La idea es alertar si el último backup OK es
demasiado viejo. Como Netdata no trae colector nativo de pgBackRest, se usa un
colector custom que parsea `pgbackrest info --output=json`:

```bash
# /usr/local/bin/pgbackrest-backup-age.sh  (corre como el usuario de pgbackrest)
# Emite la antigüedad en segundos del último backup full/incr OK.
pgbackrest info --output=json \
  | jq '[.[].backup[].timestamp.stop] | max' \
  | awk -v now="$(date +%s)" '{print "pgbackrest.backup_age age = " now-$1}'
```

Esto se conecta a Netdata vía `charts.d`/`statsd` y se le pone una alarma
`> 90000` (25 h) en `health.d/pgbackrest.conf`. Lo dejamos para la fase 4 una vez
que el resto esté andando; queda documentado acá para no perderlo.

**Pendiente además:** en `prod-2` y `prod-3` **no hay pgBackRest**. Conviene
implementarlo para tener backups en los 3 de producción (tema aparte del
monitoreo, pero importante).

## 6. Verificación end-to-end

- En Netdata Cloud, los 4 nodos en estado **Live**.
- Charts visibles: `postgres.*`, `nginx.*`, `httpcheck.*`, `apps.*` (pm2/node/python).
- Forzá una alarma de prueba (ej. llená disco en dev, o apagá un endpoint) y
  confirmá que llega a Telegram y Email.
