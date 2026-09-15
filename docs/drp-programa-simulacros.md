# Programa de simulacros de recuperación (DRP de aplicaciones)

> **Qué es:** el compromiso de **cada cuánto** se prueba que cada aplicación se puede recuperar, **en qué
> orden rotan** y **qué evidencia deja** cada prueba. Los runbooks dicen *cómo* se recupera una app; este
> documento dice *cuándo* se prueba y *cómo se demuestra* que se probó.
>
> **Por qué existe (2026-09-15).** Hasta hoy había un drill mensual automático de las **bases** (C1) y una
> frase en el [runbook general §10.7](./drp-recuperacion-axioma-en-drp.md) — *"ejecutar como simulacro, una
> app por vez"* — sin fecha, sin responsable, sin rotación y sin límite de vida. Consecuencias medidas:
> 6 de 11 aplicaciones nunca se probaron completas; y los simulacros de hub, parse y alvera del 2026-08-12
> **quedaron corriendo 34 días** en axioma-drp con datos de producción, sin que nada lo señalara.
>
> **Estado:** v1 — vigente desde 2026-09-15. Cadencia **C15** de [G6](./gobierno/g6-revisiones-periodicas.md).
> Aprobación de objetivos RPO/RTO (§6): **pendiente de la AN**.

---

## 1. Tres niveles de prueba

| Nivel | Qué prueba | Frecuencia | Quién | Automatizado |
|---|---|---|---|---|
| **1 — Datos** | Que cada stanza se restaura desde R2 y el WAL llega al presente (C1). Que el backup de adjuntos corre y el repositorio está íntegro (C14). | **Mensual** (C1) · **continuo** + semanal (C14) | automático (drp / axioma) | ✅ con alarmas |
| **2 — Aplicación** | Escenario 3 de la [matriz](./drp-app-hub-drill.md#matriz-de-escenarios-de-recuperación--qué-nivel-aplica): **una app completa** (base + código + build + config + adjuntos) levantada en drp desde fuentes independientes del server de origen, con login real. | **Trimestral**, 2–3 apps por ventana, rotando (§3) | RT | ❌ manual, 1–2 h por app |
| **3 — Servidor entero** | Escenario 4: **axioma completo** en drp (cluster entero + todas sus apps), **ejecutado por el BT sin asistencia del RT**. Prueba el bus factor, no solo la técnica. | **Anual** (coincide con C9) | **BT** (RT observa) | ❌ manual, 1 día |

El nivel 1 dice *"los datos están"*; el 2, *"la app vuelve"*; el 3, *"vuelve aunque falte quien la armó"*.
Ninguno reemplaza a otro.

---

## 2. Reglas de todo simulacro de aplicación (nivel 2 y 3)

Destiladas de los simulacros del 2026-08-12 y 2026-09-15. Cada una existe porque su ausencia ya causó un
problema real — la referencia entre paréntesis dice cuál.

### 2.1 Antes

- [ ] **Ventana acordada** y registro DNS `<app>drp.axiomacloud.com → drp` creado (sin proxy).
- [ ] **Commit de producción anotado** — el que corre, no el último de `master` (alvera: 36 commits de diferencia).
- [ ] **`infra-secrets` al día:** comparar las claves del `.env` vivo contra SOPS **por hash**, sin descifrar
      valores en pantalla. Dos de dos copias estaban vencidas y **ninguna habría arrancado** (H-1, A-2).
- [ ] **drp limpio:** sin bases, usuarios ni PM2 de simulacros anteriores (la alarma de §4 lo garantiza).

### 2.2 Durante

- [ ] Restore con **`--db-include=<base>` y `--archive-mode=off`** — nunca contaminar la stanza productiva.
- [ ] 🔴 **Neutralizar todo canal que llegue a usuarios reales** *antes* de arrancar la app: variables del
      `.env` **y configuración guardada en la base** (alvera guarda WhatsApp/email en `configurations`, A-3).
- [ ] **Legibilidad de datos cifrados** con el script de conteo (sin exponer datos): 0 fallidos (R15).
- [ ] **Adjuntos** desde R2 cuando exista backup; si no, registrar el hueco.
- [ ] **Verificación externa**: título real, redirect sin `localhost`, login inválido 401, control negativo de
      puertos, boot test, `restart_time` estable a 60 s.
- [ ] **Login real** con un usuario existente (lo hace una persona).
- [ ] Medir **RPO** (`last completed transaction` del log de PG) y **RTO** (de manos y de pared).

### 2.3 Después — **el mismo día**

- [ ] 🔴 **Teardown** (§10 de cada runbook). **Vida máxima en drp: 48 h**, con excepción declarada (§4).
- [ ] Registro en el runbook de la app, en [`drill-history.csv`](./drill-history.csv) y en la tabla de C15 de G6.
- [ ] **Informe de prueba** para el cliente de la app ([plantilla](./informes/plantilla-informe-prueba-continuidad.md)).
- [ ] Hallazgos al [plan de remediación](./plan-remediacion-hallazgos.md); **corregir el runbook** con lo aprendido.
- [ ] Actualizar la **matriz de cobertura** (§3.2).

---

## 3. Rotación

### 3.1 Criterios

1. **Frecuencia mínima por criticidad:** 🔴 datos de salud o pagos → **cada 6 meses** · 🟠 datos de negocio →
   **anual** · 🟡 terceros/agentes → **anual** (puede cubrirlo el nivel 3) · 🟢 estáticos → nivel 3.
2. **Orden dentro de la ventana:** la app con **más tiempo desde su última prueba**, ponderada por criticidad.
   Una app **nunca probada** va antes que cualquier otra de su misma criticidad.
3. **Prueba fuera de turno** (en las 4 semanas siguientes) cuando ocurre alguno de estos disparadores:
   - rename o cambio de estructura (usuario, base, rutas) — el de mediflow→alvera dejó 3 artefactos rotos;
   - salto de versión mayor de Node, Next, Prisma o PostgreSQL;
   - cambio en el cifrado de la app o en sus claves;
   - integración nueva que envía mensajes o escribe en sistemas de terceros;
   - migración de la app a otro server, o cambio de proveedor;
   - un hallazgo 🔴 del simulacro anterior marcado como resuelto (se cierra probándolo, G10).
4. **Un nivel 3 cuenta** como prueba anual de todas las apps del server que recupera.

### 3.2 Matriz de cobertura

| App | Server | Datos | Crit. | Frecuencia | Última prueba completa | Resultado | Próxima |
|---|---|---|---|---|---|---|---|
| **alvera** | axioma | salud (cifrados) | 🔴 | 6 meses | **2026-09-15** | ✅ PASS · RPO≈0 · RTO 13 min | 2027-01 |
| **clubix** | clubix | pagos | 🔴 | 6 meses | **nunca** | — | **2026-10** |
| **hub** | axioma | negocio | 🟠 | anual | 2026-08-12 | ✅ PASS (login) | 2027-08 (nivel 3) |
| **parse** | axioma | negocio + credencial Google | 🟠 | anual | 2026-08-12 | ✅ PASS | 2027-08 (nivel 3) |
| **checkpoint** | dev-1 | personas + biometría (cifrada) | 🟠 | anual | **2026-09-15** | ✅ PASS · RPO≈2 min | 2027-07 |
| **mini** | axioma | negocio | 🟠 | anual | **nunca** | — | **2026-10** |
| **tally** | axioma | negocio | 🟠 | anual | **nunca** (app nueva) | — | **2026-10** |
| **axio** (backend + ml) | axiodemo | negocio | 🟠 | anual | **nunca** | — | 2027-04 |
| **elore** | axioma | negocio | 🟡 | anual | **nunca** | — | 2027-01 |
| **evolution-api** | axioma | mensajería (terceros) | 🟡 | anual | **nunca** | — | 2027-07 |
| **axio-db-agent** | axioma | lee 4 bases | 🟡 | anual | **nunca** | — | 2027-08 (nivel 3) |
| estáticos (checkpoint site, corporate) | axioma | — | 🟢 | nivel 3 | nunca | — | 2027-08 (nivel 3) |

### 3.3 Calendario (anclado a las ventanas trimestrales de G6: día 23)

| Ventana | Nivel 2 — apps | Nivel 3 | Por qué este orden |
|---|---|---|---|
| **2026-10-23** | **clubix**, **mini**, **tally** | — | Tres nunca probadas; clubix es 🔴 (pagos) |
| **2027-01-23** | **alvera**, **elore** | — | alvera cumple 6 meses; elore nunca probada |
| **2027-04-23** | **clubix**, **axio** | — | clubix cumple 6 meses; axio nunca probada |
| **2027-07-23** | **checkpoint**, **evolution-api** | — | checkpoint anual; evolution nunca probada |
| **2027-08** | — | **axioma entero, por el BT** | Aniversario del primer simulacro; cubre hub, parse, alvera, mini, tally, elore, evolution, db-agent y estáticos |

Una ventana que no se ejecuta **se registra como omitida** en G6 (como el drill de agosto): no se reprograma
en silencio.

---

## 4. Control: simulacros olvidados en drp

**Alarma `watchdog_drp_simulacro_olvidado`** (warn) — la publica `hardening-selfcheck.sh` **solo en el host
de simulacros** (marcado con `/etc/drp/host-simulacros`):

- Cuenta las bases de datos de drp (excepto `postgres` y plantillas) con **más de 48 h** desde su creación
  (fecha de `PG_VERSION` de la base).
- Una base puede quedar más tiempo **solo si está declarada** en `/etc/drp/simulacros-permitidos` con fecha
  de vencimiento (`<base> <AAAA-MM-DD>`). Vencida la fecha, vuelve a contar.
- Métrica `watchdog.self.drp_limpio` (1 = sin simulacros vencidos). Despliegue:
  [`scripts/38-deploy-drp-guardia.sh`](../scripts/38-deploy-drp-guardia.sh).

Se mide por la base y no por PM2 porque **la base es donde están los datos reales**: una app caída con su base
viva sigue siendo una copia de producción en un server de pruebas.

---

## 5. Evidencia y verificación por terceros

Cada simulacro deja evidencia en tres capas. Las dos primeras son internas; la tercera es la que puede ver
un cliente.

| Capa | Qué | Dónde |
|---|---|---|
| **Operativa** | Paso a paso con comandos, horas, mediciones y hallazgos | Runbook de la app (§ registro) |
| **Cadencia** | Una fila por prueba: fecha, apps, resultado | [`drill-history.csv`](./drill-history.csv) · G6 C15 |
| **Para el cliente** | Informe de prueba de continuidad, sin secretos ni datos personales | [`docs/informes/`](./informes/) |

**Evidencia verificable sin confiar en nuestra palabra** — citarla en el informe:

- **Certificate Transparency:** cada certificado TLS del entorno de recuperación queda en logs públicos
  (consultable en `crt.sh`) con fecha y hora de emisión: prueba independiente de que el entorno existió ese día.
- **Historial de git** de los runbooks y registros (fechas de commit; recomendado firmar commits).
- **Registros del sistema:** etiqueta del backup de pgBackRest usado, línea `last completed transaction` del
  log de PostgreSQL, lista de snapshots de restic, historial de alarmas de Netdata Cloud.
- **Prueba presenciada:** el cliente puede participar de un simulacro e **ingresar con su propio usuario** al
  entorno recuperado. Es la evidencia más fuerte y la única que no requiere confianza técnica. Ofrecerla al
  menos una vez por año por cliente, o a pedido en una auditoría.

---

## 6. Objetivos RPO/RTO — 🔴 pendientes de aprobación

**Hoy no hay objetivos formales por aplicación**: el [DRP de base de datos](./disaster-recovery-plan.md)
declara un *RPO efectivo de 4 horas* (desactualizado: el archivado continuo de WAL da minutos) y RTO
*estimados* por escenario. Sin objetivos acordados, un informe puede decir cuánto se tardó pero no si
**se cumplió**. Propuesta, basada en lo medido, para que la AN apruebe o ajuste:

| Alcance | RPO objetivo | RTO objetivo | Medido (último simulacro) |
|---|---|---|---|
| Base de datos de una app | **≤ 15 min** | — | ≈ 0 (alvera) · ≈ 2 min (checkpoint) |
| Adjuntos de una app (con backup a R2) | **≤ 15 min** | — | 15 min por diseño (alvera) |
| Una aplicación completa (nivel 2) | — | **≤ 4 h** | 13 min (alvera, de manos) · ≈ 20 min (checkpoint) |
| Servidor entero (nivel 3) | — | **≤ 8 h** | sin medir (estimado 2–8 h en el runbook general) |

Hasta la aprobación, los informes muestran **lo medido** y marcan el objetivo como *propuesto*.
