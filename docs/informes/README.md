# Informes de prueba de continuidad (para clientes)

Un informe por aplicación y por prueba de recuperación. Son la **capa de evidencia para el cliente** del
[programa de simulacros](../drp-programa-simulacros.md#5-evidencia-y-verificación-por-terceros): resultado,
RPO/RTO medidos contra objetivo, verificaciones, observaciones y evidencia verificable por terceros.

- **Plantilla:** [`plantilla-informe-prueba-continuidad.md`](./plantilla-informe-prueba-continuidad.md)
- **Reglas de redacción:** sin IPs, nombres de servidores internos, nombres de secretos ni detalle explotable
  de un hallazgo; nunca datos personales. El detalle técnico vive en el runbook de cada app.
- **Antes de enviar:** completar cliente y firmas, verificar la evidencia de Certificate Transparency y
  exportar a PDF.

| N.º | Fecha | Aplicación | Resultado | Estado del informe |
|---|---|---|---|---|
| IPC-2026-001 | 2026-09-15 | [Alvera](./2026-09-15-alvera.md) | ✅ Superada | 📝 Borrador — falta cliente, aprobación y firmas |
| IPC-2026-002 | 2026-09-15 | [Checkpoint](./2026-09-15-checkpoint.md) | ⚠️ Superada con observaciones | 📝 Borrador — falta cliente, aprobación y firmas |
