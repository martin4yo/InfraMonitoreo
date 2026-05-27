#!/usr/bin/env bash
# Despliega la protección anti-scanners de nginx en cada server.
#
# Bots (sobre todo desde IPs de Azure) escanean cada ~2h buscando exploits de
# WordPress/PHP: /wp-login.php, /xmlrpc.php, /wso.php, etc. Ninguna app nuestra
# usa PHP, así que no hay riesgo real, pero la ráfaga de 301 (redirect http->https)
# dispara la alarma web_log de Netdata (redirects 3xx altos).
#
# Solución (ver docs/nginx-anti-scanner.md):
#   - map $request_uri $loggable  (0 = scanner)            [snippets/scanner-map.conf]
#   - access_log ... if=$loggable  en nginx.conf           => Netdata no ve el ruido
#   - if ($loggable = 0) { return 444; } en cada server{}  [snippets/block-scanners.conf]
#
# El helper _nginx-block-scanners.py hace backup + edita + 'nginx -t' (con
# auto-restore si falla). Acá sólo orquestamos: copiar, correr y recargar.
# Idempotente: re-correr salta lo ya aplicado. Reload es graceful (zero-downtime).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

HELPER="$ROOT_DIR/scripts/_nginx-block-scanners.py"
REMOTE_HELPER="/tmp/_nginx-block-scanners.py"

for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  log "Anti-scanner en $S_NAME ($S_HOST:$S_PORT)"
  SUDO="$(sudo_prefix "$S_USER")"

  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$HELPER" "$REMOTE_HELPER"
  # El helper deja la config válida en disco (o la revierte si nginx -t falla).
  if ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}python3 $REMOTE_HELPER"; then
    ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}systemctl reload nginx && rm -f $REMOTE_HELPER"
    ok "$S_NAME → aplicado y nginx recargado"
  else
    ssh_run "$S_USER" "$S_HOST" "$S_PORT" "rm -f $REMOTE_HELPER" || true
    err "$S_NAME → falló (config revertida por el helper, sin reload)"
  fi
done

log "Anti-scanner desplegado. Verificación rápida desde un server:"
log "  curl -s -o /dev/null -w '%{http_code}\\n' --max-time 5 http://127.0.0.1/wp-login.php   # esperado: 000 (444)"
log "Nota: tras el reload, el 1er request puede pasar por el worker viejo drenando; re-testear a los pocos segundos."
