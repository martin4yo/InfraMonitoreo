# G6 — Cadencia y Registro de Revisiones Periódicas

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G6** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
>
> **Estado:** v1 — redacción inicial (2026-08-06).
>
> **Hallazgo que motiva este documento.** Los documentos técnicos **declaran** cadencias
> (el [DRP](../disaster-recovery-plan.md) §7.1 pide revisión trimestral; §7.2 un drill mensual; §5.3 una
> verificación mensual del acceso SSH de emergencia) pero **no existía un registro de ejecución**: un
> auditor no podía distinguir una cadencia comprometida de una cadencia cumplida. Este documento
> consolida **todas** las cadencias del marco en un solo calendario y aporta el **libro de evidencia**
> donde cada ejecución se asienta con fecha, ejecutor y resultado.
>
> **Principio.** Una cadencia sin registro de ejecución no es un control: es una intención. La evidencia
> de este documento es lo que convierte los gaps 🟡 en 🟢.

## 1. Calendario consolidado de cadencias

| # | Actividad | Frecuencia | Responsable | Origen | Evidencia (dónde se asienta) |
|---|---|---|---|---|---|
| **C1** | **Restore drill** de las 3 stanzas productivas | Mensual (~día 19) | RT (co-ejecución BT) | [DRP §7.2](../disaster-recovery-plan.md) | `drill-history.csv` (auto) + DRP §7.3 (curado) |
| **C2** | **Verificación del acceso SSH de emergencia** a los 5 servers | Mensual | RT | [DRP §5.3](../disaster-recovery-plan.md) | §3 de este documento |
| **C3** | **Escaneo de vulnerabilidades** — `npm audit` de apps propias + `apt list --upgradable` | Mensual | RT | [G4 §3](./g4-gestion-vulnerabilidades.md) | §4 de este documento |
| **C4** | **Auditoría de accesos** — usuarios del sistema, `authorized_keys`, roles de PostgreSQL, sudoers | Trimestral | RT | [G1 §3](./g1-politica-seguridad.md) | §5 de este documento |
| **C5** | **Revisión de versiones vs. EOL/avisos** — PostgreSQL, Node, nginx, pgBackRest | Trimestral | RT | [G4 §3](./g4-gestion-vulnerabilidades.md) | §4 de este documento |
| **C6** | **Revisión documental del marco de gobierno** — G1–G10 + registro de riesgos | Trimestral | RT (aprueba AN lo que corresponda) | [G1 §9](./g1-politica-seguridad.md), [G3 §5](./g3-registro-riesgos.md) | §6 de este documento |
| **C7** | **Revisión del DRP** | Trimestral + tras incidente o cambio de infraestructura | RT | [DRP §7.1](../disaster-recovery-plan.md) | §6 de este documento |
| **C8** | **Verificación de backups** — `pgbackrest check` en las 4 stanzas + frescura | Continua (alarmas Netdata) + confirmación en el drill mensual | RT | [G1 §6](./g1-politica-seguridad.md) | Netdata Cloud + C1 |
| **C9** | **Ejercicio de incidente simulado** | Anual | RT + BT | [G5 §8](./g5-respuesta-incidentes.md) | §7 de este documento |
| **C10** | **Revisión del inventario de secretos y rotación programada** | Semestral (inventario) · según [G7 §4](./g7-rotacion-secretos.md) (rotación) | RT | [G7](./g7-rotacion-secretos.md) | G7 §5 (registro de rotaciones) |
| **C11** | **Ventana de reinicio de servidores** — activar kernels y `libc6` ya descargados | Mensual (o ante paquete que lo requiera) | RT | [G4](./g4-gestion-vulnerabilidades.md) · relevamiento 2026-08-09 | §4 de este documento |
| **C12** | **Prueba de continuidad** — restaurar el kit desde los respaldos declarados, en equipo limpio | Semestral | **BT** (no el RT) | [G9 §6](./g9-continuidad-negocio.md) | §7 de este documento |

### 1.1 Anclaje del calendario

Para que las cadencias no dependan de la memoria, se anclan a fechas fijas:

| Ciclo | Anclaje | Actividades |
|---|---|---|
| **Mensual** | ~día **19** de cada mes | C1, C2, C3, **C11** (reinicio, en la misma ventana) |
| **Trimestral** | **23 de ene / abr / jul / oct** | C4, C5, C6, C7 |
| **Semestral** | **23 de ene / jul** | C10 (inventario de secretos) · **C12** (prueba de continuidad) |
| **Anual** | a definir en el primer ejercicio | C9 |

> El anclaje mensual al día 19 consolida drill + escaneo + verificación de acceso en una sola ventana de
> mantenimiento (criterio ya adoptado en [G4 §3](./g4-gestion-vulnerabilidades.md)). El trimestral al 23
> hereda la fecha de redacción del marco (2026-07-23), que fija la próxima revisión en **2026-10-23**.

## 2. Registro de restore drills (C1)

> **Fuente de verdad:** [`drill-history.csv`](../drill-history.csv), escrito automáticamente por
> `scripts/70-restore-drill.sh` (una fila por stanza por corrida, auto-evaluante). El resumen curado
> por evento vive en [DRP §7.3](../disaster-recovery-plan.md). Esta tabla es el **registro de cadencia**:
> una fila por ciclo mensual, para responder "¿se cumplió el compromiso este mes?".

| Ciclo | Fecha | Ejecutor | Stanzas en PASS | Resultado del ciclo | Notas |
|---|---|---|---|---|---|
| 2026-07 | 2026-07-19 | martin4yo | 3/3 (AxiomaCloudProd, clubix, axiodemo) | ✅ **Cumplido** | Primer ciclo completo de las 3 stanzas. Los 2 FAIL previos fueron **falsos negativos** por 2 bugs del script, corregidos; PASS en la 3ª corrida. WAL lag 0–1 min. |
| 2026-08 | _pendiente_ | — | — | ⬜ **Programado** (~2026-08-19) | Objetivo: 2º ciclo consecutivo → habilita pasar R11 a 🟢 y es la oportunidad de la **primera co-ejecución del BT** (cierra R08). |

> **Estado de la cadencia:** **1 ciclo ejecutado**. La cadencia mensual se considera **sostenida** (y el
> riesgo **R11** de [G3](./g3-registro-riesgos.md) pasa a 🟢) cuando acumule **≥3 ciclos consecutivos**
> cumplidos. Un ciclo omitido reinicia el conteo y se registra el motivo.

## 3. Registro de verificación de acceso de emergencia (C2)

> Lo pide el [DRP §5.3](../disaster-recovery-plan.md): verificar mensualmente que el acceso SSH desde el
> equipo de restauración a los servidores funciona, para no descubrir en un incidente que una clave
> expiró o fue revocada. **Al 2026-08-06 no hay ninguna ejecución registrada** — la verificación se
> declaraba pero no se asentaba.
>
> ⚠️ **Y el 2026-08-09 se descubrió por qué importa.** Al reconstruir el entorno de trabajo en un equipo
> nuevo no había **ni clave SSH, ni `inventory.sh`, ni clave age**. El acceso de emergencia era
> **inexistente en la práctica** mientras el DRP lo daba por disponible. El inventario se pudo reconstruir
> desde el propio repo (DNS de los dominios + `from=` en `pgbackrest-setup.md` + puertos en
> `hardening.md`), pero la clave age **no**: se perdió (ver [G7 §7.1](./g7-rotacion-secretos.md)). Esta
> cadencia no es burocracia — es la que hubiera evitado descubrirlo en el peor momento posible.

**Procedimiento (solo lectura, no invasivo):**

1. Desde el equipo de restauración, `ssh` a cada uno de los 5 servidores con la clave de emergencia.
2. Confirmar que la sesión abre **sin password** y que `sudo -n true` responde donde corresponde.
3. Verificar que el acceso del **BT** también funciona (no solo el del RT) — es lo que sostiene el bus factor 2.
4. Asentar el resultado en la tabla.

| Fecha | Ejecutor | axioma | clubix | axiodemo | dev-1 | axioma-drp | Acceso BT | Resultado |
|---|---|---|---|---|---|---|---|---|
| **2026-08-09** | martin4yo | ✅ OK | ✅ OK (:2222) | ✅ OK | ✅ OK | ⚠️ No alcanzado | ⬜ No verificado | 🟡 **4 de 5.** Primera ejecución registrada de C2 |
| **2026-08-11** | martin4yo | ✅ OK | ✅ OK (:2222) | ✅ OK | ✅ OK | ✅ **OK** — `sudo` NOPASSWD | ⬜ No verificado | ✅ **5 de 5.** Ver corrección abajo |
| _pendiente_ | — | — | — | — | — | — | — | ⬜ Próxima ~2026-09-09 |


> ⚠️ **Corrección del registro del 2026-08-09 (aplicando R5/R7 de [G10](./g10-verificacion-remediaciones.md)).**
> Ese día se asentó que axioma-drp tenía el **22/tcp filtrado**. Era una **lectura incorrecta de la
> evidencia**: el puerto estaba abierto y lo que faltaba era la llave del equipo nuevo en ese server. Se
> confundió *«no puedo entrar»* con *«el puerto está cerrado»*, que son diagnósticos distintos con
> remediaciones distintas. Verificado el 2026-08-11: acceso OK con `sudo` sin contraseña.
> **Contexto que faltaba:** a axioma-drp le reinstalaron el SO el **2026-08-08** y se rearmó de cero — el
> usuario `axiomacloud` se creó ese día. El acceso de emergencia es `linuxadmin` (sudo con password).
> Un servidor reinstalado 24 h antes del relevamiento explica el hueco, y es justo el tipo de cambio que
> esta cadencia existe para detectar.

> **Nota de alcance.** El DRP §5.2 lista 4 servidores (es previo a la incorporación de `axioma-drp`).
> Esta verificación cubre los **5**, incluyendo el host de DRP. Corregir el DRP §5.2 en la próxima
> revisión trimestral (C7).

## 4. Registro de escaneo de vulnerabilidades (C3 / C5)

> Política y SLA en [G4](./g4-gestion-vulnerabilidades.md). Aquí se asienta **la ejecución**.

| Fecha | Alcance | Ejecutor | Hallazgos | Acción / SLA | Resultado |
|---|---|---|---|---|---|
| 2026-07-20 | `npm audit` — **hub** (backend + frontend) | martin4yo | 61 vulns (3 críticas) → **11** (0 críticas) | Remediado dentro de semver + mitigación `disableEval` para la cadena de `pdfjs`; 57/57 tests en PASS | ✅ **Desplegado y verificado** (H13, sin rollback) |
| 2026-07-23 | `unattended-upgrades` — los 5 servidores (relevamiento, solo lectura) | martin4yo | Operativo en 5/5; los 5 aplicaron upgrades de seguridad ese mismo día | Cobertura de parcheo automático 100%. `Automatic-Reboot=false` → kernel requiere reboot manual en ventana | ✅ **Verificado** |
| **2026-08-09** | **Primer ciclo completo de C3/C5** — `npm audit --package-lock-only` en **42 proyectos** de los 4 servidores alcanzables + `apt list --upgradable` + versiones de runtime. Informe: [`relevamiento-vulnerabilidades-2026-08-09.md`](../relevamiento-vulnerabilidades-2026-08-09.md) | martin4yo | **Producción, solo runtime: 8 críticas · 154 altas · 107 medias** (con devDependencies: 13 · 224 · 140). dev-1: 23 · 343 · 197. Solo 2 de 42 proyectos limpios. Peor caso `clubix/server` (4 críticas, 30 altas, con pasarela de pago viva); `mediflow/backend` sin críticas pero con 23 altas y es la app de la base 🔴 | **73 paquetes crít./altos distintos → 53 con fix compatible (nivel 1), 17 con salto mayor (nivel 2), 3 sin fix upstream (nivel 3)**. 🔴 **Hallazgo de SO: los 4 servidores requieren reboot** — axioma y clubix con 2 kernels de atraso, `libc6` pendiente de activación en los 4. 0 paquetes de seguridad sin descargar: el parcheo automático funciona, lo que falta es la **ventana de reinicio** | ✅ **Relevado, sin remediar.** Solo lectura |
| _pendiente_ | Segundo ciclo mensual completo | — | — | — | ⬜ ~2026-09-09 |

> **Estado del proceso:** las dos entradas de julio eran **ejecuciones reales pero puntuales**. El
> **2026-08-09 se ejecutó el primer ciclo completo** (42 proyectos, 4 servidores, npm + SO). El gap G4 pasa
> a 🟢 cuando acumule **≥2 ciclos mensuales completos** (criterio de
> [G4 §7](./g4-gestion-vulnerabilidades.md)): **falta el segundo, ~2026-09-09**. Riesgo asociado: **R09**.
>
> ⚠️ **Lo que el primer ciclo dejó al descubierto sobre el proceso mismo:** el parcheo automático del SO
> funciona (0 paquetes de seguridad sin descargar en los 4 servidores) pero **ninguno se reinició nunca**,
> así que kernels y `libc6` están instalados y **sin activar** — axioma y clubix con dos versiones de
> atraso. `Automatic-Reboot=false` es una decisión razonable, pero **sin una ventana de reinicio
> programada convierte el parcheo automático en parches que no protegen de nada**. La cadencia que falta
> no es de escaneo sino de **reinicio**: se propone incorporarla como **C11** en la próxima revisión (C6).

**Pendiente de política arrastrado desde G4 §6:** unificar el alcance de `unattended-upgrades` (axioma y
dev-1 incluyen `-updates`; clubix, axiodemo y axioma-drp solo `-security` + ESM). Decidir a propósito el
caso de **dev-1** por ser el repo host de todos los backups. A resolver en la próxima revisión trimestral (C6).

## 5. Registro de auditoría de accesos (C4)

> Lo exige [G1 §3](./g1-politica-seguridad.md). **Al 2026-08-06 no hay una auditoría de accesos
> calendarizada ejecutada como tal.** Lo que sí existe es evidencia dispersa y verificada de la pasada de
> hardening (ver "línea de base" abajo), que sirve como punto de partida pero **no** como cadencia.

**Alcance de cada auditoría (los 5 servidores):**

- [ ] Usuarios del sistema: altas/bajas desde la última revisión; usuarios sin uso activo bloqueados (`passwd -l`).
- [ ] `authorized_keys` de cada cuenta con acceso: ninguna clave no reconocida (control de persistencia — ver [G5 §4.3](./g5-respuesta-incidentes.md)).
- [ ] `sudoers` / membresías de grupos privilegiados: sin ampliaciones no justificadas.
- [ ] Config SSH: `PermitRootLogin no` + `PasswordAuthentication no` siguen vigentes.
- [ ] Roles de PostgreSQL: sin roles huérfanos, 0 hashes `md5`, `pg_hba` sin reglas `0.0.0.0/0`.
- [ ] Usuarios de aplicación: cada app corre bajo su `<app>app` dedicado, sin shell de login.

**Línea de base verificada (evidencia previa, no cadencia):**

| Control | Estado verificado | Fuente |
|---|---|---|
| SSH sin root ni password en los 5 | ✅ | H05 |
| Usuarios de provisioning/terceros bloqueados (`linuxadmin` en axioma-drp) | ⚠ **re-verificar cada vez** — la reinstalación del SO de axioma-drp (2026-08-08) revirtió la mitigación y **reintrodujo la llave ajena desde la imagen del proveedor**. Re-cerrado 2026-08-11 | H10 |
| `pg_hba` a loopback + `scram-sha-256`, 0 hashes `md5` | ✅ | H01 (cerrado 2026-07-22) |
| Apps bajo usuario dedicado | ⚠ **parcial** — desvíos abiertos: `mediflow-backend` (dev-1) corre como **root**; `checkpoint-web` como `axiomacloud`; `axio-ml` como `axiomacloud` (R04) | H04 / H11 |
| **Detección de reinstalación de un server** (host key SSH vs. línea de base) | ✅ **automatizado 2026-08-11** — watchdog en dev-1, cron cada 15 min, alarma crítica validada end-to-end (dispara en 20s). Cubre los 5 servers. **Deja de ser una verificación manual de cadencia**: pasa a control continuo, como C8 | [hardening §12](../hardening.md) |

| Fecha | Ejecutor | Alcance | Hallazgos | Resultado |
|---|---|---|---|---|
| _pendiente_ | — | — | — | ⬜ Primera auditoría formal programada **2026-10-23** |

## 6. Registro de revisiones documentales (C6 / C7)

| Fecha | Documentos revisados | Ejecutor | Cambios | Próxima |
|---|---|---|---|---|
| 2026-07-18 | Dossier — revisión de deltas post-compilación (solo lectura) | martin4yo | Sin cambios de estado en H01–H14; precisiones en CIS 4/5 y §6.3 | — |
| 2026-07-20 | Dossier — actualización de estado tras la pasada de remediación | martin4yo | H03/H07/H08 cerrados; H04 parcial; **H06 reabierto**; H09 bloqueado; §7.1 y G10 nuevos | — |
| 2026-07-22 | Dossier + `hardening.md` + `plan-remediacion-hallazgos.md` — cierre documental | martin4yo | Colaterales elevados al dossier; G7 con sus 2 candidatos de rotación | — |
| 2026-07-23 | Dossier (MD ↔ HTML) + DRP + `nginx-anti-scanner.md` — revisión final pre-entrega | martin4yo | Consolidado final: 10 cerrados · 2 parciales · 1 bloqueado · 1 pendiente. **Versión entregada al auditor externo** | — |
| 2026-07-23 | **Redacción de G1–G5** | martin4yo | Marco de gobierno creado; 5 de 10 gaps redactados | 2026-10-23 |
| 2026-08-06 | **Redacción de G6–G8** | martin4yo | **8 de 10** gaps redactados (cadencias/libro de evidencia, rotación e inventario de secretos, clasificación de datos); pendientes de firma/aprobación. **Faltan G9 (BCP) y G10 (verificación de remediaciones)** | 2026-10-23 |
| 2026-08-09 | Dossier (MD ↔ HTML) + `marco-gobierno.md` — sincronización de G6–G8 | martin4yo | G6/G7/G8 incorporados al §8 del dossier con su estado 🟡 y criterio de paso a 🟢; conteo de gobierno 5 → **8 de 10** en §1/§2/§8; CIS 3 y CIS 5 actualizados. **El dominio Gobierno se mantiene en 🔴**: documento redactado ≠ gap cerrado. Hallazgo elevado: **R13** propuesto (datos 🔴 en dev-1). Corregida esta misma tabla, que declaraba "G6–G10 · 10/10 redactados" | 2026-10-23 |
| 2026-08-09 | **C10 — inventario de secretos** (`infra-secrets`, solo nombres de variable, sin descifrar) + G7, G8, G3, dossier MD↔HTML y README del repo de secretos | martin4yo | **Primera ejecución de C10.** Inventario desagregado (16 `.env`, no 15); 3 clases de secreto nuevas (S15 cifrado de datos, S16 cuentas de SO, S17 proveedores de IA); S12 corregido y S18 separado; **4 riesgos nuevos en G3 (R13–R16)**; G8 ampliado con 2 canales de datos no contemplados; semáforo de secretos 🟢 → 🟡. **Evento de seguridad:** exposición de la contraseña de SO `axiomacloud` → rotación inmediata pendiente (G7/A6) | **2027-02-09** (semestral) |
| **2026-08-09** | 🔴 **C10 — verificación de custodia de la clave age: FALLA.** Intento de restaurar el acceso desde un equipo nuevo | martin4yo | **La clave age no existe** ni en el equipo ni en el gestor de contraseñas. Repo de secretos ilegible → **R17** (materializado). G7 §2 la declaraba "✅ Vigente" sin evidencia. Bajan a 🔴 los dominios **Gestión de secretos** y **DRP** del dossier. **Esta es la primera vez que una cadencia de este documento se ejecuta y encuentra un control roto** — y muestra por qué C10 no podía seguir sin corridas | **inmediata** (A9) |
| **2026-08-09** | **C4 — auditoría de accesos (primera ejecución) + S10** — `authorized_keys`, claves privadas y `sshd -T` en los 4 servers alcanzables | martin4yo | 🔴 **3 hallazgos que la documentación no reflejaba:** 48 llaves `@donweb.com` en la cuenta con `sudo` de dev-1 con **uso confirmado** (R20); ~43 llaves de donweb en `root` de axioma/clubix/dev-1, inertes por `PermitRootLogin no` (R19); archivo `99-temp-password` latente en los 4 (R18). **S10 cerrado** con inventario real de claves de deploy | ⬜ **2026-11-09** (trimestral) |
| **2026-08-12** | 🎯 **Simulacro de recuperación de aplicaciones** (C7 — revisión del DRP, ejecutada como prueba real) | martin4yo | **hub y alvera recuperadas y accesibles en axioma-drp**, con login funcional. Se cierra el gap del DRP de aplicación, redactado desde 2026-07-18 y **nunca ejecutado**. 9 hallazgos, **ninguno deducible leyendo**: locale faltante, ecosystem divergente, ecosystem ausente, config de build sin versionar y **R21 (80/443 filtrados por el proveedor)**. 27 archivos de configuración versionados en `config/axioma/` | **2026-11-12** |
| **2026-08-12** | ✅ **Verificación de legibilidad de datos cifrados** (BC-B de G9 / R15) — ejecutada dentro del simulacro | martin4yo | **Los campos cifrados de `mediflow_db` se leen en claro** tras el restore completo. Prueba que la `ENCRYPTION_MASTER_KEY` respaldada es la correcta. **R15 → 🟢** | ⬜ **Incorporar al drill mensual C1** (A3 de G9) |
| _pendiente_ | Revisión trimestral completa — G1–G10 + G3 + DRP | — | — | ⬜ **2026-10-23** |

**Contenido de la revisión trimestral (C6):**

- [ ] Releer G1–G10; actualizar lo que cambió en la infraestructura.
- [ ] Revisar el [registro de riesgos G3](./g3-registro-riesgos.md): reevaluar P×I, cerrar los mitigados, agregar los nuevos.
- [ ] Confirmar las **aprobaciones de riesgos aceptados** pendientes de firma de la AN (R03, R05, R12).
- [ ] Revisar el DRP (C7) — incluida la corrección del §5.2 a 5 servidores.
- [ ] Actualizar el §8 del dossier con el estado de cada gap.
- [ ] Verificar que las cadencias de §1 se cumplieron; registrar y explicar las omitidas.

## 7. Registro de ejercicios (C9)

| Fecha | Tipo | Participantes | Escenario | Resultado / lecciones |
|---|---|---|---|---|
| _pendiente_ | Incidente simulado | RT + BT | A definir | ⬜ Primer ejercicio anual sin fecha asignada — ver [G5 §8](./g5-respuesta-incidentes.md) |

> El ejercicio sirve a dos fines: valida el plan de respuesta a incidentes **y** constituye la primera
> co-ejecución del BT, que es lo que cierra **R08** (bus factor de ejecución, 🔴 Alto en [G3](./g3-registro-riesgos.md)).

## 8. Qué hacer cuando una cadencia se omite

Una cadencia omitida **no se borra ni se reescribe**: se registra como omitida, con motivo y plan de recuperación.

1. Asentar la fila con resultado **⚠ Omitido** y el motivo.
2. Reprogramar dentro del ciclo siguiente.
3. Si se omiten **dos ciclos consecutivos** de una misma actividad, se abre un **riesgo** en
   [G3](./g3-registro-riesgos.md) — la cadencia dejó de ser un control efectivo.
4. El conteo de ciclos consecutivos (para R11 y para el cierre de G4) **se reinicia**.

## 9. Gobierno

- Este documento se **revisa cada trimestre** (próxima **2026-10-23**) junto con el resto del marco.
- Es el **libro de evidencia** del marco: los gaps G4 y G6, y el riesgo R11, se cierran contra las tablas
  de §2–§7, no contra declaraciones de intención.
- **Estado del gap G6 al 2026-08-06:** 🟡 — cadencias consolidadas y calendario anclado, pero el registro
  de ejecución recién arranca (1 ciclo de drills; C2, C4 y C9 sin ejecuciones). Pasa a 🟢 cuando C1, C2 y
  C3 acumulen **≥3 ciclos mensuales consecutivos** y se haya ejecutado la primera auditoría de accesos (C4).
- Riesgos asociados: **R11** (cadencia de drills) y **R08** (co-ejecución del BT) en [G3](./g3-registro-riesgos.md).
