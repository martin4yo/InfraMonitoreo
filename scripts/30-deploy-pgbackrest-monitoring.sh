#!/usr/bin/env bash
# Despliega el MONITOREO de pgBackRest en el REPO HOST (dev-1): script colector +
# cron + chart statsd + alarmas, y recarga Netdata. Idempotente.
#
# El colector corre como el usuario dueño del repo (PGBACKREST_REPO_OWNER, ej.
# pgbackrest), que es quien ve TODAS las stanzas con `pgbackrest info`. Lee solo
# `info` (no fuerza WAL switches). Reporta a Netdata vía statsd la edad del backup
# de la peor stanza y un estado OK agregado; las alarmas avisan por Telegram.
#
# Asume que pgBackRest ya está funcionando (ver docs/pgbackrest-setup.md).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

NETDATA_DIR="$ROOT_DIR/netdata"
REPO_HOST="${PGBACKREST_REPO_HOST:?falta PGBACKREST_REPO_HOST en inventory.sh}"
REPO_OWNER="${PGBACKREST_REPO_OWNER:-pgbackrest}"

rec="$(server_record_by_name "$REPO_HOST")" || { err "repo host '$REPO_HOST' no está en SERVERS"; exit 1; }
parse_server "$rec"
log "Desplegando monitoreo pgBackRest en el repo host $S_NAME ($S_HOST), colector como '$REPO_OWNER'"
SUDO="$(sudo_prefix "$S_USER")"

# 1) Script colector
scp_to "$S_USER" "$S_HOST" "$S_PORT" \
  "$NETDATA_DIR/pgbackrest/pgbackrest-collect.py" "/tmp/pgbackrest-collect.py.$$"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
  "${SUDO}mv /tmp/pgbackrest-collect.py.$$ /usr/local/bin/pgbackrest-collect.py && ${SUDO}chmod 755 /usr/local/bin/pgbackrest-collect.py"
ok "colector instalado"

# 2) Cron como el usuario dueño del repo, cada 15 min (info es barato, sin WAL switch)
cron_line="*/15 * * * * ${REPO_OWNER} /usr/bin/python3 /usr/local/bin/pgbackrest-collect.py"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
  "echo '$cron_line' | ${SUDO}tee /etc/cron.d/pgbackrest-netdata >/dev/null && ${SUDO}chmod 644 /etc/cron.d/pgbackrest-netdata"
ok "cron cada 15 min (usuario ${REPO_OWNER})"

# 3) Chart statsd + alarmas
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/statsd.d/pgbackrest.conf" "/tmp/pgb-statsd.$$"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/health.d/pgbackrest.conf" "/tmp/pgb-health.$$"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  ${SUDO}mkdir -p /etc/netdata/statsd.d /etc/netdata/health.d &&
  ${SUDO}mv /tmp/pgb-statsd.$$ /etc/netdata/statsd.d/pgbackrest.conf &&
  ${SUDO}mv /tmp/pgb-health.$$ /etc/netdata/health.d/pgbackrest.conf"
ok "statsd + alarmas"

# 4) Primera corrida manual para poblar la métrica
ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
  "${SUDO}-u ${REPO_OWNER} /usr/bin/python3 /usr/local/bin/pgbackrest-collect.py || true"

# 5) Recargar Netdata (statsd nuevo requiere restart)
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}systemctl restart netdata"
ok "Netdata reiniciado"

log "Monitoreo pgBackRest desplegado en $S_NAME. Verificá el chart pgbackrest.* en Netdata Cloud."
