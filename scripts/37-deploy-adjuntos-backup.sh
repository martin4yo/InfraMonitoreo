#!/usr/bin/env bash
# Despliega el BACKUP DE ADJUNTOS A R2 (restic) de una app en su server. Idempotente.
#
#   scripts/37-deploy-adjuntos-backup.sh                      # alvera en axioma
#   APP=alvera HOST_NAME=axioma scripts/37-deploy-adjuntos-backup.sh
#
# Qué hace, en orden (cada paso verifica antes de seguir):
#   1) restic: binario oficial con sha256 FIJADO acá, bajado en el equipo del operador
#      y copiado al server (el server no necesita salir a GitHub).
#   2) credenciales: de infra-secrets (SOPS) a /etc/restic/<app>-adjuntos.env (600 root),
#      sin pasar por disco local en claro. Se agrega ORIGEN (no es secreto).
#   3) repositorio: `restic init` solo si todavía no existe.
#   4) script + cron.d (cada 15 min + mantenimiento semanal dom 04:30).
#   5) primera corrida, medida.
#   6) selfcheck + statsd + alarmas de Netdata SOLO en este server (no toca los otros 4).
#
# Por qué existe y el diseño: cabecera de restic/adjuntos-backup.sh y docs/backup-adjuntos.md.
#
# NO borra el rsync diario a dev-1 (/etc/cron.daily/<app>-adjuntos-backup): se suman.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory
NETDATA_DIR="$ROOT_DIR/netdata"

APP="${APP:-alvera}"
HOST_NAME="${HOST_NAME:-axioma}"
SECRET="${SECRET:-$HOME/Desarrollos/infra-secrets/env/restic/${APP}-adjuntos.env}"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
export SOPS_AGE_KEY_FILE

RESTIC_VERSION="0.19.1"
RESTIC_SHA256="f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c"   # restic_0.19.1_linux_amd64.bz2
RESTIC_URL="https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2"

rec="$(server_record_by_name "$HOST_NAME")" || { err "'$HOST_NAME' no está en SERVERS"; exit 1; }
parse_server "$rec"
SUDO="$(sudo_prefix "$S_USER")"
log "Backup de adjuntos de '$APP' → R2, en $S_NAME ($S_HOST:$S_PORT)"

[[ -f "$SECRET" ]] || { err "no existe $SECRET (custodia en infra-secrets)"; exit 1; }
command -v sops >/dev/null || { err "falta sops en este equipo"; exit 1; }

# Origen: UPLOADS_DIR del .env del backend si está, si no el default de la app.
ORIGEN="$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  d=\$(${SUDO}grep -E '^UPLOADS_DIR=' /var/www/${APP}/backend/.env 2>/dev/null | cut -d= -f2- | tr -d '\"')
  echo \${d:-/var/www/${APP}/backend/uploads}")"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}test -d '$ORIGEN'" \
  || warn "ORIGEN $ORIGEN todavía no existe (la app lo crea con el primer adjunto)"
ok "origen: $ORIGEN"

# 1) restic
instalada="$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" "/usr/local/bin/restic version 2>/dev/null | awk '{print \$2}'" || true)"
if [[ "$instalada" == "$RESTIC_VERSION" ]]; then
  ok "restic $RESTIC_VERSION ya instalado"
else
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/restic.bz2" "$RESTIC_URL"
  echo "$RESTIC_SHA256  $tmp/restic.bz2" | sha256sum -c --quiet \
    || { err "sha256 de restic NO coincide — abortado"; exit 1; }
  bunzip2 "$tmp/restic.bz2"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$tmp/restic" "/tmp/restic.$$"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}install -o root -g root -m 755 /tmp/restic.$$ /usr/local/bin/restic && rm -f /tmp/restic.$$"
  ok "restic $(ssh_run "$S_USER" "$S_HOST" "$S_PORT" "/usr/local/bin/restic version" | awk '{print $2}') instalado (sha256 verificado)"
fi

# 2) credenciales — descifradas en un pipe, nunca en disco local
{ sops --decrypt "$SECRET" | grep -E '^(RESTIC_REPOSITORY|RESTIC_PASSWORD|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_DEFAULT_REGION)='
  echo "ORIGEN=$ORIGEN"; } \
  | ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
      "${SUDO}install -d -o root -g root -m 700 /etc/restic && ${SUDO}install -o root -g root -m 600 /dev/stdin /etc/restic/${APP}-adjuntos.env"
n="$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}grep -c '=' /etc/restic/${APP}-adjuntos.env")"
[[ "$n" -eq 6 ]] || { err "/etc/restic/${APP}-adjuntos.env tiene $n variables, se esperaban 6"; exit 1; }
ok "credenciales en /etc/restic/${APP}-adjuntos.env (600 root, 6 variables)"

# 3) script primero (el init lo usa como entorno), después el repositorio
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$ROOT_DIR/restic/adjuntos-backup.sh" "/tmp/adjb.$$"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}install -o root -g root -m 755 /tmp/adjb.$$ /usr/local/bin/adjuntos-backup.sh && rm -f /tmp/adjb.$$"
estado_repo="$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  ${SUDO}bash -c 'set -a; . /etc/restic/${APP}-adjuntos.env; set +a
    export RESTIC_CACHE_DIR=/var/cache/restic
    if restic cat config >/dev/null 2>&1; then echo existe
    elif restic init >/dev/null 2>&1; then echo creado
    else echo ERROR; restic cat config 2>&1 | tail -2; fi'")"
case "$estado_repo" in
  existe) ok "repositorio restic ya inicializado" ;;
  creado) ok "repositorio restic INICIALIZADO en R2" ;;
  *) err "no se pudo acceder/inicializar el repositorio: $estado_repo"; exit 1 ;;
esac

# 4) cron.d — el nombre es la declaración que lee el selfcheck
cron="*/15 * * * * root /usr/local/bin/adjuntos-backup.sh ${APP} backup >/dev/null 2>&1
30 4 * * 0 root /usr/local/bin/adjuntos-backup.sh ${APP} mantenimiento >/dev/null 2>&1"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
  "printf '%s\n' \"$cron\" | ${SUDO}tee /etc/cron.d/adjuntos-backup-${APP} >/dev/null && ${SUDO}chmod 644 /etc/cron.d/adjuntos-backup-${APP}"
ok "cron.d instalado: cada 15 min + mantenimiento dom 04:30"

# 5) primera corrida, medida
log "Primera corrida…"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
  /usr/bin/time -f 'tiempo=%es cpu=%U+%Ss maxrss=%MKB' ${SUDO}/usr/local/bin/adjuntos-backup.sh ${APP} backup
  ${SUDO}cat /var/lib/adjuntos-backup/${APP}.json; echo
  ${SUDO}journalctl -t adjuntos-backup-${APP} -n 1 --no-pager -o cat"

# 6) selfcheck + statsd + alarmas, solo en este server (mismos pasos que scripts/35 §3)
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
ok "selfcheck con adjuntos_fresco/adjuntos_integro + alarmas en $S_NAME"

log "Listo. Verificar: alarmas watchdog_adjuntos_* en CLEAR y un restore de prueba (docs/backup-adjuntos.md §4)."
