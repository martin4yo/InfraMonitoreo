# Configuración de axioma — copia versionada

> **Por qué existe este directorio.** Los vhosts de nginx, los `ecosystem.config.js` y las unidades
> systemd **existían únicamente en axioma**. Si axioma muere, se pierden con él y hay que reconstruirlos
> de memoria en medio de una catástrofe. Es el hueco **10.8** del
> [runbook de recuperación](../../docs/drp-recuperacion-axioma-en-drp.md), detectado en el simulacro del
> 2026-08-12.
>
> **Extraído el 2026-08-12**, en solo lectura y sin escribir nada en axioma.
>
> ⚠️ **Esto es una FOTO, no la fuente de verdad.** La fuente sigue siendo el servidor. Si se cambia un
> vhost en axioma, hay que reflejarlo acá — la cadencia **C6** de
> [G6](../../docs/gobierno/g6-revisiones-periodicas.md) es el momento natural.

## Contenido

| Directorio | Qué hay | Para qué sirve en un DR |
|---|---|---|
| `nginx/` | 12 vhosts + `nginx.conf` + snippets anti-scanner | Reconstruir el enrutamiento: dominios, puertos de `proxy_pass`, rutas de estáticos |
| `pm2/` | 4 `ecosystem.config.js` | Arrancar cada app con sus parámetros reales (instancias, memoria, TZ) |
| `systemd/` | 9 unidades (`pm2-*`, `axio-db-agent`) | Recrear el arranque automático y el hardening del agente |

## Verificación de secretos

Antes de versionar se escaneó el contenido buscando credenciales, claves privadas, `DATABASE_URL` con
password y cadenas base64 largas. **Resultado: 0 hallazgos.** Revisión manual confirmatoria:

- Las directivas `Environment=` de systemd solo contienen `PATH`, `PM2_HOME` y `NODE_ENV`.
- Los bloques `env:` de los ecosystem solo tienen `NODE_ENV`, `PORT` y `TZ`. Los secretos viven en los
  `.env`, que están cifrados en `infra-secrets` — el `ecosystem.config.js` de parse lo dice explícito:
  *"Las API keys y credenciales deben estar en backend/.env, NO aquí"*.
- Las `ssl_certificate` son **rutas** a `/etc/letsencrypt/…`, no material criptográfico.

> **Si algún día se agrega un secreto a un `ecosystem.config.js`, este directorio deja de ser seguro para
> versionar.** Re-escanear antes de cada actualización.

## Lo que se aprende leyendo esta configuración

**`PM2_HOME` no es uniforme.** Tres apps no usan el home de su usuario:

| App | `PM2_HOME` |
|---|---|
| parse | `/var/www/parse/.pm2` |
| clubix *(en axioma)* | `/var/www/clubix/.pm2` |
| root | `/root/.pm2` |
| el resto | `/home/<user>/.pm2` |

Es la causa más probable de *"PM2 no encuentra la app"* durante un DR.

**Hay unidades systemd de apps que ya no existen.** `pm2-clubixapp.service` sigue instalada en axioma,
pero la app de clubix en ese servidor **se decomisionó el 2026-07-04** (era una instancia zombi; ver la
nota del [Apéndice A del DRP](../../docs/disaster-recovery-plan.md)). La producción de clubix vive en el
servidor `clubix`. **No recrear esta unidad en un DR.**

**Hay 3 vhosts de respaldo sin versionar** (`parse.bak-1783198297`, `.bak-1783200134`, `.bak-1783375210`)
que quedaron en `sites-available` de axioma. No se copiaron a propósito: son restos de ediciones, no
configuración vigente. Conviene limpiarlos del servidor.

## Cómo usarlo en una recuperación

Los vhosts referencian rutas y certificados que **no existen en el servidor nuevo**. Al restaurarlos:

1. Copiar el vhost a `/etc/nginx/sites-available/` y enlazarlo.
2. Ajustar `ssl_certificate` — o **quitar los bloques TLS** hasta emitir certificados nuevos. ⚠️ Ver
   [§0.4 del runbook](../../docs/drp-recuperacion-axioma-en-drp.md): el límite de Let's Encrypt es de
   **5 emisiones por dominio por semana y es compartido con axioma**.
3. Verificar que los puertos de `proxy_pass` coincidan con lo que la app realmente levantó.
4. `nginx -t` antes de recargar, y **re-testear a los pocos segundos**: tras un `reload`, el primer
   request lo atiende el worker viejo (mordió en el simulacro del 08-12).
