#!/usr/bin/env bash
# Backup de los ADJUNTOS de una app (archivos subidos) a Cloudflare R2 con restic.
# Corre por cron, como root. Destino en el server: /usr/local/bin/adjuntos-backup.sh
#
#   adjuntos-backup.sh <app> backup         cada 15 min: snapshot si hubo cambios
#   adjuntos-backup.sh <app> mantenimiento  semanal: forget+prune y check parcial
#
# POR QUÉ EXISTE (2026-09-15)
# ---------------------------
# pgBackRest respalda la BASE, no el filesystem. Los adjuntos de alvera (documentos de
# consultas, datos de salud) solo se copiaban una vez por día, por rsync, a dev-1: sin
# copia off-site y con RPO de 24 h. Si caen axioma y dev-1 juntos, se pierden; y
# aunque no caigan, un restore de la base con PITR referencia archivos subidos después
# del último rsync. Hallazgo A-5 de docs/drp-alvera-en-drp.md.
#
# Esto NO reemplaza al rsync a dev-1: lo complementa. Son dos copias en dos lugares,
# con dos herramientas distintas — un bug de una no tumba a la otra.
#
# DISEÑO
# - restic cifra del lado del cliente (AES-256): R2 nunca ve los archivos en claro.
#   Sin RESTIC_PASSWORD el repositorio es ILEGIBLE. Custodia: infra-secrets.
# - Bucket y token de R2 PROPIOS, no los de pgBackRest: un token filtrado o un prune
#   mal hecho nunca alcanzan los backups de la base.
# - --skip-if-unchanged: sin cambios no se crea snapshot. Por eso la frescura se mide
#   por la última corrida OK (ts_ok del estado), no por la fecha del último snapshot.
# - nice/ionice/GOMAXPROCS=1: en axioma convive con producción; cede ante contención.
# - flock: si una corrida se estira (red lenta), la siguiente no se superpone.
#
# CONFIG: /etc/restic/<app>-adjuntos.env (600 root) con RESTIC_REPOSITORY,
# RESTIC_PASSWORD, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION y
# ORIGEN (directorio a respaldar). Lo instala scripts/37-deploy-adjuntos-backup.sh.
#
# ESTADO: /var/lib/adjuntos-backup/<app>.json — lo lee hardening-selfcheck.sh y lo
# publica como watchdog.self.adjuntos_fresco / adjuntos_integro.
set -uo pipefail

APP="${1:?uso: $0 <app> backup|mantenimiento}"
MODO="${2:-backup}"
ENV_FILE="/etc/restic/${APP}-adjuntos.env"
STATE_DIR=/var/lib/adjuntos-backup
STATE="$STATE_DIR/${APP}.json"
TAG="adjuntos-backup-${APP}"
RESTIC="${RESTIC:-/usr/local/bin/restic}"

log()  { logger -t "$TAG" "$*"; }
fail() { logger -t "$TAG" -p user.err "$*"; echo "$*" >&2; }

[ -r "$ENV_FILE" ] || { fail "no existe $ENV_FILE"; exit 2; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
: "${ORIGEN:?ORIGEN no definido en $ENV_FILE}"

export RESTIC_CACHE_DIR=/var/cache/restic GOMAXPROCS=1
mkdir -p "$STATE_DIR" "$RESTIC_CACHE_DIR"
chmod 700 "$STATE_DIR" "$RESTIC_CACHE_DIR"

exec 9>"/run/lock/${TAG}.lock"
if ! flock -n 9; then
  log "otra corrida en curso, se omite esta"
  exit 0
fi

LIGHT=(nice -n 19 ionice -c 3)

# Actualiza una clave del JSON de estado sin perder las demás.
set_state() {  # pares clave valor (valores numéricos o strings ya con comillas)
  python3 - "$STATE" "$@" <<'EOF'
import json, sys, os
path, kv = sys.argv[1], sys.argv[2:]
try:
    d = json.load(open(path))
except Exception:
    d = {}
for k, v in zip(kv[0::2], kv[1::2]):
    try:
        d[k] = json.loads(v)
    except Exception:
        d[k] = v
tmp = path + ".tmp"
json.dump(d, open(tmp, "w"))
os.replace(tmp, path)
EOF
}

now() { date +%s; }

case "$MODO" in
backup)
  if [ ! -d "$ORIGEN" ]; then
    # Sin carpeta todavía (la crea la app con el primer adjunto): no es un error.
    log "sin carpeta $ORIGEN, nada que respaldar"
    set_state ts_ok "$(now)" resultado '"PASS"' detalle '"sin carpeta de origen"'
    exit 0
  fi
  t0=$(now)
  # Se respalda "." DESDE ADENTRO de ORIGEN, no la ruta absoluta: con la ruta absoluta
  # restic guarda también los metadatos de los directorios padres, y cualquier escritura
  # en backend/ (padre de uploads/) cambia ese árbol y hace que --skip-if-unchanged cree
  # un snapshot nuevo en CADA corrida (96 por día sin un solo adjunto nuevo). Visto en la
  # prueba del 2026-09-15.
  salida=$(cd "$ORIGEN" && "${LIGHT[@]}" "$RESTIC" backup . \
             --host "$(hostname)" --tag adjuntos --tag "$APP" \
             --skip-if-unchanged --json --quiet 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    fail "FALLÓ el backup de $ORIGEN (restic rc=$rc): $(echo "$salida" | tail -3 | tr '\n' ' ')"
    set_state ts_fail "$(now)" resultado '"FAIL"' detalle "\"rc=$rc\""
    exit $rc
  fi
  resumen=$(echo "$salida" | python3 -c '
import json, sys
s = {}
for line in sys.stdin:
    try:
        o = json.loads(line)
    except Exception:
        continue
    if o.get("message_type") == "summary":
        s = o
print("nuevos=%s modificados=%s bytes_agregados=%s snapshot=%s" % (
    s.get("files_new", 0), s.get("files_changed", 0),
    s.get("data_added", 0), (s.get("snapshot_id") or "sin-cambios")[:8]))
')
  log "ok en $(( $(now) - t0 ))s: $resumen"
  set_state ts_ok "$(now)" resultado '"PASS"' detalle "\"$resumen\""
  ;;

mantenimiento)
  t0=$(now)
  # Retención: 48 h completas (errores recientes), 14 diarios, 8 semanales y 12 meses.
  # Más larga que la de pgBackRest a propósito: un adjunto borrado no se reconstruye.
  if ! "${LIGHT[@]}" "$RESTIC" forget --host "$(hostname)" --tag adjuntos,"$APP" \
         --keep-within 48h --keep-daily 14 --keep-weekly 8 --keep-monthly 12 \
         --prune --quiet >/dev/null 2>&1; then
    fail "FALLÓ forget/prune"
    set_state ts_check "$(now)" check '"FAIL"' check_detalle '"forget/prune"'
    exit 1
  fi
  # Verifica estructura + descarga y valida el 5 % de los datos. En 8 semanas se leyó
  # (probabilísticamente) casi todo el repositorio sin bajarlo entero de una vez.
  if "${LIGHT[@]}" "$RESTIC" check --read-data-subset=5% --quiet >/dev/null 2>&1; then
    log "mantenimiento ok en $(( $(now) - t0 ))s (forget+prune+check 5%)"
    set_state ts_check "$(now)" check '"PASS"' check_detalle '"forget+prune+check 5%"'
  else
    fail "FALLÓ restic check: el repositorio de $APP tiene errores de integridad"
    set_state ts_check "$(now)" check '"FAIL"' check_detalle '"check"'
    exit 1
  fi
  ;;

*)
  fail "modo desconocido: $MODO (backup|mantenimiento)"
  exit 2
  ;;
esac
