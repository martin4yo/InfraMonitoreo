#!/usr/bin/env bash
# Despliega los colectores y alarmas de netdata/ a cada server y recarga Netdata.
# Genera el httpcheck.conf por server a partir del endpoint_health del inventario.
# Idempotente: vuelve a copiar y recargar sin duplicar nada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

NETDATA_DIR="$ROOT_DIR/netdata"

# Genera httpcheck.conf con TODAS las apps (del array ENDPOINTS) de un server.
gen_httpcheck() {
  local server="$1" found=0 ep app url ep_server
  local out="jobs:"
  for ep in "${ENDPOINTS[@]:-}"; do
    IFS='|' read -r ep_server app url <<<"$ep"
    [[ "$ep_server" == "$server" ]] || continue
    found=1
    out+="
  - name: ${app}
    url: ${url}
    status_accepted: [200]
    timeout: 5
    update_every: 10"
  done
  if [[ "$found" -eq 0 ]]; then
    echo "jobs: []"
  else
    echo "$out"
  fi
}

for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  log "Desplegando configs en $S_NAME ($S_HOST)"
  SUDO="$(sudo_prefix "$S_USER")"

  # 1) Archivos estáticos: nombre_local -> ruta_remota
  declare -A FILES=(
    ["$NETDATA_DIR/go.d/postgres.conf"]="/etc/netdata/go.d/postgres.conf"
    ["$NETDATA_DIR/go.d/nginx.conf"]="/etc/netdata/go.d/nginx.conf"
    ["$NETDATA_DIR/apps_groups.conf"]="/etc/netdata/apps_groups.conf"
    ["$NETDATA_DIR/health.d/apps_http.conf"]="/etc/netdata/health.d/apps_http.conf"
    ["$NETDATA_DIR/health.d/inframonitoreo-tuning.conf"]="/etc/netdata/health.d/inframonitoreo-tuning.conf"
  )
  for local_f in "${!FILES[@]}"; do
    remote_f="${FILES[$local_f]}"
    tmp="/tmp/$(basename "$remote_f").$$"
    scp_to "$S_USER" "$S_HOST" "$S_PORT" "$local_f" "$tmp"
    ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
      "${SUDO}mkdir -p $(dirname "$remote_f") && ${SUDO}mv $tmp $remote_f && ${SUDO}chown root:netdata $remote_f 2>/dev/null || true"
    ok "$(basename "$remote_f")"
  done

  # 2) httpcheck.conf con todas las apps del server (array ENDPOINTS)
  n_apps=$(printf '%s\n' "${ENDPOINTS[@]:-}" | grep -c "^${S_NAME}|" || true)
  tmp_http="/tmp/httpcheck.conf.$$"
  gen_httpcheck "$S_NAME" | \
    ssh_run "$S_USER" "$S_HOST" "$S_PORT" "cat > $tmp_http && ${SUDO}mv $tmp_http /etc/netdata/go.d/httpcheck.conf"
  ok "httpcheck.conf (${n_apps} app(s))"

  # 3) Reiniciar netdata para que el plugin go.d tome los colectores nuevos.
  #    OJO: 'netdatacli reload-health' solo recarga ALARMAS, no colectores nuevos
  #    (httpcheck/postgres/nginx no aparecen hasta reiniciar). Por eso reiniciamos.
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
    "${SUDO}systemctl restart netdata"
  ok "Netdata reiniciado (colectores + alarmas)"
done

log "Configs desplegadas. Revisá en Netdata Cloud que aparezcan los charts de postgres/nginx/httpcheck."
