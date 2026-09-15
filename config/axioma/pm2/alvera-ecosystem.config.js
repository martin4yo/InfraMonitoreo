// Configuración PM2 para Alvera
module.exports = {
  apps: [
    {
      name: 'alvera-backend',
      script: 'server.js',
      cwd: '/var/www/alvera/backend',
      instances: 2,
      exec_mode: 'cluster',
      // Limite de heap dimensionado para produccion (2 instancias en cluster).
      // En desarrollo se puede subir con: pm2 start ... --node-args="--max-old-space-size=512"
      node_args: '--max-old-space-size=192',
      env: {
        NODE_ENV: 'development',
        PORT: 5000
      },
      // PRODUCCION — se activa con: pm2 start ecosystem.config.js --env production
      // El puerto 5300 es el que espera el vhost de nginx (proxy_pass a 127.0.0.1:5300).
      // Corregido 2026-08-12: decia PORT 5000, que es el de desarrollo. Un despliegue
      // desde este repo levantaba la app en el puerto equivocado SIN fallar — respondia
      // y autenticaba igual, asi que el error pasaba desapercibido.
      env_production: {
        NODE_ENV: 'production',
        PORT: 5300
      },
      // Configuración de logs
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',

      // Auto-restart configuración
      watch: false,
      ignore_watch: ['node_modules', 'logs'],

      // Configuración de memoria y restart
      max_memory_restart: '500M',
      restart_delay: 4000,

      // Configuración de clusters
      kill_timeout: 5000,
      listen_timeout: 3000
    }
  ]
};