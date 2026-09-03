#!/usr/bin/env bash
# Despliega el monitoreo de archive-push en cada DB HOST (no en el repo host).
# Complementa scripts/30 (que corre en dev-1 y mira el repositorio): este corre en
# cada base y mira SU propio pg_stat_archiver + la cola de WAL sin archivar, para
# avisar aunque dev-1 (el repo host) esté caído. Idempotente.
#
# Motivación: el 2026-09-03 el reboot de dev-1 cortó archive-push ~90 s; una sesión
# lo vio como "repo1 roto" y el monitoreo (que vive en dev-1) no avisó porque el
# corte fue un blip. Un archive-push roto DE VERDAD recién se vería a ~15 min por
# atraso de WAL, y solo si dev-1 vive. Este colector cierra ese punto ciego.
#
# El colector corre como 'postgres' (ve pg_stat_archiver y el archive_status de
# PGDATA, ambos restringidos a ese usuario). Empuja a statsd local (UDP 8125).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

NETDATA_DIR="$ROOT_DIR/netdata"
PG_USER="postgres"

for name in "${PGBACKREST_SERVERS[@]}"; do
  rec="$(server_record_by_name "$name")" || { err "'$name' no está en SERVERS — se omite"; continue; }
  parse_server "$rec"
  log "Desplegando monitoreo de archive-push en $S_NAME ($S_HOST:$S_PORT)"
  SUDO="$(sudo_prefix "$S_USER")"

  scp_to "$S_USER" "$S_HOST" "$S_PORT" \
    "$NETDATA_DIR/pgbackrest/archive-push-collect.py" "/tmp/apc.$$"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" \
    "$NETDATA_DIR/statsd.d/pgbackrest-archive.conf" "/tmp/apc-statsd.$$"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" \
    "$NETDATA_DIR/health.d/pgbackrest-archive.conf" "/tmp/apc-health.$$"

  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    set -e
    ${SUDO}mv /tmp/apc.$$ /usr/local/bin/archive-push-collect.py
    ${SUDO}chmod 755 /usr/local/bin/archive-push-collect.py
    ${SUDO}mkdir -p /etc/netdata/statsd.d /etc/netdata/health.d
    ${SUDO}mv /tmp/apc-statsd.$$ /etc/netdata/statsd.d/pgbackrest-archive.conf
    ${SUDO}mv /tmp/apc-health.$$ /etc/netdata/health.d/pgbackrest-archive.conf
    echo '*/5 * * * * ${PG_USER} /usr/bin/python3 /usr/local/bin/archive-push-collect.py >/dev/null 2>&1' \
      | ${SUDO}tee /etc/cron.d/pgbackrest-archive >/dev/null
    ${SUDO}chmod 644 /etc/cron.d/pgbackrest-archive
    ${SUDO}systemctl restart netdata
    sleep 5
    ${SUDO}-u ${PG_USER} /usr/bin/python3 /usr/local/bin/archive-push-collect.py || true
    sleep 3
    ${SUDO}netdatacli reload-health >/dev/null 2>&1 || true
  "
  ok "$S_NAME → colector archive-push + cron (5 min) + statsd + alarmas"
done

log "Monitoreo de archive-push desplegado en los db hosts. Charts pgbackrest.archive_* en Netdata Cloud."
