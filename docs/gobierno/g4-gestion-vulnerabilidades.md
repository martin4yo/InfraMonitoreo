# G4 — Política de Gestión de Vulnerabilidades y Parches

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G4** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
> Alineada con **CIS Control 7** (Gestión continua de vulnerabilidades).
>
> **Estado:** v1 — redacción inicial (2026-07-23).
>
> **Hallazgo que motiva este documento.** La remediación de vulnerabilidades de hub (H13) se ejecutó,
> validó y **desplegó a producción** el 2026-07-20 (**61 → 11 vulnerabilidades, críticas 3 → 0**, 57/57
> tests en PASS, sin rollback). Pero fue una acción **reactiva y única**: no existe escaneo
> calendarizado, umbrales de severidad para actuar ni SLA de parcheo. Esta política formaliza el
> **proceso periódico** que faltaba.

## 1. Alcance

Aplica a todos los componentes de software de la infraestructura Axioma:

| Capa | Componente | Herramienta de escaneo |
|---|---|---|
| Sistema operativo | Ubuntu/Debian de los 5 servidores | `apt`/`unattended-upgrades`, `apt list --upgradable` |
| Motor de base de datos | PostgreSQL | versión vs. avisos de seguridad de PostgreSQL |
| Runtime | Node.js + PM2 | versión LTS soportada vs. EOL |
| Dependencias de apps | paquetes npm (backend + frontend de cada app propia) | `npm audit` |
| Servidor web | nginx | versión vs. CVE + config (headers, `block-scanners`) |
| Backup | pgBackRest | versión vs. avisos |

**Fuera de alcance directo:** productos de tercero (evolution-api, monitoreo SNMP de dattaweb), que se
gestionan por su canal de soporte; se registra su versión pero no se parchea localmente.

## 2. Clasificación de severidad

Se adopta la severidad reportada por la fuente (CVSS v3.1 base score / severidad de `npm audit`):

| Severidad | CVSS | Criterio |
|---|---|---|
| 🔴 Crítica | 9.0–10.0 | Explotable remotamente, sin autenticación, con impacto alto |
| 🟠 Alta | 7.0–8.9 | Impacto alto o explotación probable |
| 🟡 Media | 4.0–6.9 | Impacto o explotabilidad moderados |
| 🟢 Baja | 0.1–3.9 | Impacto limitado |

**Contexto de explotabilidad.** La severidad nominal se ajusta por explotabilidad real: una vulnerabilidad
en una dependencia **declarada pero nunca importada** (como el AWS SDK de hub) o sin cadena de ataque
alcanzable puede degradarse, dejando **registro escrito** de la justificación. Ejemplo real: la cadena de
`pdfjs` en hub se cerró con la mitigación `disableEval` porque el único vector real era el parseo de PDF
de facturas del portal de proveedores (H13).

## 3. Cadencia de escaneo

| Componente | Frecuencia | Responsable |
|---|---|---|
| `npm audit` de apps propias | **Mensual** + en cada despliegue | RT |
| Paquetes del SO (`apt list --upgradable`) | **Mensual** | RT |
| Versión de PostgreSQL / Node / nginx / pgBackRest vs. EOL y avisos | **Trimestral** | RT |
| Escaneo ad-hoc | Ante un aviso de seguridad relevante (CVE crítico publicado) | RT |

- El escaneo mensual se registra (fecha, componente, hallazgos, severidades) — la evidencia de ejecución
  se lleva en [G6](./g6-revisiones-periodicas.md).
- Coincide con la ventana del restore drill mensual (~día 19) para consolidar el mantenimiento en un ciclo.

## 4. SLA de parcheo (tiempo objetivo de remediación)

Contado desde la **detección** (escaneo o publicación del aviso) hasta el **despliegue verificado** en
producción:

| Severidad | SLA de remediación | Notas |
|---|---|---|
| 🔴 Crítica | **72 horas** | Si no hay parche, aplicar mitigación temporal (config, deshabilitar el vector) y registrar |
| 🟠 Alta | **7 días** | |
| 🟡 Media | **30 días** | Puede agruparse con el ciclo mensual |
| 🟢 Baja | **Próximo ciclo** | O aceptar el riesgo con registro en [G3](./g3-registro-riesgos.md) |

- Si un parche **no puede aplicarse dentro del SLA** (rompe el build, requiere ventana, depende de un
  tercero), se registra como **excepción** en el [registro de riesgos — G3](./g3-registro-riesgos.md) con
  mitigación temporal, owner y fecha de revisión, y aprobación de la **AN** si se acepta el riesgo.

## 5. Procedimiento de remediación

Basado en el procedimiento **ya ejecutado y validado** en H13:

1. **Escanear** (`npm audit`, `apt`, versión vs. avisos) y clasificar por severidad.
2. **Evaluar explotabilidad real** — descartar/ajustar hallazgos sin cadena de ataque alcanzable
   (dependencia no importada, vector inaccesible), con justificación escrita.
3. **Remediar dentro de semver primero** (`npm audit fix` sin `--force`); evaluar `--force` o major solo
   con validación reforzada.
4. **Verificar el build y los tests** — no desplegar sin la suite en PASS (H13: 57/57 tests).
5. **Desplegar** a producción con backup/rollback preparado.
6. **Verificar en vivo** según el criterio de cierre formal ([G10](./g10-verificacion-remediaciones.md)):
   health/login/funciones críticas OK, escaneo post-despliegue con 0 críticas, sin regresión.
7. **Registrar** el resultado (antes/después, severidades, tests, evidencia) en el registro de hallazgos
   del dossier (§7) y actualizar [G3](./g3-registro-riesgos.md) si corresponde.

## 6. Actualizaciones automáticas del SO

**Estado (relevado 2026-07-23, solo lectura): operativo en los 5 servidores.** `unattended-upgrades`
está instalado y activo (flags `Update-Package-Lists=1` + `Unattended-Upgrade=1`, disparado por
`apt-daily-upgrade.timer`); los 5 aplicaron upgrades de seguridad del SO **el mismo día del relevamiento**.
Cobertura de parcheo automático de seguridad al 100%.

- **`Automatic-Reboot = false`** en los 5 (bien para producción). Implica que un upgrade de **kernel** queda
  pendiente de **reinicio manual** en ventana coordinada con la AN si hay impacto de disponibilidad.
- **Inconsistencia de alcance a decidir (no bloqueante):** axioma y dev-1 incluyen además el origen
  `-updates` (parchean bugfixes no-seguridad, más agresivo); clubix, axiodemo y axioma-drp se limitan a
  `-security` + ESM. **Pendiente de política:** unificar el criterio, decidiendo a propósito el caso de
  dev-1 (repo host de todos los backups). Homogeneizar el alcance es un cambio de config (invasivo) que se
  planifica aparte.

## 7. Gobierno

- Esta política se **revisa cada trimestre** (próxima **2026-10-23**) en la cadencia de
  [G6](./g6-revisiones-periodicas.md).
- El estado del gap G4 en el dossier pasa a 🟡 (remediación puntual cerrada) → 🟢 cuando el proceso
  periódico acumule **al menos dos ciclos mensuales ejecutados y registrados**.
- Riesgo asociado: **R09** en [G3](./g3-registro-riesgos.md).
