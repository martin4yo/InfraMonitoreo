#!/usr/bin/env bash
# Despliega el MONITOREO de pgBackRest (no instala pgBackRest) a los servers de
# PGBACKREST_SERVERS: script colector + cron + chart statsd + alarmas, y recarga.
# Idempotente. Asumí que pgBackRest ya está instalado y con stanza creada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

NETDATA_DIR="$ROOT_DIR/netdata"
PGUSER="${PGBACKREST_USER:-postgres}"

for name in "${PGBACKREST_SERVERS[@]}"; do
  rec="$(server_record_by_name "$name")" || { err "server '$name' no está en SERVERS"; continue; }
  parse_server "$rec"
  log "Desplegando monitoreo pgBackRest en $S_NAME ($S_HOST)"
  SUDO="$(sudo_prefix "$S_USER")"

  # 1) Script colector
  scp_to "$S_USER" "$S_HOST" "$S_PORT" \
    "$NETDATA_DIR/pgbackrest/pgbackrest-collect.py" "/tmp/pgbackrest-collect.py.$$"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
    "${SUDO}mv /tmp/pgbackrest-collect.py.$$ /usr/local/bin/pgbackrest-collect.py && ${SUDO}chmod 755 /usr/local/bin/pgbackrest-collect.py"
  ok "colector instalado"

  # 2) Cron como el usuario de pgBackRest, cada 30 min ('check' hace switch de WAL)
  cron_line="*/30 * * * * ${PGUSER} /usr/bin/python3 /usr/local/bin/pgbackrest-collect.py"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
    "echo '$cron_line' | ${SUDO}tee /etc/cron.d/pgbackrest-netdata >/dev/null && ${SUDO}chmod 644 /etc/cron.d/pgbackrest-netdata"
  ok "cron cada 30 min (usuario ${PGUSER})"

  # 3) Chart statsd + alarmas
  scp_to "$S_USER" "$S_HOST" "$S_PORT" \
    "$NETDATA_DIR/statsd.d/pgbackrest.conf" "/tmp/pgb-statsd.$$"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" \
    "$NETDATA_DIR/health.d/pgbackrest.conf" "/tmp/pgb-health.$$"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    ${SUDO}mkdir -p /etc/netdata/statsd.d /etc/netdata/health.d &&
    ${SUDO}mv /tmp/pgb-statsd.$$ /etc/netdata/statsd.d/pgbackrest.conf &&
    ${SUDO}mv /tmp/pgb-health.$$ /etc/netdata/health.d/pgbackrest.conf"
  ok "statsd + alarmas"

  # 4) Primera corrida manual para poblar la métrica de una
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
    "${SUDO}-u ${PGUSER} /usr/bin/python3 /usr/local/bin/pgbackrest-collect.py || true"

  # 5) Recargar Netdata (statsd nuevo requiere restart; health solo reload)
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}systemctl restart netdata"
  ok "Netdata reiniciado"
done

log "Monitoreo pgBackRest desplegado. Verificá en Netdata Cloud los charts pgbackrest.*"
