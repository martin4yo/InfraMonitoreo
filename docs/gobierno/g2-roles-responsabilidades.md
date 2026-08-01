# G2 — Matriz de Roles y Responsabilidades (RACI)

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G2** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
>
> **Estado:** v1 — redacción inicial (2026-07-23).
>
> **Hallazgo que motiva este documento.** Al compilar el dossier existía un **responsable técnico
> único** para todos los dominios y todos los hallazgos, con **bus factor = 1** y sin segregación de
> funciones ni escalamiento definido. Este documento formaliza los roles, designa un **backup técnico**
> y deja registrado el riesgo residual con su plan de mitigación.

## 1. Personas y roles

| Rol | Persona | Contacto | Alcance |
|---|---|---|---|
| **Responsable técnico (RT)** | — | mfourgeaux@axiomacloud.com | Operación, seguridad y decisiones técnicas de los 5 servidores y sus apps. Owner por defecto de los hallazgos. |
| **Backup técnico (BT)** | Rodrigo Naranjo | rnaranjo@axiomacloud.com | Suplente del RT: continuidad de operación y respuesta ante indisponibilidad del RT. |
| **Aprobación de negocio (AN)** | Darío Cukier | dcukier@dotgestion.com | Aceptación de riesgos, presupuesto y decisiones con impacto de negocio. |
| **Proveedor de monitoreo (tercero)** | dattaweb | _(contrato)_ | Monitoreo SNMP contratado. Acceso acotado por `com2sec` a 2 IPs; fuera del control operativo directo. |

> **Nota.** El RT y el BT tienen acceso administrativo a los 5 servidores (acceso del BT ya provisto).
> La AN no requiere acceso técnico a los servers (rol de aprobación, no de operación). No existe hoy
> ninguna otra persona con acceso administrativo. Los usuarios de provisioning/terceros (`linuxadmin`
> en axioma-drp) están bloqueados (`passwd -l`) y solo se usan para emergencia por clave (H10).

## 2. Definición RACI

- **R (Responsible)** — ejecuta la tarea.
- **A (Accountable)** — responde por el resultado; hay **un solo A** por fila.
- **C (Consulted)** — se le consulta antes de actuar.
- **I (Informed)** — se le informa el resultado.

## 3. Matriz por dominio

| Dominio | RT (mfourgeaux) | BT (R. Naranjo) | Aprob. negocio | Tercero |
|---|---|---|---|---|
| Seguridad / Hardening (SSH, firewall, pg_hba, secretos) | **A/R** | C | I | — |
| Monitoreo (Netdata, colectores, alarmas) | **A/R** | C | I | — |
| Backup (pgBackRest dual-repo, retención) | **A/R** | C | I | — |
| DRP / recuperación (drills, restore) | **A/R** | **R** (co-ejecuta drills) | I | — |
| Gestión de secretos (SOPS+age, rotación) | **A/R** | C | I | — |
| Estandarización de despliegues | **A/R** | C | I | — |
| Gestión de vulnerabilidades y parches ([G4](./g4-gestion-vulnerabilidades.md)) | **A/R** | C | I | — |
| Respuesta a incidentes ([G5](./g5-respuesta-incidentes.md)) | **A/R** | **R** (contención/suplencia) | C | I |
| **Aceptación de riesgos** ([G3](./g3-registro-riesgos.md)) | R (propone) | I | **A** (aprueba) | — |
| Monitoreo SNMP contratado | A | I | I | **R** (dattaweb) |
| Relación contractual con proveedores (R2, VPS, dattaweb) | R | I | **A** | I |

> La **Aprobación de negocio** (AN) queda a cargo de Darío Cukier: es el `A` de la aceptación de
> riesgos y de las decisiones con impacto de negocio o gasto.

## 4. Riesgo residual y mitigación

**Bus factor.** Con la designación del BT, el bus factor pasa de **1 a 2** para la continuidad
operativa. Con la designación de la AN (Darío Cukier), la aceptación de riesgos y las decisiones de
negocio tienen ahora un aprobador formal distinto del ejecutor técnico —
**segregación de funciones a nivel de aprobación**. Persiste una brecha:

1. **Sin segregación de funciones plena a nivel de ejecución.** El RT concentra ejecución y
   responsabilidad técnica de casi todos los dominios. **Mitigación:** el BT ya tiene **acceso
   provisto y verificado a los 5 servidores** (2026-07-23) y debe participar en la ejecución de al
   menos DRP e incidentes (filas con `R` doble). *Acción pendiente:* registrar la **primera
   co-ejecución** del BT (próximo drill de restore o incidente simulado) para pasar el bus factor 2 de
   declarativo a probado.

Esta acción se traquea como riesgo en [G3](./g3-registro-riesgos.md) y se revisa en la cadencia de
[G6](./g6-revisiones-periodicas.md).

## 5. Escalamiento

| Situación | Primer contacto | Escala a | Notas |
|---|---|---|---|
| Incidente de seguridad / caída | RT | BT (si RT no responde) | Ver [plan de respuesta a incidentes — G5](./g5-respuesta-incidentes.md). |
| RT indisponible (vacaciones, baja) | BT | AN (D. Cukier) | El BT asume operación; decisiones de negocio esperan o escalan a la AN. |
| Decisión con impacto de negocio / gasto | RT | AN (D. Cukier) | La AN aprueba; se registra en [G3](./g3-registro-riesgos.md). |
| Dependencia de tercero (dattaweb, R2, VPS) | RT | AN (D. Cukier) | Coordinación contractual (ej. H09: cambiar community SNMP requiere coordinar con dattaweb). |

## 6. Revisión

Esta matriz se revisa junto con la [política de seguridad](./g1-politica-seguridad.md) (cadencia
trimestral, próxima **2026-10-23**) y cada vez que cambie la composición de roles.
