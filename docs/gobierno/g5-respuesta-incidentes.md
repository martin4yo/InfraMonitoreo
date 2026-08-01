# G5 — Plan de Respuesta a Incidentes (IR)

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G5** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
> Alineado con **CIS Control 17** (Gestión de respuesta a incidentes) y el ciclo NIST SP 800-61.
>
> **Estado:** v1 — redacción inicial (2026-07-23).
>
> **Relación con el DRP.** El [DRP](../disaster-recovery-plan.md) cubre la **recuperación técnica ante
> desastres de datos/infraestructura** (corrupción, pérdida de host, pérdida de repo). Este plan es más
> amplio: cubre **cualquier incidente de seguridad** — incluyendo intrusión, credencial filtrada,
> escaneo/ataque activo, malware o mal uso — con su ciclo completo de detección → contención →
> erradicación → recuperación → lecciones aprendidas. Cuando un incidente de seguridad **también** es un
> desastre de datos, la fase de recuperación (§5) invoca el runbook del DRP correspondiente.

## 1. Roles en un incidente

| Rol | Persona | Responsabilidad en el incidente |
|---|---|---|
| **Coordinador de incidente (IC)** | RT — mfourgeaux@axiomacloud.com | Declara, clasifica, dirige la respuesta y decide el cierre |
| **Suplente / co-ejecución** | BT — Rodrigo Naranjo (rnaranjo@axiomacloud.com) | Asume como IC si el RT no responde; co-ejecuta contención/recuperación |
| **Aprobación de negocio** | AN — Darío Cukier (dcukier@dotgestion.com) | Se le informa/consulta ante impacto de negocio, comunicación a clientes o decisiones de gasto/legal |
| **Terceros** | dattaweb (SNMP), Cloudflare (R2), proveedor VPS | Se contactan si el incidente los involucra |

Escalamiento y suplencia: ver [G2 §5](./g2-roles-responsabilidades.md#5-escalamiento).

## 2. Clasificación de severidad

| Sev | Definición | Ejemplos | Objetivo de respuesta inicial |
|---|---|---|---|
| **SEV-1 Crítico** | Compromiso confirmado o servicio caído con impacto a datos/clientes | Intrusión con acceso a datos, ransomware, exfiltración, DB productiva caída | **Respuesta inmediata** (< 1 h), IC activa de inmediato |
| **SEV-2 Alto** | Amenaza activa sin compromiso confirmado, o degradación seria | Credencial filtrada detectada, ataque de fuerza bruta sostenido, vuln crítica explotable expuesta | **< 4 h** |
| **SEV-3 Medio** | Evento de seguridad sin impacto inmediato | Escaneo/probing anómalo, hallazgo de config riesgosa, intento de acceso bloqueado | **< 24 h** |
| **SEV-4 Bajo** | Evento menor o falso positivo a confirmar | Alerta aislada de Netdata, anomalía puntual | Próximo ciclo / revisión |

## 3. Detección

Fuentes de detección disponibles hoy:

- **Netdata Cloud** (claimed en los 5): alarmas custom + notificaciones **Telegram + Email**. Alarmas de
  antigüedad de backup, estado de stanzas, recursos, httpcheck de apps.
- **Logs:** `auth.log`/`journalctl` (accesos SSH), logs de PostgreSQL (auth failures), logs de nginx
  (patrones de escaneo — mitigados por `block-scanners`), logs de PM2.
- **Firewall:** ufw default-deny (los intentos hacia puertos cerrados no llegan).
- **Reporte humano:** usuario/cliente que reporta comportamiento anómalo.

> **Gap conocido:** no hay SIEM ni agregación central de logs. La detección depende de las alarmas de
> Netdata y de la revisión de logs. Mejora futura registrada en [G3](./g3-registro-riesgos.md) / [G6](./g6-revisiones-periodicas.md).

## 4. Flujo de respuesta

### 4.1 Detección y declaración
1. Identificar el evento (alarma, log, reporte).
2. El IC **confirma** que es un incidente real (no falso positivo) y **registra el timestamp de detección**.
3. **Clasificar la severidad** (§2) y declarar el incidente.
4. Abrir el **registro del incidente** (§7, plantilla) — a partir de acá se documenta todo con timestamps.

### 4.2 Contención
Objetivo: detener la propagación sin destruir evidencia.
- **Contención inmediata** (SEV-1/2): aislar el activo afectado — bloquear IP en ufw, deshabilitar el
  usuario/credencial comprometido (`passwd -l`, revocar clave SSH, rotar el secreto), detener el
  servicio afectado si es necesario.
- **Preservar evidencia** antes de limpiar: copiar logs relevantes, `pg_hba`/config afectada, timestamps.
- Comunicar según §6.

### 4.3 Erradicación
- Eliminar la causa raíz: cerrar la vulnerabilidad ([G4](./g4-gestion-vulnerabilidades.md)), remover
  accesos no autorizados, rotar **todos** los secretos potencialmente expuestos ([G7](./g7-rotacion-secretos.md)).
- Verificar que no queden persistencias (cron/systemd unit ajenos, `authorized_keys` no reconocidas,
  usuarios nuevos).

### 4.4 Recuperación
- Restaurar el servicio a operación normal. Si hubo pérdida/corrupción de datos, **invocar el runbook del
  [DRP](../disaster-recovery-plan.md)** correspondiente (escenarios A–D) y su checklist post-restore (§6 del DRP).
- Verificar por el criterio de cierre formal ([G10](./g10-verificacion-remediaciones.md)): health/login/
  funciones críticas OK, control negativo, sin regresión.
- Monitoreo reforzado post-recuperación durante un período de observación.

### 4.5 Lecciones aprendidas
- Post-mortem obligatorio para SEV-1 y SEV-2 (recomendado para SEV-3), dentro de los **5 días hábiles**.
- Sin culpa (blameless): foco en la causa raíz y en el control que faltó, no en la persona.
- Las acciones correctivas se convierten en **riesgos/tareas** en [G3](./g3-registro-riesgos.md) y, si
  aplica, en hallazgos del dossier (§7).

## 5. Comunicación

| Audiencia | Cuándo | Canal | Responsable |
|---|---|---|---|
| IC ↔ BT (equipo técnico) | Inmediato al declarar | Telegram / teléfono | IC |
| AN (Darío Cukier) | SEV-1/2, o si hay impacto a clientes/negocio | Email + teléfono | IC |
| Cliente/usuario afectado | Cuando hay impacto en su servicio | Email / canal acordado | IC (con OK de la AN si el mensaje tiene implicancia comercial/legal) |
| Terceros (dattaweb/Cloudflare/VPS) | Si el incidente los involucra | Canal de soporte del proveedor | IC |

- Mantener un canal abierto durante toda la respuesta (heredado del DRP §3).
- **Consideración regulatoria:** si el incidente involucra **datos personales o de salud** (Ley 25.326),
  evaluar con la AN la obligación de notificación conforme a la normativa aplicable — ver [G8](./g8-clasificacion-datos.md).

## 6. Contactos de emergencia

| Contacto | Rol | Vía |
|---|---|---|
| mfourgeaux@axiomacloud.com | IC / RT | Email · Telegram |
| Rodrigo Naranjo — rnaranjo@axiomacloud.com | BT / suplente | Email |
| Darío Cukier — dcukier@dotgestion.com | AN | Email |
| dattaweb | Monitoreo SNMP contratado | Canal de soporte contractual |
| Cloudflare / proveedor VPS | R2 / hosting | Panel + soporte |

## 7. Plantilla de registro de incidente / post-mortem

```
INCIDENTE #<n> — <título corto>
Severidad: SEV-<1-4>
Coordinador (IC): <nombre>

CRONOLOGÍA (timestamps)
- Detección:        <fecha/hora> — fuente: <alarma/log/reporte>
- Declaración:      <fecha/hora>
- Contención:       <fecha/hora> — acción: <...>
- Erradicación:     <fecha/hora>
- Recuperación:     <fecha/hora> — RTO real: <...>
- Cierre:           <fecha/hora>

DESCRIPCIÓN
- Qué pasó:
- Activos afectados (servers/apps/datos):
- Datos involucrados (¿PII/salud/financiero? → §8 / Ley 25.326):

CAUSA RAÍZ
- Causa técnica:
- Control que faltó o falló:

ACCIONES
- Contención aplicada:
- Erradicación:
- Recuperación (¿se invocó el DRP? escenario):
- Secretos rotados (§ G7):

COMUNICACIÓN
- A quién / cuándo / qué se dijo:
- ¿Notificación regulatoria requerida? (Ley 25.326):

LECCIONES APRENDIDAS
- Qué mejorar (control/proceso):
- Acciones correctivas → riesgos/tareas en G3:
```

## 8. Gobierno

- Este plan se **revisa cada trimestre** (próxima **2026-10-23**) en la cadencia de [G6](./g6-revisiones-periodicas.md).
- **DEBERÍA** ejercitarse con un **incidente simulado** al menos una vez al año (sirve además como la
  primera co-ejecución del BT — cierra R08 de [G3](./g3-registro-riesgos.md)).
- Riesgo asociado: **R10** en [G3](./g3-registro-riesgos.md).
