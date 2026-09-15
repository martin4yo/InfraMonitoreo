#!/usr/bin/env bash
# Despliega la GUARDIA DE SIMULACROS en el host de simulacros (axioma-drp). Idempotente.
#
# Marca el host con /etc/drp/host-simulacros y actualiza el selfcheck + statsd + alarmas
# SOLO en ese host. Desde ahí, hardening-selfcheck.sh publica watchdog.self.drp_limpio y la
# alarma watchdog_drp_simulacro_olvidado avisa si una base de simulacro supera las 48 h sin
# estar declarada en /etc/drp/simulacros-permitidos.
#
# POR QUÉ (2026-09-15): los simulacros de hub, parse y alvera del 2026-08-12 dieron PASS y
# quedaron corriendo 34 días con datos de producción. Ver docs/drp-programa-simulacros.md §4.
#
# Declarar una excepción (simulacro de varios días), en el host:
#   echo "clubix_db 2026-10-26" | sudo tee -a /etc/drp/simulacros-permitidos
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory
NETDATA_DIR="$ROOT_DIR/netdata"

HOST_NAME="${HOST_NAME:-axioma-drp}"
rec="$(server_record_by_name "$HOST_NAME")" || { err "'$HOST_NAME' no está en SERVERS"; exit 1; }
parse_server "$rec"
# En un server productivo la guardia contaría como "simulacro vencido" TODA base con >48 h.
[[ "$S_NAME" == "axioma-drp" || "${FORCE:-0}" == "1" ]] || {
  err "$S_NAME no es el host de simulacros (axioma-drp). Usar FORCE=1 solo si lo es."; exit 1; }
SUDO="$(sudo_prefix "$S_USER")"
log "Guardia de simulacros en $S_NAME ($S_HOST:$S_PORT)"

ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  set -e
  ${SUDO}install -d -m 755 /etc/drp
  echo '# Host de simulacros DRP: hardening-selfcheck.sh vigila bases de simulacro con >48 h. Ver docs/drp-programa-simulacros.md' \
    | ${SUDO}tee /etc/drp/host-simulacros >/dev/null
  [ -f /etc/drp/simulacros-permitidos ] || printf '%s\n' \
    '# Excepciones con vencimiento: <base> <AAAA-MM-DD> (vigente hasta ese dia inclusive).' \
    '# Una linea por base. Vencida la fecha, la base vuelve a contar como simulacro olvidado.' \
    | ${SUDO}tee /etc/drp/simulacros-permitidos >/dev/null
"
ok "host marcado (/etc/drp/host-simulacros) y archivo de excepciones presente"

scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/watchdog/hardening-selfcheck.sh" "/tmp/sc.$$"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/statsd.d/watchdog-self.conf" "/tmp/sc-statsd.$$"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/health.d/watchdog-self.conf" "/tmp/sc-health.$$"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  set -e
  ${SUDO}mv /tmp/sc.$$ /usr/local/bin/hardening-selfcheck.sh && ${SUDO}chmod 755 /usr/local/bin/hardening-selfcheck.sh
  ${SUDO}mv /tmp/sc-statsd.$$ /etc/netdata/statsd.d/watchdog-self.conf
  ${SUDO}mv /tmp/sc-health.$$ /etc/netdata/health.d/watchdog-self.conf
  ${SUDO}systemctl restart netdata
  sleep 5
  ${SUDO}/usr/local/bin/hardening-selfcheck.sh || true
  sleep 3
  ${SUDO}netdatacli reload-health >/dev/null 2>&1 || true
"
ok "selfcheck con drp_limpio + alarma watchdog_drp_simulacro_olvidado en $S_NAME"
