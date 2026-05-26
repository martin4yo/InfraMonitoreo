#!/usr/bin/env bash
# Instala o actualiza el agente Netdata en cada server y lo reclama contra
# Netdata Cloud, todo en una sola pasada con el script oficial kickstart.
# Es idempotente: si ya está instalado, lo actualiza; si ya está reclamado, no rompe.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

if [[ -z "${CLAIM_TOKEN:-}" || -z "${CLAIM_ROOMS:-}" ]]; then
  err "Faltan CLAIM_TOKEN y/o CLAIM_ROOMS."
  echo "  Obtenelos en Netdata Cloud (ver docs/setup-netdata-cloud.md) y poné" >&2
  echo "  en secrets.sh:  CLAIM_TOKEN=...  CLAIM_ROOMS=...  (gitignored)" >&2
  exit 1
fi

for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  log "Instalando/actualizando Netdata en $S_NAME ($S_HOST)"
  SUDO="$(sudo_prefix "$S_USER")"
  # --non-interactive evita prompts; --stable-channel usa releases estables.
  remote="
    set -e
    wget -qO /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh || \
      curl -fsSL https://get.netdata.cloud/kickstart.sh -o /tmp/netdata-kickstart.sh
    ${SUDO}sh /tmp/netdata-kickstart.sh \
      --non-interactive \
      --stable-channel \
      --claim-token '${CLAIM_TOKEN}' \
      --claim-rooms '${CLAIM_ROOMS}' \
      --claim-url '${CLAIM_URL}'
  "
  if ssh_run "$S_USER" "$S_HOST" "$S_PORT" "$remote"; then
    ok "$S_NAME listo y reclamado"
  else
    err "$S_NAME falló — revisá la salida de arriba"
  fi
done

log "Listo. Verificá los nodos en https://app.netdata.cloud"
