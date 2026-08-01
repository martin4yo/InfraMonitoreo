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

- **Total:** 12 riesgos operativos/gobierno + 4 escenarios de desastre.
- **🔴 Alto:** R08 (bus factor de ejecución), RD-A (corrupción de datos). Son los de atención prioritaria.
- **🟡 Medio:** R02, R06, R09, R10, R11, R12, RD-B, RD-C, RD-D.
- **🟢 Bajo:** R01, R03, R04, R05, R07.
- **Aceptados (requieren firma AN):** R03, R05, R12.

## 5. Gobierno del registro

- El registro se **revisa cada trimestre** (próxima **2026-10-23**) junto con la
  [política de seguridad](./g1-politica-seguridad.md) y en la cadencia de [G6](./g6-revisiones-periodicas.md).
- Todo **riesgo aceptado** debe llevar la aprobación formal de la **AN** (Darío Cukier) con fecha y
  fecha de revisión. Aprobaciones pendientes de firma: R03, R05, R12.
- Cuando un hallazgo del dossier (§7) se cierra, su riesgo asociado se marca **cerrado** aquí con la
  fecha; cuando aparece uno nuevo, se agrega una fila.
