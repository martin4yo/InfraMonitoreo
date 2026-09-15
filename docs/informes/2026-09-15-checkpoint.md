# Informe de prueba de continuidad — Checkpoint

<!-- Borrador generado desde docs/drp-checkpoint-en-drp.md. Completar cliente, aprobación y firmas; revisar
     la sección 5 antes de enviar. Detalle técnico interno: docs/drp-checkpoint-en-drp.md -->

| | |
|---|---|
| **Informe N.º** | IPC-2026-002 |
| **Aplicación** | Checkpoint — Gestión de RRHH y control de presencia |
| **Cliente** | *[a completar]* |
| **Fecha de la prueba** | 2026-09-15, 08:37–09:18 (hora de Argentina) · verificación de usuario por la tarde |
| **Tipo de prueba** | Nivel 2 — recuperación completa de la aplicación en infraestructura alternativa |
| **Ejecutó** | *[a completar]*, Responsable Técnico |
| **Revisó / aprobó** | *[a completar]* |
| **Resultado** | ⚠️ **SUPERADA CON OBSERVACIONES** — un archivo adjunto no pudo recuperarse (sección 5, obs. 2) |

---

## 1. Resumen

Se simuló la pérdida total del servidor donde opera Checkpoint. La aplicación se recuperó en un servidor de
otro proveedor con **2 minutos de pérdida de datos** y **unos 20 minutos de trabajo efectivo**. Los datos
biométricos cifrados se verificaron legibles y un usuario real ingresó a la aplicación recuperada. **Los
archivos subidos por usuarios no tenían respaldo**: el único documento existente no se pudo recuperar.

| Indicador | Objetivo *(propuesto, pendiente de acuerdo)* | Medido | ¿Cumple? |
|---|---|---|---|
| **RPO** — datos perdidos | ≤ 15 min | **≈ 2 min** | ✅ |
| **RTO** — tiempo hasta servicio restablecido | ≤ 4 h | **≈ 20 min** de trabajo efectivo · 41 min de reloj | ✅ |
| Datos biométricos cifrados legibles tras recuperar | 100 % | **2 de 2** registros (9 plantillas faciales) | ✅ |
| Archivos adjuntos recuperados | 100 % | **0 de 1** — sin respaldo | ❌ |
| Ingreso real de un usuario | Sí | **Sí** | ✅ |

## 2. Escenario simulado

Pérdida total del servidor de origen. Recuperación en un servidor de recuperación **de otro proveedor**, con
fuentes independientes del servidor perdido:

| Componente | Fuente usada |
|---|---|
| Base de datos | Respaldo continuo, **cifrado**, almacenado fuera del proveedor principal |
| Código | Repositorio versionado — **la misma versión que operaba en el servidor de origen** |
| Configuración y credenciales | Custodia cifrada independiente de los servidores |
| Archivos adjuntos | **No disponible** — sin respaldo al momento de la prueba |

**El entorno de origen no se tocó** y el servicio no tuvo interrupción.

## 3. Protección de los datos durante la prueba

- Acceso al entorno de recuperación por HTTPS con certificado válido; servicios internos no expuestos.
- **Antes de iniciar la aplicación se desactivaron correo y notificaciones push**, para que ninguna persona
  recibiera mensajes originados en la prueba.
- La legibilidad de los datos biométricos se verificó **por conteo**, sin visualizar contenido.
- **El entorno se eliminó el mismo día**: base de datos, archivos, configuración y certificado.

## 4. Verificaciones realizadas

| # | Verificación | Resultado |
|---|---|---|
| 1 | Restauración de la base desde el respaldo, con aplicación de cambios hasta el presente | ✅ 28 s + 29 s |
| 2 | Estructura de la base igual al origen (tablas, versión de esquema, controles de auditoría) | ✅ 103 tablas · 5 versiones de esquema · 4 controles de auditoría |
| 3 | Legibilidad de datos biométricos cifrados con las claves custodiadas | ✅ 2/2 |
| 4 | Aplicación accesible por HTTPS con certificado válido | ✅ |
| 5 | Rechazo de credenciales inválidas y acceso a archivos sin sesión | ✅ |
| 6 | Recuperación automática ante reinicio del servicio | ✅ |
| 7 | Ingreso real de un usuario | ✅ |
| 8 | Servicios internos no accesibles desde Internet | ✅ |
| 9 | Archivos adjuntos | ❌ el documento existente no tenía respaldo |

## 5. Observaciones y acciones

| # | Observación | Impacto | Acción | Estado |
|---|---|---|---|---|
| 1 | La copia custodiada de la configuración estaba desactualizada respecto de una rotación de credenciales: la aplicación no habría iniciado. | Alto | Copia actualizada y verificada. Comparación de configuración como paso previo obligatorio de cada prueba. | ✅ Resuelto 2026-09-15 |
| 2 | Los archivos subidos por usuarios no tienen respaldo. | Alto | Mover el almacenamiento de archivos fuera del directorio de la aplicación y respaldarlo cifrado cada 15 minutos fuera del proveedor principal (mecanismo ya operativo para otra aplicación). | ⏳ Planificado |
| 3 | Ordenamiento de permisos internos de la base de datos. | Bajo | Normalización en el origen. | ⏳ Planificado |

## 6. Evidencia disponible

| Evidencia | Referencia | Cómo se verifica |
|---|---|---|
| Certificado TLS del entorno de recuperación | `checkpointdrp.axiomacloud.com`, vigente desde 2026-09-15 11:04 UTC | **Público:** Certificate Transparency (`crt.sh`). *Al emitir este borrador aún no estaba indexado: verificar antes de enviar.* |
| Respaldo de base utilizado | `20260913-034513F_20260915-074512I` + registro continuo de cambios | Registro del sistema de respaldo |
| Registro detallado de la ejecución | documento interno `drp-checkpoint-en-drp.md`, revisión `cb61f56` | Historial de versiones con fecha |
| Registro de la cadencia de pruebas | Registro de revisiones periódicas, cadencia C15 | Auditoría |

**Prueba presenciada:** el cliente puede participar de la próxima prueba e ingresar con su propio usuario al
entorno recuperado. Coordinar con *[contacto]*.

## 7. Próxima prueba programada

**Julio 2027** — frecuencia anual. Se adelanta si se completa la acción 2 (respaldo de archivos), para
verificarla.

## 8. Conformidad

| Rol | Nombre | Fecha | Firma |
|---|---|---|---|
| Responsable Técnico | | | |
| Aprobación | | | |
| Recibido por el cliente | | | |
