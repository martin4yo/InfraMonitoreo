// Configuración PM2 para MediFlow
module.exports = {
  apps: [
    {
      name: 'mediflow-backend',
      script: 'server.js',
      cwd: '/var/www/mediflow/backend',
      instances: 2,
      exec_mode: 'cluster',
      node_args: '--max-old-space-size=192',
      env: {
        NODE_ENV: 'production',
        PORT: 5300
      },
      env_production: {
        NODE_ENV: 'production',
        PORT: 5300
      },
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      watch: false,
      ignore_watch: ['node_modules', 'logs'],
      max_memory_restart: '500M',
      restart_delay: 4000,
      kill_timeout: 5000,
      listen_timeout: 3000
    }
  ]
};
