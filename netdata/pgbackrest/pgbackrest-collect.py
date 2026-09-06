#!/usr/bin/env python3
"""Recolecta el estado de pgBackRest y lo empuja a Netdata vía statsd (UDP).

Corre por cron en el REPO HOST (dev-1) como el usuario dueño del repo (pgbackrest),
que es quien ve TODAS las stanzas con `pgbackrest info`. No fuerza WAL switches: lee
solo `info --output=json` (barato) y stat-ea archivos del repo. La validación real del
archiving la hace el `check` semanal del cron de backups.

Métricas AGREGADAS (compat con las alarmas históricas):
  pgbackrest.backup_age  -> seg desde el último backup OK de la PEOR stanza
                            (la más atrasada; una stanza vieja no queda tapada)
  pgbackrest.backup_ok   -> 1 si TODAS las stanzas están 'ok' y con backups; si no 0

Métricas POR STANZA (<st> = nombre de stanza):
  pgbackrest.<st>.backup_age -> seg desde el último backup OK de esa stanza
  pgbackrest.<st>.wal_age    -> seg desde que llegó el último WAL al repo
                                (mtime del segmento 'max' en archive/<st>/)
  pgbackrest.<st>.backup_ok  -> 1 si la stanza está 'ok' y con al menos un backup
  pgbackrest.<st>.verify_age -> seg desde el último `verify` de esa stanza (el más
                                viejo de sus repos; infinito si a algún repo le falta)

INTEGRIDAD (pgbackrest.verify_*)
--------------------------------
El `verify` NO lo corre este colector: es caro (>16 min la stanza más chica) y lo
dispara pgbackrest-verify.sh una vez por semana por stanza. Acá solo se LEEN sus
archivos de estado y se publican. Que la edad la recalcule este colector cada 15 min
es el punto: crece sola, así que un cron de verify muerto dispara la alarma de edad.
Si el verify publicara su propia métrica, moriría con ella congelada en verde.

Si VERIFY_DIR no existe, no se emite ninguna métrica de verify: el chequeo no está
desplegado en este server y una alarma en rojo sería ruido, no información.

SEÑAL DE VIDA (STAMP_PATH)
--------------------------
Al terminar una corrida completa se toca /var/lib/pgbackrest-netdata/repo.stamp.
NO es una métrica: es un archivo, y eso es a propósito.

Las métricas de arriba NO alcanzan para detectar que este colector murió. El chart
de statsd está en `gaps when not collected = no`, así que netdata re-emite el último
valor cada segundo: si el cron deja de correr, `backup_age` se CONGELA en su última
lectura y nunca cruza el umbral de 25h. Todas las alarmas de pgBackRest quedarían
en CLEAR con el backup roto. Verificado el 2026-09-05 en dev-1: `last_collected_t`
del chart daba 1 segundo de antigüedad con el colector corriendo cada 15 min, y el
historial se ve plano 14 min y salta exactamente +900 en cada corrida. Por lo mismo
tampoco sirve la alarma estándar de netdata `$now - $last_collected_t`.

La frescura del stamp la mide hardening-selfcheck.sh, que corre por OTRO cron y como
OTRO usuario. Residual conocido: si mueren los dos crones a la vez, nadie avisa.
"""
import glob
import json
import os
import socket
import subprocess
import sys
import time

STATSD_HOST = "127.0.0.1"
STATSD_PORT = 8125
REPO_PATH = "/backup/pgbackrest"
NO_BACKUP_AGE = 99999999  # edad "infinita" (sin backups / sin WAL / pgbackrest caído)
STAMP_PATH = "/var/lib/pgbackrest-netdata/repo.stamp"  # señal de vida; ver docstring
VERIFY_DIR = "/var/lib/pgbackrest-netdata/verify"      # estado que deja pgbackrest-verify.sh


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def send(metric, value):
    msg = f"{metric}:{value}|g".encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(msg, (STATSD_HOST, STATSD_PORT))


def verify_state(name, repo_keys, now):
    """(edad del verify más viejo, ok) de una stanza, exigiendo TODOS sus repos.

    Los repos esperados salen de `info`, no de los archivos que haya en disco: si se
    pide el estado por lo que existe, una stanza verificada en repo1 y nunca en repo2
    se vería como verificada entera — justo el repo off-site, que es el que importa
    el día del desastre.

    Las dos señales dicen cosas distintas y no se mezclan:
      edad -> ¿se está verificando? Un repo sin estado (nunca verificado, o archivo
              ilegible) da edad infinita y lo levanta la alarma de atraso.
      ok   -> ¿alguna verificación FALLÓ? Solo un rc != 0 la baja. "Nunca verificado"
              no es "verificado y corrupto": mezclarlos haría que un despliegue nuevo
              gritara "checksums que no validan" sin haber leído un solo archivo.
    """
    peor_edad, ok = 0, 1
    for key in repo_keys:
        ruta = f"{VERIFY_DIR}/{name}.repo{key}.json"
        try:
            with open(ruta) as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            peor_edad = NO_BACKUP_AGE  # nunca verificado o estado ilegible
            continue
        peor_edad = max(peor_edad, int(now - d.get("ts", 0)))
        if d.get("rc", 1) != 0:
            ok = 0
    return (peor_edad, ok) if repo_keys else (NO_BACKUP_AGE, ok)


def touch_stamp():
    """Marca que esta corrida llegó hasta el final (señal de vida del colector)."""
    os.makedirs(os.path.dirname(STAMP_PATH), exist_ok=True)
    with open(STAMP_PATH, "a"):
        pass
    os.utime(STAMP_PATH, None)


def backup_age(stanza, now):
    """Segundos desde el último backup OK de la stanza."""
    backups = stanza.get("backup", [])
    if not backups:
        return NO_BACKUP_AGE
    latest_stop = max((b.get("timestamp", {}).get("stop", 0) or 0) for b in backups)
    return (now - latest_stop) if latest_stop > 0 else NO_BACKUP_AGE


def wal_age(stanza, now):
    """Segundos desde el mtime del último WAL ('max') archivado en el repo.

    Apunta directo al segmento 'max' que reporta `info` (barato). Si no lo encuentra
    (p.ej. nombre comprimido inesperado) cae a recorrer archive/<stanza>/ buscando el
    archivo más nuevo.
    """
    archives = stanza.get("archive") or []
    if not archives:
        return NO_BACKUP_AGE
    a = archives[0]
    wid, wmax = a.get("id"), a.get("max")
    if not wid or not wmax:
        return NO_BACKUP_AGE
    base = f"{REPO_PATH}/archive/{stanza['name']}/{wid}/{wmax[:16]}"
    matches = (
        glob.glob(f"{base}/{wmax}-*")   # comprimido: <wal>-<hash>.lz4
        + glob.glob(f"{base}/{wmax}")    # sin comprimir
        + glob.glob(f"{base}/{wmax}.*")  # otras compresiones (.gz, .zst)
    )
    if not matches:
        newest = 0.0
        for dirpath, _, filenames in os.walk(f"{REPO_PATH}/archive/{stanza['name']}"):
            for fn in filenames:
                try:
                    newest = max(newest, os.path.getmtime(os.path.join(dirpath, fn)))
                except OSError:
                    pass
        return int(now - newest) if newest else NO_BACKUP_AGE
    try:
        newest = max(os.path.getmtime(m) for m in matches)
    except OSError:
        return NO_BACKUP_AGE
    return int(now - newest)


def collect():
    """Empuja métricas agregadas y por stanza a statsd."""
    now = int(time.time())

    info = run(["pgbackrest", "info", "--output=json"])
    try:
        data = json.loads(info.stdout) if info.returncode == 0 else None
    except (ValueError, json.JSONDecodeError):
        data = None
    if not data:
        # pgbackrest no responde / sin stanzas: falla total
        send("pgbackrest.backup_age", NO_BACKUP_AGE)
        send("pgbackrest.backup_ok", 0)
        return

    # El verify solo se publica si está desplegado (ver docstring).
    hay_verify = os.path.isdir(VERIFY_DIR)
    verify_all_ok = 1
    verify_worst_age = 0

    all_ok = True
    worst_age = 0
    for stanza in data:
        name = stanza.get("name", "unknown")
        # Multi-repo: el status agregado da 'mixed' (code 4) si repo2 está atrasado
        # y 'running' (code 3) durante un backup; ninguno de esos es un fallo. La
        # stanza está sana si AL MENOS UN repo está ok (code 0) y hay backup reciente.
        repos = stanza.get("repo", [])
        if repos:
            any_repo_ok = any(r.get("status", {}).get("code", 1) == 0 for r in repos)
        else:  # config viejo single-repo sin lista "repo"
            any_repo_ok = stanza.get("status", {}).get("code", 1) == 0
        b_age = backup_age(stanza, now)
        w_age = wal_age(stanza, now)
        st_ok = 1 if (any_repo_ok and b_age < NO_BACKUP_AGE) else 0

        send(f"pgbackrest.{name}.backup_age", b_age)
        send(f"pgbackrest.{name}.wal_age", w_age)
        send(f"pgbackrest.{name}.backup_ok", st_ok)

        if hay_verify:
            v_age, v_ok = verify_state(name, [r.get("key") for r in repos], now)
            send(f"pgbackrest.{name}.verify_age", v_age)
            verify_worst_age = max(verify_worst_age, v_age)
            if not v_ok:
                verify_all_ok = 0

        if not st_ok:
            all_ok = False
        worst_age = max(worst_age, b_age)

    backup_ok = 1 if (all_ok and worst_age < NO_BACKUP_AGE) else 0
    send("pgbackrest.backup_age", worst_age)
    send("pgbackrest.backup_ok", backup_ok)
    if hay_verify:
        send("pgbackrest.verify_age", verify_worst_age)
        send("pgbackrest.verify_ok", verify_all_ok)


def main():
    try:
        collect()
        # Después de collect(): el stamp significa "corrida completa", no "arrancó".
        touch_stamp()
    except OSError as e:
        print(f"No se pudo enviar a statsd: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
