#!/usr/bin/env bash
# Helpers comunes para los scripts de orquestación por SSH.
set -euo pipefail

# Resuelve la raíz del repo y carga el inventario.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_inventory() {
  if [[ -f "$ROOT_DIR/secrets.sh" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/secrets.sh"
  fi
  if [[ ! -f "$ROOT_DIR/inventory.sh" ]]; then
    echo "ERROR: falta inventory.sh. Copiá la plantilla:" >&2
    echo "  cp inventory.example.sh inventory.sh && editalo" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source "$ROOT_DIR/inventory.sh"
}

# Parsea un registro "nombre|host|user|port|rol" en variables globales.
parse_server() {
  local rec="$1"
  IFS='|' read -r S_NAME S_HOST S_USER S_PORT S_ROLE <<<"$rec"
}

# ¿El server 'nombre' está en PGBACKREST_SERVERS? (0 = sí)
is_pgbackrest_server() {
  local name="$1" s
  for s in "${PGBACKREST_SERVERS[@]:-}"; do
    [[ "$s" == "$name" ]] && return 0
  done
  return 1
}

# Devuelve el registro completo de un server por su nombre (o vacío).
server_record_by_name() {
  local name="$1" rec
  for rec in "${SERVERS[@]}"; do
    [[ "${rec%%|*}" == "$name" ]] && { echo "$rec"; return 0; }
  done
  return 1
}

# Ejecuta un comando remoto. Uso: ssh_run "$S_USER" "$S_HOST" "$S_PORT" "comando"
ssh_run() {
  local user="$1" host="$2" port="$3" cmd="$4"
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
      -p "$port" "${user}@${host}" "$cmd"
}

# Copia un archivo local a un destino remoto. Uso: scp_to user host port local remote
scp_to() {
  local user="$1" host="$2" port="$3" local_path="$4" remote_path="$5"
  scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
      -P "$port" "$local_path" "${user}@${host}:${remote_path}"
}

# sudo solo si el usuario no es root.
sudo_prefix() {
  local user="$1"
  [[ "$user" == "root" ]] && echo "" || echo "sudo "
}

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! \033[0m%s\n' "$*"; }
err()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; }
