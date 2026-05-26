#!/usr/bin/env bash
# Plantilla de inventario. Copiala a inventory.sh y completá tus datos reales.
#   cp inventory.example.sh inventory.sh
#
# ─────────────────────────────────────────────────────────────────────────────
# SERVIDORES
# Formato de cada server (campos separados por '|'):
#   nombre | host_o_ip | usuario_ssh | puerto_ssh | rol
#
#   - nombre:      alias para mostrar (sin espacios), ej. prod-api
#   - host_o_ip:   IP o hostname para SSH
#   - usuario_ssh: usuario con sudo (o root) — el mismo de tu clave SSH
#   - puerto_ssh:  normalmente 22
#   - rol:         prod | dev   (informativo)
# ─────────────────────────────────────────────────────────────────────────────
SERVERS=(
  "prod-1|1.2.3.4|root|22|prod"
  "prod-2|5.6.7.8|ubuntu|22|prod"
  "prod-3|9.10.11.12|root|22|prod"
  "dev-1|13.14.15.16|ubuntu|22|dev"
)

# ─────────────────────────────────────────────────────────────────────────────
# ENDPOINTS HTTP A CHEQUEAR  (¡varias apps por server!)
# Formato de cada endpoint (campos separados por '|'):
#   server | nombre_app | url
#
#   - server:     debe coincidir con el 'nombre' de un server de arriba
#   - nombre_app: alias de la app (sin espacios), ej. api, admin, web
#   - url:        URL a chequear, idealmente un endpoint /health que devuelva 200
#
# Poné tantas líneas como apps tengas. El chequeo de cada server corre DESDE ese
# server (chequea sus propias apps en localhost o por su dominio).
# ─────────────────────────────────────────────────────────────────────────────
ENDPOINTS=(
  "prod-1|api|https://api.midominio.com/health"
  "prod-1|web|https://www.midominio.com/"
  "prod-1|admin|http://127.0.0.1:3001/health"
  "prod-2|tienda|https://tienda.midominio.com/health"
  "prod-2|checkout|https://checkout.midominio.com/health"
  "prod-3|app|https://app.otrodominio.com/health"
  "dev-1|api-dev|http://127.0.0.1:3000/health"
)

# ─────────────────────────────────────────────────────────────────────────────
# pgBackRest
# Servers donde correr el MONITOREO de pgBackRest (por 'nombre').
# Objetivo: pgBackRest en los 3 de prod + dev, todos pegando al repo en dev-1.
# ─────────────────────────────────────────────────────────────────────────────
PGBACKREST_SERVERS=("prod-1" "prod-2" "prod-3" "dev-1")
PGBACKREST_USER="postgres"   # usuario dueño de pgBackRest en los servers
PGBACKREST_REPO_HOST="dev-1" # server que aloja el repositorio central de backups

# ─────────────────────────────────────────────────────────────────────────────
# Netdata Cloud — token y room (ver docs/setup-netdata-cloud.md).
# Mejor exportarlos desde secrets.sh (gitignored) en vez de hardcodearlos acá.
# ─────────────────────────────────────────────────────────────────────────────
CLAIM_TOKEN="${CLAIM_TOKEN:-}"
CLAIM_ROOMS="${CLAIM_ROOMS:-}"
CLAIM_URL="${CLAIM_URL:-https://app.netdata.cloud}"
