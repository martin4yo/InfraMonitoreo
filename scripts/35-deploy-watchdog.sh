#!/usr/bin/env bash
# Despliega el WATCHDOG de la flota. Idempotente.
#
# Dos piezas, a propósito separadas:
#
#   1) hostkey-watchdog.py  -> en dev-1 (host de monitoreo). Mira los 5 servers DESDE
#      AFUERA con ssh-keyscan (sin autenticar, sin abrir ninguna vía de acceso) y
#      alarma si una host key cambió (= sistema reinstalado) o si un server dejó de
#      responder. Es el control que faltaba cuando reinstalaron axioma-drp el
#      2026-08-08 y nadie se enteró por 3 días.
#
#   2) hardening-selfcheck.sh -> en los servers de WATCHDOG_SELF_SERVERS. Mira hacia
#      adentro (ufw / fail2ban / sshd / claim de netdata). No reemplaza a (1): si el
#      server se reinstala, esta pieza desaparece con él.
#
# La línea de base de host keys se siembra de los servers vivos EN ESTE MOMENTO. Correr
# este script asume que la flota está en buen estado: si un server ya fue reinstalado
# sin que lo sepas, se sembraría la huella del intruso como si fuera legítima.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

NETDATA_DIR="$ROOT_DIR/netdata"
WATCHDOG_HOST="${WATCHDOG_HOST:-dev-1}"
# Servers donde además corre el auto-chequeo local. Sumar uno solo después de
# verificar que su hardening está en el estado que las alarmas dan por bueno.
# (Se expande así, y no con :-, porque con `set -u` una variable de array sin
# definir en el entorno aborta el script en bash < 4.4.)
if [[ -z ${WATCHDOG_SELF_SERVERS[@]+x} || ${#WATCHDOG_SELF_SERVERS[@]} -eq 0 ]]; then
  WATCHDOG_SELF_SERVERS=("axioma-drp")
fi

# ---------------------------------------------------------------------------
# 1) Línea de base de host keys, sembrada desde los servers vivos
# ---------------------------------------------------------------------------
log "Sembrando la línea de base de host keys desde los ${#SERVERS[@]} servers del inventario"
BASELINE_TMP="$(mktemp)"
trap 'rm -f "$BASELINE_TMP"' EXIT

{
  echo '{'
  echo '  "_comentario": "Linea de base de host keys SSH. La escribe scripts/35-deploy-watchdog.sh.",'
  echo '  "servers": ['
  first=1
  for rec in "${SERVERS[@]}"; do
    parse_server "$rec"
    fp="$(ssh-keyscan -T 10 -t ed25519 -p "$S_PORT" "$S_HOST" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')"
    if [[ -z "$fp" ]]; then
      err "no se pudo leer la host key de $S_NAME ($S_HOST:$S_PORT) — queda FUERA de la línea de base"
      continue
    fi
    [[ $first -eq 0 ]] && echo ','
    first=0
    printf '    {"name": "%s", "host": "%s", "port": %s, "fp": "%s"}' "$S_NAME" "$S_HOST" "$S_PORT" "$fp"
    ok "$S_NAME → $fp" >&2
  done
  echo
  echo '  ]'
  echo '}'
} > "$BASELINE_TMP"

python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$BASELINE_TMP" \
  || { err "la línea de base generada no es JSON válido"; exit 1; }

# ---------------------------------------------------------------------------
# 2) Watchdog externo en el host de monitoreo
# ---------------------------------------------------------------------------
rec="$(server_record_by_name "$WATCHDOG_HOST")" || { err "'$WATCHDOG_HOST' no está en SERVERS"; exit 1; }
parse_server "$rec"
log "Desplegando el watchdog externo en $S_NAME ($S_HOST)"
SUDO="$(sudo_prefix "$S_USER")"

scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/watchdog/hostkey-watchdog.py" "/tmp/wd-collect.$$"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$BASELINE_TMP" "/tmp/wd-baseline.$$"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/statsd.d/watchdog-fleet.conf" "/tmp/wd-statsd.$$"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/health.d/watchdog-fleet.conf" "/tmp/wd-health.$$"

ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  set -e
  ${SUDO}mv /tmp/wd-collect.$$ /usr/local/bin/hostkey-watchdog.py
  ${SUDO}chmod 755 /usr/local/bin/hostkey-watchdog.py
  ${SUDO}mkdir -p /etc/watchdog /etc/netdata/statsd.d /etc/netdata/health.d
  ${SUDO}mv /tmp/wd-baseline.$$ /etc/watchdog/baseline.json
  ${SUDO}chmod 644 /etc/watchdog/baseline.json
  ${SUDO}mv /tmp/wd-statsd.$$ /etc/netdata/statsd.d/watchdog-fleet.conf
  ${SUDO}mv /tmp/wd-health.$$ /etc/netdata/health.d/watchdog-fleet.conf
  echo '*/15 * * * * root /usr/bin/python3 /usr/local/bin/hostkey-watchdog.py >/dev/null 2>&1' \
    | ${SUDO}tee /etc/cron.d/watchdog-fleet >/dev/null
  ${SUDO}chmod 644 /etc/cron.d/watchdog-fleet
"
ok "colector + línea de base + cron (cada 15 min) + statsd + alarmas"

# Restart PRIMERO (statsd nuevo lo requiere) y recién después la corrida que puebla
# las métricas: al revés, el restart se lleva puesto lo que acaba de enviar el
# colector y los charts no existen hasta el próximo cron.
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}systemctl restart netdata"
sleep 5
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}/usr/bin/python3 /usr/local/bin/hostkey-watchdog.py || true"
# Idem: los charts statsd recién existen ahora, así que health necesita re-engancharse.
sleep 3
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}netdatacli reload-health >/dev/null 2>&1 || true"
ok "Netdata reiniciado en $S_NAME, métricas pobladas y alarmas enganchadas"

# ---------------------------------------------------------------------------
# 3) Auto-chequeo local en los servers elegidos
# ---------------------------------------------------------------------------
for name in "${WATCHDOG_SELF_SERVERS[@]}"; do
  rec="$(server_record_by_name "$name")" || { err "'$name' no está en SERVERS — se omite"; continue; }
  parse_server "$rec"
  log "Desplegando el auto-chequeo de hardening en $S_NAME ($S_HOST)"
  SUDO="$(sudo_prefix "$S_USER")"

  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/watchdog/hardening-selfcheck.sh" "/tmp/sc.$$"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/statsd.d/watchdog-self.conf" "/tmp/sc-statsd.$$"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$NETDATA_DIR/health.d/watchdog-self.conf" "/tmp/sc-health.$$"

  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    set -e
    ${SUDO}mv /tmp/sc.$$ /usr/local/bin/hardening-selfcheck.sh
    ${SUDO}chmod 755 /usr/local/bin/hardening-selfcheck.sh
    ${SUDO}mkdir -p /etc/netdata/statsd.d /etc/netdata/health.d
    ${SUDO}mv /tmp/sc-statsd.$$ /etc/netdata/statsd.d/watchdog-self.conf
    ${SUDO}mv /tmp/sc-health.$$ /etc/netdata/health.d/watchdog-self.conf
    echo '*/15 * * * * root /usr/local/bin/hardening-selfcheck.sh >/dev/null 2>&1' \
      | ${SUDO}tee /etc/cron.d/watchdog-self >/dev/null
    ${SUDO}chmod 644 /etc/cron.d/watchdog-self
    ${SUDO}systemctl restart netdata
    sleep 5
    ${SUDO}/usr/local/bin/hardening-selfcheck.sh || true
    # Los charts de statsd nacen recién con la primera métrica, DESPUÉS de que health
    # cargó: sin este reload las alarmas quedan sin engancharse a ningún chart.
    sleep 3
    ${SUDO}netdatacli reload-health >/dev/null 2>&1 || true
  "
  ok "$S_NAME → auto-chequeo instalado y Netdata reiniciado"
done

log "Watchdog desplegado. Verificá los charts watchdog.* en Netdata Cloud."
log "Tras una reinstalación LEGÍTIMA: hostkey-watchdog.py --reseed <server> en $WATCHDOG_HOST."
