#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Túnel SSH para acceder a las aplicaciones recuperadas en axioma-drp.
#
# POR QUÉ HACE FALTA: baehost (proveedor de axioma-drp) filtra los puertos 80/443 hacia
# axioma-drp (verificado 2026-08-12 — ver R21 en G3 y §8.1 del runbook de
# recuperación). El servidor está bien configurado —nginx en 0.0.0.0:80 e
# iptables con ACCEPT— pero el paquete no llega. Hasta que el proveedor los
# habilite, el único acceso es por túnel sobre el 22, que sí está abierto.
#
#   ./scripts/80-drp-tunnel.sh              levanta el túnel
#   ./scripts/80-drp-tunnel.sh --stop       lo baja
#   ./scripts/80-drp-tunnel.sh --status     dice si está activo
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

DRP_HOST="${DRP_HOST:-170.78.75.249}"
DRP_USER="${DRP_USER:-axiomacloud}"
DRP_PORT="${DRP_PORT:-22}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
LOCAL_PORT_TLS="${LOCAL_PORT_TLS:-8443}"
APPS=(hub-drill.local alvera-drill.local)

C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_0=$'\e[0m'
ok(){ echo "${C_OK}✔${C_0} $*"; }
warn(){ echo "${C_WARN}⚠${C_0} $*"; }
err(){ echo "${C_ERR}✘${C_0} $*" >&2; }
info(){ echo "${C_DIM}·${C_0} $*"; }

PATTERN="${LOCAL_PORT}:127.0.0.1:80"
PATTERN_TLS="${LOCAL_PORT_TLS}:127.0.0.1:443"

tunnel_pid(){ pgrep -f "ssh.*-L *${PATTERN}.*${DRP_HOST}" 2>/dev/null | head -1; }

stop_tunnel(){
    local pid; pid=$(tunnel_pid)
    if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null && ok "Túnel detenido (pid $pid)"
    else info "No había ningún túnel activo"; fi
}

status_tunnel(){
    local pid; pid=$(tunnel_pid)
    if [[ -n "$pid" ]]; then
        ok "Túnel ACTIVO (pid $pid) — localhost:${LOCAL_PORT} → ${DRP_HOST}:80"
        return 0
    fi
    info "Túnel inactivo"; return 1
}

case "${1:-}" in
    --stop)   stop_tunnel; exit 0 ;;
    --status) status_tunnel; exit $? ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# ── 1. ¿ya hay uno? ──────────────────────────────────────────────────────────
if pid=$(tunnel_pid); [[ -n "$pid" ]]; then
    warn "Ya hay un túnel activo (pid $pid). Lo reutilizo."
else
    # ── 2. el puerto local no debe estar ocupado por otra cosa ───────────────
    if ss -ltn 2>/dev/null | grep -q ":${LOCAL_PORT}\b"; then
        err "El puerto ${LOCAL_PORT} ya está en uso por otro proceso."
        err "Usá otro:  LOCAL_PORT=8081 $0"
        exit 1
    fi

    info "Levantando túnel ${LOCAL_PORT} → ${DRP_HOST}:80 …"
    if ! ssh -f -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
             -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
             -L "${PATTERN}" -L "${PATTERN_TLS}" -p "${DRP_PORT}" "${DRP_USER}@${DRP_HOST}"; then
        err "No se pudo abrir el túnel."
        err "Verificá el acceso:  ssh -p ${DRP_PORT} ${DRP_USER}@${DRP_HOST}"
        exit 1
    fi
    sleep 2
    ok "Túnel levantado"
fi

# ── 3. probar cada app a través del túnel ────────────────────────────────────
echo
echo "Aplicaciones recuperadas en axioma-drp:"
fallos=0
for app in "${APPS[@]}"; do
    # alvera exige HTTPS: su cookie de sesion sale con flag Secure (NODE_ENV=production)
    if [[ "$app" == alvera-* ]]; then
        url="https://127.0.0.1:${LOCAL_PORT_TLS}/"; flags="-sk"; puerto="${LOCAL_PORT_TLS}"; esquema="https"
    else
        url="http://127.0.0.1:${LOCAL_PORT}/";      flags="-s";  puerto="${LOCAL_PORT}";     esquema="http"
    fi
    code=$(curl $flags -o /dev/null -w '%{http_code}' -H "Host: ${app}" "$url" --max-time 15 2>/dev/null)
    title=$(curl $flags -H "Host: ${app}" "$url" --max-time 15 2>/dev/null \
            | grep -oE '<title>[^<]*</title>' | sed 's/<[^>]*>//g')
    if [[ "$code" == "200" ]]; then
        printf "  ${C_OK}%s${C_0}  %-22s ${C_DIM}%s${C_0}\n" "200" "${esquema}://${app}:${puerto}" "${title:-—}"
    else
        printf "  ${C_ERR}%s${C_0}  %-22s ${C_DIM}(sin respuesta)${C_0}\n" "${code:-000}" "$app"
        fallos=$((fallos+1))
    fi
done

# ── 4. instrucciones para el navegador ───────────────────────────────────────
echo
if ! grep -qE "^\s*127\.0\.0\.1\s+.*hub-drill\.local" /etc/hosts 2>/dev/null; then
    warn "Para abrirlas en el navegador falta una línea en /etc/hosts:"
    echo
    echo "    sudo sh -c 'echo \"127.0.0.1 ${APPS[*]}\" >> /etc/hosts'"
    echo
else
    ok "/etc/hosts ya tiene las entradas"
fi
echo "Abrí en el navegador:"
echo "    http://hub-drill.local:${LOCAL_PORT}"
echo "    https://alvera-drill.local:${LOCAL_PORT_TLS}   ${C_DIM}(certificado autofirmado: el navegador va a advertir)${C_0}"
echo
info "alvera SOLO funciona por HTTPS: su cookie de sesion sale con flag Secure"
info "y el navegador la descarta sobre http://. No es un fallo: es la app protegiendose."
echo
info "Para bajarlo:  $0 --stop"

(( fallos > 0 )) && exit 1 || exit 0
