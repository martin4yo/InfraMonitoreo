# Estándar de seguridad para aplicaciones Axioma / DotGestion

**Alcance:** toda aplicación nueva o existente de la plataforma (Hub, Parse, Tally, Checkpoint, Clubix, Elore, Alvera, …), independientemente del framework. Nace de las respuestas de seguridad comprometidas con UdeSA (`hub/docs/RESPUESTAS_SEGURIDAD_UDESA.md`) y de los hallazgos del relevamiento de Checkpoint del 2026-09-12 (`checkpoint-web/docs/PLAN-SEGURIDAD-UDESA.md`).
**Componente reutilizable:** `@axioma/security` (diseño en `checkpoint-web/docs/DISENO-AXIOMA-SECURITY.md`): núcleo sin framework + adaptadores Express (Hub, Parse, Tally) y Next (Checkpoint). Cada punto de este checklist debe cumplirse usando el paquete, no con código propio.
**Implementación de referencia:** `checkpoint-web` (`src/lib/env.ts`, `src/lib/auth.ts`, `src/lib/auth-context.ts`, `src/lib/rate-limit.ts`, `src/lib/uploads.ts`, `src/middleware.ts`, `next.config.ts`). Copiar esos módulos y adaptar en lugar de reinventarlos.
**Uso:** checklist obligatorio en cada PR que toque autenticación, rutas, archivos, IA o logs, y en el arranque de cada proyecto nuevo.

---

## 1. Repositorio

- [ ] Ningún secreto, dump, backup, cookie ni `.env*` en el repo. `.gitignore` con `*.sql`, `*.backup`, `*.dump`, `cookies.txt`, `.env*`, `/uploads/`.
- [ ] `.env.example` completo, con valores vacíos para secretos y el comando para generarlos (`openssl rand -hex 32`). Nunca un secreto "de ejemplo" que funcione.
- [ ] `gitleaks` en CI y como hook `pre-commit`.
- [ ] Contraseñas de demo sólo en seeds marcados como desarrollo; jamás en la base de un ambiente accesible desde internet.
- [ ] Si un secreto llegó al historial: purgar con `git filter-repo`, force-push, y **rotar el secreto igual**.

## 2. Configuración y secretos

- [ ] Validación estricta al arranque (zod o equivalente): la app **no inicia** si falta `DATABASE_URL`, la clave de firma de sesiones (≥ 32 chars) o la clave maestra de cifrado. Sin `|| 'fallback'` en ningún secreto.
- [ ] En producción, además: rechazar valores de ejemplo y exigir `https` en la URL pública.
- [ ] Secretos en archivo de entorno con permisos `600` del usuario de sistema de la app, fuera del repo y de los backups de código. En AWS: carga desde Secrets Manager con el rol IAM de la instancia.
- [ ] Rotación sin corte: la verificación acepta la clave vigente y la anterior (`*_PREVIOUS`); se firma siempre con la vigente; la anterior se retira a los 7 días.
- [ ] Credenciales guardadas en base (SMTP, ERP, IdP, claves de IA) cifradas con AES-256-GCM, formato versionado (`v1:<keyId>:<iv>:<tag>:<data>`), clave maestra en entorno. API keys y secretos de clientes OAuth guardados sólo como hash.

## 3. Autenticación y sesión

- [ ] Contraseñas con bcrypt (cost ≥ 12). Política: ≥ 10 caracteres, distinta del email, no en lista de comunes. Cambio obligatorio al primer ingreso.
- [ ] Sesión web: cookie `HttpOnly`, `Secure` (siempre en producción), `SameSite=Lax` como mínimo, `Path=/`; duración ≤ 12 h con renovación deslizante. Sesión móvil: Bearer con duración acotada y refresh.
- [ ] Revocación server-side (`tokenVersion` por usuario) en logout, cambio de contraseña, desactivación y cambio de rol.
- [ ] Rate limit de login: 5 fallos por cuenta y 20 por IP cada 15 min → `429` + `Retry-After`. Mismo tiempo de respuesta exista o no el usuario. Lo mismo para PIN/QR/biometría.
- [ ] Nunca loguear tokens, contraseñas, hashes ni fragmentos de ellos.
- [ ] SSO: Google OIDC como estándar; OIDC genérico por tenant (Entra ID, Okta, Keycloak) con `state`, `nonce`, PKCE, vinculación por email verificado dentro del tenant, auto-alta desactivada por defecto. TOTP para cuentas locales, exigible por tenant.

## 4. Autorización y multi-tenant

- [ ] Un único helper de contexto (`getAuthContext`) que resuelve usuario, tenant, roles y canal. Ninguna ruta repite el bloque "leer token → verificar → buscar usuario".
- [ ] Un wrapper (`withAuth(handler, {roles})`) para toda ruta no pública. Lista **explícita** de rutas públicas en el middleware; nada de excluir prefijos (`/api/mobile/*`) ni extensiones (`.jpg`).
- [ ] **El `tenantId` nunca viene del cliente.** Sale del contexto; un superusuario puede elegir tenant sólo por un canal explícito y validado.
- [ ] Toda consulta por `id` incluye `tenantId` en el `where` (`findFirst({ where: { id, tenantId } })`, nunca `findUnique({ where: { id } })` a secas). Recurso ajeno → `404`, no `403`.
- [ ] Defensa en profundidad: extensión del ORM que inyecta el tenant del contexto en todas las consultas de modelos con `tenantId`.
- [ ] Reglas de negocio mínimas: nadie se desactiva o elimina a sí mismo; no se puede desactivar al último admin del tenant; un admin de tenant no toca superusuarios.
- [ ] Test automatizado de aislamiento: dos tenants, cada ruta con `[id]` probada con id ajeno → `404/403`. Corre en CI.

## 5. Superficie HTTP

- [ ] Cabeceras: `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` restrictiva; sin `X-Powered-By` ni `Server` con versión. CSP primero en `Report-Only`, luego enforce.
- [ ] CSRF: mutaciones autenticadas por cookie exigen `Sec-Fetch-Site: same-origin` u `Origin` permitido. Bearer exento.
- [ ] Rate limit general por usuario/IP (≈ 300 req/min) y específicos (IA, uploads, exports). En memoria mientras haya una instancia; interfaz que permita cambiar el store.
- [ ] Validación de entrada con esquema (zod) en toda ruta mutante; `400` con detalle acotado.
- [ ] Errores: respuesta genérica + `requestId`; nunca `error.message` ni stack al cliente.
- [ ] Endpoints de cron/tareas protegidos por secreto compartido (comparación en tiempo constante), sin `GET` "para probar". Endpoints de prueba (`test-*`, `initialize-*`) sólo para superusuario o fuera de producción.
- [ ] El proceso escucha en `127.0.0.1`; nginx es la única puerta (TLS 1.2/1.3, `server_tokens off`, `limit_req` en login y API, `client_max_body_size` acotado).

## 6. Archivos

- [ ] Nada subido por usuarios vive bajo el webroot (`public/`). Directorio `UPLOAD_DIR` fuera, permisos `640/750` del usuario de la app.
- [ ] Se sirven **sólo** por una ruta autenticada que resuelve el archivo desde el registro en base que lo referencia y verifica tenant (y rol si aplica). Un archivo sin registro no existe. Ruta canónica con `path.resolve` + `path.relative` (sin `..`).
- [ ] Al subir: tipo por firma binaria (magic bytes), no por extensión ni `Content-Type`; allowlist por caso de uso; tamaño máximo; nombre aleatorio con extensión derivada del tipo real. Al servir: `nosniff`, `Content-Disposition: attachment` salvo imágenes, `Cache-Control: private, no-store`.

## 7. Auditoría y logs

- [ ] Auditoría de escrituras (entidad, id, acción, before/after redactado, usuario, tenant, IP, ruta, `requestId`) capturada a nivel del cliente de base, consultable por API con alcance por tenant y exportable a CSV.
- [ ] Eventos de autenticación: login ok/fallido, logout, cambio de contraseña, cambio de rol, MFA, revocación, rate-limited.
- [ ] `X-Request-Id` generado en el borde (nginx o middleware), propagado a logs y auditoría, devuelto al cliente.
- [ ] Logs JSON estructurados con redacción de campos sensibles (`password`, `token`, `authorization`, `cookie`, biometría, texto enviado a la IA). Rotación (pm2-logrotate o logrotate). Nada de `console.log` con datos de negocio.
- [ ] Retención configurable por tenant; envío al SIEM del cliente filtrado por tenant.

## 8. IA

- [ ] Habilitación por tenant verificada **en el servidor** (no sólo en la UI), desactivable sin redeploy.
- [ ] Cliente único (`ai-client`) con proveedor por configuración (`anthropic` | `bedrock`); en AWS, Bedrock con rol IAM.
- [ ] Sólo el texto del usuario y el contexto mínimo; sin volcados de tablas en el prompt. Salida validada contra un esquema cerrado de acciones; cada acción pasa por el mismo control de permisos que la UI y queda auditada con `actorType: 'ia'`.
- [ ] Medición de tokens por tenant y usuario; cuota mensual; rate limit por usuario. No se loguea el contenido.

## 9. Dependencias, CI y despliegue

- [ ] CI obligatoria para merge: lint, tipos, `npm audit --audit-level=high`, build, tests de aislamiento, gitleaks. Dependabot semanal agrupado.
- [ ] Sin `ignoreBuildErrors` / `ignoreDuringBuilds` en producción.
- [ ] Reemplazar dependencias sin fix (`xlsx` → `exceljs`; `jspdf/html2pdf` → generación server-side). Quitar dependencias sin uso (cada una es superficie y CVEs).
- [ ] Despliegue idempotente por tag: `releases/<tag>` + symlink `current`, `migrate deploy`, healthcheck, `pm2 reload`, rollback automático. `GET /health` sin datos sensibles.
- [ ] Un usuario de sistema por aplicación, sin root, `.env` `600`, servicios en loopback. Imagen Docker multi-stage con usuario no root para staging.

## 10. Datos del cliente

- [ ] Exportación completa por tenant (JSON/CSV por entidad + archivos + auditoría, manifiesto con hashes, paquete cifrado) y borrado por tenant verificable con acta. Ambos como scripts versionados.
- [ ] Backups cifrados, retención definida (30 días), restore probado y documentado.
- [ ] Feature flags globales y por tenant, con kill-switch de rutas desde el middleware, para mitigar un hallazgo sin redeploy.

---

### Cómo aplicarlo en un proyecto nuevo (orden)

1. `.gitignore`, `.env.example`, `env.ts` con validación estricta, gitleaks.
2. `auth.ts` (bcrypt, JWT con rotación), `auth-context.ts` + `withAuth`, middleware con lista pública explícita, CSRF y `requestId`.
3. Cabeceras de seguridad y `poweredByHeader: false`; proceso en loopback; plantilla nginx.
4. `rate-limit.ts` en login y global.
5. `uploads.ts` si hay archivos.
6. Auditoría + logger JSON desde el primer modelo.
7. CI + Dependabot + `deploy.sh` idempotente + `/health`.
