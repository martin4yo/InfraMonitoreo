#!/usr/bin/env python3
"""Colector del lado DB HOST: vigila que archive-push funcione, desde el propio
servidor de base y de forma INDEPENDIENTE del repo host (dev-1).

Por qué existe (2026-09-03). El monitoreo de pgBackRest de `netdata/pgbackrest/`
vive SOLO en el repo host y mide el repositorio: edad de backup y atraso de WAL en
el repo. Tiene dos puntos ciegos que un susto real destapó:
  1. Si dev-1 (repo host) cae, ese colector cae con él — justo cuando archive-push
     empieza a fallar en los db hosts. El que vigila los backups no puede vigilarse
     a sí mismo cuando él es el que falló.
  2. No mira `pg_stat_archiver` de los db hosts: un archive-push roto recién se vería
     a los ~15 min por atraso de WAL, y solo si dev-1 está vivo para calcularlo.

Este colector corre en cada DB HOST (como `postgres`) y empuja a SU PROPIO Netdata
vía statsd (UDP 8125). Así el aviso de "no puedo mandar mis backups" nace en el
server que lo sufre, sin depender de dev-1.

Métricas (una por db host — un cluster por server):
  pgbackrest.archive.ready_backlog  -> nº de .ready en pg_wal/archive_status (WAL
                                       generado y aún NO archivado; se acumula si el
                                       push está trabado, drena solo si es un blip)
  pgbackrest.archive.failing        -> 1 si el ÚLTIMO evento de archiving fue un fallo
                                       posterior al último éxito (push roto y sin
                                       recuperar); 0 si ya se recuperó
  pgbackrest.archive.since_last_ok  -> seg desde last_archived_time
  pgbackrest.archive.failed_total   -> failed_count acumulado (para el chart/tendencia)

Diseño de umbral: las alarmas (health.d) piden que la condición se sostenga ~10 min,
para NO gritar por el blip normal de 90 s cuando dev-1 reinicia. Ese fue exactamente
el falso "repo1 roto" del 2026-09-03.
"""
import glob
import os
import socket
import subprocess
import time

STATSD = ("127.0.0.1", 8125)
NO_OK_AGE = 99999999  # "infinito" cuando nunca hubo archivado exitoso


def send(metric, value):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(f"{metric}:{value}|g".encode(), STATSD)


def psql(sql):
    r = subprocess.run(
        ["psql", "-tAqc", sql], capture_output=True, text=True, timeout=20
    )
    return r.stdout.strip() if r.returncode == 0 else ""


def main():
    now = int(time.time())

    # Cola de WAL sin archivar: archivos .ready en PGDATA/pg_wal/archive_status.
    ready_backlog = 0
    pgdata = psql("show data_directory")
    if pgdata:
        status_dir = os.path.join(pgdata, "pg_wal", "archive_status")
        ready_backlog = len(glob.glob(os.path.join(status_dir, "*.ready")))
    send("pgbackrest.archive.ready_backlog", ready_backlog)

    # Estado de archive-push desde pg_stat_archiver.
    row = psql(
        "select failed_count, "
        "coalesce(extract(epoch from last_archived_time)::bigint, 0), "
        "coalesce(extract(epoch from last_failed_time)::bigint, 0) "
        "from pg_stat_archiver"
    )
    failing = 0
    since_ok = NO_OK_AGE
    failed_total = 0
    if row:
        parts = row.split("|")
        failed_total = int(parts[0] or 0)
        last_ok = int(parts[1] or 0)
        last_fail = int(parts[2] or 0)
        since_ok = (now - last_ok) if last_ok else NO_OK_AGE
        # "failing" = el último evento de archiving fue un fallo posterior (o igual)
        # al último éxito. Tras recuperarse, last_ok > last_fail -> 0.
        failing = 1 if (last_fail > 0 and last_fail >= last_ok) else 0

    send("pgbackrest.archive.failed_total", failed_total)
    send("pgbackrest.archive.failing", failing)
    send("pgbackrest.archive.since_last_ok", since_ok)


if __name__ == "__main__":
    main()
