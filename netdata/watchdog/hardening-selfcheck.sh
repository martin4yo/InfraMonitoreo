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
#   watchdog.self.ufw_enabled     -> 1 si la unit ufw está enabled (sobrevive al reboot)
#   watchdog.self.fail2ban        -> 1 fail2ban active Y con el jail sshd vivo
#   watchdog.self.sshd_nopassword -> 1 si sshd tiene PasswordAuthentication no
#   watchdog.self.sshd_noroot     -> 1 si sshd tiene PermitRootLogin no
#   watchdog.self.netdata_claimed -> 1 si el agente está claimed y online en Cloud
#   watchdog.self.ok              -> 1 si TODAS las anteriores dieron 1
#   watchdog.self.reboot_pending  -> 1 si hay un reboot pendiente (kernel/libc sin
#                                    activar). NO entra en 'ok': es mantenimiento,
#                                    no una regresión de hardening. Alarma propia.
#
# Cada métrica de control vale 0 cuando el control está caído o la herramienta no
# está instalada: en un server donde el control se da por puesto, "ausente" es
# "caído". El caso testigo de 'ufw_enabled': el 2026-09-03 ufw estaba `active` pero
# la unit `disabled` en los 3 servers de donweb, así que no sobrevivía al reboot —
# y `ufw` (active) no lo detectaba. Ver docs/hardening.md.
set -uo pipefail

STATSD_HOST=127.0.0.1
STATSD_PORT=8125

send() { printf '%s:%s|g' "$1" "$2" >/dev/udp/$STATSD_HOST/$STATSD_PORT 2>/dev/null; }

# ufw activo
ufw_ok=0
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw_ok=1
fi

# ufw ANCLADO al arranque (systemctl is-enabled). Un ufw active pero disabled queda
# vivo en caliente pero NO vuelve tras un reboot: es el modo de falla que dejó a
# dev-1 sin firewall 20 días (2026-08-14 → 09-03), invisible para el chequeo de
# 'active'. Solo aplica si ufw está instalado.
ufw_enabled=0
if command -v ufw >/dev/null 2>&1; then
  [ "$(systemctl is-enabled ufw 2>/dev/null)" = "enabled" ] && ufw_enabled=1
else
  # sin ufw instalado, 'enabled' no aplica: no debe tirar el ok por un control ausente
  # que ya reporta ufw=0. Se marca 1 para no duplicar la señal de "sin firewall".
  ufw_enabled=1
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

# reboot pendiente: kernel/libc actualizados por unattended-upgrades pero sin activar.
# NO es una regresión de hardening (no entra en 'ok'): es un recordatorio de que la
# ventana de reinicio (C11 de G6) está pendiente. Alarma propia, de aviso.
reboot_pending=0
[ -f /var/run/reboot-required ] && reboot_pending=1

all_ok=1
for v in "$ufw_ok" "$ufw_enabled" "$f2b_ok" "$sshd_nopass" "$sshd_noroot" "$nd_ok"; do
  [ "$v" -eq 1 ] || all_ok=0
done

send watchdog.self.ufw             "$ufw_ok"
send watchdog.self.ufw_enabled     "$ufw_enabled"
send watchdog.self.fail2ban        "$f2b_ok"
send watchdog.self.sshd_nopassword "$sshd_nopass"
send watchdog.self.sshd_noroot     "$sshd_noroot"
send watchdog.self.netdata_claimed "$nd_ok"
send watchdog.self.ok              "$all_ok"
send watchdog.self.reboot_pending  "$reboot_pending"

printf 'ufw=%s ufw_enabled=%s fail2ban=%s sshd_nopassword=%s sshd_noroot=%s netdata_claimed=%s ok=%s reboot_pending=%s\n' \
  "$ufw_ok" "$ufw_enabled" "$f2b_ok" "$sshd_nopass" "$sshd_noroot" "$nd_ok" "$all_ok" "$reboot_pending"

[ "$all_ok" -eq 1 ] || exit 1
