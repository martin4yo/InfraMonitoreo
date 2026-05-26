#!/usr/bin/env bash
# Fija el hostname que cada agente Netdata reporta (dashboard local + Netdata Cloud)
# al 'nombre' del server en el inventario, en vez del hostname real de la VPS.
#
# Mecanismo: agrega un bloque [global] con 'hostname = <nombre>' al final de
# /etc/netdata/netdata.conf. Netdata mergea las secciones y la última definición
# gana, así que el override pisa el hostname auto-detectado. El bloque va entre
# marcadores para ser idempotente (se reemplaza, no se duplica, al re-correr).
# La identidad del nodo (machine GUID) NO cambia → no se pierde historial en Cloud.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

BEGIN="# >>> inframonitoreo hostname override >>>"
END="# <<< inframonitoreo hostname override <<<"

for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  log "Fijando hostname '$S_NAME' en $S_NAME ($S_HOST)"
  SUDO="$(sudo_prefix "$S_USER")"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    CONF=/etc/netdata/netdata.conf
    ${SUDO}sed -i '/# >>> inframonitoreo hostname/,/# <<< inframonitoreo hostname/d' \"\$CONF\"
    printf '\n%s\n[global]\n    hostname = %s\n%s\n' '$BEGIN' '$S_NAME' '$END' | ${SUDO}tee -a \"\$CONF\" >/dev/null
    ${SUDO}systemctl restart netdata
  "
  ok "$S_NAME → netdata reiniciado"
done

log "Hostnames aplicados. Verificá en Netdata Cloud que los nodos se vean con el nombre del inventario."
