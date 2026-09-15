# G1 — Política de Seguridad de la Información

> Parte del [Marco de Gobierno de Seguridad](../marco-gobierno.md) · Cubre el gap **G1** del
> [dossier de auditoría](../dossier-auditoria-seguridad.md#8-gaps-de-gobierno-documentos-que-un-auditor-pediría-y-hoy-no-existen).
>
> **Estado:** v1 — redacción inicial (2026-07-23). Aprobación formal pendiente de firma del responsable.
> Consolida prácticas ya vigentes y verificadas, dispersas en `hardening.md`, `estandar-despliegue.md`
> y `disaster-recovery-plan.md`. Referencia normativa: CIS Controls v8.
>
> **Lenguaje normativo:** **DEBE** = obligatorio · **DEBERÍA** = recomendado salvo justificación
> registrada · **PUEDE** = opcional.

## 1. Propósito y alcance

Esta política establece los principios y requisitos mínimos de seguridad de la información para la
infraestructura del ecosistema Axioma. Su objetivo es proteger la **confidencialidad, integridad y
disponibilidad** de los datos y servicios operados.

- **Aplica a:** los 5 servidores de la infraestructura (`axioma`, `clubix`, `axiodemo`, `dev-1`,
  `axioma-drp`), todas las aplicaciones propias que corren en ellos, las bases de datos PostgreSQL,
  los backups (pgBackRest → dev-1 SSH + Cloudflare R2) y los secretos que custodia el ecosistema.
- **Aplica a:** toda persona con acceso administrativo a esos sistemas (hoy el responsable técnico y
  su backup — ver [G2](./g2-roles-responsabilidades.md)).
- **No aplica a:** servicios de terceros fuera del control operativo directo (evolution-api como
  producto de tercero, el monitoreo SNMP contratado a dattaweb), salvo en lo referido a cómo la
  infraestructura interactúa con ellos.

## 2. Principios rectores

1. **Mínimo privilegio.** Cada aplicación corre bajo su **propio usuario dedicado** (`<app>app`),
   sin shell de login, sin sudo y sin pertenecer a grupos privilegiados. Ninguna app corre como
   `root` ni como un usuario compartido. *(Vigente y verificado — `estandar-despliegue.md` §2.)*
2. **Defensa en profundidad.** Ningún control es la única barrera: firewall (ufw default-deny) +
   bind a loopback + TLS/headers en nginx + autenticación fuerte de base de datos operan en capas.
3. **Superficie de ataque mínima.** Los servicios escuchan en `127.0.0.1` salvo los estrictamente
   públicos (SSH, 80/443). El firewall bloquea por defecto todo lo entrante y habilita por
   excepción (`ufw` allowlist explícita). *(Vigente — `hardening.md` §2.)*
4. **Secreto por defecto.** Las credenciales se custodian cifradas (SOPS+age) y nunca se exponen en
   texto en logs, sesiones ni commits. *(Vigente — ver [G7](./g7-rotacion-secretos.md).)*
5. **Verificación como control.** Un cambio no está cerrado hasta que se verifica contra el criterio
   formal de cierre (próximo arranque, cobertura total, control negativo). *(Ver [G10](./g10-verificacion-remediaciones.md).)*
6. **Transparencia.** Los falsos verdes y los incidentes se documentan deliberadamente; la capacidad
   de detectar y revertir un error es parte de la evidencia de control.

## 3. Control de acceso

- **SSH.** Acceso **solo por clave pública**. `PermitRootLogin no` y `PasswordAuthentication no` en
  los 5 servidores. El acceso de emergencia con clave se verifica periódicamente (ver [G6](./g6-revisiones-periodicas.md)).
  *(Vigente — H05 cerrado, `hardening.md` §3.)*
- **Usuarios de sistema.** Cada app usa `<app>app` dedicado. Los usuarios de provisioning o de
  terceros sin uso activo se bloquean (`passwd -l`) conservando el acceso por clave para emergencia.
  *(Vigente — H10.)*
- **Base de datos.** Autenticación `scram-sha-256` (nunca `md5`). Las reglas de `pg_hba.conf` se
  acotan a `127.0.0.1/32` / `::1/128`; ninguna regla `0.0.0.0/0`. *(Vigente — H01 cerrado.)*
- **Segregación de funciones.** Actualmente limitada por el bus factor = 1; el plan de mitigación
  vive en [G2](./g2-roles-responsabilidades.md).

## 4. Cifrado

- **En tránsito.** TLS en todo servicio público (nginx con headers de seguridad y `block-scanners`).
  Backups replicados a R2 cifrados AES off-site; WAL replay verificado por drill.
- **En reposo.** Secretos cifrados con SOPS+age (cifrado por-valor, clave age fuera de banda).
  Backups pgBackRest cifrados (`cipher-pass`). *(Vigente — [G7](./g7-rotacion-secretos.md).)*
- **Autenticación de DB.** Hashes `scram-sha-256`; 0 roles con hash `md5`.

## 5. Clasificación y manejo de datos

La infraestructura procesa **datos personales (PII), datos de salud y datos financieros**, sujetos a
la **Ley 25.326** de Protección de Datos Personales (Argentina). Los datos de salud son **datos
sensibles** (art. 7 de la Ley) y reciben el nivel de protección más alto. El detalle de clasificación
por base de datos y las obligaciones de cumplimiento se desarrollan en [G8](./g8-clasificacion-datos.md).

## 6. Retención y respaldo

- Backups dual-repo pgBackRest: repo1 (SSH dev-1) + repo2 (R2 cifrado off-site).
- Retención: `full=4` / `diff=7`; cron full/diff/incremental.
- Recuperación probada por **restore drills** con WAL replay (umbral de frescura 30 min),
  auto-evaluantes y registrados en `drill-history.csv`. Cadencia mensual comprometida
  (ver [G6](./g6-revisiones-periodicas.md)).

## 7. Gestión de vulnerabilidades

Todo componente (SO, PostgreSQL, Node, dependencias npm) está sujeto a escaneo y parcheo según la
[política de gestión de vulnerabilidades — G4](./g4-gestion-vulnerabilidades.md).

## 8. Respuesta a incidentes

Todo evento de seguridad se gestiona según el [plan de respuesta a incidentes — G5](./g5-respuesta-incidentes.md).

## 9. Cumplimiento y revisión

- Esta política se **revisa como mínimo cada trimestre** (próxima revisión: **2026-10-23**) o ante un
  cambio significativo de la infraestructura o del marco regulatorio. La cadencia trimestral se alinea
  con la del DRP y se registra en [G6](./g6-revisiones-periodicas.md).
- El cumplimiento se evidencia mediante el registro de revisiones periódicas
  ([G6](./g6-revisiones-periodicas.md)) y el registro de hallazgos del dossier (§7).
- Las excepciones a esta política **DEBEN** registrarse con justificación, responsable y fecha de
  revisión (riesgo aceptado en el [registro de riesgos — G3](./g3-registro-riesgos.md)).

## 10. Aprobación

| Rol | Responsable | Fecha | Firma |
|---|---|---|---|
| Responsable técnico | mfourgeaux@axiomacloud.com | 2026-07-23 | _pendiente_ |
| Backup técnico | Rodrigo Naranjo — rnaranjo@axiomacloud.com | 2026-07-23 | _pendiente_ |
