# Configuración de build de los frontends

Variables que **se hornean en el bundle al compilar**. No son secretos —viajan en el JavaScript que
descarga cualquier usuario— pero **sin ellas el build sale mal y la app falla en runtime**, no al compilar.

| App | Archivo | Destino en el server |
|---|---|---|
| alvera (mediflow) | `mediflow-frontend.env.production` | `/var/www/mediflow/frontend/.env.production` |

## Por qué están acá y no en el repo de cada app

Los repos de aplicación **gitignorean todos los `.env`** — política correcta para no filtrar secretos, pero
que arrastra consigo archivos que **no** contienen ninguno. El resultado es que la configuración de build
de producción termina existiendo en un solo lugar: el servidor. Que es exactamente lo que un DR no tiene.

## Uso en una recuperación

```bash
cp mediflow-frontend.env.production /var/www/mediflow/frontend/.env.production
cd /var/www/mediflow/frontend && npm run build      # Vite lo lee solo
```

**Verificación obligatoria** — que no haya quedado el fallback de desarrollo:

```bash
grep -c "localhost:5000" dist/assets/*.js     # debe dar 0
```

> ⚠️ **La solución de fondo es otra.** Lo correcto sería versionar `.env.production` en el repo de cada
> app con una excepción explícita en su `.gitignore` (`!.env.production`), porque así **Vite lo carga solo
> y es imposible equivocarse**. Este directorio es la solución que no requiere cambiar la política de los
> repos de aplicación — pero depende de que alguien se acuerde de copiar el archivo, que es justo el modo
> de falla que produjo el problema.
