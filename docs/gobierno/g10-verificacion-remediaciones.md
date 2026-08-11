# G10 — Procedimiento de Verificación de Remediaciones

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G10** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md).
>
> **Estado:** v1 — redacción inicial (2026-08-11).
>
> **Hallazgo que motiva este documento.** La reapertura de **H06** mostró que no existía un estándar
> escrito de **qué evidencia hace válido el cierre de un hallazgo**. Un hallazgo se declaró cerrado el
> 2026-07-18 con una verificación insuficiente, y un cierre posterior derivado de ese mismo criterio
> **provocó un incidente en producción**. El criterio corregido se venía aplicando en la práctica desde
> entonces, pero sin estar formalizado: vivía en la memoria de quien lo aprendió, no en un procedimiento.
>
> **Principio.** *Cerrar un hallazgo es una afirmación sobre la realidad, no sobre el trabajo hecho.*
> "Apliqué el fix" no es evidencia de cierre; "verifiqué que el problema ya no ocurre, en todos lados,
> contra el estado futuro y no contra el actual" sí lo es.
>
> **Lenguaje normativo:** **DEBE** = obligatorio · **DEBERÍA** = recomendado salvo justificación
> registrada · **PUEDE** = opcional.

## 1. Alcance

Aplica al cierre de:

- **Hallazgos** del [dossier de auditoría](../dossier-auditoria-seguridad.md) (H01–H14 y sucesivos).
- **Acciones abiertas** de cualquier documento de gobierno (las `A<n>` de G7, G8, etc.).
- **Remediaciones de vulnerabilidades** ([G4 §6](./g4-gestion-vulnerabilidades.md)).
- **Rotaciones de secretos** ([G7 §5](./g7-rotacion-secretos.md)).
- **Erradicación de incidentes** ([G5 §4.3](./g5-respuesta-incidentes.md)).

No aplica a cambios que no cierran un hallazgo (mejoras, refactors, despliegues rutinarios), aunque las
reglas de §2 son buena práctica igual.

## 2. Las siete reglas de verificación

Cada una nació de un error real. Se listan con su origen para que no se relajen por comodidad.

### R1 — Verificar contra el **próximo arranque**, no contra el proceso vivo

Un `chmod`/`chown`/cambio de `.env` **no rompe un proceso ya corriendo**: el descriptor de archivo sigue
abierto. Que la app siga viva después del cambio **no prueba nada**. El fallo aparece en el próximo
reinicio, y puede quedar latente días.

- **DEBE** verificarse reiniciando el servicio, o comparando la configuración contra el **usuario
  configurado del proceso**, nunca contra el owner del directorio ni contra el proceso en ejecución.

> *Origen: H06. El cierre del 2026-07-17 se validó contra el proceso vivo; el fallo estalló 3 días después
> al primer restart de mini en axioma, con error 500 en producción.*

### R2 — **Cobertura total**, no una muestra

Verificar un servidor y extrapolar al resto no es verificación: es una suposición con formato de evidencia.

- **DEBE** verificarse en **todos** los servidores, apps o instancias alcanzados por el hallazgo, y
  registrarse el conteo explícito (*"5 de 5"*, no *"verificado"*).
- Si alguno no se pudo verificar, **DEBE** decirse cuál y por qué; el hallazgo queda **parcial**, no cerrado.

> *Origen: H06. Se verificó solo dev-1 cuando mini también corría en axioma — el server que después falló.*

### R3 — **Control negativo**: probar que lo que debe fallar, falla

Comprobar que lo permitido funciona no prueba que lo prohibido esté bloqueado.

- **DEBE** ejecutarse al menos una prueba que **espere un fallo** y confirmarlo (conexión rechazada desde
  una IP no autorizada, puerto cerrado desde afuera, 0 coincidencias en un `grep` de control).

> *Origen: anti-scanner nginx (`curl` de una ruta de scanner debe dar 000, y la ruta no debe aparecer en
> `access.log`) y cierre de H01 (0 líneas `md5` activas en el `pg_hba`).*

### R4 — Inspeccionar el **contenido**, no solo el código de estado

Un código HTTP correcto puede acompañar una respuesta incorrecta.

- **DEBE** inspeccionarse el cuerpo o las cabeceras relevantes cuando el hallazgo lo requiera —
  en particular el header **`Location`** en respuestas 3xx.

> *Origen: H04. El flag `-H` de Next.js bindea bien pero rompe los redirects: sigue devolviendo `307`, y
> un `curl` que solo mira el código no lo detecta. La URL absoluta apuntaba a `localhost`.*

### R5 — Verificar contra el **sistema**, no contra el documento

La documentación describe lo que alguien escribió, no lo que está pasando. Un documento no puede
auditarse a sí mismo.

- **DEBE** obtenerse la evidencia del sistema en vivo. Una afirmación documentada **no cierra nada**,
  ni siquiera si la escribió quien aplicó el fix.

> *Origen: relevamiento in-situ del 2026-08-09. Tres afirmaciones del dossier resultaron falsas —
> el proveedor de hosting "sin acceso a datos de aplicación" tenía 48 llaves en la cuenta con `sudo` de
> dev-1; existía un segundo `axio-db-agent` en clubix; el blocklist que "restringía" el acceso a datos
> clínicos no nombraba ninguna tabla clínica. Ninguna era detectable leyendo el repo.*

### R6 — Verificar el **respaldo**, no la copia de trabajo

Probar que algo funciona con la copia que ya tenés a mano no prueba que exista la copia que vas a
necesitar cuando no tengas nada.

- **DEBE** verificarse restaurando **desde el respaldo declarado**, a un entorno limpio.

> *Origen: pérdida de la clave age (2026-08-09). G7 §2 declaraba la custodia "✅ Vigente y verificada".
> El roundtrip se había corrido con la copia de trabajo, que descifra igual aunque el respaldo no exista.*

### R7 — Un cambio **escrito** no es un cambio **aplicado**

Editar el archivo de configuración correcto no significa que el servicio lo esté usando.

- **DEBE** confirmarse el estado **efectivo** del servicio, no el contenido del archivo: `sshd -T`,
  `nginx -T`, `pg_settings`, `systemctl show`, según corresponda.

> *Origen: `99-temp-password-axiomacloud.conf` (2026-08-09). El archivo existía con
> `PasswordAuthentication yes` en los 4 servidores, pero `sshd` nunca se recargó: la configuración viva
> seguía en `no`. Se creyó habilitado algo que no lo estaba — y el archivo quedó armado para activarse
> solo en el próximo reboot.*

## 3. Checklist de cierre

Un hallazgo **NO DEBE** marcarse cerrado sin completar esta checklist. Se adjunta al registro del hallazgo.

```
Hallazgo / acción : ____________________          Fecha: __________
Ejecutor          : ____________________          Revisor (si aplica): __________

[ ] R1  Verificado contra el próximo arranque (o contra el usuario configurado)
        Cómo: ______________________________________________
[ ] R2  Cobertura total — verificado en ___ de ___ instancias
        No verificadas y por qué: __________________________
[ ] R3  Control negativo ejecutado y confirmado
        Prueba y resultado esperado: _______________________
[ ] R4  Contenido/cabeceras inspeccionados (no solo el código de estado)
[ ] R5  Evidencia obtenida del sistema en vivo, no de documentación
[ ] R6  Si hay respaldo involucrado: verificado DESDE el respaldo
[ ] R7  Estado efectivo del servicio confirmado (no solo el archivo)
[ ] Rollback disponible y probado, o justificación de por qué no aplica
[ ] Residuos barridos (backups temporales, .bak, logs con el valor viejo) — 0 ocurrencias
[ ] Documentación actualizada: dossier + documento técnico + registro de riesgos
```

## 4. Estados admitidos

Un hallazgo **DEBE** estar siempre en uno de estos estados. **No existe "cerrado con salvedades"**: si hay
salvedad, es parcial.

| Estado | Significa | Requisito |
|---|---|---|
| ✅ **Cerrado** | El problema ya no ocurre, verificado por §3 | Checklist completa |
| 🟡 **Parcial** | Parte verificada, parte no. **DEBE** enumerarse qué falta | Checklist con ítems abiertos explícitos |
| ⏸ **Bloqueado** | Depende de un tercero o de una ventana. **DEBE** nombrarse el bloqueo y quién lo levanta | — |
| ⚠️ **Reabierto** | Se cerró y la verificación resultó insuficiente | **DEBE** registrarse por qué falló la verificación original |
| ⬜ **Abierto** | Sin remediar | — |

## 5. Reapertura — cómo se registra

Un cierre que resulta falso **no se corrige en silencio**: se documenta.

1. El hallazgo pasa a **⚠️ Reabierto**, conservando la fecha del cierre original.
2. **DEBE** registrarse **qué regla de §2 falló** y por qué no se detectó.
3. Si la reapertura causó impacto (incidente, indisponibilidad), se trata además como incidente por
   [G5](./g5-respuesta-incidentes.md).
4. La regla que falló **DEBERÍA** incorporarse a §2 si no estaba — así el marco aprende del error una vez
   y no dos.

> **Por qué se registra y no se disimula.** La capacidad de detectar y revertir un falso verde **es
> evidencia de control**, y un auditor la valora más que un historial sin reaperturas. Un registro sin
> reaperturas admite dos lecturas: que nunca hubo un cierre incorrecto, o que nunca se los buscó.

## 6. Quién verifica

- El **RT** ejecuta y verifica. Es lo vigente y lo que el tamaño del equipo permite.
- Para hallazgos **🔴 críticos** y para todo cierre que ya haya sido **reabierto una vez**, la verificación
  **DEBERÍA** ejecutarla o revisarla el **BT** ([G2](./g2-roles-responsabilidades.md)).
- **Riesgo residual aceptado:** hoy ejecutor y verificador son la misma persona. Es el mismo problema de
  segregación que **R08**, aplicado al cierre de hallazgos. La revisión cruzada del BT es la mitigación
  natural y **queda pendiente de su primera ejecución**.

## 7. Gobierno

- Este procedimiento se **revisa cada trimestre** (próxima **2026-10-23**) dentro de la cadencia **C6** de
  [G6](./g6-revisiones-periodicas.md), y **ante toda reapertura** — una reapertura es, por definición,
  evidencia de que §2 tenía un hueco.
- **Estado del gap G10 al 2026-08-11:** 🟡 — el procedimiento queda formalizado y las siete reglas están
  destiladas de errores reales y verificados. Pasa a 🟢 cuando **al menos 3 cierres** se ejecuten con la
  checklist de §3 completa y adjunta, y **al menos uno** haya sido verificado por el BT.
- **Deuda reconocida:** los cierres previos al 2026-08-11 **no tienen la checklist adjunta**. No se
  propone reverificarlos retroactivamente en bloque, pero **DEBERÍAN** revisarse bajo R5 y R7 los que se
  cerraron sin evidencia obtenida del sistema en vivo — el relevamiento del 2026-08-09 mostró que ese es
  el modo de falla más frecuente del marco.
- Riesgos asociados: **R08** (segregación entre ejecutor y verificador).
