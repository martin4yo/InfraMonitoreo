#!/usr/bin/env bash
# Recorre todos los servers del inventario y reporta el estado de Netdata:
# si está instalado, versión, si está activo y si ya está reclamado a la nube.
# Solo lee información — no instala ni cambia nada.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

printf '%-12s %-18s %-12s %-9s %-9s\n' "SERVER" "HOST" "VERSION" "ACTIVO" "CLAIMED"
printf '%-12s %-18s %-12s %-9s %-9s\n' "------" "----" "-------" "------" "-------"

for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  remote='
    if command -v netdata >/dev/null 2>&1; then
      ver=$(netdata -v 2>/dev/null | head -1 | awk "{print \$2}");
      [ -z "$ver" ] && ver="instalado";
    else ver="-"; fi;
    if systemctl is-active --quiet netdata 2>/dev/null; then act="si"; else act="no"; fi;
    if [ -f /var/lib/netdata/cloud.d/claimed_id ]; then cl="si"; else cl="no"; fi;
    echo "$ver|$act|$cl"
  '
  if out=$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" "$remote" 2>/dev/null); then
    IFS='|' read -r VER ACT CL <<<"$out"
    printf '%-12s %-18s %-12s %-9s %-9s\n' "$S_NAME" "$S_HOST" "$VER" "$ACT" "$CL"
  else
    printf '%-12s %-18s %-12s %-9s %-9s\n' "$S_NAME" "$S_HOST" "SSH-ERROR" "-" "-"
  fi
done
