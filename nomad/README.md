# Migracion a Nomad

Este proyecto ya contiene todo lo necesario para migrar el sitio sin recrearlo a mano:

- Un WordPress completo en `public/`
- Un dump de base de datos valido en `cerveceria.sql`
- Un Dockerfile para publicar el WordPress en GHCR
- Un Dockerfile para publicar el restore de MariaDB en GHCR

## Lo que ya pude confirmar

- URL original: `https://cerveceriastammtisch.com.ar`
- Tema detectado: `astra`
- Plugins relevantes presentes: `updraftplus`, `ultimate-addons-for-gutenberg`, `eps-301-redirects`, `qr-redirector`
- El dump fue exportado desde MariaDB 11.1.2 y es compatible con MariaDB/MySQL, no con PostgreSQL
- WordPress y MariaDB corren en el mismo allocation de Nomad, asi que la conexion entre ambos usa `127.0.0.1:${NOMAD_PORT_db}` dentro del namespace compartido del grupo `bridge`

## Estrategia recomendada

No conviene reconstruir este sitio desde cero si ya tenemos el dump bueno.

La ruta de menor riesgo es:

1. Construir una imagen custom de WordPress desde `public/`.
2. Construir una imagen custom de MariaDB con el restore SQL dentro de `/docker-entrypoint-initdb.d/`.
3. Publicar ambas imagenes en GHCR desde GitHub Actions.
4. Levantar `wordpress + mariadb` en Nomad apuntando a esas imagenes.
5. Publicar el servicio detras de tu proxy o ingress.

El archivo [wordpress.nomad.hcl](/Users/loko_/sitios/cerveceriastammtisch.com.ar/nomad/wordpress.nomad.hcl) deja ese stack listo.

## 1. Crear la carpeta persistente en el nodo de Nomad

No hace falta preparar carpetas manualmente en el VPS: el job usa un volumen Docker nombrado para MariaDB y Docker lo crea en el primer arranque.

## 2. Preparar el dump para restaurar

```powershell
powershell -ExecutionPolicy Bypass -File .\nomad\scripts\extract-db-dump.ps1
```

Eso genera:

- `nomad/dist/db-init/01-restore.sql`

Ese archivo se copia dentro de la imagen custom de MariaDB, asi que ya no hace falta subirlo manualmente al host.

## 3. Ajustar variables del job

Copia [wordpress.nomad.vars.hcl.example](/Users/loko_/sitios/cerveceriastammtisch.com.ar/nomad/wordpress.nomad.vars.hcl.example) y completalo con secretos reales.

Campos importantes:

- `db_password`: usa una clave nueva. No reutilices la del `wp-config.php` actual.
- `wordpress_image` y `mariadb_image`: normalmente apuntan a GHCR y en deploy los rellena GitHub Actions.
- El dump ya trae `home` y `siteurl` con `https://cerveceriastammtisch.com.ar`, asi que no hace falta inyectarlos por `WORDPRESS_CONFIG_EXTRA`.
- El `wp-config-docker.php` oficial ya maneja `HTTP_X_FORWARDED_PROTO`, por eso no hace falta agregar ese bloque manualmente.
- No uses `service()` para construir `WORDPRESS_DB_HOST` en este job: esa funcion consulta Consul, mientras que este stack solo necesita la red compartida del allocation.

## 4. Desplegar

Con el archivo de variables listo:

```bash
nomad job run -var-file=nomad/wordpress.nomad.vars.hcl nomad/wordpress.nomad.hcl
```

## 5. Publicacion y chequeos

El job expone:

- `http` para WordPress
- `db` para MariaDB dentro del mismo grupo

Todavia necesitas conectar ese `service` a tu ingress o reverse proxy del cluster.

Despues del primer arranque, valida:

1. Que el sitio responda.
2. Que las imagenes de `uploads` carguen.
3. Que el admin de WordPress abra.
4. Que los enlaces permanentes funcionen.

## Riesgos a tener en cuenta

- El `wp-config.php` actual no se publica dentro de la imagen.
- Si el dominio cambia, hay que actualizar `home`, `siteurl` y revisar contenido serializado si aparecen URLs absolutas antiguas.
- WordPress sigue requiriendo MariaDB/MySQL; el PostgreSQL que ya existe en Nomad no sirve para este sitio sin una capa de compatibilidad que no recomiendo.
- Si tu cluster usa Traefik, Caddy o Nginx, faltaria agregar etiquetas o configuracion especifica del proxy. Este job queda intencionalmente generico.
