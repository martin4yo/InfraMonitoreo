# Protección anti-scanners de nginx

Corta los bots que escanean exploits de WordPress/PHP y, de paso, silencia la
alarma de Netdata que disparaban. Se aplica con
[`scripts/60-deploy-anti-scanner.sh`](../scripts/60-deploy-anti-scanner.sh).

## El problema

Bots (sobre todo desde IPs de **Microsoft Azure**, con User-Agent vacío o
`*-Scanner/*`) escanean cada ~2 horas buscando rutas tipo `/wp-login.php`,
`/xmlrpc.php`, `/wso.php`, `/wp-content/...`, `/xmlrpc.php`, etc.

Ninguna de nuestras apps usa PHP, así que **no hay riesgo real**: el bot recibe
un `301` (redirect http→https) o nuestro `index.html`, nunca ejecuta nada. Pero
la ráfaga de cientos de `301` en un minuto dispara la alarma de Netdata:

```
web_log_nginx.requests_by_type
⚠️ web log 1m redirects     (3xx salvo 304 supera el umbral)
🔴 web log 1m successful    (baja como contracara de lo anterior)
```

Se recupera sola en minutos, pero es ruido recurrente.

## La solución (3 piezas)

| Pieza | Archivo | Qué hace |
|---|---|---|
| `map $request_uri $loggable` | `snippets/scanner-map.conf` (contexto `http`) | Marca con `0` las URIs de scanner (`.php`, `.cgi`, `wp-*`, `xmlrpc`, …) |
| `access_log … if=$loggable` | `nginx.conf` | El scanner (`loggable=0`) **no se escribe** en `access.log`. Netdata lee ese archivo ⇒ deja de ver el ruido ⇒ no dispara la alarma |
| `if ($loggable = 0) { return 444; }` | `snippets/block-scanners.conf`, incluido al inicio de **cada** `server{}` | Cierra la conexión sin responder. Va a nivel server, así corre **antes** del `return 301` y también protege los vhosts de redirección |

`444` = nginx cierra la conexión sin enviar respuesta (no alimenta al bot).
El tráfico legítimo (`loggable=1`) pasa exactamente igual que antes.

## Aplicar

```bash
./scripts/60-deploy-anti-scanner.sh        # itera SERVERS de inventory.sh
```

Por cada server, el helper `_nginx-block-scanners.py`:

1. Hace **backup** completo en `/etc/nginx/_backup_block_scanners_<timestamp>`.
2. Escribe los snippets y edita `nginx.conf` + cada archivo de `sites-enabled` y
   `conf.d` que tenga `server{}` (salta el de Netdata/stub_status).
3. Corre `nginx -t`. **Si falla, restaura el backup automáticamente** y aborta
   sin recargar.

El orquestador recién entonces hace `systemctl reload nginx` (graceful, sin
downtime). Es **idempotente**: re-correrlo salta lo ya aplicado, por lo que
conviene re-ejecutarlo al **agregar un vhost o un server nuevo**.

> **Nota:** tras el reload, el primer request puede pasar de largo porque lo
> atiende el worker viejo que está drenando. Re-testear a los pocos segundos.

## Verificar

Desde el propio server (ajustá el Host a un vhost real):

```bash
# scanner -> 000 (conexión cerrada = 444)
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 \
     -H 'Host: TU-VHOST' http://127.0.0.1/wp-login.php

# legítimo -> 301 (http) / 200 (https), sin cambios
curl -s  -o /dev/null -w '%{http_code}\n' -H 'Host: TU-VHOST' http://127.0.0.1/
curl -sk -o /dev/null -w '%{http_code}\n' --resolve TU-VHOST:443:127.0.0.1 https://TU-VHOST/

# que el scanner NO quede en access.log (lo que ve Netdata)
curl -s -o /dev/null -H 'Host: TU-VHOST' http://127.0.0.1/zzz-check.php
sudo grep -c zzz-check /var/log/nginx/access.log    # -> 0
```

## Rollback

```bash
BK=/etc/nginx/_backup_block_scanners_<timestamp>     # ver el que corresponda
sudo cp -a "$BK"/etc/nginx/. /etc/nginx/
sudo nginx -t && sudo systemctl reload nginx
```

## Nota sobre clubix

`clubix` fue el primero y usa una variante equivalente basada en `location`
(devuelve `444` + `access_log off` en `sites-available/clubix`), no el `map`.
El resultado es el mismo; no hace falta re-aplicarlo, pero correr el script ahí
también es inofensivo (ambos terminan en `444`).
