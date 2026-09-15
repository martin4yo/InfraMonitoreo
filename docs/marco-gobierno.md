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
| **G6** | [Cadencia y registro de revisiones periódicas](./gobierno/g6-revisiones-periodicas.md) | ✅ v1 redactada — 🟡 **C2, C4 y C10 ejecutadas por primera vez el 2026-08-09** |
| **G7** | [Política de rotación e inventario de secretos](./gobierno/g7-rotacion-secretos.md) | ✅ v1 redactada — 🔴 **la clave age se perdió** (§7.1); repo reconstituido, custodia pendiente |
| **G8** | [Clasificación de datos y cumplimiento](./gobierno/g8-clasificacion-datos.md) | ✅ v1 redactada — 🔴 **el proveedor de hosting es encargado de tratamiento** (§4.2), sin contrato |
| **G9** | [Plan de continuidad de negocio (BCP)](./gobierno/g9-continuidad-negocio.md) | ✅ v1 redactada — 🟡 kit de 11 elementos · **BC-A probado end-to-end el 08-12** |
| **G10** | [Procedimiento de verificación de remediaciones](./gobierno/g10-verificacion-remediaciones.md) | ✅ v1 redactada — 🟡 sin cierres ejecutados con la checklist |

> **Marco completo — 10 de 10 documentos redactados (2026-08-11).** Ninguno está en 🟢: los diez son
> políticas escritas a la espera de evidencia de ejecución. Es un hito de cobertura documental, **no de
> madurez de control** — y la distinción importa, porque el 2026-08-09 mostró que un documento puede
> describir con precisión algo que dejó de ser cierto.

> A medida que cada documento se redacta, esta tabla y el §8 del dossier se actualizan. Los links de
> los gaps aún pendientes se activan cuando su archivo se crea.
>
> **Cómo leer el estado.** ✅ se refiere al **documento** (existe una v1 redactada); el semáforo que lo
> acompaña se refiere al **gap** (🟡 = política escrita pero sin evidencia de ejecución suficiente ·
> 🟢 = cerrado). Un documento redactado no cierra su gap por sí solo: cada uno declara en su §Gobierno
> qué evidencia concreta lo lleva a 🟢. G6 es el libro de evidencia donde esa ejecución se asienta.
>
> ⚠️ **2026-08-09 — el marco se contrastó por primera vez contra los servidores.** Hasta esa fecha, los
> ocho documentos se habían redactado **leyendo el repositorio**. Al ejecutar las cadencias C2, C4 y C10
> contra la infraestructura real aparecieron cinco hallazgos y **tres afirmaciones documentadas que habían
> dejado de ser ciertas** (ver §7.2 del [dossier](./dossier-auditoria-seguridad.md)). G7 y G8 bajaron a 🔴.
>
> **La lección vale para todo el marco:** un documento de gobierno describe lo que alguien escribió, no lo
> que está pasando. Lo que convierte una política en control es la **cadencia que la contrasta contra la
> realidad** — y la evidencia de haberla corrido.
