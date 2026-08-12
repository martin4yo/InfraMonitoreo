// ===========================================
// HUB - PM2 Ecosystem Configuration
// ===========================================
//
// Uso:
//   pm2 start ecosystem.config.js
//   pm2 restart all
//   pm2 logs
//
// ===========================================

module.exports = {
  apps: [
    {
      name: 'hub-backend',
      cwd: '/var/www/hub/backend',
      script: 'dist/server.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 5200
      },
      error_file: '/var/log/hub/backend-error.log',
      out_file: '/var/log/hub/backend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      time: true
    },
    {
      name: 'hub-frontend',
      cwd: '/var/www/hub/frontend',
      script: 'node_modules/next/dist/bin/next',
      args: 'start -p 8089',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 8089
      },
      error_file: '/var/log/hub/frontend-error.log',
      out_file: '/var/log/hub/frontend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      time: true
    }
  ]
};
