#!/usr/bin/env python3
"""Despliega (idempotente) la protección anti-scanners de nginx en un host.

Corre EN el server (vía 60-deploy-anti-scanner.sh). Aplica 3 cosas:
  1) snippets/scanner-map.conf  -> map $request_uri $loggable (0 = scanner)
  2) nginx.conf: include del map + 'access_log ... if=$loggable'
     => las peticiones de scanner NO se loguean ⇒ Netdata (que lee access.log)
        no dispara la alarma web_log de redirects/bad-requests.
  3) snippets/block-scanners.conf -> 'if ($loggable = 0) { return 444; }'
     insertado al inicio de cada server{} de sites-enabled y conf.d. Corre
     antes del 'return 301', así también protege los vhosts de redirección.

Hace backup completo bajo /etc/nginx/_backup_block_scanners_<ts> y, si
`nginx -t` falla al final, restaura automáticamente y sale con error (no recarga;
el reload lo hace el orquestador). Re-ejecutar es seguro: salta lo ya aplicado.
"""
import os, re, glob, time, shutil, subprocess, sys

NGINX = "/etc/nginx"
SNIP = f"{NGINX}/snippets"
TS = time.strftime("%Y%m%d_%H%M%S")
BK = f"{NGINX}/_backup_block_scanners_{TS}"

MAP_SNIPPET = r"""# scanner-map.conf  (contexto http) - marca peticiones de scanners WordPress/PHP/CGI.
# $loggable = 0  -> NO se loguea (access_log if=$loggable) y se bloquea (return 444).
map $request_uri $loggable {
    default                                                                       1;
    ~*\.(php|phtml|php[0-9]|aspx?|jsp|cgi|pl|sh|asp)([?]|$)                        0;
    ~*/(wp-admin|wp-includes|wp-content|wp-login|wp-json|xmlrpc|wlwmanifest|wso)  0;
}
"""

BLOCK_SNIPPET = """# block-scanners.conf  (contexto server) - corta scanners marcados por $loggable.
# Se inserta al inicio de cada server{}; corre antes del 'return 301', así
# también protege los vhosts de redirección http->https. No toca tráfico real.
if ($loggable = 0) { return 444; }
"""

MAP_INC = "include /etc/nginx/snippets/scanner-map.conf;"
BLOCK_INC = "    include snippets/block-scanners.conf;"
RE_SERVER = re.compile(r'^\s*server\s*\{')


def site_files():
    files = []
    for f in sorted(glob.glob(f"{NGINX}/sites-enabled/*")):
        rp = os.path.realpath(f)
        if os.path.isfile(rp):
            files.append(rp)
    for f in sorted(glob.glob(f"{NGINX}/conf.d/*.conf")):
        base = os.path.basename(f).lower()
        if "netdata" in base or "stub_status" in base:
            continue  # no tocar la config de monitoreo
        try:
            if re.search(r'^\s*server\s*\{', open(f, encoding="utf-8", errors="replace").read(), re.M):
                files.append(f)
        except OSError:
            pass
    seen, out = set(), []
    for f in files:
        if f not in seen:
            seen.add(f); out.append(f)
    return out


def bk(p):
    return BK + p


def backup(paths):
    for p in [f"{NGINX}/nginx.conf"] + paths:
        d = bk(p); os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copy2(p, d)
    print(f"  backup -> {BK}")


def restore(paths):
    for p in [f"{NGINX}/nginx.conf"] + paths:
        if os.path.exists(bk(p)):
            shutil.copy2(bk(p), p)
    print("  *** nginx -t FALLÓ: restaurado el estado previo ***")


def edit_nginx_conf():
    p = f"{NGINX}/nginx.conf"
    txt = open(p, encoding="utf-8").read()
    changed = False
    if "snippets/scanner-map.conf" not in txt:
        out, done = [], False
        for ln in txt.splitlines(keepends=True):
            out.append(ln)
            if not done and re.match(r'^\s*http\s*\{', ln):
                ind = re.match(r'^(\s*)', ln).group(1) + "\t"
                out.append(f"{ind}{MAP_INC}\n")
                done = True
        txt = "".join(out); changed = True
        print("  nginx.conf: +include scanner-map.conf en http{}")
    if "if=$loggable" not in txt:
        new, n = re.subn(r'(^[ \t]*access_log\s+/var/log/nginx/access\.log)\s*;',
                         r'\1 combined if=$loggable;', txt, flags=re.M)
        if n:
            txt = new; changed = True
            print(f"  nginx.conf: access_log -> if=$loggable ({n} línea/s)")
    if changed:
        open(p, "w", encoding="utf-8").write(txt)
    else:
        print("  nginx.conf: ya estaba aplicado")


def edit_site(p):
    txt = open(p, encoding="utf-8").read()
    if "snippets/block-scanners.conf" in txt:
        print(f"  {p}: ya tenía el include (skip)")
        return
    out, n = [], 0
    for ln in txt.splitlines(keepends=True):
        out.append(ln)
        if RE_SERVER.match(ln):
            out.append(BLOCK_INC + "\n"); n += 1
    open(p, "w", encoding="utf-8").write("".join(out))
    print(f"  {p}: +include en {n} server block(s)")


def main():
    if os.geteuid() != 0:
        sys.exit("Correr con sudo.")
    os.makedirs(SNIP, exist_ok=True)
    paths = site_files()
    print("Archivos con server{}:", len(paths))
    backup(paths)
    open(f"{SNIP}/scanner-map.conf", "w", encoding="utf-8").write(MAP_SNIPPET)
    open(f"{SNIP}/block-scanners.conf", "w", encoding="utf-8").write(BLOCK_SNIPPET)
    print("  snippets escritos")
    edit_nginx_conf()
    for p in paths:
        edit_site(p)
    print("--- nginx -t ---")
    r = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        restore(paths)
        sys.exit("nginx -t falló (cambios revertidos).")
    print("OK: nginx -t pasó. Cambios en disco, listos para reload.")


if __name__ == "__main__":
    main()
