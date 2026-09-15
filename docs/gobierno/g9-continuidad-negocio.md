# G9 — Plan de Continuidad de Negocio (BCP)

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G9** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md).
>
> **Estado:** v1 — redacción inicial (2026-08-11).
>
> **Hallazgo que motiva este documento.** El [DRP](../disaster-recovery-plan.md) cubre la **recuperación
> técnica** de bases y aplicaciones: qué comando correr para volver a levantar un servidor. Lo que no
> existía es el plan de **continuidad operativa**: qué pasa cuando el problema no es un servidor caído
> sino que se perdió la clave que descifra los secretos, que el proveedor suspende la cuenta, o que la
> única persona que sabe operar la infraestructura no está disponible.
>
> **La diferencia no es teórica.** El 2026-08-09, reconstruir el entorno de trabajo en un equipo nuevo
> reveló que **no había ni clave SSH, ni inventario, ni clave age**. Los servidores estaban perfectos y
> los backups también: lo que faltaba era **la capacidad de llegar a ellos**. El DRP no cubre ese
> escenario porque no es un desastre de datos — y sin embargo dejaba la infraestructura tan inoperable
> como si lo fuera.
>
> **Principio.** *El DRP responde «cómo lo recupero». Este documento responde «con qué, desde dónde y
> quién», que son las preguntas que se vuelven difíciles justo cuando hacen falta.*
>
> **Lenguaje normativo:** **DEBE** = obligatorio · **DEBERÍA** = recomendado salvo justificación
> registrada · **PUEDE** = opcional.

## 1. Alcance y relación con el DRP

| | [DRP](../disaster-recovery-plan.md) | **Este documento (BCP)** |
|---|---|---|
| Pregunta | ¿Cómo recupero los datos y las apps? | ¿Con qué recursos, desde dónde y con quién opero? |
| Disparador | Pérdida o corrupción de datos, caída de un host | Pérdida de **acceso**, de **claves**, de **proveedor** o de **personas** |
| Cubre | 4 escenarios de desastre (RD-A…D), RPO/RTO, restore drills | Habilitantes de la operación, terceros, sucesión |
| Estado | Formal y probado (drills registrados) | v1 — este documento |

El BCP **no reemplaza** al DRP: lo precede. Todo runbook del DRP asume implícitamente que existen un
operador con acceso, un inventario y unas claves. **Este documento hace explícitos esos supuestos** y los
convierte en algo verificable.

## 2. El kit de continuidad

Lo mínimo indispensable para que **una persona autorizada, desde un equipo limpio**, pueda operar la
infraestructura. Este inventario es la contribución central del documento: se construyó reproduciendo el
escenario real del 2026-08-09.

| # | Elemento | Dónde vive hoy | Estado |
|---|---|---|---|
| **K1** | **Clave SSH** de operación con acceso a los 5 servidores | Equipo del RT + `authorized_keys` de los servers | 🟡 Regenerada el 08-09. **Solo el RT** |
| **K2** | **Inventario** — IPs, puertos SSH, usuarios, roles | `inventory.sh` (gitignoreado) + **procedencia documentada en él** | 🟢 Reconstruido el 08-09 desde DNS + documentación del repo. **Se probó que es reconstruible sin acceso previo** |
| **K3** | **Clave age** — descifra los 37 `.env` de `infra-secrets` | Equipo del RT + LastPass | 🟡 Rotada el 08-09 (la anterior **se perdió**). ✅ **Probada en el simulacro del 08-12**: descifró los `.env` de hub y alvera. Falta copia del BT |
| **K4** | **Claves de cifrado de datos de aplicación** (`ENCRYPTION_MASTER_KEY`, `SEARCH_HASH_SALT` de mediflow; `ENCRYPTION_KEY`, `SYNC_PASSWORD_KEY` de parse) | `.env` de cada app + `infra-secrets` | 🔴 **Ver §4.2 — sin ellas el backup es ilegible** |
| **K5** | **Credenciales de pgBackRest / R2** (`repo2-s3-key`, `cipher-pass`) | `/etc/pgbackrest/*.conf` + `infra-secrets` | ✅ Respaldadas |
| **K6** | **Acceso al panel del proveedor VPS** (consola, reinicio, reinstalación) | Cuenta del RT | 🔴 **No inventariado ni compartido** |
| **K7** | **Acceso a GitHub** (código de las apps + `infra-secrets`) | Cuenta del RT + llave SSH dedicada | 🟡 Solo el RT |
| **K8** | **Acceso a Cloudflare** (R2 y DNS de los dominios) | Cuenta del RT | 🔴 **No inventariado.** Sin DNS no hay servicio, aunque los servers estén vivos |
| **K9** | **Acceso a Netdata Cloud** | Cuenta del RT + `secrets.sh` | ✅ Token de claim respaldado |
| **K10** | **Este repositorio de documentación** | GitHub (público) | ✅ |
| **K11** | 🔴 **Configuración de despliegue** — vhosts de nginx, `ecosystem.config.js`, unidades systemd, `.env.production` de los frontends | **[`config/axioma/`](../../config/axioma/)** *(versionado el 2026-08-12)* | 🟡 **Hueco cerrado, pero es una FOTO.** Vivía solo en axioma. Mantenerla al día es parte de C6 |

> 🔴 **El hallazgo más importante de esta sección.** De los **once** elementos, **siete dependen
> exclusivamente del RT** y cuatro (**K6, K8, K11** y parcialmente **K3**) **no estaban inventariados en
> ningún lado antes de este documento** — K11 apareció recién al ejecutar el simulacro del 08-12. K8 es especialmente grave y contraintuitivo: si se pierde el acceso a Cloudflare, los
> servidores siguen funcionando perfectamente y **el servicio igual queda caído**, porque nadie puede
> apuntar los dominios. No hay backup que resuelva eso.

### 2.1 Reglas del kit

- Cada elemento del kit **DEBE** existir en **dos lugares independientes**, uno de ellos accesible por el
  **BT** ([G2](./g2-roles-responsabilidades.md)).
- «Independiente» significa **que no compartan modo de falla**: la copia de trabajo y el llavero del
  sistema operativo del mismo equipo **no cuentan como dos** — es el error que produjo la pérdida de K3.
- El kit **DEBE** revisarse **semestralmente** contra un equipo limpio (ver §6). Verificarlo desde el
  equipo habitual no prueba nada: ese equipo ya tiene todo.

## 3. Dependencias de terceros

Cierra el riesgo **R12** de [G3](./g3-registro-riesgos.md), que estaba *aceptado hasta que existiera este
documento*.

| Proveedor | Qué provee | Si desaparece | SLA | Plan |
|---|---|---|---|---|
| **VPS — donweb/dattaweb** | axioma, clubix, dev-1 *(y probablemente no axiodemo)* | 🔴 Caída de producción | ⚠ **Sin acuerdo formal** | §3.1 |
| **VPS — baehost** *(axioma-drp)* | El **servidor de recuperación**. 🔴 **Filtra 80/443 entrantes** (verificado 08-12) | 🔴 **El DR no puede completarse** | ⚠ Sin acuerdo | **R21** — solicitar la habilitación **a baehost**. Es una dependencia que **no se puede respaldar ni mitigar desde el servidor** |
| **Cloudflare R2** | Backups off-site (repo2) | 🟡 Queda repo1 en dev-1 | ⚠ Sin acuerdo | Dual-repo ya mitiga |
| **Cloudflare DNS** | Resolución de todos los dominios | 🔴 **Servicio caído con servers sanos** | ⚠ Sin acuerdo | §3.2 |
| **GitHub** | Código + secretos cifrados | 🟡 Código vive también en los servers | Términos estándar | Aceptable |
| **Netdata Cloud** | Monitoreo y alarmas | 🟢 Degradación de visibilidad | Plan gratuito | Aceptable |
| **Proveedores de IA** (Anthropic, Gemini) | Funciones de 14 apps | 🟡 Degradación funcional | Términos de API | Evaluar por app |
| **MercadoPago** | Cobros de clubix | 🔴 Sin cobros | Términos estándar | Del negocio, no de infra |
| **Twilio / WhatsApp Business** | Notificaciones de hub | 🟢 Degradación | Términos estándar | Aceptable |

### 3.0 ✅ La infraestructura NO está en un solo proveedor — y eso es una fortaleza

**Corregido el 2026-08-12.** Este documento asumía un único proveedor de VPS. No es así:

| Servidor | Proveedor | Evidencia |
|---|---|---|
| axioma, clubix, dev-1 | **donweb / dattaweb** | 43–44 llaves `@donweb.com` en `/root/.ssh/authorized_keys` de cada uno |
| **axioma-drp** | **baehost** | **0 llaves de donweb**; confirmado por el responsable |
| axiodemo | *(a confirmar)* | 0 llaves de donweb; IP en el mismo rango que drp |

> **Es una propiedad de resiliencia que nadie había registrado**: el servidor de recuperación está en un
> proveedor **distinto** del de producción. Una caída, un bloqueo administrativo o una disputa comercial
> con donweb **no se lleva a axioma-drp**, y los backups de repo2 están en un tercero más (Cloudflare R2).
> El escenario **BC-E** —pérdida de acceso al proveedor— está mucho mejor cubierto de lo que este documento
> suponía.
>
> **La contracara:** son **dos relaciones contractuales** que gestionar, no una. R21 se le pide a
> **baehost**; el contrato de tratamiento de datos (§3.1) se le pide a **donweb**, que es quien tiene
> acceso a dev-1. Confundirlos hace perder tiempo pidiéndole a cada uno lo que le corresponde al otro.

### 3.1 El proveedor de hosting es también **encargado de tratamiento**

*(Aplica a **donweb/dattaweb**, proveedor de dev-1 — no a baehost.)* No es solo un riesgo de disponibilidad. Como se verificó el 2026-08-09
([G8 §4.2](./g8-clasificacion-datos.md)), el proveedor tiene **acceso administrativo efectivo a dev-1**,
que aloja 16 copias de bases productivas incluida `mediflow_db`. Eso lo convierte, bajo la
**Ley 25.326**, en **encargado de tratamiento de datos de salud**.

- **DEBE** formalizarse un contrato que cubra finalidad, confidencialidad, medidas de seguridad,
  subencargados, **registro de accesos** y **destino de los datos al terminar la relación**.
- La cláusula de **salida** es la parte propiamente de continuidad: hoy **no está definido** qué pasa con
  los datos alojados si la relación termina, ni en cuánto tiempo se pueden migrar los 5 servidores.
- Riesgos asociados: **R20** (acceso), **R12** (sin SLA).

### 3.2 DNS — el punto ciego

Ningún documento del marco cubría el DNS hasta ahora, y es el único tercero cuya pérdida deja el servicio
caído **sin que nada esté roto**.

- **DEBE** inventariarse quién tiene acceso a la cuenta de Cloudflare y bajo qué credenciales (**K8**).
- **DEBERÍA** exportarse periódicamente la **configuración de zona** de todos los dominios, para poder
  reconstruirla en otro proveedor sin depender de la memoria de nadie.

## 4. Escenarios de continuidad

Complementan los cuatro escenarios de desastre del DRP (RD-A…D). **Ninguno de estos está cubierto allí.**

### 4.1 BC-A — Pérdida del entorno de trabajo del operador · 🔴 **MATERIALIZADO 2026-08-09**

Se pierde el equipo desde el que se opera (robo, falla, o simplemente uno nuevo).

**Ocurrió.** Al reconstruir el entorno faltaban K1, K2 y K3 simultáneamente. Recuperación real:

- **K2 (inventario)** se reconstruyó **desde el propio repositorio**: DNS de los dominios documentados,
  la IP de dev-1 en el `from=` de `pgbackrest-setup.md`, y los puertos SSH de `hardening.md:197`.
  *Lección: la documentación pública sirvió de respaldo del inventario privado.*
- **K1 (SSH)** se regeneró y se instaló desde un equipo que aún tenía acceso.
- **K3 (clave age)** **no se pudo recuperar**: no existía respaldo. Hubo que **regenerar el par y
  re-cifrar los 37 `.env` desde los servidores** (ver §4.2 y [G7 §7.1](./g7-rotacion-secretos.md)).

**RTO observado:** ~4 horas, con los servidores sanos todo el tiempo.
**Mitigación:** §2.1 (kit en dos lugares) + §6 (prueba semestral desde equipo limpio).

### 4.1.1 ✅ BC-A probado end-to-end — simulacro del 2026-08-12

**El escenario dejó de ser hipótesis.** Se recuperaron **hub y alvera** en axioma-drp partiendo de cero:
stack base instalado, base restaurada desde R2, código desde los repos, configuración desde
`infra-secrets`, y **login funcional en el navegador**. Ambas apps conviviendo en 907 MB de 3911.

**Lo que el simulacro confirmó del kit:**

| | Resultado |
|---|---|
| **K2** (inventario) | ✅ Reconstruible desde el propio repo — DNS de los dominios + `from=` de `pgbackrest-setup.md` + puertos de `hardening.md` |
| **K3** (clave age) | ✅ Restaurada y **probada**: descifró los `.env` de ambas apps |
| **K7** (GitHub) | ✅ El código salió de los repos, no de axioma |
| **K11** (config de despliegue) | 🔴 **Faltaba por completo** — se creó a raíz de este ejercicio |

> 🔴 **Y descubrió el bloqueante que ningún inventario mostraba: R21.** El proveedor **filtra 80/443
> hacia drp**. El kit puede estar completo, el runbook ejecutado y las apps corriendo —y el servicio sigue
> caído—. **Ningún elemento del kit lo cubría**, porque no es un recurso que se pueda respaldar: es un
> permiso de red del proveedor. Se incorpora como dependencia crítica en §3.

### 4.2 BC-B — Pérdida de las claves de cifrado de datos · 🔴 **El hueco más caro**

**El DRP asume que restaurar la base restaura los datos. Para `mediflow_db` eso es falso.**

La aplicación cifra campos en reposo con `ENCRYPTION_MASTER_KEY` y genera sus índices de búsqueda con
`SEARCH_HASH_SALT` (**K4**). Un restore de pgBackRest devuelve las filas **cifradas**: sin esas claves,
los datos de salud son **permanentemente ilegibles**, y ningún backup lo resuelve porque el backup nunca
fue el problema.

- Estas claves **DEBEN** tratarse como parte del backup, no como configuración de la aplicación.
- **DEBEN** respaldarse junto con —y por separado de— los backups de base.
- El **restore drill** ([G6 §2](./g6-revisiones-periodicas.md)) **DEBE** incluir, para mediflow, una
  verificación de que un campo cifrado **se lee legible** tras el restore. Hoy el drill valida que la base
  levanta y replica WAL; **no valida que los datos sean legibles**.
- Riesgo asociado: **R15**. Acción **A7** de G7.

> *Estado: las claves quedaron respaldadas el 2026-08-09. Lo que sigue pendiente es incorporarlas al
> procedimiento de drill, que es lo que evita volver a descubrirlo tarde.*

### 4.3 BC-C — Pérdida de la clave age · 🔴 **MATERIALIZADO 2026-08-09**

Documentado en detalle en [G7 §7.1](./g7-rotacion-secretos.md). Resumen para continuidad:

- **No se perdió ningún secreto** — los valores viven en los `.env` de cada servidor.
- Se perdió la **capacidad de leer el repo**, lo que dejó **inejecutables** el Paso 5 del
  [DRP de aplicación](../drp-app-hub-drill.md) y la Fase 7 del [estándar](../estandar-despliegue.md).
- **La recuperación dependió de que los servidores siguieran en pie.** Si el mismo evento hubiera
  destruido los servidores, la pérdida habría sido total: no había origen desde el cual re-cifrar.
- **Regla derivada:** la clave age **NO DEBE** compartir modo de falla con los servidores. Custodia en
  LastPass + copia cifrada con `age -p` fuera de línea + copia del BT.

### 4.4 BC-D — Indisponibilidad del responsable técnico

El RT concentra la ejecución técnica de casi todos los dominios (**R08**, 🔴 Alto desde G2).

- El BT (Rodrigo Naranjo) tiene **acceso SSH provisto** a los 5 servidores, pero **no tiene** K3 (clave
  age), K6 (panel del proveedor) ni K8 (Cloudflare). Con lo que tiene hoy **puede operar los servidores
  pero no puede desplegar una aplicación desde cero** ni recuperar el DNS.
- **DEBE** completarse el acceso del BT a K3, K6 y K8 para que el bus factor 2 sea real y no declarativo.
- **DEBERÍA** registrarse una **co-ejecución** en el próximo drill o incidente — es lo que convierte el
  bus factor de declarado en probado.

### 4.5 BC-E — Pérdida de acceso al proveedor o suspensión de cuenta

Cuenta suspendida, disputa comercial, o baja del proveedor.

- Los servidores pueden estar sanos y aun así ser **inalcanzables**.
- **Mitigante actual:** los backups de repo2 están en **Cloudflare R2**, un proveedor distinto → los datos
  sobreviven a la pérdida del hosting. Es el control más fuerte que tiene la infraestructura hoy.
- **Pendiente:** no está medido cuánto tarda un aprovisionamiento desde cero en otro proveedor. El drill
  de aplicación (hub → axioma-drp) es la aproximación más cercana y **sigue sin ejecutarse**.

## 5. Objetivos de continuidad

Distintos de los RPO/RTO técnicos del DRP, que siguen vigentes (**RPO 4 h · RTO 15–90 min**).

| Escenario | Objetivo | Estado real |
|---|---|---|
| BC-A — entorno de trabajo | **4 h** para operar desde un equipo limpio | 🟡 ~4 h observado, con recuperación parcial (K3 se perdió) |
| BC-B — claves de cifrado | **0** — no debe ocurrir | 🟡 Respaldadas; falta validarlo en el drill |
| BC-C — clave age | **2 h** para restaurar desde respaldo | 🔴 No probado desde el respaldo |
| BC-D — indisponibilidad del RT | **24 h** para que el BT opere de forma autónoma | 🔴 **No alcanzable hoy**: le faltan K3, K6 y K8 |
| BC-E — cambio de proveedor | **A definir** | 🔴 Sin medir |

## 6. Prueba de continuidad — la cadencia que faltaba

Un plan de continuidad no probado es una hipótesis. Se incorpora a [G6](./g6-revisiones-periodicas.md)
como **C12**, cadencia **semestral**:

1. Desde un **equipo limpio** (o un usuario nuevo sin acceso previo), restaurar el kit de §2 **usando solo
   los respaldos declarados** — nunca la copia de trabajo (regla **R6** de
   [G10](./g10-verificacion-remediaciones.md)).
2. Verificar acceso SSH a los 5 servidores.
3. Descifrar un `.env` de `infra-secrets` con la clave age restaurada.
4. Verificar que un campo cifrado de mediflow **se lee legible** tras un restore de prueba (BC-B).
5. **Que la ejecute el BT**, no el RT — es la única forma de probar BC-D de verdad.
6. Asentar el resultado y el tiempo real en G6.

> El ejercicio del 2026-08-09 fue una **prueba no planificada de BC-A**, y encontró tres huecos en pocas
> horas. Una prueba planificada cada seis meses cuesta una mañana; descubrirlo en un incidente cuesta el
> incidente.

## 7. Acciones abiertas

| # | Acción | Prioridad | Responsable |
|---|---|---|---|
| **A1** | Completar la **custodia de K3** (clave age): copia del **BT** + copia cifrada fuera de línea | 🔴 Crítica | RT |
| **A2** | Inventariar y compartir **K6** (panel del proveedor) y **K8** (Cloudflare) | 🔴 Crítica | RT |
| **A3** | Incorporar la verificación de **legibilidad de datos cifrados** (BC-B) al restore drill | 🔴 Crítica | RT |
| **A4** | **Contrato de tratamiento** con el proveedor de hosting, con cláusula de salida (§3.1) | 🔴 Crítica | RT → **AN** + legal |
| **A5** | Exportar y versionar la **configuración de zona DNS** de todos los dominios | 🟠 Alta | RT |
| **A6** | Registrar la primera **co-ejecución del BT** (cierra R08 y prueba BC-D) | 🟠 Alta | RT + BT |
| **A7** | Ejecutar el **drill de aplicación** pendiente, para medir BC-E | 🟡 Media | RT |
| **A8** | Definir el objetivo de continuidad de **BC-E** una vez medido | 🟡 Media | RT + AN |

## 8. Gobierno

- Este documento se **revisa cada trimestre** (próxima **2026-10-23**) dentro de **C6**, y la prueba de
  continuidad (**C12**) corre **semestralmente**.
- **Estado del gap G9 al 2026-08-12:** 🟡 — el plan está redactado, el kit inventariado (11 elementos) y
  **BC-A probado end-to-end**: se recuperaron hub y alvera en drp hasta login funcional. Tres escenarios
  (BC-A, BC-C y parte de BC-E) están **documentados desde su ocurrencia real**, no desde la hipótesis.
  ⚠️ El simulacro descubrió además **R21**, una dependencia de red del proveedor que **ningún elemento del
  kit puede cubrir** porque no es un recurso respaldable. Pasa a 🟢 cuando: (a) A1, A2 y A3 estén ejecutadas, (b) se haya corrido **una prueba C12
  completa ejecutada por el BT**, y (c) el contrato con el proveedor (A4) tenga resolución de la AN.
- **Lo que este documento no puede resolver solo.** Tres de sus acciones críticas (A2, A4 y el fondo de
  BC-D) no son técnicas: dependen de **compartir accesos** y de una **decisión contractual**. Un BCP
  redactado por una sola persona que además es la única con todas las llaves describe, en el mejor de los
  casos, un plan que solo esa persona puede ejecutar — que es exactamente el riesgo que pretende mitigar.
- Riesgos asociados: **R08** (bus factor), **R12** (terceros sin SLA), **R15** (claves de cifrado),
  **R17** (repo de secretos), **R20** (acceso del proveedor) en [G3](./g3-registro-riesgos.md).
