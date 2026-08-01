# Marco de Gobierno de Seguridad — Infraestructura Axioma

> **Propósito.** Índice del conjunto de documentos de gobierno que cubren los **gaps G1–G10**
> identificados en el §8 del [dossier de auditoría de seguridad](./dossier-auditoria-seguridad.md).
> Son los artefactos de gobierno que un auditor externo pide y que, al compilar el dossier, **no
> existían como documento formal**. No son fallas técnicas: las prácticas ya estaban en su mayoría
> implementadas y dispersas en los documentos técnicos del repo; lo que faltaba era **consolidarlas
> en políticas aprobadas** con alcance, responsables y cadencia explícitos.
>
> Cada gap vive en su propio documento bajo [`docs/gobierno/`](./gobierno/). Este archivo es la
> portada: se lee de arriba hacia abajo y enlaza a cada uno.
>
> **Lenguaje normativo** (heredado del [estándar de despliegue](./estandar-despliegue.md)):
> **DEBE** = obligatorio · **DEBERÍA** = recomendado salvo justificación registrada · **PUEDE** = opcional.

## Responsables

| Rol | Persona | Contacto |
|---|---|---|
| Responsable técnico | — | mfourgeaux@axiomacloud.com |
| Backup técnico | Rodrigo Naranjo | rnaranjo@axiomacloud.com |

## Documentos de gobierno

| Gap | Documento | Estado |
|---|---|---|
| **G1** | [Política de seguridad de la información](./gobierno/g1-politica-seguridad.md) | ✅ v1 redactada — firma pendiente |
| **G2** | [Matriz de roles y responsabilidades (RACI)](./gobierno/g2-roles-responsabilidades.md) | ✅ v1 redactada |
| **G3** | [Registro de riesgos](./gobierno/g3-registro-riesgos.md) | ✅ v1 redactada |
| **G4** | [Política de gestión de vulnerabilidades y parches](./gobierno/g4-gestion-vulnerabilidades.md) | ✅ v1 redactada |
| **G5** | [Plan de respuesta a incidentes (IR)](./gobierno/g5-respuesta-incidentes.md) | ✅ v1 redactada |
| **G6** | Cadencia y registro de revisiones periódicas | ⬜ pendiente |
| **G7** | Política de rotación e inventario de secretos | ⬜ pendiente |
| **G8** | Clasificación de datos y cumplimiento | ⬜ pendiente |
| **G9** | Continuidad de negocio (BCP) | ⬜ pendiente |
| **G10** | Procedimiento de verificación de remediaciones | ⬜ pendiente |

> A medida que cada documento se redacta, esta tabla y el §8 del dossier se actualizan. Los links de
> los gaps aún pendientes se activan cuando su archivo se crea.
