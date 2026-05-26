#!/usr/bin/env python3
"""Recolecta el estado de pgBackRest y lo empuja a Netdata vía statsd (UDP).

Corre por cron en el REPO HOST (dev-1) como el usuario dueño del repo (pgbackrest),
que es quien ve TODAS las stanzas con `pgbackrest info`. No fuerza WAL switches: lee
solo `info --output=json` (barato). La validación de archiving la hace el `check`
semanal del cron de backups.

Métricas (agregadas sobre todas las stanzas del repo):
  pgbackrest.backup_age  -> segundos desde el último backup OK de la PEOR stanza
                            (la más atrasada; así una stanza vieja no queda tapada
                             por otra reciente)
  pgbackrest.backup_ok   -> 1 si TODAS las stanzas están 'ok' y tienen al menos un
                            backup; 0 si alguna falla o no tiene backups
"""
import json
import socket
import subprocess
import sys
import time

STATSD_HOST = "127.0.0.1"
STATSD_PORT = 8125
NO_BACKUP_AGE = 99999999  # edad "infinita" para una stanza sin backups


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def send(metric, value):
    msg = f"{metric}:{value}|g".encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(msg, (STATSD_HOST, STATSD_PORT))


def collect():
    """Devuelve (worst_age_segundos, backup_ok)."""
    now = int(time.time())

    info = run(["pgbackrest", "info", "--output=json"])
    if info.returncode != 0 or not info.stdout.strip():
        # pgbackrest no responde / sin stanzas: falla total
        return NO_BACKUP_AGE, 0
    try:
        data = json.loads(info.stdout)
    except (ValueError, json.JSONDecodeError):
        return NO_BACKUP_AGE, 0
    if not data:
        return NO_BACKUP_AGE, 0

    all_ok = True
    worst_age = 0
    for stanza in data:
        # status.code == 0 significa "ok"
        if stanza.get("status", {}).get("code", 1) != 0:
            all_ok = False
        backups = stanza.get("backup", [])
        if not backups:
            all_ok = False
            worst_age = NO_BACKUP_AGE
            continue
        latest_stop = max(
            (b.get("timestamp", {}).get("stop", 0) or 0) for b in backups
        )
        age = (now - latest_stop) if latest_stop > 0 else NO_BACKUP_AGE
        worst_age = max(worst_age, age)

    backup_ok = 1 if (all_ok and worst_age < NO_BACKUP_AGE) else 0
    return worst_age, backup_ok


def main():
    worst_age, backup_ok = collect()
    try:
        send("pgbackrest.backup_age", worst_age)
        send("pgbackrest.backup_ok", backup_ok)
    except OSError as e:
        print(f"No se pudo enviar a statsd: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
