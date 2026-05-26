#!/usr/bin/env python3
"""Recolecta el estado de pgBackRest y lo empuja a Netdata vía statsd (UDP).

Pensado para correr por cron como el usuario dueño de pgBackRest (normalmente
'postgres'). No escribe archivos ni necesita permisos especiales: solo manda
3 gauges a Netdata en 127.0.0.1:8125.

Métricas:
  pgbackrest.backup_age  -> segundos desde el último backup OK (de cualquier stanza)
  pgbackrest.backup_ok   -> 1 si todas las stanzas reportan estado OK y hay backups; si no 0
  pgbackrest.check_ok    -> 1 si 'pgbackrest check' pasa en todas las stanzas; si no 0
"""
import json
import socket
import subprocess
import sys
import time

STATSD_HOST = "127.0.0.1"
STATSD_PORT = 8125


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def send(metric, value):
    msg = f"{metric}:{value}|g".encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(msg, (STATSD_HOST, STATSD_PORT))


def collect():
    last_epoch = 0
    backup_ok = 0
    check_ok = 0

    info = run(["pgbackrest", "info", "--output=json"])
    if info.returncode != 0 or not info.stdout.strip():
        # pgbackrest no responde / sin stanzas: todo en falla
        return last_epoch, backup_ok, check_ok

    try:
        data = json.loads(info.stdout)
    except (ValueError, json.JSONDecodeError):
        return last_epoch, backup_ok, check_ok

    if not data:
        return last_epoch, backup_ok, check_ok

    all_ok = True
    stanzas = []
    for stanza in data:
        stanzas.append(stanza.get("name", ""))
        # status.code == 0 significa "ok" en la salida de pgbackrest
        if stanza.get("status", {}).get("code", 1) != 0:
            all_ok = False
        for backup in stanza.get("backup", []):
            stop = backup.get("timestamp", {}).get("stop", 0) or 0
            if stop > last_epoch:
                last_epoch = stop

    backup_ok = 1 if (all_ok and last_epoch > 0) else 0

    # 'check' verifica archiving de WAL + acceso al repositorio (requiere stanza).
    # Hace un switch de WAL de prueba, por eso no conviene correrlo muy seguido.
    check_ok = 1
    for st in [s for s in stanzas if s]:
        r = run(["pgbackrest", f"--stanza={st}", "check"])
        if r.returncode != 0:
            check_ok = 0

    return last_epoch, backup_ok, check_ok


def main():
    last_epoch, backup_ok, check_ok = collect()
    now = int(time.time())
    age = (now - last_epoch) if last_epoch > 0 else 99999999
    try:
        send("pgbackrest.backup_age", age)
        send("pgbackrest.backup_ok", backup_ok)
        send("pgbackrest.check_ok", check_ok)
    except OSError as e:
        print(f"No se pudo enviar a statsd: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
