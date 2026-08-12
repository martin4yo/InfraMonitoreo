#!/usr/bin/env bash
# Auto-chequeo de hardening: verifica que los controles del server sigan puestos y
# empuja el resultado al Netdata LOCAL vía statsd. Corre por cron, como root.
#
# POR QUÉ EXISTE
# --------------
# Complementa a hostkey-watchdog.py (que corre en dev-1 y detecta reinstalaciones
# desde afuera). Este mira hacia adentro: detecta que alguien apagó ufw, que
# fail2ban se murió, o que un drop-in de sshd dejó de aplicar — cosas que desde
# afuera no se ven y que el server, estando perfectamente "reachable", no reporta.
#
# LÍMITE CONOCIDO: si el server se reinstala, este script desaparece con él y deja
# de emitir. Por eso NO es el control de "server ausente" — ese es el de dev-1.
# La alarma de netdata sobre estas métricas usa `delay` largo para no gritar en
# cada reboot legítimo.
#
# MÉTRICAS
#   watchdog.self.ufw             -> 1 ufw active
#   watchdog.self.fail2ban        -> 1 fail2ban active Y con el jail sshd vivo
#   watchdog.self.sshd_nopassword -> 1 si sshd tiene PasswordAuthentication no
#   watchdog.self.sshd_noroot     -> 1 si sshd tiene PermitRootLogin no
#   watchdog.self.netdata_claimed -> 1 si el agente está claimed y online en Cloud
#   watchdog.self.ok              -> 1 si TODAS las anteriores dieron 1
#
# Cada métrica vale 0 cuando el control está caído o la herramienta no está
# instalada: en un server donde el control se da por puesto, "ausente" es "caído".
set -uo pipefail

STATSD_HOST=127.0.0.1
STATSD_PORT=8125

send() { printf '%s:%s|g' "$1" "$2" >/dev/udp/$STATSD_HOST/$STATSD_PORT 2>/dev/null; }

# ufw activo
ufw_ok=0
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw_ok=1
fi

# fail2ban activo Y con el jail sshd realmente levantado. Chequear solo el servicio
# no alcanza: en drp el 2026-07-17 y de nuevo el 08-11 el servicio figuraba presente
# con el jail sshd caído (buscaba /var/log/auth.log en un server con journald).
f2b_ok=0
if systemctl is-active --quiet fail2ban && fail2ban-client status sshd >/dev/null 2>&1; then
  f2b_ok=1
fi

# sshd: se lee la config EFECTIVA (sshd -T), no los archivos — un drop-in puede
# existir y no estar aplicado si nunca se recargó el servicio.
sshd_nopass=0
sshd_noroot=0
if effective=$(sshd -T 2>/dev/null); then
  grep -qi '^passwordauthentication no' <<<"$effective" && sshd_nopass=1
  grep -qi '^permitrootlogin no'        <<<"$effective" && sshd_noroot=1
fi

# netdata reclamado y con la conexión a Cloud viva
nd_ok=0
if aclk=$(netdatacli aclk-state 2>/dev/null); then
  if grep -q '^Claimed: Yes' <<<"$aclk" && grep -q '^Online: Yes' <<<"$aclk"; then
    nd_ok=1
  fi
fi

all_ok=1
for v in "$ufw_ok" "$f2b_ok" "$sshd_nopass" "$sshd_noroot" "$nd_ok"; do
  [ "$v" -eq 1 ] || all_ok=0
done

send watchdog.self.ufw             "$ufw_ok"
send watchdog.self.fail2ban        "$f2b_ok"
send watchdog.self.sshd_nopassword "$sshd_nopass"
send watchdog.self.sshd_noroot     "$sshd_noroot"
send watchdog.self.netdata_claimed "$nd_ok"
send watchdog.self.ok              "$all_ok"

printf 'ufw=%s fail2ban=%s sshd_nopassword=%s sshd_noroot=%s netdata_claimed=%s ok=%s\n' \
  "$ufw_ok" "$f2b_ok" "$sshd_nopass" "$sshd_noroot" "$nd_ok" "$all_ok"

[ "$all_ok" -eq 1 ] || exit 1
