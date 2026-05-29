#!/usr/bin/env bash
# Restore drill desde repo2 (Cloudflare R2) en esta máquina local.
# Restaura cada stanza en un directorio temporal aislado bajo /tmp/restore-drill,
# arranca una instancia PG efímera en un puerto libre, verifica integridad y limpia.
# Requiere: pgbackrest 2.58, pg14+pg16 binaries, sudo martin→postgres sin password.
#
# Uso:
#   ./70-restore-drill.sh                        # las 3 stanzas
#   ./70-restore-drill.sh AxiomaCloudProd        # solo una
#   ./70-restore-drill.sh clubix axiodemo        # subset

set -euo pipefail

# ── Configuración ────────────────────────────────────────────────────────────

# Drill base en el home de postgres — evita conflictos de permisos en /tmp
DRILL_BASE="/var/lib/postgresql/restore-drill"
LOG_DIR="/tmp/restore-drill-logs"
PGBACKREST_CONF="${DRILL_BASE}/pgbackrest-local.conf"
LOG_FILE="${LOG_DIR}/drill-$(date +%Y%m%d-%H%M%S).log"

PG14_BIN="/usr/lib/postgresql/14/bin"
PG16_BIN="/usr/lib/postgresql/16/bin"

DEV1_SSH="axiomacloud@149.50.148.198"

# Puertos efímeros (evitan colisión con el 5432 local)
PORT_AxiomaCloudProd=5442
PORT_clubix=5443
PORT_axiodemo=5444

# ── Stanzas ──────────────────────────────────────────────────────────────────

declare -A STANZA_PG_VER=(  [AxiomaCloudProd]=14  [clubix]=14  [axiodemo]=16 )
declare -A STANZA_PORT=(
    [AxiomaCloudProd]=$PORT_AxiomaCloudProd
    [clubix]=$PORT_clubix
    [axiodemo]=$PORT_axiodemo
)
ALL_STANZAS=(AxiomaCloudProd clubix axiodemo)

# ── Helpers ──────────────────────────────────────────────────────────────────

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()    { echo -e "$(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
ok()     { log "${GREEN}[OK]${NC}   $*"; }
fail()   { log "${RED}[FAIL]${NC} $*"; FAILURES+=("$*"); }
info()   { log "${YELLOW}[--]${NC}   $*"; }
header() {
    echo -e "\n${BOLD}══════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}  $*${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}

FAILURES=()
declare -A DRILL_RESULTS=()

sudo_pg() { sudo -u postgres -H "$@"; }

# ── Paso 1: obtener credenciales R2 desde dev-1 ──────────────────────────────

fetch_r2_credentials() {
    info "Leyendo credenciales R2 desde dev-1..."
    local conf
    conf=$(ssh "$DEV1_SSH" "sudo cat /etc/pgbackrest/pgbackrest.conf")

    R2_BUCKET=$(   echo "$conf" | grep 'repo2-s3-bucket='     | cut -d= -f2 | tr -d ' ')
    R2_ENDPOINT=$( echo "$conf" | grep 'repo2-s3-endpoint='   | cut -d= -f2 | tr -d ' ')
    R2_REGION=$(   echo "$conf" | grep 'repo2-s3-region='     | cut -d= -f2 | tr -d ' ')
    R2_KEY=$(      echo "$conf" | grep 'repo2-s3-key='        | cut -d= -f2 | tr -d ' ')
    R2_SECRET=$(   echo "$conf" | grep 'repo2-s3-key-secret=' | cut -d= -f2 | tr -d ' ')
    R2_CIPHER=$(   echo "$conf" | grep 'repo2-cipher-pass='   | cut -d= -f2-)

    [[ -z "$R2_BUCKET" || -z "$R2_SECRET" || -z "$R2_CIPHER" ]] && {
        echo "ERROR: no se pudieron leer las credenciales R2 desde dev-1" >&2; exit 1
    }
    ok "Credenciales R2 obtenidas (bucket: $R2_BUCKET)"
}

# ── Paso 2: generar pgbackrest.conf local ────────────────────────────────────

write_local_conf() {
    sudo_pg mkdir -p "${DRILL_BASE}/log" "${DRILL_BASE}/lock"
    mkdir -p "$LOG_DIR"
    # Escribir conf como postgres para que tenga acceso de lectura
    sudo_pg bash -c "cat > '${PGBACKREST_CONF}'" <<EOF
[global]
repo1-type=s3
repo1-path=/pgbackrest
repo1-s3-bucket=${R2_BUCKET}
repo1-s3-endpoint=${R2_ENDPOINT}
repo1-s3-region=${R2_REGION}
repo1-s3-uri-style=path
repo1-s3-key=${R2_KEY}
repo1-s3-key-secret=${R2_SECRET}
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=${R2_CIPHER}
repo1-bundle=y
compress-type=lz4
log-level-console=info
log-level-file=detail
log-path=${DRILL_BASE}/log
lock-path=${DRILL_BASE}/lock
log-level-stderr=off

[AxiomaCloudProd]
pg1-path=${DRILL_BASE}/AxiomaCloudProd/pgdata

[clubix]
pg1-path=${DRILL_BASE}/clubix/pgdata

[axiodemo]
pg1-path=${DRILL_BASE}/axiodemo/pgdata
EOF
    sudo_pg chmod 600 "$PGBACKREST_CONF"
    ok "Config local escrita en $PGBACKREST_CONF"
}

# ── Paso 3: restore de una stanza ────────────────────────────────────────────

restore_stanza() {
    local stanza=$1
    local pgver=${STANZA_PG_VER[$stanza]}
    local pgdata="${DRILL_BASE}/${stanza}/pgdata"

    header "RESTORE: ${stanza} (PG${pgver})"

    # Limpiar ejecución anterior
    if [[ -d "$pgdata" ]]; then
        info "Limpiando pgdata anterior..."
        sudo_pg "/usr/lib/postgresql/${pgver}/bin/pg_ctl" \
            stop -D "$pgdata" -m immediate 2>/dev/null || true
        sudo_pg rm -rf "$pgdata"
    fi

    # El directorio base debe ser de postgres para que pueda crear pgdata
    sudo_pg mkdir -p "${DRILL_BASE}/${stanza}"
    sudo_pg mkdir -p "$pgdata"
    sudo_pg chmod 700 "$pgdata"

    info "Iniciando pgbackrest restore desde R2..."
    local t0=$SECONDS

    # --type=standby hace que pgbackrest escriba recovery.signal + restore_command
    # apuntando al propio pgbackrest, para que PG pueda aplicar el WAL archivado en R2
    # durante el startup. El --target-action=promote hace que PG promueva al llegar
    # al último WAL disponible en el archive.
    sudo_pg pgbackrest \
        --config="$PGBACKREST_CONF" \
        --stanza="$stanza" \
        --type=standby \
        restore 2>&1 | tee -a "$LOG_FILE" || {
        fail "${stanza}: pgbackrest restore retornó error"
        return 1
    }

    local elapsed=$(( SECONDS - t0 ))
    ok "Restore completado en ${elapsed}s"

    # Capturar qué backup se usó
    local label
    label=$(sudo_pg pgbackrest --config="$PGBACKREST_CONF" --stanza="$stanza" \
                --output=json info 2>/dev/null \
            | python3 -c "
import sys, json
d = json.load(sys.stdin)
backups = d[0]['backup']
print(backups[-1]['label'] if backups else 'N/A')
" 2>/dev/null || echo "N/A")

    info "Backup restaurado: $label (WAL replay hasta último segmento archivado)"
    DRILL_RESULTS[$stanza]="backup=${label} restore=${elapsed}s"
}

# ── Paso 4: arrancar instancia PG temporal ───────────────────────────────────

start_temp_pg() {
    local stanza=$1
    local pgver=${STANZA_PG_VER[$stanza]}
    local pgdata="${DRILL_BASE}/${stanza}/pgdata"
    local port=${STANZA_PORT[$stanza]}
    local pglog="${DRILL_BASE}/${stanza}/pg.log"

    info "Arrancando PG${pgver} en puerto ${port}..."

    # pg_hba.conf: en Ubuntu el PGDATA de producción no lo incluye (está en /etc/postgresql).
    # Copiamos el del cluster local si existe, si no generamos uno mínimo.
    local hba_src="/etc/postgresql/${pgver}/main/pg_hba.conf"
    if [[ -f "$hba_src" ]]; then
        sudo_pg cp "$hba_src" "${pgdata}/pg_hba.conf"
        info "pg_hba.conf copiado desde ${hba_src}"
    else
        sudo_pg bash -c "cat > '${pgdata}/pg_hba.conf'" <<'HBAEOF'
local   all   all                trust
host    all   all   127.0.0.1/32 trust
HBAEOF
        info "pg_hba.conf mínimo generado"
    fi

    # pg_ident.conf también puede faltar
    [[ ! -f "${pgdata}/pg_ident.conf" ]] && sudo_pg touch "${pgdata}/pg_ident.conf"

    # Sobreescribir parámetros en postgresql.conf
    sudo_pg bash -c "cat >> '${pgdata}/postgresql.conf'" <<PGEOF

# restore-drill overrides
port = ${port}
hba_file = '${pgdata}/pg_hba.conf'
ident_file = '${pgdata}/pg_ident.conf'
PGEOF

    # --type=standby escribe standby.signal; lo reemplazamos por recovery.signal
    # para que PG aplique el WAL archivado y luego promueva en lugar de quedarse
    # esperando un primary.
    sudo_pg bash -c "rm -f '${pgdata}/standby.signal' && touch '${pgdata}/recovery.signal'"

    # El WAL replay desde R2 puede tardar varios minutos; timeout generoso.
    sudo_pg "/usr/lib/postgresql/${pgver}/bin/pg_ctl" \
        start -D "$pgdata" -l "$pglog" -w -t 300 2>&1 | tee -a "$LOG_FILE"

    ok "Instancia PG${pgver} arrancada en puerto ${port} (aplicando WAL archive...)"
}

# ── Paso 5: verificación ─────────────────────────────────────────────────────

verify_stanza() {
    local stanza=$1
    local pgver=${STANZA_PG_VER[$stanza]}
    local port=${STANZA_PORT[$stanza]}
    local psql="/usr/lib/postgresql/${pgver}/bin/psql"
    local conn="-h 127.0.0.1 -p ${port} -U postgres"

    header "VERIFICACIÓN: ${stanza}"

    # 1. Conectividad
    if sudo_pg "$psql" $conn -tAq -c "SELECT 1" 2>/dev/null | grep -q 1; then
        ok "PostgreSQL acepta conexiones en puerto ${port}"
    else
        fail "${stanza}: PostgreSQL no responde en puerto ${port}"
        return 1
    fi

    # 2. Esperar promoción — el WAL replay desde R2 puede tardar varios minutos
    local in_recovery deadline
    deadline=$(( SECONDS + 300 ))
    while (( SECONDS < deadline )); do
        in_recovery=$(sudo_pg "$psql" $conn -tAq -c "SELECT pg_is_in_recovery();" 2>/dev/null | tr -d ' \n')
        [[ "$in_recovery" == "f" ]] && break
        local last_ts
        last_ts=$(sudo_pg "$psql" $conn -tAq \
            -c "SELECT to_char(pg_last_xact_replay_timestamp(),'HH24:MI:SS');" \
            2>/dev/null | tr -d ' \n')
        info "  WAL replay en curso... último xact: ${last_ts:-desconocido}"
        sleep 5
    done
    if [[ "$in_recovery" == "f" ]]; then
        ok "Instancia promovida correctamente"
    else
        fail "${stanza}: instancia sigue en recovery tras 300s"
    fi

    # 2b. Verificar frescura del WAL: el último xact reproducido debe estar
    #     dentro de los últimos 30 minutos (frecuencia de incr = 4h, pero el
    #     WAL archive debería tener segmentos de hace pocos minutos).
    local last_xact_epoch now_epoch wal_lag_min
    last_xact_epoch=$(sudo_pg "$psql" $conn -tAq \
        -c "SELECT EXTRACT(EPOCH FROM pg_last_xact_replay_timestamp())::bigint;" \
        2>/dev/null | tr -d ' \n')
    now_epoch=$(date +%s)
    if [[ -n "$last_xact_epoch" && "$last_xact_epoch" -gt 0 ]]; then
        wal_lag_min=$(( (now_epoch - last_xact_epoch) / 60 ))
        if (( wal_lag_min <= 30 )); then
            ok "Último xact reproducido hace ${wal_lag_min} min — WAL archive FRESCO"
            DRILL_RESULTS[$stanza]+=" wal_lag=${wal_lag_min}m"
        else
            fail "${stanza}: último xact reproducido hace ${wal_lag_min} min — WAL archive DESACTUALIZADO (umbral 30min)"
            DRILL_RESULTS[$stanza]+=" wal_lag=${wal_lag_min}m"
        fi
    else
        fail "${stanza}: pg_last_xact_replay_timestamp() es NULL — no se aplicó WAL archive"
        DRILL_RESULTS[$stanza]+=" wal_lag=NULL"
    fi

    # 3. Listar bases
    info "Bases de datos:"
    sudo_pg "$psql" $conn -c "\l" 2>/dev/null | tee -a "$LOG_FILE" || true

    # 4. Contar tablas por base
    local db_list total_tables=0
    db_list=$(sudo_pg "$psql" $conn -tAq \
        -c "SELECT datname FROM pg_database
            WHERE datistemplate=false AND datname<>'postgres'
            ORDER BY datname;" 2>/dev/null)

    while IFS= read -r db; do
        [[ -z "$db" ]] && continue
        local cnt
        cnt=$(sudo_pg "$psql" $conn -tAq -d "$db" \
            -c "SELECT count(*) FROM information_schema.tables
                WHERE table_schema NOT IN ('pg_catalog','information_schema');" \
            2>/dev/null | tr -d ' \n')
        cnt=${cnt:-0}
        info "  ${db}: ${cnt} tablas"
        total_tables=$(( total_tables + cnt ))
    done <<< "$db_list"

    if (( total_tables > 0 )); then
        ok "Total tablas: ${total_tables}"
    else
        fail "${stanza}: 0 tablas encontradas"
    fi

    # 5. Antigüedad del backup (umbral 25h = incr cada 4h + holgura)
    local stop_epoch now_epoch age_h
    stop_epoch=$(sudo_pg pgbackrest \
        --config="$PGBACKREST_CONF" --stanza="$stanza" \
        --output=json info 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
b = d[0]['backup']
print(b[-1]['timestamp']['stop'] if b else 0)
" 2>/dev/null || echo 0)

    now_epoch=$(date +%s)
    age_h=$(( (now_epoch - stop_epoch) / 3600 ))

    if (( age_h <= 25 )); then
        ok "Backup tiene ${age_h}h de antigüedad — AL DÍA"
        DRILL_RESULTS[$stanza]+=" age=${age_h}h STATUS=OK"
    else
        fail "${stanza}: backup tiene ${age_h}h de antigüedad — DESACTUALIZADO"
        DRILL_RESULTS[$stanza]+=" age=${age_h}h STATUS=FAIL"
    fi
}

# ── Paso 6: limpieza ─────────────────────────────────────────────────────────

cleanup_stanza() {
    local stanza=$1
    local pgver=${STANZA_PG_VER[$stanza]}
    local pgdata="${DRILL_BASE}/${stanza}/pgdata"
    local pgctl="/usr/lib/postgresql/${pgver}/bin/pg_ctl"

    info "Deteniendo instancia temporal ${stanza}..."
    sudo_pg "$pgctl" stop -D "$pgdata" -m fast 2>/dev/null \
        && ok "Instancia ${stanza} detenida" \
        || info "Instancia ${stanza} ya estaba detenida"

    sudo_pg rm -rf "${DRILL_BASE:?}/${stanza}"
    ok "Directorio de ${stanza} eliminado"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    local stanzas=("${@:-${ALL_STANZAS[@]}}")

    mkdir -p "$LOG_DIR"
    sudo_pg mkdir -p "${DRILL_BASE}/log" "${DRILL_BASE}/lock"

    header "RESTORE DRILL — $(date '+%Y-%m-%d %H:%M:%S')"
    info "Stanzas: ${stanzas[*]}"
    info "Log: $LOG_FILE"

    fetch_r2_credentials
    write_local_conf

    for stanza in "${stanzas[@]}"; do
        if restore_stanza "$stanza"; then
            start_temp_pg  "$stanza" || { fail "${stanza}: no arrancó PG temporal"; continue; }
            verify_stanza  "$stanza" || true
        else
            fail "${stanza}: restore fallido, saltando verificación"
        fi
    done

    header "LIMPIEZA"
    for stanza in "${stanzas[@]}"; do
        cleanup_stanza "$stanza" || true
    done
    sudo_pg rm -f "$PGBACKREST_CONF"

    # ── Resumen ──
    header "RESUMEN"
    printf "%-20s %-38s %-10s %-10s %-12s %s\n" "Stanza" "Backup" "Restore" "Edad" "WAL lag" "Estado" | tee -a "$LOG_FILE"
    printf '%.0s─' {1..95} | tee -a "$LOG_FILE"; echo | tee -a "$LOG_FILE"
    for stanza in "${stanzas[@]}"; do
        local res=${DRILL_RESULTS[$stanza]:-"no ejecutado"}
        local backup elapsed age wal_lag status
        backup=$(  echo "$res" | grep -oP 'backup=\K\S+' || echo "-")
        elapsed=$( echo "$res" | grep -oP 'restore=\K\S+' || echo "-")
        age=$(     echo "$res" | grep -oP 'age=\K\S+' || echo "-")
        wal_lag=$( echo "$res" | grep -oP 'wal_lag=\K\S+' || echo "-")
        status=$(  echo "$res" | grep -oP 'STATUS=\K\S+' || echo "-")
        printf "%-20s %-38s %-10s %-10s %-12s %s\n" "$stanza" "$backup" "$elapsed" "$age" "$wal_lag" "$status" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"

    if (( ${#FAILURES[@]} == 0 )); then
        echo -e "${GREEN}${BOLD}✓  DRILL EXITOSO — todas las stanzas OK${NC}\n" | tee -a "$LOG_FILE"
        exit 0
    else
        echo -e "${RED}${BOLD}✗  DRILL CON FALLOS:${NC}" | tee -a "$LOG_FILE"
        printf '  • %s\n' "${FAILURES[@]}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        exit 1
    fi
}

main "$@"
