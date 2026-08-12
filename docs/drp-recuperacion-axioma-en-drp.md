# DRP — Recuperación de axioma en axioma-drp · Runbook general

> **Escenario que cubre:** axioma **deja de existir** (hardware perdido, host irrecuperable, cuenta
> suspendida) y hay que levantar sus servicios en **axioma-drp**.
>
> **Cómo se usa:** este documento es el **procedimiento común a todas las aplicaciones**, con `<app>` como
> variable. Los datos concretos de cada una —puerto, base, usuario, dominio, repo, particularidades— están
> en las [fichas por aplicación](./drp-fichas-apps-axioma.md). Se leen **juntos**: el runbook dice *qué
> hacer*, la ficha dice *con qué valores*.
>
> **Estado:** v1 (2026-08-11) — **redactado, NO ejecutado**. Los tiempos son estimados salvo donde se
> indique medido. La primera ejecución de prueba debe corregir este documento.
>
> **Relación con el resto del marco:** el [DRP de base de datos](./disaster-recovery-plan.md) cubre la
> recuperación de PostgreSQL (§2 de este runbook lo invoca). El [BCP — G9](./gobierno/g9-continuidad-negocio.md)
> cubre los habilitantes (accesos, claves, DNS). El criterio de cierre de cada verificación es
> [G10](./gobierno/g10-verificacion-remediaciones.md).

---

## 0. Lo que hay que saber antes de empezar

### 0.1 axioma-drp no es igual a axioma

| | axioma | axioma-drp | Consecuencia |
|---|---|---|---|
| RAM | 11 GB | **3911 MB** ✅ *(ampliada el 2026-08-12; antes 1 GB)* + 4 GB swap | 🔴 **No se compila en drp.** Ver §0.2 |
| vCPU | 8 | 2 | Todo tarda más; no paralelizar builds |
| Disco libre | 23 GB | 54 GB | ✅ Sin problema — PGDATA son 696 MB |
| PostgreSQL | 14.23 | **14.23** | ✅ Misma versión: el restore es directo |
| pgBackRest | 2.58.0 | 2.59.0 | ✅ Compatible (lee la stanza sin problema) |
| Node / PM2 / nginx / certbot / pgbouncer | ✅ | ❌ **nada instalado** | Fase 1 los instala |
| Ubuntu / glibc | 22.04 / 2.35 | 22.04 / **2.35** | ✅ **Binarios compatibles entre sí** |

### 0.1.1 🔴 De dónde sale cada cosa — el runbook NO puede depender de axioma

En una catástrofe **axioma no existe**. Todo lo necesario tiene que venir de otro lado:

| Qué | De dónde | ¿Depende de axioma? |
|---|---|---|
| **Datos** | backup en **R2** (pgBackRest) | ❌ No |
| **Código** | **repositorio git** de cada app | ❌ No |
| **Config de PM2** | 🔴 **[`config/axioma/pm2/`](../config/axioma/)** — ⚠️ **NO el `ecosystem.config.js` del repo**, que difiere de producción (ver ficha de alvera) | ❌ No |
| **Configuración** (`.env`) | **`infra-secrets`** (SOPS) | ❌ No |
| **Artefactos compilados** | pre-compilados en R2 (§10.1) o compilados desde el repo | ❌ No |
| Puertos, vhosts, `ecosystem.config.js`, unidades systemd | ✅ **[`config/axioma/`](../config/axioma/)** *(versionado el 2026-08-12)* | ❌ No |

> ✅ **Hueco cerrado el 2026-08-12.** Los 27 archivos de configuración que solo vivían en axioma están
> versionados en [`config/axioma/`](../config/axioma/) — 12 vhosts, 4 ecosystem, 9 unidades systemd,
> `nginx.conf` y los snippets anti-scanner. Verificados **sin secretos** antes de commitear.
> **Con esto, ningún paso del runbook depende ya de que axioma exista.**

### 0.2 🔴 Regla de oro: **no se compila en drp**

Con 4 GB, `next build` de una sola aplicación (1–2 GB de pico) puede tumbar el servidor con PostgreSQL y
otras apps ya corriendo. La separación que lo resuelve:

| Paso | Consume RAM | Depende de la plataforma |
|---|---|---|
| **Compilar** (`next build`, `tsc`) → `.next`, `dist` | 🔴 1–2 GB | ❌ No — es JavaScript |
| **Instalar** (`npm ci --omit=dev`) → binarios nativos | 🟢 ~200 MB | 🔴 **Sí** |

**El paso que come memoria es portable; el que depende de la plataforma es liviano.** Por eso:

> **Se compila afuera y se instala en drp.**
>
> ⚠️ **MATIZADO CON MEDICIÓN REAL (2026-08-12).** Se compiló el frontend de alvera **en drp**, con hub ya
> corriendo: **33 segundos, y el mínimo de memoria disponible fue 1598 MB** de 3911. El pico consumió
> ~1,2 GB. **La regla se relaja a: «compilar en drp es viable, de a UNA app por vez y midiendo».** Sigue
> siendo preferible el artefacto pre-compilado —es 33 s contra minutos, por app— pero **compilar en drp
> ya no es un bloqueante**, que es lo que este documento suponía antes de medirlo.

⚠️ **Y "afuera" no significa tu notebook.** El equipo de trabajo corre **Linux Mint 22.3 con glibc 2.39**;
los servidores usan **glibc 2.35**. glibc es compatible hacia atrás, **no hacia adelante**: un binario
compilado contra 2.39 falla en 2.35 con `GLIBC_2.38 not found`. Y hay **49 binarios `.node`** en juego,
más Prisma en 4 apps, `sharp` en 2 y `bcrypt` en 2.

**Opciones válidas para compilar, en orden de preferencia:**

1. **Pre-compilar en axioma mientras está vivo** y guardar el artefacto junto a los backups. Plataforma
   idéntica garantizada, y convierte el DR de *«compilar bajo presión»* a *«descargar y arrancar»*.
   👉 **Es la opción recomendada, y hay que montarla ANTES del desastre** (ver §10).
2. **Contenedor `node:20-bullseye` o `ubuntu:22.04`** en cualquier máquina. Reproducible y con la glibc
   correcta.
3. **Compilar en otro servidor del parque** (clubix o dev-1, ambos Ubuntu 22.04 / glibc 2.35).
4. **Último recurso: compilar en drp, de a una app por vez**, con las demás detenidas. Funciona, pero es
   el camino lento y frágil.

> **Nota sobre `npm ci` en drp:** sí se corre en drp, y está bien. No compila desde fuente: descarga los
> *prebuilds* que cada paquete publica para la plataforma destino. Es liviano y garantiza que los binarios
> nativos correspondan a glibc 2.35.

### 0.3 Orden de levantamiento

Con 4 GB entra todo el régimen estable (medido en axioma: **1737 MB de apps + ~600 MB de PostgreSQL +
~600 MB de sistema ≈ 3 GB**), pero **el margen es de ~900 MB**. Levantar en este orden permite verificar en
cada escalón y detenerse si la memoria aprieta:

1. **PostgreSQL** (§2) — sin base no arranca ninguna app
2. **mediflow / alvera** — datos de salud, la más crítica
3. **hub**, **parse**, **mini** — núcleo operativo
4. **elore**
5. **evolution-api** — software de terceros, el más pesado (330 MB)
6. **axio-db-agent** y estáticos

Después de cada app: `free -m` y verificación de la ficha. **Si el disponible baja de 300 MB, parar.**

### 0.4 ¿Esto afecta a axioma? — acoplamientos verificados

**Ejecutar este runbook hasta la Fase 7 NO afecta a axioma.** Verificado el 2026-08-12:

| Por qué es independiente | Evidencia |
|---|---|
| drp restaura **desde R2**, no desde dev-1 | Su `pgbackrest.conf` no tiene `repo1-host`; el repo es S3/R2 directo |
| `restore` es **solo lectura** sobre el repositorio | No escribe backups, no altera la stanza |
| 🔴 **drp no archiva WAL** | `archive_mode = off` y `archive_command = (disabled)` |
| El procedimiento ya está probado | Los restore drills mensuales corren así desde 2026-05 sin afectar producción |

> **El punto crítico es el tercero.** Si el cluster restaurado arrancara con el `archive_command` heredado
> de axioma, empezaría a empujar WAL **a la misma stanza** y contaminaría la línea temporal de los backups
> productivos. Está desactivado en drp, pero **verificarlo antes de cada simulacro** es obligatorio:
> ```bash
> sudo -u postgres psql -tAc "show archive_mode"   # DEBE decir: off
> ```

**Las tres cosas que SÍ acoplan con producción — no hacerlas en un simulacro:**

1. 🔴 **`pgbackrest expire` o `backup` desde drp.** Escriben en el repositorio **compartido** con
   producción. El propio `pgbackrest.conf` de drp lo advierte. Desde drp: solo `restore` e `info`.
2. 🔴 **Fase 8 (DNS).** Es el único paso que redirige tráfico real. En un simulacro **no se toca**.
3. 🟡 **Fase 7 con dominios reales.** Let's Encrypt limita a **5 emisiones por dominio por semana**, y ese
   contador es **compartido con axioma**: emitir certificados de prueba desde drp puede dejar a axioma sin
   poder renovar los suyos. En simulacro: `/etc/hosts` + certificado autofirmado, **nunca `certbot`
   contra los dominios productivos**.

**Lo que sí cambia en drp:** la Fase 2 pisa su PGDATA actual. Es invasivo **sobre drp**, reversible por el
respaldo de §2.2, y deja las 11 bases de axioma aunque el simulacro pruebe una sola app.

---

## 1. Fase 1 — Preparar el stack base en drp

> ✅ **EJECUTADA el 2026-08-12** — 25 min reales + el paso 1.8, descubierto al ejecutar la Fase 2. Se hizo con axioma vivo, que es como corresponde:
> esta fase no debe esperar al incidente.

- [x] **1.1** Confirmar acceso: `ssh axiomacloud@170.78.75.249` con `sudo -n true` OK. ✅
- [x] **1.2** ~~Ampliar la RAM a 4 GB desde el panel del proveedor~~ — ✅ **hecho el 2026-08-12**: 3911 MB + 4 GB swap.
- [x] **1.3** ✅ Instalado **v20.20.2 / npm 10.8.2** — *idéntico a axioma*, que es lo que garantiza que los binarios nativos de `npm ci` sean compatibles:
  ```bash
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
  node -v    # debe decir v20.x
  ```
- [x] **1.4** ✅ Instalados **PM2 6.0.14** (axioma: 6.0.13), **nginx 1.18.0** y **certbot 1.21.0** — mismas versiones:
  ```bash
  sudo npm install -g pm2@6
  sudo apt-get install -y nginx certbot python3-certbot-nginx
  ```
- [x] **1.5** ✅ **Ya estaban abiertos** — drp venía con 22/80/443 en ufw desde su reinstalación del 08-08:
  ```bash
  sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw status
  ```
- [x] **1.6** ✅ **7 de 7 creados** el 2026-08-12, con home propio y `mediflowapp` en el grupo `www-data`
      como en axioma. Los UID **no** coinciden con los de axioma (drp: 992–998) y **no importa**: lo que
      referencian los `.env`, las rutas y las unidades systemd son los **nombres**.
  ```bash
  for u in mediflowapp hubapp parseapp miniapp eloreapp evolutionapp axioapp; do
    sudo useradd -r -m -s /bin/bash "$u" 2>/dev/null || echo "$u ya existe"
  done
  ```
- [x] **1.8** 🔴 **Generar el locale `en_US.UTF-8`** — *paso descubierto ejecutando, el 2026-08-12*:
  ```bash
  sudo locale-gen en_US.UTF-8 && sudo update-locale
  ```
  ⚠️ **Sin esto el cluster restaurado NO ARRANCA.** El cluster de axioma se inicializó con
  `LC_COLLATE = en_US.UTF-8`; drp, reinstalado el 08-08, traía solo `C`, `C.utf8` y `POSIX`. PostgreSQL
  falla al arrancar con:
  ```
  FATAL: database locale is incompatible with operating system
  DETAIL: The database was initialized with LC_COLLATE "en_US.UTF-8",
          which is not recognized by setlocale()
  ```
  **Es un bloqueante total del DR** y no aparece en ningún inventario de paquetes ni de configuración:
  el `pgbackrest restore` termina *"completed successfully"* y el fallo recién se ve al arrancar. Un
  documento escrito sin ejecutar nunca lo hubiera detectado.

- [x] **1.7** ✅ Verificado — drp ve las **4 stanzas**:
  ```bash
  sudo -u postgres pgbackrest info --stanza=AxiomaCloudProd
  ```
  ✅ *Ya verificado el 2026-08-11: drp ve las 4 stanzas.*

> **Estado tras la Fase 1 (2026-08-12):** drp quedó con **416 MB usados y 3236 MB disponibles**, con
> nginx, PostgreSQL y ufw activos. El stack base está listo: a partir de acá, un DR real arranca
> directamente en la Fase 2 y se ahorra estos 25 minutos.

---

## 2. Fase 2 — Restaurar PostgreSQL

> ⏱ Medido: el último full backup tardó **8 min** en generarse; el restore es del mismo orden.
> Los datos son **361 MB** en total (PGDATA 696 MB), así que esta fase es la rápida.

- [ ] **2.1** Detener PostgreSQL en drp: `sudo systemctl stop postgresql`
- [ ] **2.2** ⚠️ **INVASIVO** — Respaldar el PGDATA actual de drp antes de pisarlo:
  ```bash
  sudo mv /var/lib/postgresql/14/main /var/lib/postgresql/14/main.pre-drp-$(date +%Y%m%d%H%M)
  ```
- [ ] **2.3** Restaurar la stanza de axioma:
  ```bash
  sudo -u postgres pgbackrest --stanza=AxiomaCloudProd --delta restore
  ```
  Para un punto en el tiempo concreto, agregar `--type=time --target="YYYY-MM-DD HH:MM:SS"`.
  Ver [DRP §2](./disaster-recovery-plan.md) para los escenarios.
- [ ] **2.4** Arrancar y verificar réplica de WAL:
  ```bash
  sudo systemctl start postgresql
  sudo -u postgres psql -c "select datname, pg_size_pretty(pg_database_size(datname)) from pg_database where oid>16383 order by 2 desc;"
  ```
  ✅ Deben aparecer las **11 bases**: `mini_db`, `parse_db`, `mediflow_db`, `elore_db`, `hub_db`,
  `axiomadocs`, `chequescloud`, `iasqlassistant_db`, `checkpoint_db`, `evolution`, `core_db`.
- [ ] **2.5** 🔴 **Verificar LEGIBILIDAD, no solo existencia.** Es el paso que el DRP no tenía:
  ```bash
  # mediflow cifra campos en reposo a nivel de aplicación (ENCRYPTION_MASTER_KEY).
  # Que la base levante NO prueba que los datos se puedan leer.
  ```
  La verificación real es funcional y se hace **después** de levantar mediflow (§9.3). Anotarlo acá para
  no darlo por hecho: **una base restaurada con datos cifrados ilegibles es una recuperación fallida que
  parece exitosa.** Riesgo **R15**.

---

## 3. Fase 3 — Roles de PostgreSQL

> El `pgbackrest restore` trae el cluster completo **incluidos los roles**, porque son objetos globales.
> Esta fase es de **verificación**, no de creación — salvo que algo falte.

- [ ] **3.1** Verificar que existen los roles de app:
  ```bash
  sudo -u postgres psql -c "\du" | grep -E "mediflowuser|hubuser|parseuser|miniuser|eloreuser"
  ```
- [ ] **3.2** Si falta alguno, crearlo **con el password que está en su `.env`** (de `infra-secrets`):
  ```bash
  sudo -u postgres psql -c "CREATE ROLE <app>user LOGIN PASSWORD '<del .env>';"
  sudo -u postgres psql -c "ALTER DATABASE <app>_db OWNER TO <app>user;"
  ```
  ⚠️ Por el [estándar §9](./estandar-despliegue.md), `<app>user` debe ser **owner de la base y de todos
  sus objetos**, no solo tener GRANT. Fue el aprendizaje del drill de hub.
- [ ] **3.3** Verificar `pg_hba.conf`: debe permitir loopback con `scram-sha-256` y **ninguna línea `md5`**.
- [ ] **3.4** ⚠️ **pgbouncer no está instalado en drp, y lo usan TRES aplicaciones.** Verificado en los
      `.env`: **mediflow, mini y parse** conectan a `localhost:**6432**`; **hub y elore** van directo al
      `5432`. Dos caminos:
  - **A (rápido):** en los `.env` de **mediflow, mini y parse**, cambiar el puerto a `5432` y quitar
    `?pgbouncer=true`. Sirve para el DR; anotar que es un desvío del estándar.
  - **B (fiel):** `sudo apt-get install -y pgbouncer` y replicar la config de axioma.

  👉 **Para una recuperación de emergencia, usar A.** Menos piezas, menos que puede fallar. Pero **hay que
  acordarse de las tres**: si solo se corrige mediflow, mini y parse arrancan y fallan al primer query,
  con un error de conexión que no dice "falta pgbouncer".

---

## 4. Fase 4 — Código y artefactos compilados

> ⏱ Es la fase larga si hay que compilar. Con artefactos pre-compilados (§10), baja a minutos.

Por cada `<app>`, según su ficha:

- [ ] **4.1** Traer el código al `<path>` de la ficha:
  ```bash
  sudo -u <appuser> git clone <repo> /var/www/<app>
  ```
  ⚠️ Los repos de **hub, mediflow, mini y parse** son **SSH** (`git@github.com:…`): requieren una deploy
  key. Si no está disponible, clonar por HTTPS con token, o traer el código del artefacto de §10.
- [ ] **4.2** Colocar el **artefacto compilado** (`.next/`, `dist/`, `build/`) según la ficha.
      **No ejecutar `next build` en drp** (§0.2).
- [ ] **4.3** Instalar dependencias de producción — **esto sí se hace en drp**:
  ```bash
  cd /var/www/<app> && sudo -u <appuser> npm ci --omit=dev
  ```
- [ ] **4.4** Si la app usa **Prisma**, regenerar el cliente para esta plataforma:
  ```bash
  sudo -u <appuser> npx prisma generate
  ```
  Aplica a **mediflow, parse, mini y elore**.
- [ ] **4.5** Verificar propiedad de todo el árbol (regla del estándar y origen de H06):
  ```bash
  sudo chown -R <appuser>:<appuser> /var/www/<app>
  sudo find /var/www/<app> -not -user <appuser> | head    # debe salir vacío
  ```

---

## 5. Fase 5 — Los `.env` desde SOPS

> 🔴 **Esta fase depende de la clave age.** Si no está disponible, **el DR se detiene acá**: las apps no
> arrancan sin configuración. Ver [G9 §4.3](./gobierno/g9-continuidad-negocio.md) y
> [G7 §7.1](./gobierno/g7-rotacion-secretos.md) — ya pasó una vez.

- [ ] **5.1** Restaurar la clave age en el equipo desde el que se opera:
  ```bash
  mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age
  # pegar las 3 líneas guardadas en LastPass en ~/.config/sops/age/keys.txt
  chmod 600 ~/.config/sops/age/keys.txt
  age-keygen -y ~/.config/sops/age/keys.txt
  # DEBE imprimir: age182586wqdnzjqhwjn4vwd8pp7mempkm3x82jgvj5dud2c05fex36qy3f4gm
  ```
- [ ] **5.2** Clonar el repo de secretos: `git clone git@github.com:martin4yo/infra-secrets.git`
- [ ] **5.3** Descifrar y colocar el `.env` de la app **con permisos y owner correctos**:
  ```bash
  export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
  sops --decrypt env/axioma/<app>-backend.env | \
    ssh axiomacloud@170.78.75.249 "sudo tee /var/www/<app>/backend/.env >/dev/null"
  ssh axiomacloud@170.78.75.249 "sudo chmod 600 /var/www/<app>/backend/.env && sudo chown <appuser>:<appuser> /var/www/<app>/backend/.env"
  ```
- [ ] **5.4** Ajustar en el `.env` lo que cambia en drp: `DATABASE_URL` si se optó por A en §3.4, y las
      URLs públicas si el DNS todavía no apunta a drp.

---

## 6. Fase 6 — Arrancar con PM2

- [ ] **6.1** Arrancar con el ecosystem de la app **como su usuario** (nunca como root):
  ```bash
  cd /var/www/<app> && sudo -u <appuser> pm2 start ecosystem.config.js
  ```
  ⚠️ **`PM2_HOME` no es uniforme.** `parseapp` usa `/var/www/parse/.pm2`; el resto usa
  `/home/<user>/.pm2`. Si PM2 "no ve" la app, es esto.
- [ ] **6.2** Persistir y crear la unidad systemd:
  ```bash
  sudo -u <appuser> pm2 save
  sudo env PATH=$PATH pm2 startup systemd -u <appuser> --hp /home/<appuser>
  ```
- [ ] **6.3** Verificar: `sudo -u <appuser> pm2 list` → status `online`, 0 restarts.
- [ ] **6.4** `free -m` — si el disponible bajó de **300 MB**, detenerse y revisar antes de seguir con la
      siguiente app (§0.3).

---

## 7. Fase 7 — nginx y TLS

- [ ] **7.1** Copiar el vhost de la app. Los originales de axioma están en `/etc/nginx/sites-available/`;
      si axioma no existe, reconstruirlos desde la ficha (dominios y puertos están ahí).
- [ ] **7.2** Ajustar `proxy_pass` al puerto de la ficha y las rutas `root` de los estáticos.
- [ ] **7.3** Aplicar el snippet anti-scanner (`block-scanners`) — ver
      [`nginx-anti-scanner.md`](./nginx-anti-scanner.md); el script `60-deploy-anti-scanner.sh` es idempotente.
- [ ] **7.4** `sudo nginx -t && sudo systemctl reload nginx`
- [ ] **7.5** **TLS.** Certbot necesita que el DNS ya apunte a drp para validar por HTTP-01:
  ```bash
  sudo certbot --nginx -d <dominio> -d <dominio-api>
  ```
  ⚠️ Si el DNS todavía no se movió, usar `/etc/hosts` + certificado autofirmado para probar, y emitir el
  certificado real recién después de §8. **No reemitir el cert de producción mientras axioma siga vivo**:
  Let's Encrypt tiene límite de 5 emisiones por dominio por semana.

---

## 8. Fase 8 — DNS · 🔴 el paso que se olvida

> **Podés tener todo levantado y perfecto en drp, y el servicio seguir caído**, porque los dominios
> siguen apuntando a la IP de axioma. Ningún backup resuelve esto. Es **K8** del
> [kit de continuidad](./gobierno/g9-continuidad-negocio.md).

- [ ] **8.1** Entrar a **Cloudflare** (K8) y cambiar los registros `A` de axioma
      (`66.97.45.210`) a drp (`170.78.75.249`).
- [ ] **8.2** Dominios a mover — todos los que servía axioma:
  ```
  alvera.axiomacloud.com · api.alvera.axiomacloud.com · alvera.com.ar · www.alvera.com.ar
  hub.axiomacloud.com · api.hub.axiomacloud.com
  parse.axiomacloud.com · api.parse.axiomacloud.com
  mini.axiomacloud.com · axioma.ar · www.axioma.ar
  elore.com.ar · www.elore.com.ar · *.elore.com.ar
  evolution.axiomacloud.com · checkpoint.axiomacloud.com · prd.axiomacloud.com
  axiomaweb.axiomacloud.com
  ```
- [ ] **8.3** **Bajar el TTL a 60 s ANTES** de un cambio planificado. En una catástrofe no hay tiempo:
      por eso conviene tener el TTL bajo de forma permanente en los registros críticos.
- [ ] **8.4** Verificar propagación: `dig +short <dominio>` debe devolver `170.78.75.249`.

---

## 9. Fase 9 — Verificación

> Se aplica el criterio de cierre de [G10](./gobierno/g10-verificacion-remediaciones.md). No alcanza con
> que las apps estén `online` en PM2.

- [ ] **9.1** **Próximo arranque (R1).** Reiniciar cada app y confirmar que vuelve sola:
      `sudo -u <appuser> pm2 restart <name> && sleep 10 && sudo -u <appuser> pm2 list`
- [ ] **9.2** **Cobertura total (R2).** Las 11 bases presentes y **cada app de la ficha** verificada. Anotar
      el conteo explícito, no "verificado".
- [ ] **9.3** 🔴 **Legibilidad de datos cifrados (BC-B).** En mediflow, abrir un registro que use campos
      cifrados y confirmar que **se lee en claro**. Si sale ilegible, falta la `ENCRYPTION_MASTER_KEY`
      correcta: la recuperación **no está completa** aunque todo lo demás funcione.
- [ ] **9.4** **Contenido, no solo código (R4).** En los dominios con redirect, revisar el header
      `Location`: debe apuntar al dominio público, **no a `localhost`**. Es el patrón de H04.
  ```bash
  curl -sI https://<dominio>/ | grep -i location
  ```
- [ ] **9.5** **Control negativo (R3).** Una ruta de scanner debe dar conexión cerrada:
  ```bash
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: <dominio>' http://127.0.0.1/wp-login.php   # → 000
  ```
- [ ] **9.6** **Login funcional** en cada app con interfaz. Es la prueba que integra base, `.env`, backend
      y frontend de una sola vez.
- [ ] **9.7** `free -m` final y `sudo -u <appuser> pm2 list` de todas: 0 restarts inesperados.

---

## 10. Antes del desastre — lo que hay que tener montado

> Esta sección es la que decide si el DR tarda **horas o días**. Todo lo de acá se hace **con axioma vivo**.

- [ ] **10.1** 🔴 **Artefactos pre-compilados.** Un job periódico en axioma que empaquete, por app, el
      `.next`/`dist` + `package.json` + `package-lock.json`, y lo suba a **R2 junto a los backups**.
      Plataforma idéntica garantizada, y el DR pasa a ser *descargar y arrancar*.
- [ ] **10.2** **Stack base ya instalado en drp** (Fase 1 completa). No hay razón para dejarla para el día
      del incidente: son 30 minutos que se pueden gastar hoy.
- [ ] **10.3** **Clave age en dos lugares**, uno accesible por el BT. Sin esto, la Fase 5 no se puede
      ejecutar y el DR se detiene — ya ocurrió el 2026-08-09.
- [ ] **10.4** **Acceso a Cloudflare (K8) documentado y compartido.** Sin DNS no hay servicio.
- [ ] **10.5** **Deploy keys de GitHub** disponibles para el BT, o una copia del código fuera de los servers.
- [ ] **10.6** **TTL bajo** en los registros DNS críticos.
- [x] **10.8** ✅ **Configuración versionada el 2026-08-12** en [`config/axioma/`](../config/axioma/):
      27 archivos, sin secretos. **Mantenerla al día es parte de C6** — es una foto, no la fuente de
      verdad.
- [ ] **10.7** **Ejecutar este runbook como simulacro, una app por vez.** Es lo que convierte este
      documento de hipótesis en procedimiento. Empezar por la ficha más simple, no por mediflow.

---

## 11. Vuelta atrás

Cuando axioma se recupere o se reemplace:

1. **Detener escrituras en drp** — es la fuente de verdad mientras esté sirviendo.
2. **Backup completo desde drp**: `pgbackrest --stanza=AxiomaCloudProd backup --type=full`.
3. Reconstruir axioma con este mismo runbook (es simétrico).
4. **Mover el DNS de vuelta**, con TTL bajo.
5. Recién entonces detener las apps en drp y volver su PostgreSQL al `main.pre-drp-*` de §2.2.

> ⚠️ **Nunca dejar los dos sirviendo a la vez.** Dos instancias escribiendo en bases distintas producen
> divergencia de datos que ningún backup reconcilia — es el peor resultado posible de un DR.

---

## 12. Tiempos estimados

| Fase | Con artefactos pre-compilados | Compilando en el momento |
|---|---|---|
| 1 — Stack base | 0 (ya hecho) | 30–45 min |
| 2 — PostgreSQL | 10–15 min *(medido: full en 8 min)* | ídem |
| 3 — Roles | 5 min | ídem |
| 4 — Código y build | 15–20 min | **2–4 h** (secuencial, de a una app) |
| 5 — `.env` | 15 min | ídem |
| 6 — PM2 | 20 min | ídem |
| 7 — nginx + TLS | 30 min | ídem |
| 8 — DNS | 10 min + propagación | ídem |
| 9 — Verificación | 30–45 min | ídem |
| **Total** | **≈ 2–3 h** | **≈ 5–8 h** |

> **La diferencia entre 2 y 8 horas es la §10.1.** Es la acción con mejor relación esfuerzo/beneficio de
> todo este plan.

---

*Documento redactado el 2026-08-11 · **no ejecutado**. Los tiempos son estimados salvo los marcados como
medidos. La primera ejecución de prueba DEBE corregir este documento y registrarse en
[G6](./gobierno/g6-revisiones-periodicas.md).*
