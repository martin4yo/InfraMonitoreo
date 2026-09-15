# Rotación de logs PM2 — los 5 servers

Configs de `logrotate` versionadas. Se despliegan en `/etc/logrotate.d/pm2-apps`
de cada server. Resuelven el crecimiento sin control de los logs de PM2
(en julio 2026 había un `pm2.log` de **2,07 GB** en dev-1 y 246 MB en axioma).

| Archivo | Server | Notas |
|---|---|---|
| `pm2-axioma` | axioma | mini **excluido** (bloque comentado, ver abajo) |
| `pm2-dev-1` | dev-1 | incluye `/var/log/mini` |
| `pm2-clubix` | clubix | |
| `pm2-axiodemo` | axiodemo | |
| `pm2-axioma-drp` | axioma-drp | preventiva: hoy el server no tiene apps |

## Despliegue

```bash
sudo install -m 644 -o root -g root logrotate/pm2-<server> /etc/logrotate.d/pm2-apps
sudo logrotate -d /etc/logrotate.d/pm2-apps      # simulación, no escribe nada
sudo logrotate -fv /etc/logrotate.d/pm2-apps     # rotación forzada (solo si hace falta)
```

Rollback: `sudo rm /etc/logrotate.d/pm2-apps`. No hay servicios que reiniciar ni
configs de PM2 modificadas — esa es la ventaja de `copytruncate` sobre el módulo
`pm2-logrotate`.

## Criterios

- **`copytruncate`** — copia el archivo y trunca el original en su lugar. La app
  conserva su descriptor abierto, así que **no hay que reiniciar ni recargar nada**.
  Contrapartida: entre el `cp` y el `truncate` hay una ventana de milisegundos
  donde las líneas escritas se pierden. Aceptable para logs de acceso; no lo sería
  para auditoría.
- **`daily` + `rotate 7`** — una semana de retención. Se evaluó `size 50M` y se
  descartó: el crecimiento es de ~2,8 MB/día, el corte diario es más predecible.
- **`compress` + `delaycompress`** — el gzip ocurre en la corrida siguiente, lo que
  reparte el I/O en dos días. Importante con archivos de cientos de MB.
- **`su <user> <group>`** — obligatorio, ver gotcha #2.
- **`create 640 <user> <group>`** — ver gotcha #3.

## Gotchas (aprendidos ejecutando, no teóricos)

### 1. `~/.pm2/logs/*.log` NO alcanza: el stdout real va a `~/.pm2/pm2.log`

**El hallazgo más importante de esta tanda.** Los archivos `<app>-out-N.log` de
`~/.pm2/logs/` pueden estar **en 0 bytes mientras la app loguea normalmente**:
PM2 redirige el stdout/stderr de los procesos a `~/.pm2/pm2.log`, un nivel arriba.

En dev-1 ese archivo tenía **2,07 GB** y no lo cubría ningún glob del inventario
inicial, que solo miró `~/.pm2/logs/`.

Cómo verificar a qué archivo escribe realmente un proceso:

```bash
sudo ls -l /proc/<pid>/fd/1 /proc/<pid>/fd/2
# -> /home/<user>/.pm2/pm2.log
```

Por eso **cada bloque lista los dos patrones**:
`/home/<user>/.pm2/logs/*.log /home/<user>/.pm2/pm2.log`.

Corolario para diagnosticar: un log activo que queda en 0 bytes tras rotar **no
prueba** que `copytruncate` haya fallado — puede ser que nadie escriba ahí. La
prueba concluyente es escribir al descriptor y ver si el archivo crece:

```bash
sudo sh -c "echo TEST >> /proc/<pid>/fd/1"
sudo stat -c %s /home/<user>/.pm2/pm2.log   # > 0 => el fd está sano
```

### 2. `su` es obligatorio, o logrotate ignora el bloque

Los directorios `.pm2` son `775` (writable por grupo), y logrotate se niega a
rotar bajo directorios que considera inseguros:

```
error: skipping "/home/x/.pm2/pm2.log" because parent directory has insecure
permissions (It's world writable or writable by group which is not "root")
```

Se resuelve con `su <user> <group>` en cada bloque. Por eso no se usa una config
genérica con globs `/home/*/.pm2/...`: cada bloque necesita su propio `su`.

### 3. Con `copytruncate`, `create` NO aplica al archivo activo

`copytruncate` trunca el archivo existente en vez de crear uno nuevo, así que la
directiva `create 640` **solo rige sobre los rotados**. El archivo activo conserva
sus permisos originales (los de PM2, típicamente `664` = world-readable).

Para cerrar la exposición hay que hacer un `chmod 640` explícito sobre los activos,
como paso aparte. Es seguro en caliente: el proceso ya tiene el descriptor abierto
y los permisos se evalúan al abrir, no al escribir — pero conviene verificarlo
empíricamente después (escribir al fd y confirmar que el archivo crece).

### 4. El archivo de config debe ser `644 root:root`

Si es writable por grupo u otros, logrotate lo **ignora en silencio**:

```
error: Ignoring /etc/logrotate.d/pm2-apps because it is writable by group or others.
```

De ahí el `install -m 644 -o root -g root` del despliegue.

### 5. En dev-1, coordinar con pgBackRest

dev-1 es el repo host de los backups de toda la infra. Antes de una rotación
forzada de archivos grandes, verificar que no haya un backup en curso:

```bash
sudo ps -eo args | grep "[p]gbackrest"
```

Referencia de costo: copiar 2,07 GB tardó **59 s** y no afectó a las apps.

## Pendiente — mini en axioma

El bloque de `/home/miniapp/.pm2/logs/` en `pm2-axioma` está **comentado a propósito**.

`mini-backend-out-0.log` (~125 MB) contiene **credenciales en claro** —
contraseñas de usuarios finales, `whatsappApiKey` de Evolution API y `smtpPass`
de Gmail— volcadas por tres `console.log` de la app
(`src/middleware/validateRequest.ts:7` y `:9`, `src/routes/tenants.ts:154`).

El archivo es la evidencia del alcance de esa exposición. **No rotar hasta que el
usuario termine de rotar esas credenciales.** Para activarlo: descomentar el
bloque y correr `logrotate -d` antes de aplicar.
