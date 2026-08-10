# G8 — Clasificación de Datos y Cumplimiento

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G8** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
> Alineada con **CIS Control 3** (Protección de datos).
>
> **Estado:** v1 — redacción inicial (2026-08-06).
>
> **Hallazgo que motiva este documento.** La [política de seguridad G1 §5](./g1-politica-seguridad.md)
> declara que la infraestructura procesa datos personales, de salud y financieros bajo la **Ley 25.326**,
> pero **no existía la clasificación por base de datos**: qué contiene cada una, qué nivel de protección
> le corresponde y qué obligaciones regulatorias dispara. Sin esa clasificación no se puede decidir
> proporcionalmente dónde reforzar controles, ni responder ante un incidente si corresponde **notificar**.
>
> ⚠️ **Alcance de esta versión.** La clasificación de §3 se construyó desde el **inventario técnico**
> (nombre de base, dominio funcional de la app, [DRP Apéndice A](../disaster-recovery-plan.md)) — **no**
> desde una inspección del esquema ni del contenido de las tablas. Las filas marcadas **(a confirmar)**
> requieren validación funcional con el responsable de cada aplicación antes de tratarse como definitivas.
> Ver §7.

## 1. Niveles de clasificación

| Nivel | Definición | Ejemplos | Requisitos mínimos |
|---|---|---|---|
| 🔴 **Sensible** | Datos sensibles en el sentido del **art. 7 de la Ley 25.326** (salud, origen racial/étnico, opiniones políticas, convicciones religiosas, vida sexual) | Historias clínicas, datos de pacientes | Cifrado en tránsito y en reposo · acceso estrictamente mínimo · retención acotada · notificación evaluada ante incidente · **no se replican a entornos de prueba con datos reales** |
| 🟠 **Confidencial** | Datos personales (PII) no sensibles y datos financieros/comerciales | Nombres, DNI, emails, teléfonos, domicilios, datos de facturación, transacciones | Cifrado en tránsito y en reposo · acceso por rol dedicado · backup cifrado · registro de acceso |
| 🟡 **Interno** | Datos operativos sin PII cuya divulgación afectaría la operación | Configuración, metadatos, logs operativos, catálogos | Acceso restringido a la operación · sin exposición pública |
| 🟢 **Público** | Información destinada a publicación | Contenido público de sitios | Sin requisitos de confidencialidad; sí de **integridad** |

> **Regla de agregación.** Una base se clasifica por **su dato más sensible**: una base con un solo campo
> de salud es 🔴, aunque el 99% de su contenido sea 🟡.

## 2. Marco regulatorio aplicable

### 2.1 Ley 25.326 — Protección de Datos Personales (Argentina)

Norma principal aplicable. Puntos que impactan directamente a esta infraestructura:

| Obligación | Artículo | Estado en la infraestructura |
|---|---|---|
| **Datos sensibles** (incl. salud) con protección reforzada | art. 7 | ⚠ Aplica a las bases 🔴 — ver §3 y §5 |
| **Medidas técnicas y organizativas** de seguridad y confidencialidad | art. 9 | ✅ Controles vigentes: TLS, cifrado de backups, mínimo privilegio, firewall, `scram-sha-256` |
| **Deber de confidencialidad** de quienes tratan los datos | art. 10 | ✅ Alcanza al RT y BT ([G2](./g2-roles-responsabilidades.md)) |
| **Cesión de datos** a terceros con consentimiento/base legal | art. 11 | ⚠ **A verificar** — ver §4 (proveedores) |
| **Transferencia internacional** a países sin protección adecuada | art. 12 | ⚠ **A evaluar** — los backups se replican a **Cloudflare R2** (off-site, posiblemente fuera del país). Ver §4 |
| **Registro de bases de datos** ante la autoridad de aplicación (AAIP) | art. 21 | ⚠ **A verificar** si corresponde inscripción — ver §6 |
| **Derechos del titular** (acceso, rectificación, supresión) | arts. 14–16 | ⚠ Sin procedimiento formal documentado — ver §6 |

> **Nota.** El régimen argentino **no impone hoy** un deber general de notificación de brechas equivalente
> al del GDPR. Aun así, [G5 §5](./g5-respuesta-incidentes.md) exige **evaluar con la AN** la notificación
> ante todo incidente que involucre datos 🔴 o 🟠 — criterio conservador adoptado deliberadamente.

### 2.2 Otros marcos

- **Normativa de salud** (secreto médico / historia clínica, Ley 26.529): aplicable si alguna base contiene
  datos clínicos de pacientes identificables. ⚠ **A confirmar** — depende de la validación de §3.
- **GDPR / normativa extranjera:** aplicaría solo si se tratan datos de titulares en la UE. ⚠ **A
  confirmar** con la AN si hay clientes o usuarios fuera de Argentina.
- **PCI-DSS:** **no aplica** mientras los datos de tarjeta se procesen íntegramente en la pasarela de pago
  (MercadoPago) y **no se almacenen** en las bases propias. ⚠ Confirmar que ninguna base guarda PAN o CVV.

## 3. Clasificación por base de datos

> Fuente del inventario: [DRP Apéndice A](../disaster-recovery-plan.md) (tomado 2026-07-04).
> **La columna "Contenido" es inferida del dominio funcional de la app**, salvo donde se indica.

### 3.1 Stanza `AxiomaCloudProd` — servidor **axioma** (producción)

| Base | Contenido (inferido) | Clasificación | Justificación |
|---|---|---|---|
| `mediflow_db` | Gestión médica — pacientes, prestaciones | 🔴 **Sensible** **(a confirmar)** | Datos de salud → art. 7. **Máxima prioridad de validación** |
| `mini_db` | App de gestión con facturación | 🟠 Confidencial | PII de clientes + datos de transacciones. ⚠ **Corregido 2026-08-09:** decía "y pagos (MercadoPago)". La integración de pago existe en el código pero **no está configurada** — `mercadopago_config` está **vacía** y `mini-backend.env` no tiene credenciales de la pasarela ([hardening §9](../hardening.md), [G7 §3.2](./g7-rotacion-secretos.md)). Quien procesa pagos es **clubix** |
| `chequescloud` | Gestión de cheques | 🟠 Confidencial | Datos financieros e identificatorios |
| `core_db` | Núcleo transversal — usuarios/cuentas | 🟠 Confidencial **(a confirmar)** | Probable PII de usuarios del ecosistema |
| `hub_db` | Portal de proveedores (facturas) | 🟠 Confidencial | Datos comerciales y de facturación de terceros |
| `elore_db` | Aplicación de negocio | 🟠 Confidencial **(a confirmar)** | Clasificación conservadora hasta validar |
| `checkpoint_db` | Control de accesos/presencia | 🟠 Confidencial **(a confirmar)** | Probable PII (identificación de personas) |
| `axiomadocs` | Gestión documental | 🟠 Confidencial **(a confirmar)** | Depende del contenido de los documentos; podría escalar a 🔴 |
| `parse_db` | Backend de aplicaciones (Parse) | 🟠 Confidencial **(a confirmar)** | Almacén genérico; clasificar por las apps que lo usan |
| `evolution` | evolution-api (mensajería WhatsApp) | 🟠 Confidencial | Contenido de conversaciones y números de contacto |
| `iasqlassistant_db` | Asistente SQL | 🟡 Interno **(a confirmar)** | Sin PII esperada; escala si guarda consultas con datos reales |

### 3.2 Stanza `clubix` — servidor **clubix** (producción)

| Base | Contenido (inferido) | Clasificación | Justificación |
|---|---|---|---|
| `clubix_db` | Gestión de club/socios (`clubix.com.ar`) **con pagos vía MercadoPago** | 🟠 Confidencial **(a confirmar)** | PII de socios + **datos de transacciones de pago** (confirmado 2026-08-09: `MERCADOPAGO_ACCESS_TOKEN` vive en `clubix-server.env`, [G7 §3.2](./g7-rotacion-secretos.md)). ⚠ **Escala a 🔴** si registra aptos médicos o datos de salud deportiva. Aplica la verificación de §2.2 sobre datos de tarjeta |

### 3.3 Stanza `axiodemo` — servidor **axiodemo**

| Base | Contenido (inferido) | Clasificación | Justificación |
|---|---|---|---|
| `axio_db` | Entorno demo de axio | 🟡 Interno **(a confirmar)** | ⚠ **Escala a 🟠/🔴 si contiene datos productivos reales** — ver §5.2 |
| `axio_ml` | Modelos / datos de ML | 🟡 Interno **(a confirmar)** | Escala según el dataset de entrenamiento |

### 3.4 Stanza `dev-1` — servidor **dev-1** (repo host + desarrollo)

**16 bases** (`clubix_db`, `mini_db`, `rojoplus_db`, `parse_db`, `mediflow_db`, `axioma_erp`, `hub_db`,
`elore_db`, `axioma_metadata`, `checkpoint_db`, `axiomaweb_db`, `tally_db`, `core_db`, `axiomadb`,
`fitness_db`, `axio_db`).

> ⚠️ **Hallazgo de clasificación — el más relevante de este documento.** dev-1 es un servidor de
> **desarrollo** que aloja **copias homónimas de bases productivas** (`mini_db` 89 MB, `clubix_db` 171 MB,
> `mediflow_db` 20 MB, `checkpoint_db`, `hub_db`, `core_db`…). Si esas copias contienen **datos reales**,
> entonces dev-1 hereda la clasificación de producción — incluido el 🔴 de `mediflow_db` — y un entorno de
> desarrollo estaría tratando datos sensibles bajo controles pensados para desarrollo.
>
> **Clasificación provisional: 🟠 Confidencial como piso**, con `mediflow_db` en 🔴 **(a confirmar)**.
> Adicionalmente `fitness_db` podría contener datos de salud deportiva. **Acción A2 en §7.**

> `axioma_metadata` y `axiomadb` se clasifican **🟡 Interno** (metadatos/configuración) **(a confirmar)**.

### 3.5 Resumen

| Clasificación | Bases | Servidores involucrados |
|---|---|---|
| 🔴 Sensible | 1 confirmada por dominio (`mediflow_db`) × 2 instancias (axioma, dev-1) | axioma, dev-1 |
| 🟠 Confidencial | La mayoría de las bases de negocio | axioma, clubix, dev-1 |
| 🟡 Interno | Metadatos, demo, ML | axiodemo, dev-1 |
| 🟢 Público | — | — |

## 4. Terceros y transferencia de datos

| Tercero | Datos que recibe/aloja | Clasificación de esos datos | Situación |
|---|---|---|---|
| **Cloudflare R2** | **Backups completos cifrados** de las 4 stanzas | Hasta 🔴 | ⚠ **Transferencia internacional (art. 12)** — a evaluar. **Mitigante fuerte:** los backups están **cifrados AES** (`cipher-pass`) y Cloudflare **no tiene la clave**, por lo que recibe cifrado opaco, no datos personales legibles. Documentar este argumento formalmente. |
| **Proveedor VPS** | Alojamiento de los servidores (datos en reposo) | Hasta 🔴 | ⚠ Sin acuerdo de tratamiento de datos formalizado. Ver [G9](./g9-continuidad-negocio.md) |
| **dattaweb / donweb** (proveedor de hosting) | ⚠️ **Acceso administrativo al sistema operativo de dev-1**, que aloja **16 copias de bases productivas** incluida `mediflow_db` | 🔴 **Hasta Sensible** | 🔴 **CORREGIDO 2026-08-09 — la fila anterior era falsa.** Decía *"✅ Sin acceso a datos de aplicación. Acotado por `com2sec` a 2 IPs"*, describiendo solo el canal SNMP. Ver §4.2 |
| **Netdata Cloud** | Métricas de infraestructura y alarmas | 🟡 Interno | ✅ Sin datos de aplicación |
| **MercadoPago** | Datos de pago de los usuarios finales — **de `clubix`** | 🟠 Confidencial | Procesamiento en la pasarela. ⚠ Confirmar que **no** se almacenan datos de tarjeta localmente (§2.2). *Corregido 2026-08-09: el origen es clubix, no mini.* |
| **GitHub** | Código + secretos **cifrados** (repo privado `infra-secrets`) | 🟠 (cifrado) | ✅ Cifrado por-valor con SOPS+age; GitHub no tiene la clave |
| **Proveedores de IA** (Anthropic, Google Gemini) | **A determinar** — 8 apps tienen `ANTHROPIC_API_KEY` y 2 `GEMINI_API_KEY`, incluida **mediflow** (base 🔴) | **Potencialmente hasta 🔴** | 🔴 **Hallazgo nuevo 2026-08-09** — ver §4.1 |

### 4.2 🔴 El proveedor de hosting es encargado de tratamiento, no proveedor de monitoreo (2026-08-09)

**El hallazgo más relevante del relevamiento in-situ.** Hasta hoy este documento clasificaba a **dattaweb /
donweb** como un tercero que recibe *métricas SNMP* — 🟡 Interno, sin acceso a datos de aplicación. La
verificación contra los servers muestra otra cosa:

| Server | Llaves `@donweb.com` en `root` | Llaves `@donweb.com` en `axiomacloud` (cuenta con `sudo` sin password) | ¿Utilizable hoy? |
|---|---|---|---|
| axioma | 43 | 0 | ❌ Inerte — `PermitRootLogin no` |
| clubix | 44 | 0 | ❌ Inerte |
| axiodemo | 0 | 0 | — (prueba que el server **puede operar sin ellas**) |
| **dev-1** | 43 | 🔴 **48** | ✅ **SÍ — acceso administrativo directo** |

Las llaves **no tienen `from=` ni `command=`**: sin restricción de origen ni de comando.

**Uso confirmado** (`/var/log/auth.log`, ventana retenida 2026-07-12 → 08-09):

- `santiago.fernandez@donweb.com` autenticó como **root** en dev-1 el **2026-07-14 a las 11:29:52 y
  12:32:24**, desde `200.58.112.191` — una de las dos IPs de dattaweb que este mismo marco documentaba
  como "solo monitoreo SNMP".
- `lastlog` registra un acceso de `root` previo desde la misma IP el **2026-06-11 02:39**, fuera de la
  ventana de logs.

**Lo que la evidencia NO permite afirmar.** No hay indicios de exploración interactiva: el
`/root/.bash_history` de dev-1 es continuo desde 2026-01-11 hasta 2026-08-06 y **no tiene ningún comando
entre el 13 y el 15 de julio**. Pero tampoco permite descartar acceso a datos: un `ssh host <comando>` no
interactivo o un `scp` **no dejan rastro** en el historial, `sshd` registra la autenticación y no lo que se
ejecuta, y `auditd` solo retiene **2 días**. La conclusión honesta es **acceso confirmado, uso no
determinable**.

**Consecuencia regulatoria.** Quien puede leer datos personales por cuenta del responsable es, bajo la
**Ley 25.326**, un **encargado de tratamiento** — con obligación de contrato que fije finalidad,
confidencialidad, medidas de seguridad y destino de los datos al terminar. Eso aplica aunque nunca hayan
mirado un solo registro: la figura la define la **posibilidad de acceso**, no su ejercicio. Y como dev-1
aloja `mediflow_db`, el objeto son datos del **art. 7**.

> **Por qué la clasificación no lo vio.** Este documento se redactó leyendo el repo, y el repo describía a
> dattaweb por su canal *contratado* (SNMP). El canal *real* —llaves inyectadas al aprovisionar el VPS—
> nunca estuvo documentado porque nunca se relevó `authorized_keys`. Es exactamente lo que la cadencia
> **C4** de [G6](./g6-revisiones-periodicas.md) (auditoría de accesos trimestral) existe para detectar, y
> estaba sin ejecutar. Riesgo **R20** en [G3](./g3-registro-riesgos.md); acciones **A9** y **A10**.

### 4.1 Transferencia a proveedores de IA (hallazgo 2026-08-09)

El inventario desagregado de secretos ([G7 §3.2](./g7-rotacion-secretos.md)) mostró que **8 de las apps
tienen credenciales de proveedores de IA**, entre ellas **`mediflow-backend`**, que es la aplicación de la
única base **🔴 Sensible** del marco. Esta clasificación **no contemplaba ese canal**: se analizaron los
terceros de *infraestructura* (R2, VPS, dattaweb, Netdata) pero no los de *aplicación*.

Es material para el cumplimiento porque, si una app envía contenido de sus registros a un modelo, hay
**transferencia internacional de datos** (art. 12 de la Ley 25.326) — y en el caso de mediflow, de datos
del **art. 7**. A diferencia de R2, acá **no hay mitigante de cifrado opaco**: el proveedor procesa el
contenido en claro por definición.

> ⚠ **Lo que este documento NO puede afirmar.** Tener la credencial **no prueba** que se envíen datos
> personales: la app podría usar el modelo solo para tareas que no tocan datos de pacientes. Determinarlo
> exige revisar el **código de cada app**, que está [fuera del alcance del dossier](../dossier-auditoria-seguridad.md).
> Lo que sí se afirma es que **el canal existe y no está evaluado**. → Acción **A7**.

## 5. Controles por nivel de clasificación

### 5.1 Controles vigentes (aplican a toda base 🟠 y 🔴)

| Control | Estado |
|---|---|
| Cifrado en tránsito (TLS) | ✅ nginx con TLS y headers de seguridad |
| Cifrado de backups en reposo (off-site) | ✅ pgBackRest `cipher-pass` (AES) hacia R2 |
| Autenticación fuerte de DB (`scram-sha-256`, 0 `md5`) | ✅ H01 cerrado |
| Acceso a DB restringido a loopback | ✅ `pg_hba` sin reglas `0.0.0.0/0` |
| Mínimo privilegio — un rol `<app>user` por app | ✅ estándar vigente (con desvíos abiertos: R04) |
| Firewall default-deny | ✅ ufw en los 5 |
| Recuperabilidad probada | ✅ restore drills con WAL replay ([G6 §2](./g6-revisiones-periodicas.md)) |
| Rotación de logs (acota retención de datos en logs) | ✅ logrotate en los 5 |

### 5.2 Controles adicionales exigidos para 🔴 Sensible

- **DEBE** limitarse el acceso al conjunto mínimo de personas y roles; sin acceso compartido.
- **NO DEBE** replicarse a entornos de desarrollo/demo con **datos reales**. Usar datos anonimizados o
  sintéticos. ⚠ **Posible incumplimiento hoy** — ver el hallazgo de §3.4 (dev-1) y la acción **A2**.
- **DEBE** evaluarse la notificación ante incidente con la AN ([G5 §5](./g5-respuesta-incidentes.md)).
- **DEBERÍA** registrarse el acceso administrativo directo a la base (más allá del acceso de la app).
- **DEBE** cifrarse en reposo a nivel de aplicación donde el dato lo amerite. ✅ **Vigente en mediflow**
  (`ENCRYPTION_MASTER_KEY` + `SEARCH_HASH_SALT`, [G7 S15](./g7-rotacion-secretos.md)) — control **fuerte**
  que esta clasificación desconocía hasta el 2026-08-09, y que conviene registrar como evidencia a favor.
  Su contracara es **R15**: si esa clave se pierde, los datos restaurados desde backup son ilegibles.

### 5.2.1 Canales de acceso a datos 🔴 más allá de la app (hallazgo 2026-08-09)

La regla "un rol `<app>user` por app" da la imagen de que **solo mediflow** lee `mediflow_db`. El
inventario de secretos mostró que **no es así**:

| Canal | Alcance | Control actual | Evaluación |
|---|---|---|---|
| App `mediflow` | `mediflow_db` | Rol `mediflowuser`, loopback, `scram-sha-256` | ✅ Esperado. ⚠ Su password es **débil** (8 caracteres, R06) |
| **`axio-db-agent`** (`/opt`, **axioma**) | **4 bases productivas**: `mini_db`, **`mediflow_db`** (vía `ALVERA_DATABASE_URL`), `parse_db`, `elore_db` | `*_BLOCKED_TABLES` / `*_BLOCKED_COLUMNS` en su `.env` + auth por `x-agent-key` + `User=axioapp` con hardening systemd + publicado por nginx en `https://prd.axiomacloud.com/axio-agent` | 🔴 **R14 — verificado y peor de lo supuesto.** Ver §5.2.2 |
| **`axio-db-agent`** (`/opt`, **clubix**) | `clubix_db` | Mismo esquema, `SERVER_NAME="Servidor Clubix"` | ⚠️ **Segunda instancia, no documentada.** `hardening.md` afirmaba *"hay un solo agente, en axioma; en clubix y axiodemo no existe"*. Está **`enabled` y `active` desde 2026-07-24** — un día después de entregar el dossier al auditor. Deriva post-entrega |

#### 5.2.2 🔴 A8 verificada — el blocklist no incluye los datos que debía proteger

Contenido real, leído del `.env` en el server el **2026-08-09**:

```
BLOCKED_TABLES  = admins, admin_tokens, tenant_configuracion, configuracion, audit_log, sessions
BLOCKED_COLUMNS = password, token, tokenPortal, apiKey, secret, hash
MAX_ROWS        = 1000
```

**Es idéntico en las 5 configuraciones** — `MINI_`, `ALVERA_`, `PARSE_`, `ELORE_` en axioma y `CLUBIX_` en
clubix. No es que el blocklist de mediflow se haya quedado corto: **nunca se escribió un blocklist por
aplicación**. El mismo texto genérico cubre una base de historias clínicas, una de facturación, una
documental y una de socios de club.

Y lo que bloquea es **el sistema, no a las personas**: administradores, tokens, configuración, auditoría y
sesiones. **No hay una sola tabla clínica, de pacientes ni de negocio en la lista.** Las historias clínicas
de `mediflow_db` son legibles por el agente hasta **1000 filas por consulta**.

Agravante de fondo: el agente conecta con el rol **`mediflowuser`**, que por el
[estándar §9](../estandar-despliegue.md) es **owner de la base y de todos sus objetos**. A nivel PostgreSQL
tiene acceso total de lectura y escritura; el blocklist es una cortesía de la aplicación. Y ese rol es
justamente el de la **contraseña débil de 8 caracteres** (R06, rotación pendiente).

> **Por qué importa para la clasificación.** Un control sobre datos 🔴 que vive en una variable de entorno
> tiene la misma fuerza que la disciplina de quien edita esa variable — y en este caso ni siquiera nombra
> los datos que debía proteger. La mitigación de fondo es un **rol de PostgreSQL de solo lectura con
> privilegios a nivel de columna**: así el control lo aplica el motor, es auditable y no se puede levantar
> editando un `.env`. Acción **A8** cerrada como hallazgo; la remediación queda como **A11**.

### 5.3 Retención y supresión

⚠ **Gap abierto.** No existe hoy una política de retención por tipo de dato ni un procedimiento de
supresión a pedido del titular (arts. 14–16). Lo único definido es la **retención de backups**
(`full=4` / `diff=7`), que es un parámetro operativo, no una política de datos.

> **Consecuencia práctica a documentar:** una supresión solicitada por un titular se aplica a la base
> viva, pero el dato **sobrevive en los backups** hasta que el ciclo de retención los rota. Es una
> limitación técnica legítima y común, pero **DEBE** estar documentada y comunicada, no ser implícita.

## 6. Obligaciones a verificar con la AN

| # | Obligación | Estado |
|---|---|---|
| **O1** | Inscripción de las bases ante la **AAIP** (art. 21) | ⬜ A verificar si corresponde y si está vigente |
| **O2** | **Transferencia internacional** hacia R2 (art. 12) — documentar el argumento del cifrado opaco | ⬜ A evaluar |
| **O3** | **Acuerdos de tratamiento de datos** con proveedores (VPS, Cloudflare) | ⬜ A verificar |
| **O4** | Procedimiento de **derechos del titular** (acceso, rectificación, supresión) | ⬜ A definir |
| **O5** | **Política de retención y supresión** por tipo de dato | ⬜ A definir (§5.3) |
| **O6** | Confirmar que **no se almacenan datos de tarjeta** localmente (alcance PCI) | ⬜ A verificar |

> Estas obligaciones son de naturaleza **legal/de negocio**, no técnica: el `A` es la **AN**
> ([G2 §3](./g2-roles-responsabilidades.md)) y su resolución **DEBERÍA** contar con asesoramiento legal.

## 7. Acciones abiertas

| # | Acción | Prioridad | Responsable |
|---|---|---|---|
| **A1** | **Validar funcionalmente la clasificación de §3** — confirmar con el responsable de cada app qué datos contiene realmente cada base. Prioridad absoluta: `mediflow_db` (¿datos de salud identificables?), `clubix_db` (¿aptos médicos?), `fitness_db`, `axiomadocs` | 🔴 Crítica | RT + responsables de app |
| **A2** | **Determinar si dev-1 aloja datos productivos reales** y, si es así, decidir: anonimizar, restringir o elevar los controles de dev-1 al nivel de producción | 🔴 Crítica | RT |
| **A3** | Elevar a la **AN** las obligaciones O1–O6 de §6 | 🟠 Alta | RT → AN |
| **A4** | Definir la **política de retención y supresión** (§5.3), incluida la limitación de los backups | 🟠 Alta | RT + AN |
| **A5** | Documentar formalmente el **argumento del cifrado opaco** para la transferencia a R2 (O2) | 🟡 Media | RT |
| **A6** | Registrar el resultado de A1 como **actualización de §3**, retirando las marcas *(a confirmar)* | 🟡 Media | RT |
| **A7** | **Evaluar el canal hacia proveedores de IA** (§4.1) — determinar, app por app, si se envía contenido con datos personales a Anthropic/Gemini. Empezar por **mediflow** (base 🔴). Si se confirma, es **transferencia internacional** (art. 12) sobre datos del **art. 7** | 🔴 **Crítica** | RT + responsables de app → AN |
| **A8** | ~~Verificar el contenido real de `ALVERA_BLOCKED_TABLES`/`_BLOCKED_COLUMNS`~~ — ✅ **cerrada 2026-08-09**: verificado en el server, el blocklist es genérico, idéntico en las 5 configuraciones y **no incluye ninguna tabla clínica** (§5.2.2). La remediación pasa a **A11** | ✅ Cerrada | RT |
| **A9** | 🔴 **Formalizar la relación con el proveedor de hosting como encargado de tratamiento** (§4.2): contrato con finalidad, confidencialidad, medidas de seguridad, subencargados y destino de los datos; y **solicitarle su registro de accesos** a dev-1 | 🔴 **Crítica** | RT → **AN** + asesoría legal |
| **A10** | 🔴 **Reducir el acceso del proveedor**: purgar las 48 llaves `@donweb.com` de `/home/axiomacloud/.ssh/authorized_keys` en dev-1 (axiodemo tiene 0 y opera igual), o —mejor— **sacar los datos productivos de dev-1** para que el acceso deje de ser sobre datos reales | 🔴 **Crítica** | RT (coordinar con el proveedor) |
| **A11** | **Migrar el control del `axio-db-agent` a PostgreSQL**: rol de solo lectura con privilegios a nivel de columna por app, en lugar del blocklist en `.env` (§5.2.2) | 🔴 **Crítica** | RT |

## 8. Gobierno

- Este documento se **revisa cada trimestre** (próxima **2026-10-23**) y **ante el alta de toda base nueva**
  — una base sin clasificar es un gap por definición.
- **Estado del gap G8 al 2026-08-09:** 🟡 — marco de clasificación, marco regulatorio y mapa de terceros
  definidos; la **clasificación concreta es provisional** (inferida del inventario técnico, no validada
  funcionalmente). Pasa a 🟢 cuando A1, A2, A7 y A8 estén ejecutadas y las obligaciones de §6 tengan
  resolución de la AN.
- **Riesgos registrados en [G3](./g3-registro-riesgos.md) el 2026-08-09:** **R13** (posible tratamiento de
  datos 🔴 en dev-1 bajo controles de desarrollo — pendiente de confirmación por A2, ya **no** propuesto
  sino registrado) y **R14** (acceso del `axio-db-agent` a 4 bases productivas incluida `mediflow_db`,
  §5.2.1).
- **Lo que cambió el 2026-08-09.** El inventario desagregado de secretos de [G7 §3.2](./g7-rotacion-secretos.md)
  —hecho leyendo solo nombres de variable, sin descifrar nada— corrigió y amplió este documento en cuatro
  puntos: se corrigió la atribución de los pagos (**clubix**, no mini), se descubrió un **canal de acceso
  a datos 🔴 no contemplado** (el db-agent, §5.2.1), se descubrió un **canal de transferencia a terceros
  no contemplado** (proveedores de IA, §4.1) y se incorporó como evidencia un **control fuerte que no se
  conocía** (el cifrado en reposo de mediflow, §5.2). Es el argumento más concreto a favor de mantener el
  inventario de secretos al día: **el mapa de secretos es, en la práctica, el mapa de por dónde salen los
  datos.**
- Referencias cruzadas: [G1 §5](./g1-politica-seguridad.md) (declaración de clasificación),
  [G5 §5](./g5-respuesta-incidentes.md) (notificación regulatoria), [G9](./g9-continuidad-negocio.md)
  (dependencias de terceros).
