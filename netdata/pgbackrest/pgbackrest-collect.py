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


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def send(metric, value):
    msg = f"{metric}:{value}|g".encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(msg, (STATSD_HOST, STATSD_PORT))


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

        if not st_ok:
            all_ok = False
        worst_age = max(worst_age, b_age)

    backup_ok = 1 if (all_ok and worst_age < NO_BACKUP_AGE) else 0
    send("pgbackrest.backup_age", worst_age)
    send("pgbackrest.backup_ok", backup_ok)


def main():
    try:
        collect()
    except OSError as e:
        print(f"No se pudo enviar a statsd: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
