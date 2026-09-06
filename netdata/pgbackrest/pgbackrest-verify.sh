#!/usr/bin/env bash
# Verificación de INTEGRIDAD del repositorio pgBackRest. Corre en el REPO HOST
# (dev-1) como el usuario dueño del repo (pgbackrest), por cron, una stanza por
# noche y contra los dos repos.
#
# POR QUÉ EXISTE
# --------------
# El resto del monitoreo responde "¿hay un backup reciente y el WAL está llegando?".
# Ninguna de esas métricas mira ADENTRO de los archivos. `pgbackrest verify` recorre
# el repo y valida los checksums de backups y WAL: es lo único que detecta corrupción
# silenciosa —un bit podrido en disco, un objeto truncado en R2— antes de que la
# descubras el día del desastre, restaurando.
#
# Estaba documentado en docs/restore-drill-procedure.md como paso previo opcional del
# drill, y por eso nunca se corrió sostenidamente: el drill es manual y mensual.
#
# NO EMPUJA MÉTRICAS
# ------------------
# Deja el resultado en un archivo de estado y se va. Quien publica a Netdata es
# pgbackrest-collect.py, en su corrida de cada 15 min. Es a propósito:
#   - la EDAD del último verify la recalcula el colector, así que crece sola y un
#     cron de verify muerto se detecta por la alarma de edad. Si este script
#     empujara su propia métrica, moriría con ella congelada en verde — el mismo
#     punto ciego de statsd que documenta pgbackrest-collect.py;
#   - y hereda gratis la señal de vida del colector.
#
# COSTO REAL (medido en dev-1 el 2026-09-05)
# ------------------------------------------
# `verify` lee TODO el repo. La stanza más chica (axiodemo: 2.7 GB de archive) tardó
# >16 min con un solo proceso. Por eso: PROCESS_MAX>1, una stanza por noche, y fuera
# de la ventana de backups (02:00-04:00). No es un chequeo que se pueda correr seguido.
#
# Uso:  pgbackrest-verify.sh <stanza> [repo...]     (por defecto, repos 1 y 2)
set -uo pipefail

STATE_DIR="/var/lib/pgbackrest-netdata/verify"
PROCESS_MAX="${PROCESS_MAX:-2}"   # dev-1 tiene 4 cores y comparte con las apps

stanza="${1:?uso: pgbackrest-verify.sh <stanza> [repo...]}"
shift
repos=("$@")
[ ${#repos[@]} -eq 0 ] && repos=(1 2)

mkdir -p "$STATE_DIR" || { echo "no se puede escribir en $STATE_DIR" >&2; exit 1; }

rc_total=0
for repo in "${repos[@]}"; do
  inicio=$(date +%s)
  salida=$(pgbackrest --stanza="$stanza" --repo="$repo" --process-max="$PROCESS_MAX" verify 2>&1)
  rc=$?
  fin=$(date +%s)

  # Última línea con contenido: alcanza para saber por qué falló sin guardar el log
  # entero en el estado (el log completo queda en /var/log/pgbackrest/).
  detalle=$(printf '%s' "$salida" | grep -v '^[[:space:]]*$' | tail -1 | tr -d '"' | cut -c1-300)

  printf '{"stanza":"%s","repo":%s,"ts":%s,"rc":%s,"secs":%s,"detalle":"%s"}\n' \
    "$stanza" "$repo" "$fin" "$rc" "$((fin - inicio))" "$detalle" \
    > "$STATE_DIR/$stanza.repo$repo.json"

  if [ "$rc" -eq 0 ]; then
    printf 'verify %s repo%s OK en %s s\n' "$stanza" "$repo" "$((fin - inicio))"
  else
    printf 'verify %s repo%s FALLO (rc=%s) en %s s: %s\n' \
      "$stanza" "$repo" "$rc" "$((fin - inicio))" "$detalle" >&2
    rc_total=1
  fi
done

exit "$rc_total"
