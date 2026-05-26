#!/usr/bin/env bash
# Genera una CA propia y un par (clave + certificado) por server, para la
# comunicación TLS de pgBackRest entre los DB hosts y el repo host (dev-1).
# El CN de cada cert = nombre del server en el inventario (se usa para autorizar).
# Salida en pgbackrest/certs/ (gitignored: son secretos).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_inventory

CERT_DIR="$ROOT_DIR/pgbackrest/certs"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

DAYS=3650

# 1) CA (una sola vez)
if [[ ! -f ca.crt ]]; then
  log "Generando CA propia"
  openssl req -new -x509 -days "$DAYS" -nodes -newkey rsa:4096 \
    -keyout ca.key -out ca.crt -subj "/CN=pgBackRest-CA"
  ok "ca.crt / ca.key"
else
  warn "ca.crt ya existe, se reutiliza"
fi

# 2) Un cert por server, firmado por la CA (CN = nombre del server)
for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  name="$S_NAME"
  if [[ -f "$name.crt" ]]; then
    warn "$name.crt ya existe, se omite"
    continue
  fi
  log "Generando cert para $name (CN=$name)"
  openssl req -new -nodes -newkey rsa:4096 -keyout "$name.key" \
    -out "$name.csr" -subj "/CN=$name"
  openssl x509 -req -days "$DAYS" -in "$name.csr" \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out "$name.crt"
  rm -f "$name.csr"
  ok "$name.crt / $name.key"
done

chmod 600 *.key
log "Certificados en $CERT_DIR (NO se versionan)."
echo "Cada server recibirá: ca.crt + <su-nombre>.crt + <su-nombre>.key en /etc/pgbackrest/cert/"
