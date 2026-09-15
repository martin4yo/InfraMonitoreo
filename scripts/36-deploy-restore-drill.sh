#!/usr/bin/env bash
# Despliega el RESTORE DRILL en el host ejecutor (por defecto axioma-drp): script +
# cron mensual + verificación de prerequisitos. Idempotente.
#
# POR QUÉ EXISTE (2026-09-05)
# ---------------------------
# El drill era el único control del marco que dependía de que una persona se acordara
# de correrlo, en una máquina de escritorio (`KEYSOFT-UBUNTU`) que no está siempre
# encendida. Resultado: **48 días sin correr** entre el 2026-07-19 y el 2026-09-05,
# con los backups sin probar en todo ese tiempo.
#
# Mudarlo a un server siempre prendido es lo que permite ponerle cron, y ponerle cron
# es lo que lo convierte de intención en control. La alarma que cierra el círculo
# (`watchdog_drill_atrasado`) la levanta hardening-selfcheck.sh leyendo el estado que
# deja el drill; sin ella, un cron que deja de correr es igual de invisible.
#
# EL HOST EJECUTOR NO PUEDE SER dev-1. dev-1 aloja el repositorio: un drill tiene que
# restaurar en un host DISTINTO del repo host, que es lo único que prueba el escenario
# real de desastre. axioma-drp además está en OTRO proveedor que producción.
#
# NO PROVISIONA CREDENCIALES. El drill necesita /etc/pgbackrest/drill-r2.env (600
# root) con las 6 variables R2_*, que salen de la custodia (infra-secrets, SOPS). Ese
# paso es manual a propósito: mover credenciales no es algo que deba hacer un script
# de despliegue sin que alguien lo decida. Si el archivo falta, esto avisa y sigue.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

DRILL_HOST="${DRILL_HOST:-axioma-drp}"
REMOTE_DIR="InfraMonitoreo"   # relativo al home del usuario SSH

rec="$(server_record_by_name "$DRILL_HOST")" || { err "'$DRILL_HOST' no está en SERVERS"; exit 1; }
parse_server "$rec"
[[ "$S_NAME" == "${PGBACKREST_REPO_HOST:-dev-1}" ]] && {
  err "$S_NAME es el repo host: el drill NO puede correr ahí (ver cabecera)"; exit 1; }

log "Desplegando el restore drill en $S_NAME ($S_HOST:$S_PORT)"
SUDO="$(sudo_prefix "$S_USER")"

# 1) Prerequisitos. Se chequean ANTES de instalar el cron: un cron que falla todos los
#    meses en silencio es peor que no tenerlo.
log "Verificando prerequisitos en $S_NAME"
faltantes="$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" '
  falta=""
  command -v pgbackrest >/dev/null || falta="$falta pgbackrest"
  [ -x /usr/lib/postgresql/14/bin/pg_ctl ] || falta="$falta binarios-pg14"
  [ -x /usr/lib/postgresql/16/bin/pg_ctl ] || falta="$falta binarios-pg16"
  id postgres >/dev/null 2>&1 || falta="$falta usuario-postgres"
  sudo -n true 2>/dev/null || falta="$falta sudo-nopasswd"
  echo "$falta"
')"
if [[ -n "${faltantes// /}" ]]; then
  err "faltan prerequisitos en $S_NAME:$faltantes"
  err "  binarios de PG: sudo apt-get install -y postgresql-14 postgresql-16"
  exit 1
fi
ok "prerequisitos OK (pgbackrest + binarios pg14/pg16 + postgres + sudo)"

# 2) Script e historial. El CSV viaja para que las corridas nuevas se agreguen a la
#    historia real y no arranquen un archivo vacío en el server.
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "mkdir -p ~/$REMOTE_DIR/scripts ~/$REMOTE_DIR/docs"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$ROOT_DIR/scripts/70-restore-drill.sh" "$REMOTE_DIR/scripts/70-restore-drill.sh"
scp_to "$S_USER" "$S_HOST" "$S_PORT" "$ROOT_DIR/docs/drill-history.csv"     "$REMOTE_DIR/docs/drill-history.csv"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" "chmod +x ~/$REMOTE_DIR/scripts/70-restore-drill.sh"
ok "script + historial en ~/$REMOTE_DIR"

# 3) Credenciales R2: se avisa, no se instalan (ver cabecera).
if ssh_run "$S_USER" "$S_HOST" "$S_PORT" "${SUDO}test -f /etc/pgbackrest/drill-r2.env"; then
  ok "credenciales R2 presentes en /etc/pgbackrest/drill-r2.env"
else
  warn "FALTA /etc/pgbackrest/drill-r2.env — el drill va a fallar hasta que lo crees."
  warn "  Desde la custodia, sin dejar el texto plano en disco local:"
  warn "  sops -d infra-secrets/env/pgbackrest/repo2-r2.env | <mapear a R2_*> |"
  warn "    ssh $S_USER@$S_HOST \"sudo sh -c 'umask 077; cat > /etc/pgbackrest/drill-r2.env'\""
fi

# 4) Cron mensual. Día 19 = el anclaje mensual de G6 §1.1 (drill + escaneo + accesos en
#    la misma ventana). 03:00: después del full de las 02:00 en dev-1, así el drill
#    prueba un backup del día y no uno a punto de ser reemplazado.
# Path absoluto, resuelto en el server: en cron.d el entorno es mínimo y no conviene
# depender de que $HOME esté seteado como uno espera.
REMOTE_HOME="$(ssh_run "$S_USER" "$S_HOST" "$S_PORT" 'echo $HOME')"
[[ -n "$REMOTE_HOME" ]] || { err "no se pudo resolver el home de $S_USER en $S_NAME"; exit 1; }
cron_line="0 3 19 * * ${S_USER} cd ${REMOTE_HOME}/${REMOTE_DIR} && bash scripts/70-restore-drill.sh >> /tmp/restore-drill-cron.log 2>&1"
ssh_run "$S_USER" "$S_HOST" "$S_PORT" \
  "echo '$cron_line' | ${SUDO}tee /etc/cron.d/restore-drill >/dev/null && ${SUDO}chmod 644 /etc/cron.d/restore-drill"
ok "cron mensual instalado (día 19, 03:00)"

log "Drill desplegado en $S_NAME."
log "El estado para las alarmas queda en /var/lib/pgbackrest-drill/last-drill.json,"
log "y lo publica hardening-selfcheck.sh (scripts/35) como watchdog.self.drill_*."
warn "El CSV de historial vive en ${REMOTE_HOME}/${REMOTE_DIR}/docs/drill-history.csv y va a"
warn "  DIVERGIR del repo con cada corrida del cron. Para traerlo:"
warn "  scp -P ${S_PORT} ${S_USER}@${S_HOST}:${REMOTE_DIR}/docs/drill-history.csv docs/"
warn "  No es el control —eso son las alarmas watchdog_drill_*— pero sí la evidencia de G6."
