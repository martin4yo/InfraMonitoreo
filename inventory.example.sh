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
PGBACKREST_USER="postgres"      # usuario dueño de pgBackRest en los db hosts
PGBACKREST_REPO_HOST="dev-1"    # server que aloja el repositorio central de backups
PGBACKREST_REPO_OWNER="pgbackrest"  # usuario OS dueño del repo (corre el colector de monitoreo)

# ─────────────────────────────────────────────────────────────────────────────
# OFFSITE a Cloudflare R2 (repo2, S3-compatible, cifrado). scripts/50-deploy-r2-offsite.sh
# Las CREDENCIALES van en secrets.sh (gitignored), NO acá:
#   R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
#   PGBACKREST_R2_CIPHER_PASS   (la passphrase es CRÍTICA: sin ella el offsite es irrecuperable)
# Knobs opcionales (defaults sanos para R2):
# ─────────────────────────────────────────────────────────────────────────────
R2_REGION="${R2_REGION:-auto}"             # R2 usa 'auto'
R2_REPO2_PATH="${R2_REPO2_PATH:-/pgbackrest}"  # prefijo dentro del bucket

# ─────────────────────────────────────────────────────────────────────────────
# Netdata Cloud — token y room (ver docs/setup-netdata-cloud.md).
# Mejor exportarlos desde secrets.sh (gitignored) en vez de hardcodearlos acá.
# ─────────────────────────────────────────────────────────────────────────────
CLAIM_TOKEN="${CLAIM_TOKEN:-}"
CLAIM_ROOMS="${CLAIM_ROOMS:-}"
CLAIM_URL="${CLAIM_URL:-https://app.netdata.cloud}"
