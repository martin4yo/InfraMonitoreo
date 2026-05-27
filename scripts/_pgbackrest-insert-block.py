#!/usr/bin/env python3
"""Inserta (idempotente) un bloque de claves dentro de la sección [global] de un
pgbackrest.conf, entre marcadores. Re-ejecutar reemplaza el bloque previo.

Uso: _pgbackrest-insert-block.py <conf_path> <block_file>

El <block_file> es el contenido a insertar (sin los marcadores; los agrega este
script). Se inserta justo después de la línea '[global]'. Si ya existe un bloque
entre marcadores, se reemplaza en su lugar.
"""
import sys

BEGIN = "# >>> inframonitoreo r2 offsite >>>"
END = "# <<< inframonitoreo r2 offsite <<<"


def main():
    conf_path, block_file = sys.argv[1], sys.argv[2]
    with open(block_file) as f:
        block = f.read().strip("\n")
    with open(conf_path) as f:
        lines = f.read().split("\n")

    # 1) sacar bloque previo (entre marcadores) si existe
    out, skipping = [], False
    for ln in lines:
        if ln.strip() == BEGIN:
            skipping = True
            continue
        if ln.strip() == END:
            skipping = False
            continue
        if not skipping:
            out.append(ln)

    # 2) insertar el bloque nuevo justo después de [global]
    block_lines = [BEGIN] + block.split("\n") + [END]
    result, inserted = [], False
    for ln in out:
        result.append(ln)
        if not inserted and ln.strip().lower() == "[global]":
            result.extend(block_lines)
            inserted = True
    if not inserted:
        sys.exit("ERROR: no se encontró la sección [global] en " + conf_path)

    with open(conf_path, "w") as f:
        f.write("\n".join(result).rstrip("\n") + "\n")
    print("bloque repo2 insertado/actualizado en " + conf_path)


if __name__ == "__main__":
    main()
