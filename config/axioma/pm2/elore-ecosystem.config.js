module.exports = {
  apps: [{
    name: 'elore',
    cwd: '/var/www/elore',
    script: 'node_modules/next/dist/bin/next',
    args: 'start -p 3700',
    instances: 1,
    exec_mode: 'fork',
    node_args: '--max-old-space-size=384',
    autorestart: true,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      // Se fija ANTES de arrancar Node: el horario laboral del SLA se calcula con
      // la TZ del proceso (setHours/getDay), no con BusinessHours.timezone.
      TZ: 'America/Argentina/Buenos_Aires',
      PORT: 3700
    },
    error_file: '/var/log/elore/error.log',
    out_file: '/var/log/elore/out.log',
    time: true
  }]
};
