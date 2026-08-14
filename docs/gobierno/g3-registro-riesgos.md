# G3 — Registro de Riesgos

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G3** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
>
> **Estado:** v1 — redacción inicial (2026-07-23).
>
> **Propósito.** Registro formal de riesgos de la infraestructura Axioma: identificación, valoración
> (probabilidad × impacto), tratamiento y estado. Consolida en un solo lugar los riesgos derivados de
> los **hallazgos abiertos** del dossier (§7), los **residuales aceptados**, los riesgos de **gobierno**
> (procesos aún ausentes) y los **escenarios de desastre** del [DRP](../disaster-recovery-plan.md). El
> DRP cubre la *recuperación* técnica; este registro cubre el *análisis de riesgo* que la precede.

## 1. Metodología de valoración

- **Probabilidad:** Baja (B) · Media (M) · Alta (A) — likelihood de materialización en un horizonte de 12 meses.
- **Impacto:** Bajo (B) · Medio (M) · Alto (A) — sobre confidencialidad, integridad, disponibilidad o cumplimiento.
- **Nivel de riesgo** (matriz P×I):

  | | Impacto B | Impacto M | Impacto A |
  |---|---|---|---|
  | **Prob. A** | 🟡 Medio | 🔴 Alto | 🔴 Crítico |
  | **Prob. M** | 🟢 Bajo | 🟡 Medio | 🔴 Alto |
  | **Prob. B** | 🟢 Bajo | 🟢 Bajo | 🟡 Medio |

- **Tratamiento:** Mitigar · Aceptar · Transferir · Evitar. Un riesgo **Aceptado** requiere aprobación
  de la **AN** (Darío Cukier — ver [G2](./g2-roles-responsabilidades.md)).
- **Owner:** responsable del tratamiento (por defecto RT `mfourgeaux`, salvo indicación).

## 2. Registro de riesgos

| ID | Riesgo | Origen | P | I | Nivel | Tratamiento | Estado / mitigación | Owner | Aprob. |
|---|---|---|---|---|---|---|---|---|---|
| **R01** | 5 apps Next.js escuchan en `0.0.0.0` (acceso salteando nginx/TLS/headers si cae el firewall) | H04 | B | M | 🟢 Bajo | Mitigar | Mitigado por ufw default-deny (puertos tapados desde afuera) + `proxy_pass` a loopback. Bloqueado por patrón del framework (`-H` rompe redirects de Next). Resolver una sola vez antes de reintentar el rebindeo | RT | — |
| **R02** | Árbol de mini/axioma con ~83.000 archivos owner ≠ `miniapp` (permisos laxos en app productiva) | H06 | M | M | 🟡 Medio | Mitigar | `.env` backend ya en `600 miniapp`; el `chown -R` masivo **requiere ventana** (server productivo). Riesgo latente de exposición local y de romper el próximo arranque | RT | — |
| **R03** | snmpd con community `public` en dev-1 (lectura de métricas del sistema) | H09 | B | B | 🟢 Bajo | Aceptar | Acotado por `com2sec` a 2 IPs de dattaweb + ufw (161 solo desde esas IPs). Cambiar la community **cortaría el monitoreo contratado** → requiere coordinar con dattaweb. Aceptado hasta esa coordinación | RT | AN |
| **R04** | `axio-ml` corre como `axiomacloud` (owner ≠ app dedicada) en axiodemo | H11 | B | B | 🟢 Bajo | Mitigar | Normalizar a usuario dedicado + hook ollama (Fase 6 de estandarización) | RT | — |
| **R05** | Credenciales R2 en texto plano en los `.conf` que pgBackRest debe leer | H03 (residual) | B | M | 🟢 Bajo | Aceptar | **Limitación del producto** (pgBackRest necesita leerlas). Mitigado por `640` + owner + firewall + custodia SOPS. Token ya rotado; 0 `.bak` con creds viejas | RT | AN |
| **R06** | Password de `mediflowuser` corto/débil (8 caracteres) | G7 (candidato rotación) | M | M | 🟡 Medio | Mitigar | Rotar a credencial fuerte según política de rotación ([G7](./g7-rotacion-secretos.md)). Mitigado parcialmente: DB solo accesible por loopback + scram | RT | — |
| **R07** | Credenciales AWS en el `.env` de hub para un SDK **nunca importado** (exposición sin uso) | H13 (colateral) | B | M | 🟢 Bajo | Evitar | **Revocar** las credenciales (peso muerto, no aportan función). Anotado en el cierre de H13 | RT | — |
| **R08** | Bus factor a nivel de **ejecución**: el RT concentra la operación técnica de casi todos los dominios | G2 (residual) | M | A | 🔴 Alto | Mitigar | BT (R. Naranjo) designado **con acceso ya provisto**. *Pendiente:* registrar la **primera co-ejecución** (próximo drill ~2026-08-19 o incidente) para pasar el bus factor 2 de declarativo a probado | RT + BT | — |
| **R09** | Ausencia de proceso periódico de gestión de vulnerabilidades y parches | G4 | M | M | 🟡 Medio | Mitigar | Remediación de hub desplegada (H13) fue reactiva y única. Formalizar escaneo calendarizado + umbrales + SLA de parcheo ([G4](./g4-gestion-vulnerabilidades.md)) | RT | — |
| **R10** | Ausencia de plan formal de respuesta a incidentes | G5 | B | A | 🟡 Medio | Mitigar | El DRP cubre flujos de comunicación por escenario, pero falta un IR plan independiente (detección, severidad, contención, post-mortem). Formalizar en [G5](./g5-respuesta-incidentes.md) | RT | — |
| **R11** | Cadencia mensual de restore drills aún no sostenida (un solo ciclo completo) | H07 / G6 | M | M | 🟡 Medio | Mitigar | 3 stanzas en PASS el 2026-07-19 (1er ciclo). Sostener la cadencia y registrar en `drill-history.csv`; próxima ~2026-08-19 ([G6](./g6-revisiones-periodicas.md)) | RT | — |
| **R12** | Dependencia de terceros sin SLA formal (Cloudflare R2, VPS, Netdata Cloud, dattaweb) | G9 | B | A | 🟡 Medio | Aceptar | Sin acuerdos de nivel de servicio formalizados. Cubrir en el [BCP — G9](./g9-continuidad-negocio.md); aceptado hasta entonces | RT | AN |
| **R13** | **dev-1 (entorno de desarrollo) podría alojar datos productivos reales**, incluidos datos de salud 🔴 | [G8 §3.4](./g8-clasificacion-datos.md) | **A** | **A** | 🔴 **Alto** | Mitigar | dev-1 tiene **16 bases homónimas de las productivas** (`mediflow_db`, `mini_db`, `clubix_db`, `checkpoint_db`, `hub_db`, `core_db`…). Si contienen datos reales, un entorno de desarrollo trata datos del art. 7 de la Ley 25.326 bajo controles de desarrollo. **P alta** porque el patrón habitual de refresco de entornos es restaurar un dump de producción. *Acción A2 de G8:* confirmar el contenido y, según resultado, anonimizar, restringir o elevar los controles de dev-1 a nivel producción | RT | AN |
| **R14** | 🔴 **`axio-db-agent`: el blocklist que debía proteger los datos no los incluye** — acceso a 4 bases productivas, incluida `mediflow_db` (🔴, base de la app **alvera** — ver nomenclatura en [G8 §3](./g8-clasificacion-datos.md)), conectando como **owner** de cada base | [G8 §5.2.1](./g8-clasificacion-datos.md) · A8 verificada 2026-08-09 | **A** | **A** | 🔴 **Alto** | Mitigar | **Verificado en el server (A8).** El agente de axioma conecta a `mini_db`, `mediflow_db`, `parse_db` y `elore_db`, y el de **clubix** (que `hardening.md` afirmaba inexistente, activo desde 2026-07-24) a `clubix_db`. El control declarado es un blocklist en variable de entorno, y su contenido es **idéntico en las 5 configuraciones**: tablas `admins, admin_tokens, tenant_configuracion, configuracion, audit_log, sessions` y columnas `password, token, tokenPortal, apiKey, secret, hash`. **No hay una sola tabla de negocio ni clínica en la lista**: protege *el sistema* (credenciales, config, auditoría), no *a los pacientes*. Las historias clínicas quedan legibles hasta `MAX_ROWS=1000` por consulta. Agravante: conecta con el rol **`mediflowuser`**, que por el estándar es **owner de la base y de todos sus objetos** → a nivel PostgreSQL tiene acceso total, y es el rol de la **contraseña débil de 8 caracteres** (R06). *Mitigación de fondo:* rol de PostgreSQL **de solo lectura con privilegios a nivel de columna**, para que el control lo haga el motor y quede auditable | RT | AN |
| **R15** | **Claves de cifrado de datos en reposo sin respaldo verificado** — perderlas haría ilegibles los datos restaurados | [G7 §4.3](./g7-rotacion-secretos.md) | B | **A** | 🟢 **Bajo** | Mitigar | ✅ **VERIFICADO 2026-08-12.** Se restauró `mediflow_db` desde el backup de R2 en axioma-drp, se desplegó alvera con el `.env` recuperado de `infra-secrets`, y **los campos cifrados se leen en claro**. Queda probado que la `ENCRYPTION_MASTER_KEY` respaldada es la correcta y que el circuito **backup → restore → aplicación** funciona. **Era el único modo de falla del DR que no avisa**: base levantada, app respondiendo, datos ilegibles y ningún error en los logs. **Residual:** la verificación **no está incorporada al restore drill mensual** — se hizo a mano en este simulacro. Baja de 🟡 a 🟢 y cierra cuando el drill la incluya (acción A3 de [G9](./g9-continuidad-negocio.md)) | RT | — |
| **R16** | **Contraseñas de cuentas de SO fuera de todo inventario y política** — materializado en una exposición | [G7 §3.3](./g7-rotacion-secretos.md) | **A** | M | 🟡 Medio | Mitigar | El alcance original de G7 cubría roles de PostgreSQL y claves SSH pero **no** las contraseñas de las cuentas con `sudo`. El 2026-08-09 la contraseña de `axiomacloud` quedó **expuesta en claro** en una sesión de asistente. ⚠️ **Corrección del mismo día:** este riesgo se elevó a 🔴 por creer que se había reactivado `PasswordAuthentication`; **la reactivación nunca tuvo efecto** y se devuelve a 🟡. Ver R18 por el residual real. El mitigante estructural **se sostiene**: `sshd -T` confirma `passwordauthentication no` y `permitrootlogin no` en los 4 servers verificados. *Acción A6 de G7:* rotar la contraseña igual — sigue expuesta y sirve para `sudo` y para la consola del proveedor | RT | — |
| **R17** | **Repo de secretos ilegible — pérdida de la clave age** | [G7 §7.1](./g7-rotacion-secretos.md) | B | **A** | 🟡 **Medio** | Mitigar | ✅ **Reconstituido el 2026-08-09 y probado el 08-12**: par age nuevo, **37 `.env` re-cifrados** con roundtrip verificado, y el simulacro de recuperación **descifró con éxito** los `.env` de hub, alvera y parse. Se sumó `creds/` para credenciales en archivo (S19). **Baja de 🔴 a 🟡. Residual — y es el que importa:** la clave nueva está en **dos lugares que dependen del RT** (su equipo + su LastPass). **Ninguna copia es accesible por el BT**, así que el escenario que causó la pérdida original —una persona, un punto de falla— sigue vigente. Cierra cuando exista la tercera copia compartida (A9 de G7) | RT | — |
| **R18** | ~~Cambio de `sshd` escrito y nunca aplicado — habilitación latente de password auth~~ — ✅ **RESUELTO 2026-08-13** | Verificación in-situ 2026-08-09 | — | — | ✅ **Cerrado** | Evitar | **`99-temp-password-axiomacloud.conf` eliminado de los 4 servidores donde existía** (axioma, clubix, axiodemo, dev-1), con respaldo previo en `/root/`. **axioma-drp verificado y limpio** —se reinstaló el 08-08 y nunca tuvo el archivo—, así que la cobertura es **5 de 5** (regla R2 de G10). `sshd -t` válido y config viva sin cambios: `passwordauthentication no` · `permitrootlogin no`. **No se recargó sshd** — la config en ejecución ya era la correcta, y recargar era el único paso con riesgo. Acceso verificado con **conexión nueva** a los 4 (regla R1 de [G10](./g10-verificacion-remediaciones.md)). ⚠️ **Hallazgo colateral → R22** | RT | — |
| **R19** | **~43 llaves SSH de terceros en `/root/.ssh/authorized_keys`, sin inventariar** | S10 / relevamiento 2026-08-09 | M | **A** | 🟡 Medio | Mitigar | axioma **46**, clubix **43**, dev-1 **43** entradas, de las cuales ~43-44 son de `@donweb.com`. **Hoy inertes** por `PermitRootLogin no` — el fix del 2026-07-17 les cortó el acceso sin que se registrara ese efecto. Quedan como **acceso latente**: revertir esa directiva (o que la revierta una actualización) reabre las ~43 de golpe. axiodemo tiene **0**, lo que prueba que el server puede operar sin ellas. *Acción:* inventariar, decidir cuáles conservar y **purgar el resto**; no depender de una sola directiva como control | RT | AN |
| **R20** | 🔴 **El proveedor de hosting tiene acceso administrativo efectivo a dev-1, que aloja 16 copias de bases productivas** — incluida `mediflow_db` (🔴 salud) | S10 / auth.log 2026-08-09 | **Materializado** | **A** | 🔴 **Alto** | Mitigar | **48 llaves `@donweb.com` en `/home/axiomacloud/.ssh/authorized_keys` de dev-1** (53 en total) — no en `root`, sino **en la cuenta de operación, que tiene `sudo` sin contraseña**. Sin `from=` ni `command=`. **Uso confirmado:** `santiago.fernandez@donweb.com` autenticó como **root** el **2026-07-14 a las 11:29 y 12:32** desde `200.58.112.191` (IP de dattaweb documentada), y `lastlog` registra un acceso previo el **2026-06-11 02:39** desde la misma IP. **No hay evidencia de exploración interactiva** (el `bash_history` de root es continuo de ene a ago y no tiene comandos el 13–15 de julio), pero **tampoco puede descartarse acceso a datos**: un `ssh host comando` o un `scp` no dejan rastro en el historial, y `auditd` solo retiene 2 días. Bajo la **Ley 25.326** esto convierte al proveedor en **encargado de tratamiento de datos de salud**, no en un proveedor de monitoreo — figura que [G8 §4](./g8-clasificacion-datos.md) declaraba explícitamente como *"sin acceso a datos de aplicación"* | RT | **AN** |
| **R21** | ~~El proveedor filtra los puertos 80/443 hacia axioma-drp~~ — ✅ **RESUELTO 2026-08-12** | Simulacro DRP · [runbook §8.1](../drp-recuperacion-axioma-en-drp.md) | — | — | ✅ **Cerrado** | Mitigar | **baehost habilitó 80/443 entrantes** hacia `170.78.75.249`. Verificado desde fuera de la red del proveedor: `80/tcp` y `443/tcp` abiertos, `http → 301`, `https → 200`, y **ambas apps responden por internet sin túnel** (hub y alvera con su título real; API en 401, autenticación operativa). **Control negativo OK** (regla R3 de [G10](./g10-verificacion-remediaciones.md)): `5432`, `5300` y `19999` **cerrados** desde afuera. ⚠️ **Corrección metodológica:** el diagnóstico original incluía *«desde el propio drp su IP pública da 000»*. Eso **no probaba nada**: es **NAT hairpinning** —el proveedor no reenvía el tráfico del servidor hacia su propia IP externa— y sigue dando 000 ahora que los puertos están abiertos. **La única prueba válida es desde fuera de la red del proveedor.** Incorporado a G10 como regla **R8** | RT | — |
| **R22** | ~~Backups de configuración de `sshd` con `PermitRootLogin yes` dentro de `sshd_config.d`~~ — ✅ **RESUELTO 2026-08-13** | Colateral del cierre de R18 | — | — | ✅ **Cerrado** | Evitar | Los `custom.conf.bak-20260717-*` de **axioma, clubix y dev-1** se movieron a `/root/sshd-config-backups/` (modo `700`), fuera del directorio que `sshd` lee. **axiodemo y axioma-drp no tenían restos.** Cobertura **5 de 5**. Resultado verificado: **ya no existe ninguna ocurrencia de `PermitRootLogin yes` en `/etc/ssh` de ningún servidor**. `sshd -t` válido y config viva sin cambios en los 5; acceso confirmado con conexión nueva. **Se conservan los backups** —no se borraron— pero fuera del alcance del `Include` | RT | — |

## 3. Riesgos de desastre (derivados del DRP)

> Estos riesgos tienen su **tratamiento de recuperación** documentado en el
> [DRP](../disaster-recovery-plan.md) §2–§3. Se listan aquí para completar el análisis de riesgo con su
> valoración de probabilidad/impacto. RPO efectivo global: **4 h**; RTO: **15–90 min** según escenario.

| ID | Escenario | P | I | Nivel | Tratamiento (DRP) | RTO |
|---|---|---|---|---|---|---|
| **RD-A** | Corrupción de datos en un db host | M | A | 🔴 Alto | Restore desde repo1 (SSH dev-1) + WAL replay | 15–30 min |
| **RD-B** | Pérdida total de un db host | B | A | 🟡 Medio | Aprovisionar VPS + restore repo1/R2 | 30–45 min |
| **RD-C** | Pérdida de dev-1 (repo host) | B | A | 🟡 Medio | Restore desde repo2 (R2, egress WAN) | 45–60 min |
| **RD-D** | Pérdida simultánea de dev-1 + un db host (peor caso) | B | A | 🟡 Medio | Solo R2 disponible; aprovisionar infra + restore | 60–90 min |

## 4. Resumen y riesgos priorizados

- **Total:** **22** riesgos operativos/gobierno (**3 cerrados**: R18, R21, R22) + 4 escenarios de desastre. *(2026-08-12: **+R21**, el único que se descubrió **ejecutando** y no leyendo. 2026-08-09: +8 — R13 a R20,
  derivados de la redacción de G8, del inventario desagregado de secretos (G7 §3.2), de la pérdida efectiva
  de la clave age y del **primer relevamiento in-situ con acceso a los servers** — S10, A8 y C2.)*
- **🔴 Alto:** R08 (bus factor de ejecución), **R13** (posibles datos productivos 🔴 en dev-1),
  **R14** (el blocklist del db-agent no protege datos clínicos — **verificado**), **R20** (acceso administrativo del
  proveedor a dev-1 — **uso confirmado**), RD-A (corrupción de datos). *(**R21 cerrado** el 2026-08-12: baehost habilitó los puertos.)*
- **🟡 Medio:** R02, R06, R09, R10, R11, R12, **R16**, **R17**, **R19**, RD-B, RD-C, RD-D.
- **🟢 Bajo:** R01, R03, R04, R05, R07, **R15** *(verificado el 08-12)*.
- **Aceptados (requieren firma AN):** R03, R05, R12.
- **Pendientes de aprobación de la AN por su nivel 🔴:** R13, R14 y **R20** — los tres tocan el tratamiento
  de datos del art. 7 de la Ley 25.326, así que la decisión no es solo técnica. **R20 además tiene
  consecuencia contractual**: obliga a formalizar un acuerdo de tratamiento con el proveedor o a sacar los
  datos productivos de dev-1.

> **Nota de tendencia (2026-08-09).** El registro pasó de 12 a 17 riesgos en un día. **Cuatro de los cinco
> nuevos ya existían y no estaban vistos** — aparecieron al redactar G7 y G8, o sea que el marco está
> funcionando como instrumento de detección y no solo de registro. Tres de ellos (R13, R14, R15) convergen
> en el mismo punto ciego: **dónde viven realmente los datos de salud y quién puede leerlos**.
>
> **El quinto es distinto y hay que decirlo sin adornos.** **R17 no es un riesgo detectado: es un control
> que falló.** La custodia de la clave age figuraba como "✅ Vigente y verificada" en G7 §2 y resultó no
> existir. Es el segundo falso verde del marco después de H06, y por la misma causa: **se declaró
> verificado algo para lo cual no había evidencia de verificación**. La diferencia con H06 es que esta vez
> el propio marco venía señalando el hueco — C10 de [G6](./g6-revisiones-periodicas.md) es exactamente la
> cadencia que lo habría detectado, y estaba sin ejecutar. El marco identificó el control correcto; lo que
> faltó fue **correrlo**. Es el argumento más fuerte disponible para el punto que G6 sostiene desde su
> primera línea: *una cadencia sin registro de ejecución no es un control, es una intención.*
>
> **Segunda nota (misma fecha, tras el primer relevamiento con acceso a los servers).** R18, R19 y R20
> aparecieron en las primeras horas de mirar los servers en vivo, y los tres comparten una característica:
> **ninguno era deducible desde la documentación**. Todo el marco G1–G8 se construyó leyendo el repo, y
> por eso describía con precisión lo que estaba escrito y no lo que estaba pasando. La brecha más cara no
> fue un control ausente sino **una afirmación documentada que había dejado de ser cierta** — G8 §4 decía
> que el proveedor no tenía acceso a datos de aplicación mientras 48 de sus llaves vivían en la cuenta con
> `sudo` del server que aloja las copias productivas. La conclusión para la cadencia **C4** (auditoría de
> accesos, trimestral, hoy sin ejecuciones) es directa: **auditar accesos contra el server, nunca contra
> el documento.**

## 5. Gobierno del registro

- El registro se **revisa cada trimestre** (próxima **2026-10-23**) junto con la
  [política de seguridad](./g1-politica-seguridad.md) y en la cadencia de [G6](./g6-revisiones-periodicas.md).
- Todo **riesgo aceptado** debe llevar la aprobación formal de la **AN** (Darío Cukier) con fecha y
  fecha de revisión. Aprobaciones pendientes de firma: R03, R05, R12.
- Cuando un hallazgo del dossier (§7) se cierra, su riesgo asociado se marca **cerrado** aquí con la
  fecha; cuando aparece uno nuevo, se agrega una fila.
