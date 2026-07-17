# InfraMonitoreo

Monitoreo y alertas para 4 servidores Linux (3 producción + 1 desarrollo) en distintos
proveedores de hosting, basado en **Netdata + Netdata Cloud**.

Objetivo: detectar fallas de **recursos** (CPU, RAM, disco, swap), de **servicios**
(PostgreSQL, nginx, pm2/Node, Python) y de **disponibilidad de las apps** (chequeos HTTP)
**antes de que el error llegue a los clientes**, con avisos por **Telegram y Email**.

## Arquitectura

```
   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
   │  PROD-1     │   │  PROD-2     │   │  PROD-3     │   │  DEV-1      │
   │ netdata     │   │ netdata     │   │ netdata     │   │ netdata     │
   │ + colectores│   │ + colectores│   │ + colectores│   │ + colectores│
   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
          │                 │                 │                 │
          └─────────────────┴────────┬────────┴─────────────────┘
                                      │ (claim / outbound 443)
                              ┌───────▼────────┐
                              │  Netdata Cloud │  (SaaS, plan free)
                              │  dashboards +  │
                              │  alertas       │
                              └───────┬────────┘
                                      │
                          ┌───────────┴───────────┐
                          ▼                       ▼
                     📱 Telegram              📧 Email
```

- **No hay servidor central que mantener.** Cada agente sale por HTTPS (443) hacia
  Netdata Cloud; no hace falta abrir puertos de entrada en los servers.
- Las **notificaciones (Telegram + Email)** se configuran una sola vez en Netdata Cloud
  y aplican a todos los nodos.

## Qué se monitorea

| Capa            | Qué                                              | Cómo                                  |
|-----------------|--------------------------------------------------|---------------------------------------|
| Sistema         | CPU, RAM, swap, disco, I/O, red, temperatura     | Netdata (out-of-the-box)              |
| **Disco**       | % usado **y proyección de llenado**              | Alarmas `disk_fill_rate` (built-in)   |
| PostgreSQL      | conexiones, locks, replicación, cache hit, vacíos| colector `go.d/postgres`              |
| nginx           | requests, conexiones activas, 4xx/5xx            | colector `go.d/nginx` (stub_status)   |
| pm2 / Node      | procesos vivos, CPU/RAM por app                  | `apps.plugin` (apps_groups.conf)      |
| Python          | procesos, CPU/RAM                                | `apps.plugin`                         |
| **Apps (HTTP)** | ¿responde el endpoint? latencia, status code     | colector `go.d/httpcheck` (varias por server) |
| pgBackRest      | edad de backup, backup fallido, `check` fallido  | colector custom statsd (`scripts/30`) |

## Fases

1. **Inventario + Netdata base** — detectar quién ya tiene Netdata, instalar/actualizar
   en los 4, reclamar contra Netdata Cloud, validar métricas de sistema y alertas.
2. **Colectores de servicios** — PostgreSQL, nginx, apps.plugin (pm2/Node/Python).
3. **Disponibilidad de apps** — chequeos HTTP de cada endpoint público/health.
4. **Backups** — alarma de antigüedad de backup pgBackRest en los servers que lo usen.
5. **Notificaciones** — Telegram + Email en Netdata Cloud, prueba end-to-end.

## Uso

```bash
# 1. Copiá la plantilla de inventario y completala con tus servers
cp inventory.example.sh inventory.sh
$EDITOR inventory.sh

# 2. Detectar el estado actual (quién tiene netdata y qué versión)
./scripts/00-detect-netdata.sh

# 3. Instalar/actualizar agente + reclamar a Netdata Cloud
#    (necesitás CLAIM_TOKEN y CLAIM_ROOM de tu cuenta de Netdata Cloud)
./scripts/10-install-and-claim.sh

# 4. Desplegar configs de colectores y alarmas a todos los nodos
./scripts/20-deploy-configs.sh
```

> Los scripts orquestan por **SSH** desde tu máquina. En Windows corrén en **Git Bash**
> o **WSL** (necesitan `ssh`/`scp`). No requieren abrir puertos en los servers.

### Monitoreo de pgBackRest

```bash
./scripts/30-deploy-pgbackrest-monitoring.sh   # colector + alarmas en los servers con pgBackRest
```

### pgBackRest dual-repo: central en dev-1 (SSH) + Cloudflare R2 (S3)

Los 4 servers respaldan **en paralelo a dos repositorios**: **repo1** central en dev-1
(`/backup/pgbackrest`) por **SSH**, y **repo2** en **Cloudflare R2** (bucket
`axiomacloud-pgbackrest`, cifrado) como copia off-site que elimina el SPOF de dev-1.
pgBackRest 2.58 unificado (repo PGDG). Arquitectura, confianza SSH, el caso loopback de
dev-1 y los gotchas (puerto 2222 de clubix, `AllowUsers`, fail2ban) están en
[docs/pgbackrest-setup.md](docs/pgbackrest-setup.md). Configs de referencia en
`pgbackrest/repo-host/` y `pgbackrest/db-host/`.

## Documentación

- [docs/setup-netdata-cloud.md](docs/setup-netdata-cloud.md): cuenta + `CLAIM_TOKEN`,
  notificaciones Telegram + Email, usuario read-only de PostgreSQL, `stub_status` en nginx.
- [docs/pgbackrest-setup.md](docs/pgbackrest-setup.md): repositorio central pgBackRest
  por SSH (estado implementado), incluyendo el caso loopback de dev-1.
