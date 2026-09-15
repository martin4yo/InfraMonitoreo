// Configuración de PM2 para Parse
// Los puertos se configuran desde los archivos .env de cada servicio
//
// ⚠️ SEGURIDAD CRÍTICA ⚠️
// ========================
// NUNCA ejecutar PM2 como root. Siempre usar un usuario sin privilegios.
// Ver: docs/SEGURIDAD-DEPLOY.md para instrucciones completas.
//
// Comandos correctos:
//   sudo -u parseapp pm2 start ecosystem.config.js
//   sudo -u parseapp pm2 restart all
//
// NUNCA hacer:
//   sudo pm2 start ecosystem.config.js  ❌ PELIGROSO
//   pm2 start (como root)               ❌ PELIGROSO
//

module.exports = {
  apps: [
    {
      name: 'parse-backend',
      cwd: './backend',
      script: 'src/index.js',
      instances: 1,
      exec_mode: 'fork',

      // ⚠️ SEGURIDAD: Ejecutar como usuario sin privilegios
      // Descomentar y ajustar el usuario en producción:
      // user: 'parseapp',

      env: {
        NODE_ENV: 'production',
        // IMPORTANTE: En producción, configurar estas variables en el servidor
        // Las API keys y credenciales deben estar en backend/.env, NO aquí
        // Este archivo debe ser editado manualmente en el servidor con las credenciales reales
      },
      env_file: './backend/.env',
      error_file: './logs/backend-error.log',
      out_file: './logs/backend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_memory_restart: '1G',
      watch: false,

      // Límites de recursos para prevenir abuso
      max_restarts: 10,
      restart_delay: 4000,

      // Kill timeout - evita procesos zombie
      kill_timeout: 5000
    },
    {
      name: 'parse-frontend',
      cwd: './frontend',
      script: '.next/standalone/frontend/server.js',
      interpreter: 'node',
      instances: 1,
      exec_mode: 'fork',

      // ⚠️ SEGURIDAD: Ejecutar como usuario sin privilegios
      // Descomentar y ajustar el usuario en producción:
      // user: 'parseapp',

      env: {
        NODE_ENV: 'production',
        PORT: 8087,
        // El API URL se lee del frontend/.env
        // NEXT_PUBLIC_API_URL debe apuntar al backend (por defecto: http://localhost:5100)
      },
      error_file: './logs/frontend-error.log',
      out_file: './logs/frontend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      autorestart: true,
      max_memory_restart: '1G',
      watch: false,

      // Límites de recursos para prevenir abuso
      max_restarts: 10,
      restart_delay: 4000,

      // Kill timeout - evita procesos zombie
      kill_timeout: 5000
    }
  ]
};
