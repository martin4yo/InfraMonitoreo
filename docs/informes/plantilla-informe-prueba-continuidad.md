# Informe de prueba de continuidad — [Aplicación]

<!--
PLANTILLA. Cómo usarla:
- Un informe por aplicación y por prueba. Nombre del archivo: AAAA-MM-DD-<app>.md
- Es un documento PARA EL CLIENTE: no incluir IPs, nombres de servidores internos, nombres de variables
  secretas, usuarios del sistema, ni el detalle técnico que permita explotar un hallazgo. El detalle vive
  en el runbook de la app; acá va el resultado y la evidencia verificable.
- Nunca incluir datos personales del cliente (ni de muestra).
- Revisar y firmar antes de enviar. Exportar a PDF para entregarlo.
- Programa, cadencia y reglas: docs/drp-programa-simulacros.md
-->

| | |
|---|---|
| **Informe N.º** | IPC-AAAA-NNN |
| **Aplicación** | [nombre comercial] |
| **Cliente** | [razón social] |
| **Fecha de la prueba** | AAAA-MM-DD, HH:MM–HH:MM (hora de Argentina) |
| **Tipo de prueba** | Nivel 2 — recuperación completa de la aplicación en infraestructura alternativa |
| **Ejecutó** | [nombre], Responsable Técnico |
| **Revisó / aprobó** | [nombre], [cargo] |
| **Resultado** | ✅ **SUPERADA** / ⚠️ SUPERADA CON OBSERVACIONES / ❌ NO SUPERADA |

---

## 1. Resumen

[Dos o tres oraciones: qué se simuló, si la aplicación volvió a funcionar, con cuánta pérdida de datos y en
cuánto tiempo.]

| Indicador | Objetivo | Medido | ¿Cumple? |
|---|---|---|---|
| **RPO** — datos perdidos (ventana máxima) | [≤ 15 min] *(propuesto / acordado)* | [x min] | ✅ / ❌ |
| **RTO** — tiempo hasta servicio restablecido | [≤ 4 h] *(propuesto / acordado)* | [x min] | ✅ / ❌ |
| Datos protegidos con cifrado, legibles tras recuperar | 100 % | [n de n] | ✅ / ❌ |
| Archivos adjuntos recuperados e íntegros | 100 % | [n de n] | ✅ / ❌ / N/A |
| Ingreso real de un usuario a la aplicación recuperada | Sí | [Sí/No] | ✅ / ❌ |

## 2. Escenario simulado

Se simuló la **pérdida total del servidor** donde opera la aplicación. La recuperación se hizo en un servidor
de recuperación **de otro proveedor**, usando únicamente fuentes que **no dependen del servidor perdido**:

| Componente | Fuente usada en la recuperación |
|---|---|
| Base de datos | Respaldo continuo, **cifrado**, almacenado fuera del proveedor principal |
| Código de la aplicación | Repositorio de código versionado — misma versión que operaba en producción |
| Configuración y credenciales | Custodia cifrada independiente de los servidores |
| Archivos adjuntos | [Respaldo cifrado fuera del proveedor principal / N/A / no disponible — ver hallazgos] |

**No se tocó el entorno productivo**: el servicio del cliente no tuvo interrupción durante la prueba.

## 3. Protección de los datos durante la prueba

- El entorno de recuperación tuvo **acceso restringido** y certificado TLS válido.
- Se **desactivaron los canales de comunicación** con usuarios finales (correo, mensajería, notificaciones)
  antes de iniciar la aplicación, para que ninguna persona reciba mensajes originados en la prueba.
- La verificación de los datos cifrados se hizo **por conteo**, sin visualizar contenido.
- **El entorno se eliminó el [mismo día / fecha]**: base de datos, archivos, configuración y certificados.

## 4. Verificaciones realizadas

| # | Verificación | Resultado |
|---|---|---|
| 1 | Restauración de la base desde el respaldo, hasta el último cambio disponible | [✅ detalle breve] |
| 2 | Consistencia del esquema con la versión de la aplicación | [✅] |
| 3 | Legibilidad de los datos cifrados con las claves custodiadas | [✅ n valores, 0 fallos] |
| 4 | Integridad de los archivos adjuntos (comparación criptográfica) | [✅ n/n idénticos] |
| 5 | Aplicación accesible por HTTPS con certificado válido | [✅] |
| 6 | Rechazo de credenciales inválidas y rutas protegidas | [✅] |
| 7 | Recuperación automática ante reinicio del servicio | [✅] |
| 8 | Ingreso real de un usuario y consulta de información | [✅] |
| 9 | Servicios internos no expuestos a Internet | [✅] |

## 5. Observaciones y acciones

| # | Observación | Impacto | Acción | Estado |
|---|---|---|---|---|
| 1 | [descripción sin detalle explotable] | [Alto/Medio/Bajo] | [qué se hizo o se hará] | [✅ Resuelto AAAA-MM-DD / ⏳ Planificado AAAA-MM] |

## 6. Evidencia disponible

A pedido del cliente o de su auditor:

| Evidencia | Referencia | Cómo se verifica |
|---|---|---|
| Registro de certificado TLS del entorno de recuperación | dominio `[...]`, emitido AAAA-MM-DD HH:MM UTC | Público: logs de Certificate Transparency (p. ej. `crt.sh`) — **no requiere confiar en nosotros** |
| Identificador del respaldo de base usado | `[etiqueta]` | Registro del sistema de respaldo |
| Identificador del snapshot de adjuntos | `[id]` | Registro del sistema de respaldo de archivos |
| Registro detallado de la ejecución | documento interno, revisión `[commit]` | Historial de versiones con fecha |
| Registro de la cadencia de pruebas | registro de revisiones periódicas (C15) | Auditoría |

**Prueba presenciada:** el cliente puede participar de la próxima prueba e ingresar con su propio usuario al
entorno recuperado. Coordinar con [contacto].

## 7. Próxima prueba programada

[AAAA-MM] — según el programa de pruebas (frecuencia [semestral/anual] para esta aplicación).

## 8. Conformidad

| Rol | Nombre | Fecha | Firma |
|---|---|---|---|
| Responsable Técnico | | | |
| Aprobación | | | |
| Recibido por el cliente | | | |
