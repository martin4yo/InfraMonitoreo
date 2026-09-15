#!/usr/bin/env python3
"""Vigila que ningún server de la flota haya sido REINSTALADO o esté caído.

Corre por cron en dev-1 (el host de monitoreo) y empuja gauges a Netdata vía statsd.

POR QUÉ EXISTE
--------------
El 2026-08-08 le reinstalaron el SO a axioma-drp y nadie se enteró hasta el 08-11,
por casualidad: se perdieron ufw, fail2ban, Netdata, pgBackRest, la ampliación del
disco y todo el hardening de SSH. No había ningún control que lo detectara.

La alarma de "nodo unreachable" de Netdata Cloud NO alcanza para esto: un server
reinstalado vuelve a estar online enseguida (SSH abre en el 22 de nuevo), así que
para Cloud el nodo simplemente "volvió". Lo que NO vuelve igual es la **host key de
SSH**: una instalación nueva genera claves nuevas. Comparar la huella contra una
línea de base detecta la reinstalación aunque el server esté perfectamente vivo.

CÓMO
----
`ssh-keyscan` NO requiere autenticación: no hace falta ninguna llave ni usuario de
este script en los servers vigilados, así que no abre ninguna vía de acceso nueva.

MÉTRICAS (<srv> = nombre del server en la línea de base)
  watchdog.fleet.hostkey.<srv>    -> 1 si la host key coincide con la línea de base
                                     0 si CAMBIÓ (server reinstalado / MITM)
                                     (si no responde, no se toca: lo cubre reachable)
  watchdog.fleet.reachable.<srv>  -> 1 si el puerto SSH contesta, 0 si no
  watchdog.fleet.hostkey_ok       -> 1 si TODAS las huellas conocidas coinciden
  watchdog.fleet.reachable_count  -> cuántos servers responden (de N esperados)

LÍNEA DE BASE
-------------
/etc/watchdog/baseline.json, escrito por scripts/35-deploy-watchdog.sh a partir de
inventory.sh (gitignoreado: por eso las IPs no viven en este archivo). Formato:

  {"servers": [{"name": "...", "host": "...", "port": 22, "fp": "SHA256:..."}]}

Cuando una reinstalación es LEGÍTIMA, re-sembrar la línea de base con:
    hostkey-watchdog.py --reseed <server>
y dejar asentado el motivo en docs/hardening.md. Nunca re-sembrar sin verificar
por un canal independiente que la reinstalación era esperada — si no, se estaría
silenciando exactamente lo que este script existe para detectar.
"""
import argparse
import json
import os
import socket
import subprocess
import sys

STATSD_HOST = "127.0.0.1"
STATSD_PORT = 8125
BASELINE = "/etc/watchdog/baseline.json"
KEYSCAN_TIMEOUT = 10
CONNECT_TIMEOUT = 5


def send(metric, value):
    msg = f"{metric}:{value}|g".encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(msg, (STATSD_HOST, STATSD_PORT))


def load_baseline(path=BASELINE):
    with open(path) as fh:
        return json.load(fh)


def tcp_open(host, port):
    """¿Contesta el puerto SSH? Separado del keyscan para distinguir 'caído' de 'cambió'."""
    try:
        with socket.create_connection((host, int(port)), timeout=CONNECT_TIMEOUT):
            return True
    except OSError:
        return False


def fingerprint(host, port):
    """Huella SHA256 de la host key ed25519, o None si no se pudo obtener.

    No usa known_hosts ni autentica: ssh-keyscan pide la clave pública del server,
    que es justamente lo que cambia al reinstalar.
    """
    scan = subprocess.run(
        ["ssh-keyscan", "-T", str(KEYSCAN_TIMEOUT), "-t", "ed25519", "-p", str(port), host],
        capture_output=True, text=True,
    )
    if scan.returncode != 0 or not scan.stdout.strip():
        return None
    show = subprocess.run(
        ["ssh-keygen", "-lf", "-"], input=scan.stdout, capture_output=True, text=True
    )
    if show.returncode != 0:
        return None
    parts = show.stdout.split()
    return parts[1] if len(parts) > 1 else None


def check(servers):
    """Devuelve (resultados, huellas_vistas). No envía nada todavía."""
    results, seen = [], {}
    for srv in servers:
        name, host, port = srv["name"], srv["host"], srv.get("port", 22)
        up = tcp_open(host, port)
        fp = fingerprint(host, port) if up else None
        seen[name] = fp
        # match = None cuando no se pudo leer la huella: es 'desconocido', NO 'cambió'.
        # Enviar 0 ahí convertiría cada corte de red en una alarma de reinstalación.
        match = None if fp is None else (fp == srv["fp"])
        results.append({"name": name, "up": up, "fp": fp, "expected": srv["fp"], "match": match})
    return results, seen


def reseed(path, target, baseline, seen):
    """Re-siembra la huella de un server tras una reinstalación legítima."""
    hit = False
    for srv in baseline["servers"]:
        if srv["name"] != target:
            continue
        new = seen.get(target)
        if not new:
            print(f"No se pudo leer la host key de '{target}'; no se re-siembra.", file=sys.stderr)
            return 1
        print(f"{target}: {srv['fp']} -> {new}")
        srv["fp"] = new
        hit = True
    if not hit:
        print(f"'{target}' no está en la línea de base.", file=sys.stderr)
        return 1
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(baseline, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    print(f"Línea de base actualizada en {path}. Asentalo en docs/hardening.md.")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--baseline", default=BASELINE)
    ap.add_argument("--reseed", metavar="SERVER",
                    help="acepta la host key actual de SERVER como nueva referencia")
    ap.add_argument("--dry-run", action="store_true", help="muestra el estado sin enviar a statsd")
    args = ap.parse_args()

    try:
        baseline = load_baseline(args.baseline)
    except (OSError, ValueError) as e:
        print(f"No se pudo leer la línea de base {args.baseline}: {e}", file=sys.stderr)
        return 2

    servers = baseline.get("servers", [])
    results, seen = check(servers)

    if args.reseed:
        return reseed(args.baseline, args.reseed, baseline, seen)

    changed = [r for r in results if r["match"] is False]
    down = [r for r in results if not r["up"]]

    for r in results:
        estado = "OK" if r["match"] else ("CAMBIÓ" if r["match"] is False else "desconocido")
        print(f"{r['name']:<12} up={int(r['up'])} hostkey={estado}"
              + ("" if r["match"] is not False else f"  esperada={r['expected']} actual={r['fp']}"))

    if args.dry_run:
        return 1 if (changed or down) else 0

    try:
        for r in results:
            send(f"watchdog.fleet.reachable.{r['name']}", int(r["up"]))
            if r["match"] is not None:
                send(f"watchdog.fleet.hostkey.{r['name']}", int(r["match"]))
        send("watchdog.fleet.hostkey_ok", 0 if changed else 1)
        send("watchdog.fleet.reachable_count", sum(1 for r in results if r["up"]))
    except OSError as e:
        print(f"No se pudo enviar a statsd: {e}", file=sys.stderr)
        return 2

    return 1 if (changed or down) else 0


if __name__ == "__main__":
    sys.exit(main())
