# G7 — Política de Rotación e Inventario de Secretos

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G7** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
> Alineada con **CIS Control 3** (Protección de datos) y **CIS Control 5** (Gestión de cuentas).
>
> **Estado:** v1 — redacción inicial (2026-08-06).
>
> **Hallazgo que motiva este documento.** La **custodia** de secretos está resuelta y verificada:
> SOPS+age cifra los 16 `.env` de la infraestructura en un repo privado, con la clave age fuera de banda.
> Lo que faltaba es la **gestión del ciclo de vida**: no hay política de rotación (el token de R2 se rotó
> **reactivamente por exposición**, no por calendario), ni inventario formal de secretos con owner,
> frecuencia y fecha de última rotación. Sin inventario no se puede responder la pregunta que un auditor
> hace primero: *"si mañana se filtra una credencial, ¿saben cuáles existen y quién las rota?"*.
>
> **Lenguaje normativo:** **DEBE** = obligatorio · **DEBERÍA** = recomendado salvo justificación
> registrada · **PUEDE** = opcional.

## 1. Alcance

Aplica a **todo secreto** que dé acceso a un sistema, dato o servicio de la infraestructura Axioma:

- Credenciales de base de datos (roles de PostgreSQL de las apps y `postgres`).
- **Credenciales en ARCHIVO, no en variable de entorno** (claves de service account, certificados de
  cliente, keystores) — *agregado 2026-08-12: el alcance solo contemplaba variables dentro de `.env`, y
  por ese hueco `google-credentials.json` quedó sin respaldo (S19).*
- **Contraseñas de cuentas de sistema operativo** con acceso administrativo (`axiomacloud` y toda cuenta
  con `sudo`) — *agregado 2026-08-09: el alcance original las omitía, y ese hueco se materializó (S16).*
- **Claves de cifrado de datos de aplicación** (`ENCRYPTION_MASTER_KEY` y salts) — *agregado 2026-08-09.*
- Claves de API y tokens de servicios externos (Cloudflare R2, Netdata Cloud, pasarelas de pago, etc.).
- Claves de cifrado (`cipher-pass` de pgBackRest, clave privada age).
- Claves SSH (de operación y de emergencia).
- Secretos de aplicación (`JWT_SECRET`, claves de sesión, webhooks).
- Certificados TLS (gestionados por Let's Encrypt — renovación automática).

**Fuera de alcance:** credenciales de sistemas de terceros que no custodiamos (panel del proveedor VPS,
cuentas personales), salvo en cuanto a exigir MFA donde el proveedor lo ofrezca.

## 2. Custodia — estado vigente y verificado

| Aspecto | Implementación | Estado |
|---|---|---|
| **Cifrado en repo** | SOPS + age, cifrado **por-valor** (`encrypted_regex` — las claves quedan legibles, solo se cifran los valores) | ✅ Vigente |
| **Repo de secretos** | `martin4yo/infra-secrets` (GitHub **privado**), estructura `env/<server>/<app>[-<componente>].env` | ✅ Vigente — **16 `.env` cifrados** (⚠ corregido 2026-08-09: decía 15). Desglose completo en §3.2 — 13 con secretos, 3 solo con variables públicas de frontend |
| **Clave age (privada)** | `~/.config/sops/age/keys.txt` (`600`) + custodia **fuera de banda** en gestor de contraseñas | 🔴 **PERDIDA (2026-08-09)** — no está en el equipo de trabajo ni en el gestor de contraseñas. La custodia "fuera de banda" **falló**. Ver §7.1 |
| **Recipient (pública)** | `age1rsrkjwldsmc9ytusjxq6k7yyaa2k4ll9ahkvntc0hu05d5k3y50qexmku7` | ✅ Vigente |
| **Secretos en el server** | `.env` en claro **solo** en el server, `600` y owner `<app>app` | ✅ Vigente ([estándar §201](../estandar-despliegue.md)) |
| **Rotación de logs** | logrotate en los 5 servers — limita la ventana de retención de secretos filtrados a logs | ✅ Desplegado (H13/logrotate) |

### 2.1 Reglas de manejo

- Un secreto **DEBE** estar cifrado en el repo de secretos; en claro **solo** en el server que lo consume.
- El `.env` en el server **DEBE** ser `600` y owner del usuario de la app. ⚠ **Verificar contra el usuario
  configurado del proceso, no contra el owner del directorio**: un `chmod`/`chown` mal dirigido no rompe el
  proceso vivo, rompe el **próximo arranque**.
- Un secreto **NUNCA DEBE** aparecer en: commits del repo de código, `console.log`/stdout, tickets, chats,
  ni archivos `.bak`. **Regla operativa aprendida en H03:** al rotar una credencial, **no dejar `.bak` con
  el valor viejo** — la fuga real de H03 no estaban en los `.conf` (ya en `640`) sino en 4 `.bak` con las
  claves pre-rotación.
- La clave age **NUNCA DEBE** versionarse. Sin ella no se descifra nada — su pérdida es un evento de
  continuidad, no solo de seguridad (ver §7).

## 3. Inventario de secretos

> **Convención:** ID `S<n>`. "Última rotación" en blanco = **desconocida / desde el aprovisionamiento
> original**, que es en sí un hallazgo. La primera tarea de esta política es completar esa columna.
>
> **Método del inventario (2026-08-09).** El desglose de §3.2 se construyó leyendo los **nombres de
> variable** de los 16 `.env` de `infra-secrets`. La regla de `.sops.yaml` cifra **solo los valores**
> (`encrypted_regex: ^[A-Za-z_][A-Za-z0-9_]*$`), de modo que los nombres quedan legibles: se puede
> enumerar *qué* secretos existen **sin la clave age y sin descifrar un solo valor**. Esa propiedad —
> elegida originalmente para que el `git diff` mostrara qué variable cambió sin exponerla — es la que
> hace auditable el inventario. **Ningún valor fue descifrado ni leído para construir esta sección.**

### 3.1 Secretos de infraestructura y transversales

| ID | Secreto | Ubicación | Owner | Criticidad | Última rotación | Frecuencia | Estado |
|---|---|---|---|---|---|---|---|
| **S01** | Clave privada **age** (maestra de todos los secretos) | `~/.config/sops/age/keys.txt` + gestor de contraseñas | RT | 🔴 Crítica | — (generada en Fase 3) | Ver §4.1 (evento, no calendario) | ✅ Custodiada |
| **S02** | `repo2-cipher-pass` — cifrado AES de los backups en R2 | `/etc/pgbackrest/pgbackrest.conf` (5 servers, `640`) + SOPS | RT | 🔴 Crítica | — (nunca rotada, **a propósito**) | **No rotar** — ver §4.2 | ✅ Vigente |
| **S03** | `repo2-s3-key` + `repo2-s3-key-secret` — API token de Cloudflare R2 | `/etc/pgbackrest/pgbackrest.conf` (5 servers) + `infra-secrets/env/pgbackrest/repo2-r2.env` (SOPS) | RT | 🔴 Crítica | **2026-07-19** (reactiva, por exposición — H03) | **Anual** | ✅ Rotada |
| **S04** | Password del rol `mediflowuser` (PostgreSQL) | `.env` de mediflow + PostgreSQL | RT | 🟠 Alta | — | Inmediata → luego anual | ⚠ **DÉBIL — 8 caracteres.** Ver §6 |
| **S05** | Credenciales **AWS** en el `.env` de hub (SDK **nunca importado**) | `.env` de hub (axioma) | RT | 🟠 Alta | — | N/A | ⚠ **REVOCAR** — peso muerto sin función. Ver §6 |
| **S06** | Passwords de los roles `<app>user` de PostgreSQL (resto de las apps) — embebidos en `DATABASE_URL` | `.env` de cada app + PostgreSQL | RT | 🟠 Alta | — (desde aprovisionamiento) | **Anual** | ✅ **Desagregado en §3.2** (2026-08-09): **15 `DATABASE_URL`** en 11 archivos |
| **S07** | Password del rol `postgres` (superusuario) — por servidor | PostgreSQL (5 servers) | RT | 🔴 Crítica | — | **Anual** | ⬜ A verificar (acceso hoy por `peer`/`sudo -u postgres`) |
| **S08** | Secretos de aplicación (`JWT_SECRET`, `SESSION_SECRET`, salts de bcrypt) | `.env` de cada app | RT | 🟠 Alta | — | **Anual** | ✅ **Desagregado en §3.2** (2026-08-09): **8 `JWT_SECRET`** + 1 `SESSION_SECRET`. Rotar invalida sesiones activas — requiere ventana |
| **S09** | Clave SSH de operación / emergencia (`~/.ssh/id_ed25519`) | Equipo de restauración + `authorized_keys` de los 5 servers | RT | 🔴 Crítica | — | **Anual** o ante baja/cambio de equipo | ✅ Vigente — verificación mensual en [G6 §3](./g6-revisiones-periodicas.md) |
| **S10** | Claves SSH de deploy, por app | `~/.ssh/id_ed25519` de cada usuario de app + deploy keys de GitHub | RT | 🟡 Media | — | **Anual** | ✅ **Inventariado 2026-08-09 (§3.4).** axioma: `parseapp`, `miniapp`, `mediflowapp`, `eloreapp`, `axiomacloud` + 3 de root · dev-1: `hubapp`, `pgbackrest`, `parseapp`, `eloreapp`, `miniapp` + 2 de root · axiodemo: `axiomacloud` · clubix: solo root. **Todas `600` y con owner correcto** |
| **S11** | Token de claim de **Netdata Cloud** | Config de Netdata (5 servers) | RT | 🟡 Media | — | Ante cambio de espacio/baja | ✅ Vigente |
| **S12** | Credenciales de **pasarela de pago** — `MERCADOPAGO_ACCESS_TOKEN` + `MERCADOPAGO_PUBLIC_KEY` | `clubix-server.env` (**clubix**) | RT | 🔴 Crítica | — | **Anual** o ante exposición | ✅ Vigente — ⚠ **corregido 2026-08-09:** esta fila decía "MercadoPago en mini". Las credenciales vivas están **solo en clubix**; `mini-backend.env` no tiene ninguna (mini tiene el *código* de la integración, con la tabla `mercadopago_config` **vacía** — ver [hardening §9](../hardening.md)) |
| **S13** | Community SNMP (`public`) — dev-1 | `snmpd.conf` (dev-1) | RT + dattaweb | 🟢 Baja | — | Ante coordinación con dattaweb | ⏸ **Bloqueado** — R03 aceptado, cambiarla corta el monitoreo contratado |
| **S14** | Certificados TLS (Let's Encrypt) | `/etc/letsencrypt` de cada server | RT | 🟡 Media | Renovación automática (certbot) | **90 días (automática)** | ✅ Automatizado |
| **S15** | **Claves de cifrado de datos de aplicación** — `ENCRYPTION_MASTER_KEY` + `SEARCH_HASH_SALT` (mediflow); `ENCRYPTION_KEY` + `SYNC_PASSWORD_KEY` (parse) | `mediflow-backend.env`, `parse-backend.env` (axioma) | RT | 🔴 **Crítica** | — | **Ver §4.3** (no rota por calendario) | ⚠ **Alta 2026-08-09.** Cifran datos **en reposo** de `mediflow_db`, la única base 🔴 del marco. **No estaban inventariadas** |
| **S16** | **Contraseñas de cuentas de sistema operativo** — `axiomacloud` (los 5 servers), y toda cuenta con `sudo` | `/etc/shadow` de cada server + gestor de contraseñas | RT | 🔴 **Crítica** | **2026-08-09 (pendiente)** | **Anual** o ante exposición | 🔴 **EXPUESTA 2026-08-09** — ver §5.1/A6. **No estaban inventariadas**: §3 cubría el rol `postgres` (S07) y las claves SSH (S09) pero **no las contraseñas de cuentas de SO** |
| **S17** | **Claves de API de proveedores de IA** — `ANTHROPIC_API_KEY` (×8), `GEMINI_API_KEY` (×2) | 8 `.env` en axioma y axiodemo | RT | 🟠 Alta | — | **Anual** | ⚠ Nuevas en el inventario. Tienen **presupuesto en USD** configurado (`ANTHROPIC_BUDGET_USD`, `GEMINI_BUDGET_USD` en parse) → una fuga es **gasto directo**, no solo acceso |
| **S19** | 🔴 **`google-credentials.json`** — clave privada de service account de Google (Document AI) | `/var/www/parse/backend/google-credentials.json` (**axioma, única copia**) | RT | 🔴 **Crítica** | — | **Anual** | 🔴 **NO RESPALDADA.** Ni en el repo, ni en `infra-secrets`, ni en `config/axioma/`. El `.env` de parse **la referencia** (`GOOGLE_APPLICATION_CREDENTIALS=…`) y ese `.env` sí está cifrado — pero **apunta a un archivo que no lo está**. Descubierta en el simulacro del 2026-08-12 |
| **S18** | **Credenciales filtradas en los logs de mini** — `whatsappApiKey` de Evolution API, `smtpPass` de Gmail (`info.viverolaslomas@`), 12 contraseñas de 4 usuarios de `nutriarroz` | `~/.pm2/pm2.log` de `miniapp` (axioma) | RT + equipo de mini | 🔴 **Crítica** | — | **Rotación inmediata** (exposición confirmada) | 🔴 **Abierto** — ver [hardening §9](../hardening.md) y A4. **Separado de S12 el 2026-08-09**: lo filtrado en mini **no** son credenciales de pago |

> **Completitud del inventario.** Con el desglose de §3.2 (2026-08-09) quedan cubiertos **S06 y S08**.
> **Sigue abierto S10** (claves SSH de deploy), que `infra-secrets` no custodia. El inventario se declara
> completo cuando cada uno de los **16** `.env` del repo tenga sus secretos enumerados con owner y fecha de
> última rotación — la columna "Última rotación" sigue **casi enteramente vacía**, que es hoy el hallazgo
> de mayor peso de esta política.

### 3.2 Desglose por `.env` del repo de secretos

> Cierra la acción **A3**. Fuente: `infra-secrets/env/` al **2026-08-09** — **16 archivos**, no 15 como
> declaraban esta política, el README del repo y el dossier (corregido). Solo nombres de variable; ningún
> valor descifrado. `DB` = `DATABASE_URL` (password del rol embebido, S06) · `JWT` = `JWT_SECRET` (S08).
>
> **De dónde viene la diferencia.** El registro de la Fase 3
> ([plan de trabajo](../plan-trabajo-estandarizacion.md), 2026-07-05, commit `970e2ee`) dice **15 `.env`**
> con roundtrip 15/15 — y era **correcto en ese momento**. Se agregó un archivo después sin actualizar el
> conteo en ningún documento. Ese registro histórico **no se corrige**: documenta lo ejecutado ese día. Lo
> que faltaba era la cadencia que detectara la deriva, que es justamente **C10** de
> [G6 §1](./g6-revisiones-periodicas.md) (revisión semestral del inventario) — hoy sin ejecuciones.

| # | Archivo (`env/…`) | Secretos que contiene | Criticidad |
|---|---|---|---|
| 1 | `axioma/mediflow-backend.env` | DB · JWT · **`ENCRYPTION_MASTER_KEY`** · **`SEARCH_HASH_SALT`** (S15) · `EMAIL_PASS` · `TWILIO_ACCOUNT_SID`/`AUTH_TOKEN` · `ANTHROPIC_API_KEY` · `AXIO_API_KEY` · `BCRYPT_SALT_ROUNDS` | 🔴 **La más alta** — es la app de la única base 🔴 |
| 2 | `axioma/parse-backend.env` | DB · JWT · **`ENCRYPTION_KEY`** · **`SYNC_PASSWORD_KEY`** (S15) · `GOOGLE_CLIENT_SECRET` + `GOOGLE_APPLICATION_CREDENTIALS` (Document AI) · `GEMINI_API_KEY` · `ANTHROPIC_API_KEY` · `SMTP_PASS` · `PARSE_API_KEY` · `AXIO_API_KEY` | 🔴 Crítica — 45 variables, el `.env` más grande |
| 3 | `axioma/hub-backend.env` | DB · JWT · **`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`** (S05, a revocar) · `REDIS_PASSWORD` · `WHATSAPP_BUSINESS_API_TOKEN` · `TWILIO_ACCOUNT_SID`/`AUTH_TOKEN` · `SMTP_PASS` · `ANTHROPIC_API_KEY` · `PARSE_API_KEY` | 🔴 Crítica |
| 4 | `clubix/clubix-server.env` | DB · JWT · **`MERCADOPAGO_ACCESS_TOKEN`/`PUBLIC_KEY`** (S12) · **`VAPID_PRIVATE_KEY`** (push) · `RECAPTCHA_SECRET_KEY` · `SMTP_PASS` · `ANTHROPIC_API_KEY` · `AXIO_API_KEY` | 🔴 Crítica — **la única app con pagos vivos** |
| 5 | `axioma/axio-db-agent.env` | **5 `DATABASE_URL`**: `CLUBIX_`, `MINI_`, **`ALVERA_`** (= `mediflow_db`), `PARSE_` + la propia · `AGENT_API_KEY` · `HUB_API_KEY` | 🔴 Crítica — **acceso directo a 4 bases productivas**, ver §3.3 |
| 6 | `axioma/mini-backend.env` | DB · JWT · **`SESSION_SECRET`** · `SMTP_PASS` · `AXIO_API_KEY` · `BCRYPT_SALT_ROUNDS` | 🟠 Alta — ⚠ sus secretos están **filtrados a log** (S18) |
| 7 | `axioma/elore.env` | DB · JWT · `SMTP_PASS` · `ANTHROPIC_API_KEY` · `AXIO_API_KEY` · `AXIO_KB_EXPORT_KEY` | 🟠 Alta |
| 8 | `axioma/evolution-api.env` | `DATABASE_CONNECTION_URI` · **`AUTHENTICATION_API_KEY`** | 🟠 Alta — software de **terceros**; su `whatsappApiKey` es lo filtrado en S18 |
| 9 | `axiodemo/axio.env` | DB · JWT · `GEMINI_API_KEY` · `ANTHROPIC_API_KEY` · `PARSE_API_KEY` | 🟠 Alta |
| 10 | `axiodemo/axio-backend.env` | DB · JWT · `ML_SERVICE_API_KEY` · `ANTHROPIC_API_KEY` | 🟠 Alta |
| 11 | `axiodemo/axio-ml.env` | DB · `ML_SERVICE_API_KEY` · `ANTHROPIC_API_KEY` | 🟠 Alta |
| 12 | `axioma/mini-print-agent.env` | **`MINI_AGENT_TOKEN`** | 🟡 Media |
| 13 | `pgbackrest/repo2-r2.env` | `REPO2_S3_KEY`/`_SECRET` (S03) · **`REPO2_CIPHER_PASS`** (S02) | 🔴 Crítica — cubierto por S02/S03 |
| 14 | `axioma/hub-frontend.env` | — (solo URLs públicas) | 🟢 Sin secretos |
| 15 | `axioma/mini-frontend.env` | — (solo `VITE_*` públicas) | 🟢 Sin secretos |
| 16 | `axioma/parse-frontend.env` | — (solo `NEXT_PUBLIC_API_URL`) | 🟢 Sin secretos |

**Totales sobre los 15 `.env` que el repo tenía.** El recuento definitivo, sobre los **36 archivos reales**
y distinguiendo variables **cargadas** de **declaradas vacías**, está en §3.5 — la distinción importa: una
variable vacía no es un secreto, y contarla infla el inventario.

### 3.4 Relevamiento in-situ — el repo cubría el 42% (2026-08-09)

Con acceso restaurado a los servers, el inventario dejó de construirse desde el repo y pasó a construirse
**desde la realidad**. La diferencia es grande:

| Server | `.env` en el server | En `infra-secrets` | Brecha |
|---|---|---|---|
| axioma | 11 | 11 | ✅ — |
| axiodemo | 3 | 3 | ✅ — |
| clubix | **3** | 1 | ❌ faltaban `clubix-client` y el `.env` del **segundo `axio-db-agent`** |
| **dev-1** | **19** | **0** | 🔴 **el server entero nunca estuvo en el repo** |
| **Total** | **36** | **15** | **42% de cobertura** |

**dev-1 nunca se respaldó.** Sus 19 `.env` cubren hub, mini, clubix, parse, mediflow, core, tally, fitness,
checkpoint-web, axio y elore. La discusión "15 vs 16" del §3.2 era la punta del iceberg: el problema real no
era un archivo de más, era **un servidor de menos**.

**El contenido además estaba desactualizado.** El `axio-db-agent.env` cifrado tenía `CLUBIX_DATABASE_URL`;
el vivo tiene `ELORE_DATABASE_URL`. La configuración cambió y el repo quedó congelado — nadie lo notó
porque nadie tenía cadencia para mirarlo (**C10**, sin ejecuciones).

**Estado tras la reconstitución:** los **36 `.env` + las credenciales de pgBackRest** están respaldados y
re-cifrados con el par age nuevo, con roundtrip verificado **37/37 valor por valor**. Ver §7.1.

> **Nota de método.** El desglose de §3.2 se hizo leyendo nombres de variable del repo cifrado; este §3.4 se
> hizo leyendo los servers. **Solo el segundo encontró que faltaba dev-1**, porque un inventario construido
> desde el repo solo puede describir lo que el repo ya contiene. Es el mismo patrón que produjo el hallazgo
> del proveedor en [G8 §4.2](./g8-clasificacion-datos.md): **el documento no puede auditarse a sí mismo.**

### 3.5 Recuento definitivo de secretos de terceros (36 archivos, 2026-08-09)

Sobre los **510 pares `variable=valor`** de los 36 `.env`, distinguiendo **cargadas** de **declaradas
vacías**. La distinción no es cosmética: una variable vacía **no es un secreto que rotar ni que proteger**,
y contarla como tal infla el inventario y desvía el esfuerzo.

| Credencial de tercero | Cargadas | Vacías | Dónde |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | **14** | 1 | axioma (4, incluida **mediflow**), axiodemo (3), dev-1 (7). Vacía en clubix |
| `GEMINI_API_KEY` | **6** | 0 | axioma (parse), axiodemo, dev-1 (4) |
| `TWILIO_AUTH_TOKEN` | **2** | 2 | Solo **hub** (axioma + dev-1). **Vacías en mediflow** — mediflow *no* envía SMS |
| `WHATSAPP_BUSINESS_API_TOKEN` | **2** | 0 | hub (axioma + dev-1) |
| `MERCADOPAGO_ACCESS_TOKEN` | **1** | 0 | **clubix** — confirma la corrección de S12 |

**Dos precisiones que corrigen el conteo preliminar de §3.2** (hecho sobre los 15 archivos del repo):

1. Las claves de Anthropic no son 8 sino **14 cargadas**, porque dev-1 —ausente del repo— suma 7 más.
2. **`mediflow` sí tiene una clave de Anthropic cargada** (108 caracteres). Es el dato que vuelve concreta
   la preocupación de [G8 §4.1](./g8-clasificacion-datos.md): la aplicación de la única base 🔴 del marco
   tiene credencial viva de un proveedor de IA. Sigue sin poder afirmarse *qué* se envía —eso exige leer el
   código— pero el canal está **habilitado**, no solo declarado.

> **Nota de método.** Estas 7 variables vacías aparecieron al verificar, antes de commitear, que todos los
> valores hubieran quedado cifrados: `sops` no cifra un valor vacío, así que saltaron como "sin cifrar".
> No eran una fuga —no hay nada que filtrar en una variable vacía— pero el control de verificación
> encontró de paso un error real de inventario. **Vale la pena dejarlo escrito: el chequeo previo al
> commit es el que debe atrapar esto, no la revisión posterior.**

### 3.6 🔴 El inventario solo miraba dentro de los `.env` (2026-08-12)

El simulacro de recuperación de parse expuso un **hueco de alcance**, no de ejecución: la política de §1
enumeraba tipos de secreto —credenciales de DB, API keys, claves de cifrado, claves SSH— **todos
asumiendo que viven como variables dentro de un `.env`**. Los secretos que viven **en un archivo aparte**
no estaban contemplados.

Resultado concreto: **`google-credentials.json`** (S19). El `.env` de parse está prolijamente cifrado en
`infra-secrets` y **referencia** ese archivo con `GOOGLE_APPLICATION_CREDENTIALS=…`. Un inventario que
recorra los `.env` —como hizo §3.2— **lo da por cubierto**: ve la variable, no ve que apunta afuera.

> **Es el modo de falla más sutil de todo el inventario.** No falta una entrada por olvido: falta porque
> la definición de "secreto" excluía su formato. Se corrigió el alcance en §1.

**Verificación de cobertura (2026-08-12):** se revisaron los 16 `.env` buscando variables que apunten a
archivos de credenciales (`.json`, `.pem`, `.key`, `.p12`, `.crt`). **`GOOGLE_APPLICATION_CREDENTIALS` de
parse es el único caso del parque.** Eso lo hace barato de resolver — y fácil de no notar nunca.

### 3.3 Hallazgos del inventario (2026-08-09)

1. **Son 16 `.env`, no 15.** Lo declaraban mal esta política (§2), el README de `infra-secrets` y el
   dossier. Corregido en los tres.
2. **Las claves de cifrado de datos en reposo no estaban inventariadas** (S15). La
   `ENCRYPTION_MASTER_KEY` de mediflow protege la única base 🔴 del marco; es, después de la clave age,
   el secreto de mayor impacto de la infraestructura — y hasta hoy no tenía owner, frecuencia ni
   procedimiento. Requiere el mismo tratamiento de excepción que S02: ver §4.3.
3. **Las contraseñas de cuentas de SO no estaban inventariadas** (S16). El alcance de §1 nombraba roles
   de PostgreSQL y claves SSH, pero no las contraseñas de las cuentas con `sudo`. El hueco se materializó
   el mismo 2026-08-09 con la exposición de la contraseña de `axiomacloud` (A6).
4. **S12 apuntaba a la app equivocada.** MercadoPago vive en **clubix**, no en mini. Y lo que se filtró en
   los logs de mini **no** son credenciales de pago sino `whatsappApiKey`, `smtpPass` y contraseñas de
   usuarios — separado ahora como **S18**. La confusión venía de que A4 y S12 se escribieron juntos.
5. **`axio-db-agent` concentra acceso a 4 bases productivas** — incluida `mediflow_db` (🔴) vía
   `ALVERA_DATABASE_URL` (`alvera` es el dominio que sirve mediflow). El control declarado son
   `*_BLOCKED_TABLES`/`*_BLOCKED_COLUMNS`: una **allowlist por configuración de aplicación**, no permisos
   de PostgreSQL. Un cambio de config —o un bug— levanta la restricción sin dejar rastro en la base.
   Registrado como riesgo **R14** en [G3](./g3-registro-riesgos.md); ver también
   [G8 §4](./g8-clasificacion-datos.md).
6. **`clubix-server.env` tiene claves duplicadas** (`DEFAULT_TENANT_SUBDOMAIN` y
   `DEFAULT_DISCOUNT_PERCENT`, dos veces cada una). No son secretos y el efecto es "gana la última", pero
   indica que el archivo se editó por concatenación — vale revisarlo al próximo redespliegue.

## 4. Frecuencia de rotación

| Criticidad | Frecuencia base | Criterio |
|---|---|---|
| 🔴 Crítica | **Anual** | Acceso a datos, backups o a todos los secretos |
| 🟠 Alta | **Anual** | Acceso a una app o a una base puntual |
| 🟡 Media | **Anual** o ante cambio | Acceso limitado o reemitible sin impacto |
| 🟢 Baja | Ante cambio o exposición | Impacto acotado |

**Rotación inmediata obligatoria** (fuera de calendario) ante cualquiera de estos eventos:

- Sospecha o confirmación de **exposición** (log, commit, sesión, `.bak`, ticket).
- **Incidente de seguridad** — la erradicación ([G5 §4.3](./g5-respuesta-incidentes.md)) exige rotar
  **todos** los secretos potencialmente alcanzados, no solo el confirmado.
- **Baja o cambio** de una persona con acceso administrativo.
- **Cambio de proveedor** o del equipo de restauración.

### 4.1 Caso especial — clave age (S01)

No se rota por calendario: rotarla implica **re-cifrar los 16 `.env`** del repo de secretos. Se rota ante
**evento**: sospecha de compromiso de la clave, o baja de una persona que la tuvo. El procedimiento es
generar el nuevo par, agregar el nuevo recipient al `.sops.yaml`, re-cifrar todo (`sops updatekeys`),
verificar que descifra, y **recién entonces** retirar el recipient viejo.

### 4.2 Caso especial — `cipher-pass` de pgBackRest (S02)

**NO se rota.** Es la clave que descifra los backups **ya existentes** en R2: perderla o cambiarla haría
**irrecuperable** todo el histórico. Se conservó deliberadamente durante la rotación de H03 (se verificó
por hash que el valor de los `.bak` era idéntico al vivo antes de borrarlos). Cambiarla solo tiene sentido
junto con una **reinicialización completa de las stanzas**, decisión de continuidad que requiere aprobación
de la AN y un plan de retención del histórico viejo.

> **Excepción registrada:** S02 queda exento de la frecuencia anual de §4 por limitación estructural del
> producto. Riesgo residual asociado: **R05** en [G3](./g3-registro-riesgos.md) (aceptado).

### 4.3 Caso especial — claves de cifrado de datos de aplicación (S15)

Mismo patrón estructural que S02, y por la misma razón: **cifran datos que ya existen**. La
`ENCRYPTION_MASTER_KEY` de mediflow protege campos de `mediflow_db` —la única base 🔴 del marco— y el
`SEARCH_HASH_SALT` genera los hashes con los que esos campos se buscan. Cambiar cualquiera de las dos sin
migrar los datos **rompe el acceso a la información ya guardada**; cambiar el salt además invalida todos
los índices de búsqueda. Ídem `ENCRYPTION_KEY` y `SYNC_PASSWORD_KEY` en parse.

- **NO se rotan por calendario.** Rotarlas es una **migración de datos**, no un cambio de configuración:
  exige descifrar con la clave vieja y re-cifrar con la nueva, en ventana y con backup verificado previo.
- Se rotan **ante evento**: sospecha de compromiso de la clave, o incidente que la alcance
  ([G5 §4.3](./g5-respuesta-incidentes.md)).
- ⚠ **A verificar (A7):** dónde vive el respaldo de estas claves. Si la única copia es el `.env` del
  server y su cifrado en `infra-secrets`, entonces **perderlas equivale a perder los datos de salud** —
  el backup de pgBackRest restauraría filas cifradas e ilegibles. Es un escenario de continuidad que el
  [DRP](../disaster-recovery-plan.md) **no contempla**: hoy el DRP asume que restaurar la base restaura
  los datos. Debe cubrirse en el **BCP (G9)**.

> **Excepción registrada:** S15 queda exento de la frecuencia anual de §4. Riesgo asociado: **R15** en
> [G3](./g3-registro-riesgos.md).

## 5. Procedimiento de rotación

Destilado de la rotación **ya ejecutada y validada** en H03 (token de R2, 5 archivos, 4 stanzas):

1. **Identificar el alcance completo.** Cuántos archivos y servers consumen el secreto. En H03 eran **5
   archivos en 5 servers** — rotar en uno solo habría roto los backups de los otros cuatro.
2. **Generar la nueva credencial** en el sistema de origen, **sin borrar la vieja todavía**.
3. **Respaldar** la config a modificar (fuera del árbol servido, `600` root-only).
4. **Aplicar** el nuevo valor en todos los puntos de consumo.
5. **Verificar funcionalmente** — no basta con que el archivo esté escrito. En H03: `pgbackrest check` en
   las 4 stanzas (repo1 + repo2). El criterio de cierre formal es [G10](./g10-verificacion-remediaciones.md);
   incluye el **próximo arranque** cuando el secreto lo lee un proceso al iniciar.
6. **Revocar la credencial vieja** en el sistema de origen (en H03 se borró el token viejo en Cloudflare).
7. **Barrer residuos**: eliminar `.bak`, copias temporales y entradas de log con el valor viejo.
   Verificar con `grep` que quedan **0 ocurrencias** en los 5 servers.
8. **Actualizar** el valor cifrado en `infra-secrets` (SOPS) y el inventario de §3 con la nueva fecha.
9. **Asentar** la rotación en el registro de §5.1.

### 5.1 Registro de rotaciones

| Fecha | Secreto | Motivo | Alcance | Verificación | Ejecutor |
|---|---|---|---|---|---|
| 2026-07-19 | **S03** — API token de Cloudflare R2 | **Reactivo** — exposición en sesión + `.bak` (H03) | 5 archivos en 5 servers | `pgbackrest check` OK en las 4 stanzas (repo1+repo2); token viejo borrado en Cloudflare; **0 `.bak`** con creds viejas | martin4yo |
| _pendiente_ | **S04** — `mediflowuser` | Password débil (8 caracteres) | mediflow (`.env` + rol PG) | — | ⬜ |
| _pendiente_ | **S05** — creds AWS de hub | Revocación (SDK nunca importado) | `.env` de hub | — | ⬜ |
| **2026-08-09** | **S16** — contraseña de la cuenta de SO `axiomacloud` | 🔴 **Reactivo — exposición confirmada**: la contraseña se pegó en claro en una sesión de asistente (transcript + logs locales de la herramienta + scrollback de la terminal). Dispara la rotación inmediata de §4 | Los **5 servers** (cuenta con `sudo`) | ⬜ **Pendiente** — criterio: `sudo` funcional con la nueva en los 5 + `passwd -S axiomacloud` con fecha de cambio actualizada | ⬜ **A ejecutar (A6)** |
| _pendiente_ | **S18** — creds filtradas en logs de mini | Exposición confirmada en `pm2.log` (hardening §9) | `whatsappApiKey` Evolution + `smtpPass` Gmail + 4 usuarios de `nutriarroz` | — | ⬜ **Rotar ANTES de truncar el log** (es la evidencia del alcance) |

## 6. Acciones abiertas identificadas

| # | Acción | Secreto | Origen | Prioridad | Notas |
|---|---|---|---|---|---|
| **A1** | **Rotar** el password de `mediflowuser` a una credencial fuerte | S04 | Anotado al cerrar H01 (2026-07-22) | 🟠 Alta | Mitigado parcialmente: la DB solo es accesible por loopback + `scram-sha-256`. Requiere actualizar el `.env` y **reiniciar la app** → ventana. Riesgo **R06**. |
| **A2** | **Revocar** las credenciales AWS del `.env` de hub | S05 | Colateral de H13 | 🟠 Alta | El SDK está **declarado pero nunca importado**: son exposición sin función. Revocar en AWS y quitar del `.env`. Riesgo **R07** (tratamiento: *Evitar*). |
| **A3** | ~~Completar el inventario — desagregar S06, S08 y S10 por app~~ | S06/S08/S10 | Esta política | 🟠 Alta | ✅ **Cerrada parcialmente 2026-08-09** — §3.2 desagrega los 16 `.env` (cubre S06 y S08) leyendo solo nombres de variable, sin descifrar. **Queda abierto S10**: `infra-secrets` no custodia claves SSH → relevar contra los servers y GitHub. |
| **A4** | **Rotar las credenciales filtradas de mini** (axioma) | **S18** *(era S12 — reasignado 2026-08-09)* | `console.log` que filtran secretos a `~/.pm2/pm2.log` | 🔴 Crítica | **En manos del equipo de la app** (repo de mini, otro puesto): quitar los 3 `console.log`. Hasta que se roten, el bloque de logrotate de mini/axioma sigue **comentado** — no rotar logs que aún reciben secretos frescos sería inútil. |
| **A5** | **Registrar la fecha de última rotación** de los secretos sin dato | Todo el inventario | Esta política | 🟡 Media | Donde no sea recuperable, asentar "desconocida desde aprovisionamiento" y **programar** la primera rotación. Tras §3.2 el hueco está **dimensionado**: la columna sigue vacía en casi todo el inventario. |
| **A6** | **Rotar la contraseña de la cuenta de SO `axiomacloud`** en los 5 servers | **S16** | 🔴 **Exposición confirmada 2026-08-09** (pegada en claro en una sesión de asistente) | 🔴 **Crítica** | Rotación inmediata de §4. Es la cuenta con `sudo` de los 5 servers. **Mitigante:** SSH tiene `PasswordAuthentication no` desde el 2026-07-17 en los 5 ([hardening §200](../hardening.md)), así que la contraseña **no habilita sesión SSH remota** — el vector es `sudo` con sesión ya establecida y la consola física/VNC del proveedor. Verificar además que la misma contraseña **no se reutilice** en el panel del VPS ni en otras cuentas. |
| **A7** | **Determinar dónde se respalda `ENCRYPTION_MASTER_KEY`** y documentar la recuperación | **S15** | Inventario 2026-08-09 | 🔴 **Crítica** | Si su única copia es el `.env` del server + `infra-secrets`, perderla hace **ilegibles los datos de salud restaurados** desde cualquier backup de pgBackRest. El DRP asume hoy que restaurar la base restaura los datos. Cubrir en el **BCP (G9)** y en el próximo restore drill. |
| **A8** | **Inventariar las claves de API de proveedores de IA** con owner y presupuesto | **S17** | Inventario 2026-08-09 | 🟡 Media | 8 `ANTHROPIC_API_KEY` + 2 `GEMINI_API_KEY`. Verificar si son **una misma clave replicada** en 8 `.env` (rotarla implicaría los 8 a la vez) o claves distintas por app. Tienen presupuesto en USD → una fuga es gasto directo. |
| **A9** | 🔴 **Reconstituir el repo de secretos** — extraer los `.env` de los servers, generar par age nuevo, re-cifrar y verificar roundtrip | **S01** | 🔴 **Pérdida efectiva de la clave age (2026-08-09)**, §7.1 | 🔴 **Máxima — bloquea el DRP de aplicación** | Mientras no se ejecute, los servers son la **única copia** de la configuración de 11 apps, el Paso 5 del DRP de app es **inejecutable** y la Fase 7 del estándar también. **Sub-acción prioritaria (A9.1):** respaldar primero `ENCRYPTION_MASTER_KEY`/`SEARCH_HASH_SALT` de mediflow — es lo único irreversible (R15). |

## 7. Continuidad — pérdida de la clave age

La pérdida de **S01** deja los 16 `.env` del repo de secretos **irrecuperables** desde el repo. **No es una
pérdida total**: los valores en claro siguen en los `.env` de cada server, de modo que el camino de
recuperación es regenerar el par age y re-cifrar desde los servers.

### 7.1 🔴 El escenario se materializó — pérdida efectiva de S01 (2026-08-09)

**No es un ejercicio.** La clave privada age **se perdió**: no está en el equipo de trabajo (verificado:
no existe `~/.config/sops/age/keys.txt` ni ningún archivo con material age) ni en el gestor de contraseñas.
La custodia declarada como "✅ Vigente" en §2 **no existía en la práctica** — es el primer control de este
marco que se prueba contra la realidad y **falla**.

**Qué NO se perdió.** Ningún secreto. Los valores en claro siguen en los `.env` de cada server, que es el
origen de verdad. El repo `infra-secrets` está íntegro (16 archivos, `.sops.yaml`, recipient público
`age1rsrkjwl…`): lo que se perdió es la **capacidad de leerlo**.

**Qué sí se perdió — y esto es lo grave.** El repo de secretos es hoy **peso muerto**: 16 archivos que
nadie puede descifrar. Eso deja **a los propios servers como única copia** de la configuración de 11 apps
y 2 componentes. Consecuencias verificadas:

| Procedimiento documentado | Estado real al 2026-08-09 |
|---|---|
| [DRP de app — Paso 5](../drp-app-hub-drill.md) "`.env` desde SOPS" (y su decisión G7: *"la app no levanta sin config"*) | 🔴 **Inejecutable** |
| [Estándar §205](../estandar-despliegue.md) "el redespliegue (Fase 7) descifra el `.env` con SOPS al reinstalar" | 🔴 **Inejecutable** para las 11 apps |
| Restaurar una app tras perder su server | 🔴 Se recupera la **base** (pgBackRest) pero **no la configuración** |

> 🔴 **Combinación crítica con S15.** Si se pierde **axioma** antes de reconstituir el repo, se pierde con
> él la `ENCRYPTION_MASTER_KEY` de mediflow — y entonces restaurar `mediflow_db` desde pgBackRest devuelve
> **filas cifradas ilegibles, de forma permanente**. Es pérdida definitiva de datos de salud contra la cual
> **el backup no protege**, porque el backup nunca fue el problema. Este es el riesgo **R15** dejando de
> ser teórico. La ventana dura hasta que el repo se reconstituya.

**Recuperación — camino B de §7, en ejecución.** Requiere acceso SSH a los servers:

1. **Primero, y por separado: extraer y respaldar `ENCRYPTION_MASTER_KEY` + `SEARCH_HASH_SALT` de
   mediflow** (y las de parse). Es lo único cuya pérdida sería **irreversible**; todo lo demás es
   re-generable.
2. Traer los 16 `.env` en claro desde cada server.
3. Generar un par age nuevo, **custodiarlo en dos lugares antes de seguir** (equipo + gestor), y recién
   entonces actualizar `.sops.yaml` con el recipient nuevo.
4. Re-cifrar los 16 archivos y **verificar el roundtrip completo** en máquina limpia
   (`find env -name '*.env' -exec sops --decrypt {} \; >/dev/null`).
5. Retirar el recipient viejo, que ya no corresponde a ninguna clave existente.

**Lección para el marco.** La custodia se declaraba verificada en §2 sin que existiera evidencia de esa
verificación — exactamente el patrón que [G6](./g6-revisiones-periodicas.md) se creó para evitar y que
H06 ya había mostrado. **La cadencia que lo habría detectado es C10** (revisión semestral del inventario,
sin ejecuciones) y el control concreto que faltaba es un **roundtrip periódico desde el gestor de
contraseñas**, no desde la copia de trabajo: la copia de trabajo descifra aunque el respaldo no exista.
Se incorpora como control obligatorio en §8.

> ⚠ **Matiz agregado el 2026-08-09.** Ese camino de recuperación **asume que los servers siguen en pie**.
> Si el evento que hace perder la clave age es el mismo que hace perder los servers, no hay origen desde
> el cual re-cifrar. Y con **S15** el problema es peor: la `ENCRYPTION_MASTER_KEY` no solo abre un `.env`,
> **descifra los datos** — si se pierde junto con los servers, restaurar `mediflow_db` desde pgBackRest
> devuelve filas cifradas ilegibles. Escenario a cubrir en el **BCP (G9)**; acción **A7**.

- La clave **DEBE** estar custodiada en al menos **dos lugares**: el equipo del RT (`600`) y el gestor de
  contraseñas fuera de banda.
- **DEBERÍA** existir una copia accesible por el **BT** — hoy la clave la custodia únicamente el RT, lo que
  suma al bus factor (**R08**). *Acción:* resolver la custodia compartida en la próxima revisión trimestral.
- Escenario cubierto también en el [BCP — G9](./g9-continuidad-negocio.md).

## 8. Gobierno

- Esta política se **revisa cada trimestre** (próxima **2026-10-23**); el **inventario de §3 se revisa
  semestralmente** (C10 de [G6 §1](./g6-revisiones-periodicas.md)) y se actualiza ante cada alta/baja de app.
- **Estado del gap G7 al 2026-08-09:** 🔴 — **bajado de 🟡 a 🔴 el mismo día**. El inventario quedó
  desagregado (§3.2 cierra A3 salvo S10) y la política está completa, pero **la custodia —lo único que se
  daba por resuelto— resultó no existir**: la clave age se perdió (§7.1). Un repo de secretos que nadie
  puede descifrar no es custodia. Pasa a 🟡 cuando **A9** esté ejecutada y el roundtrip verificado desde
  el respaldo, y a 🟢 cuando además: (a) S10 esté relevado, (b) A1, A2, A6 y A7 estén ejecutadas, y (c) se
  registre **al menos una rotación programada** (no reactiva) en §5.1.
- **Control nuevo obligatorio (deriva de §7.1).** La verificación de custodia **DEBE** hacerse restaurando
  la clave **desde el respaldo fuera de banda** a una máquina limpia y corriendo el roundtrip completo — no
  desde la copia de trabajo. Un roundtrip que corre con la copia de trabajo **prueba que el cifrado
  funciona, no que el respaldo existe**, que es justamente la confusión que produjo esta pérdida. Se suma
  a **C10** en [G6 §1](./g6-revisiones-periodicas.md) con cadencia **semestral**.
- **La clave age DEBE custodiarse en dos lugares independientes** antes de dar por cerrada A9, uno de ellos
  accesible por el **BT** — la custodia única del RT es R08 y acaba de demostrar su costo.
- **Lectura honesta de la pasada del 2026-08-09.** El inventario desagregado no solo *completó* la
  política: **encontró tres clases de secreto que la propia política no cubría** (claves de cifrado de
  datos S15, contraseñas de cuentas de SO S16, claves de proveedores de IA S17) y **corrigió un error**
  de atribución (S12/S18). Es evidencia a favor del control —el inventario funcionó— y en contra del
  estado del gap: un inventario que en su primera pasada seria crece de 14 a 18 entradas **no estaba
  cerca de estar completo**. El 🟡 es generoso, no conservador.
- **La exposición de S16 el mismo día que se inventarió** es el caso testigo de por qué esta política
  existe: un secreto sin inventariar no tiene owner, ni frecuencia, ni procedimiento — y por eso nada lo
  atajó. Registrado en §5.1 y como acción **A6**.
- Riesgos asociados: **R05** (creds R2 en claro, aceptado), **R06** (password débil de `mediflowuser`),
  **R07** (creds AWS sin uso), **R08** (custodia única de la clave age), **R14** (acceso del db-agent a
  4 bases productivas) y **R15** (claves de cifrado de datos sin respaldo verificado) en
  [G3](./g3-registro-riesgos.md).
