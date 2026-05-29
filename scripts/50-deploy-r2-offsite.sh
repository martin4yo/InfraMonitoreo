#!/usr/bin/env bash
# Despliega el OFFSITE de pgBackRest a Cloudflare R2 como repo2 (S3-compatible),
# CIFRADO del lado cliente. Arquitectura "A": WAL continuo + backups a R2.
#
#   - repo2 (S3=R2) se configura en el repo host (dev-1) Y en los 3 DB hosts.
#   - archive-push (corre en los DB hosts) empuja WAL a repo1 (SSH→dev-1) y repo2 (R2).
#   - backup --repo=2 corre en dev-1, lee la DB por SSH y escribe en R2.
#   - WAL continuo a R2 ⇒ PITR offsite ~1 min; backups full(sem)+diff(diario) a R2.
#
# ORDEN (importante para no romper archiving):
#   repo      -> config repo2 en dev-1 + stanza-create --repo=2  [GATE de credenciales]
#   dbhosts   -> config repo2 en los 3 DB hosts (habilita WAL→R2)
#   backup    -> primer full --repo=2 de cada stanza (LENTO; corre en background)
#   verify    -> check --repo=2 de cada stanza
#   cron      -> agrega cron de backups a repo2 en dev-1
#   all       -> todo lo de arriba en orden (default)
#
# Requiere en secrets.sh: R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID,
#   R2_SECRET_ACCESS_KEY, PGBACKREST_R2_CIPHER_PASS.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

PHASE="${1:-all}"

: "${R2_ACCOUNT_ID:?falta R2_ACCOUNT_ID en secrets.sh}"
: "${R2_BUCKET:?falta R2_BUCKET en secrets.sh}"
: "${R2_ACCESS_KEY_ID:?falta R2_ACCESS_KEY_ID en secrets.sh}"
: "${R2_SECRET_ACCESS_KEY:?falta R2_SECRET_ACCESS_KEY en secrets.sh}"
: "${PGBACKREST_R2_CIPHER_PASS:?falta PGBACKREST_R2_CIPHER_PASS en secrets.sh}"

R2_REGION="${R2_REGION:-auto}"
R2_REPO2_PATH="${R2_REPO2_PATH:-/pgbackrest}"
R2_ENDPOINT="${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
STANZAS=(AxiomaCloudProd clubix axiodemo dev-1)
HELPER="$(dirname "${BASH_SOURCE[0]}")/_pgbackrest-insert-block.py"

# Genera el bloque repo2 (idéntico en todos los hosts) a un archivo temporal local.
make_block() {
  local f; f="$(mktemp)"
  cat >"$f" <<EOF
repo2-type=s3
repo2-path=${R2_REPO2_PATH}
# bundle: agrupa archivos chicos en objetos de ~20MB -> baja de ~28k PUTs a decenas.
# Clave para DBs con miles de relaciones; sin esto el full inicial a R2 tarda 1h+ vs
# minutos. Aplica a backups nuevos (los viejos no-bundle conviven sin problema).
repo2-bundle=y
repo2-s3-bucket=${R2_BUCKET}
repo2-s3-endpoint=${R2_ENDPOINT}
repo2-s3-region=${R2_REGION}
repo2-s3-uri-style=path
repo2-s3-key=${R2_ACCESS_KEY_ID}
repo2-s3-key-secret=${R2_SECRET_ACCESS_KEY}
repo2-retention-full=4
repo2-retention-diff=7
repo2-cipher-type=aes-256-cbc
repo2-cipher-pass=${PGBACKREST_R2_CIPHER_PASS}
EOF
  echo "$f"
}

# Inserta el bloque repo2 en un pgbackrest config de un server (idempotente).
# Uso: deploy_block_to <name> [conf_path]  (default /etc/pgbackrest/pgbackrest.conf)
# Si el config no existe en el server, avisa y sigue (p.ej. db.conf solo en dev-1).
deploy_block_to() {
  local name="$1" conf="${2:-/etc/pgbackrest/pgbackrest.conf}" rec block
  rec="$(server_record_by_name "$name")" || { err "server '$name' no está en SERVERS"; return 1; }
  parse_server "$rec"
  local sudo; sudo="$(sudo_prefix "$S_USER")"
  if ! ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${sudo}test -f $conf"; then
    warn "$name: $conf no existe, salteo"; return 0
  fi
  block="$(make_block)"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$block" "/tmp/r2-block.$$"
  scp_to "$S_USER" "$S_HOST" "$S_PORT" "$HELPER" "/tmp/r2-insert.$$"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    ${sudo}python3 /tmp/r2-insert.$$ $conf /tmp/r2-block.$$ &&
    ${sudo}chmod 640 $conf &&
    rm -f /tmp/r2-block.$$ /tmp/r2-insert.$$"
  rm -f "$block"
  ok "repo2 configurado en $name ($S_HOST) [$conf]"
}

# Corre un comando pgbackrest en el repo host (dev-1) como el dueño del repo.
repo_run() {
  local rec; rec="$(server_record_by_name "$PGBACKREST_REPO_HOST")"; parse_server "$rec"
  local sudo; sudo="$(sudo_prefix "$S_USER")"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${sudo}-u ${PGBACKREST_REPO_OWNER} $1"
}

phase_repo() {
  log "FASE repo: config repo2 en $PGBACKREST_REPO_HOST + stanza-create (GATE de credenciales R2)"
  deploy_block_to "$PGBACKREST_REPO_HOST"
  # dev-1 se respalda a sí mismo por loopback: su archive_command usa db.conf
  # (legible por postgres), NO el pgbackrest.conf principal. Sin repo2 ahí, el WAL
  # de dev-1 no llega a R2. Ver docs/pgbackrest-r2-offsite.md.
  deploy_block_to "$PGBACKREST_REPO_HOST" /etc/pgbackrest/db.conf
  # stanza-create opera sobre TODOS los repos configurados (no acepta --repo); como
  # repo1 ya existe, sólo crea el stanza faltante en repo2 (idempotente).
  for st in "${STANZAS[@]}"; do
    log "stanza-create $st (crea repo2 en R2)"
    repo_run "pgbackrest --stanza=$st stanza-create"
    ok "stanza $st creada en R2 (cifrada)"
  done
  ok "GATE OK: credenciales/endpoint/cifrado de R2 validados"
}

phase_dbhosts() {
  log "FASE dbhosts: config repo2 en los DB hosts (habilita WAL→R2)"
  for name in "${PGBACKREST_SERVERS[@]}"; do
    [[ "$name" == "$PGBACKREST_REPO_HOST" ]] && continue  # ya configurado en fase repo
    deploy_block_to "$name"
  done
  ok "archive-push de los DB hosts ahora empuja WAL a repo1 (SSH) y repo2 (R2)"
}

phase_backup() {
  log "FASE backup: primer full --repo=2 de cada stanza (LENTO; mirá el progreso con 'info')"
  for st in "${STANZAS[@]}"; do
    log "backup --repo=2 --type=full $st"
    repo_run "pgbackrest --stanza=$st --repo=2 --type=full backup"
    ok "full inicial de $st en R2"
  done
}

phase_verify() {
  # check opera sobre TODOS los repos (no acepta --repo): valida WAL→repo1 y repo2.
  log "FASE verify: check de cada stanza (repo1 + repo2/R2)"
  for st in "${STANZAS[@]}"; do
    repo_run "pgbackrest --stanza=$st check" && ok "check $st OK (ambos repos)"
  done
}

phase_cron() {
  log "FASE cron: backups a repo2 en dev-1 (full sem + diff diario; WAL ya es continuo)"
  local rec; rec="$(server_record_by_name "$PGBACKREST_REPO_HOST")"; parse_server "$rec"
  local sudo; sudo="$(sudo_prefix "$S_USER")"
  # Bloque idempotente (marcador). full dom + diff lun-sáb, escalonado, ventana 3:xx.
  local block='# >>> inframonitoreo r2 offsite >>>
0 3 * * 0   pgbackrest --stanza=AxiomaCloudProd --repo=2 --type=full backup
0 3 * * 1-6 pgbackrest --stanza=AxiomaCloudProd --repo=2 --type=diff backup
15 3 * * 0   pgbackrest --stanza=clubix --repo=2 --type=full backup
15 3 * * 1-6 pgbackrest --stanza=clubix --repo=2 --type=diff backup
30 3 * * 0   pgbackrest --stanza=axiodemo --repo=2 --type=full backup
30 3 * * 1-6 pgbackrest --stanza=axiodemo --repo=2 --type=diff backup
45 3 * * 0   pgbackrest --stanza=dev-1 --repo=2 --type=full backup
45 3 * * 1-6 pgbackrest --stanza=dev-1 --repo=2 --type=diff backup
# <<< inframonitoreo r2 offsite <<<'
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    cur=\$(${sudo}-u ${PGBACKREST_REPO_OWNER} crontab -l 2>/dev/null || true)
    if echo \"\$cur\" | grep -q 'inframonitoreo r2 offsite'; then
      echo 'cron repo2 ya presente, sin cambios'
    else
      printf '%s\n%s\n' \"\$cur\" \"$block\" | ${sudo}-u ${PGBACKREST_REPO_OWNER} crontab -
      echo 'cron repo2 agregado'
    fi"
  ok "cron de backups a repo2 listo"
}

case "$PHASE" in
  repo)    phase_repo ;;
  dbhosts) phase_dbhosts ;;
  backup)  phase_backup ;;
  verify)  phase_verify ;;
  cron)    phase_cron ;;
  all)     phase_repo; phase_dbhosts; phase_backup; phase_verify; phase_cron ;;
  *) err "fase desconocida: $PHASE (repo|dbhosts|backup|verify|cron|all)"; exit 1 ;;
esac

log "Fase '$PHASE' completa."
