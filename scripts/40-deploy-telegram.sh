#!/usr/bin/env bash
# Configura notificaciones Telegram a nivel agente en cada server.
#
# Netdata sólo lee UN health_alarm_notify.conf: el de /etc/netdata si existe,
# si no el stock de /usr/lib/netdata/conf.d. Por eso copiamos el stock a /etc
# (la primera vez) y seteamos ahí las 3 variables de Telegram. Idempotente:
# re-correr vuelve a fijar los valores (útil si rota el token).
#
# Requiere TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID (definidos en secrets.sh).
# Las alarmas usan roles sysadmin/webmaster, que por defecto caen en
# DEFAULT_RECIPIENT_TELEGRAM, así que un solo chat id captura todo.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_inventory

: "${TELEGRAM_BOT_TOKEN:?Falta TELEGRAM_BOT_TOKEN (definilo en secrets.sh)}"
: "${TELEGRAM_CHAT_ID:?Falta TELEGRAM_CHAT_ID (definilo en secrets.sh)}"

STOCK=/usr/lib/netdata/conf.d/health_alarm_notify.conf
DEST=/etc/netdata/health_alarm_notify.conf

SED="sed -i \
 's|^SEND_TELEGRAM=.*|SEND_TELEGRAM=\"YES\"|; \
  s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"${TELEGRAM_BOT_TOKEN}\"|; \
  s|^DEFAULT_RECIPIENT_TELEGRAM=.*|DEFAULT_RECIPIENT_TELEGRAM=\"${TELEGRAM_CHAT_ID}\"|'"

for rec in "${SERVERS[@]}"; do
  parse_server "$rec"
  log "Configurando Telegram en $S_NAME ($S_HOST)"
  SUDO="$(sudo_prefix "$S_USER")"
  ssh_run "$S_USER" "$S_HOST" "$S_PORT" "
    [ -f $DEST ] || ${SUDO}cp $STOCK $DEST
    ${SUDO}${SED} $DEST
    ${SUDO}chown root:netdata $DEST && ${SUDO}chmod 640 $DEST
    ${SUDO}netdatacli reload-health
  "
  ok "$S_NAME → Telegram configurado y health recargado"
done

log "Telegram desplegado en los $((${#SERVERS[@]})) servers."
log "Para probar el envío real desde un agente:"
log "  ssh ... 'sudo -u netdata /usr/libexec/netdata/plugins.d/alarm-notify.sh test sysadmin'"
