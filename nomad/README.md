# Migracion a Nomad

Este proyecto ya contiene todo lo necesario para migrar el sitio sin recrearlo a mano:

- Un WordPress completo en `public/`
- El contenido del sitio en `public/wp-content`
- Un dump de base de datos valido en `cerveceria.sql`

## Lo que ya pude confirmar

- URL original: `https://cerveceriastammtisch.com.ar`
- Tema detectado: `astra`
- Plugins relevantes presentes: `updraftplus`, `ultimate-addons-for-gutenberg`, `eps-301-redirects`, `qr-redirector`
- El dump fue exportado desde MariaDB 11.1.2 y es compatible con MariaDB/MySQL, no con PostgreSQL

## Estrategia recomendada

No conviene reconstruir este sitio desde cero si ya tenemos el dump bueno.

La ruta de menor riesgo es:

1. Levantar `wordpress + mariadb` en Nomad.
2. Sembrar el volumen `wp-content` con el contenido actual de `public/wp-content`.
3. Importar `cerveceria.sql` una sola vez al crear la base.
4. Publicar el servicio detras de tu proxy o ingress.

El archivo [wordpress.nomad.hcl](/Users/loko_/sitios/cerveceriastammtisch.com.ar/nomad/wordpress.nomad.hcl) deja ese stack listo.

## 1. Crear los host volumes en el cliente de Nomad

Usa como referencia [client-host-volumes.hcl.example](/Users/loko_/sitios/cerveceriastammtisch.com.ar/nomad/client-host-volumes.hcl.example).

En el nodo cliente, crea estas carpetas:

- `/srv/nomad/cerveceria/wp-content`
- `/srv/nomad/cerveceria/db-data`
- `/srv/nomad/cerveceria/db-init`

Luego reinicia el cliente de Nomad para que tome los `host_volume`.

## 2. Preparar el contenido para restaurar

Prepara el dump para el init de MariaDB:

```powershell
powershell -ExecutionPolicy Bypass -File .\nomad\scripts\extract-db-dump.ps1
```

Eso genera:

- `nomad/dist/db-init/01-restore.sql`

Ahora copia dos cosas al nodo de Nomad:

1. Todo el contenido de `public/wp-content/` a `/srv/nomad/cerveceria/wp-content/`
2. El archivo `nomad/dist/db-init/01-restore.sql` a `/srv/nomad/cerveceria/db-init/01-restore.sql`

Notas:

- `db-init` solo se usa en el primer arranque. MariaDB ejecuta esos scripts solo si `/var/lib/mysql` esta vacio.
- Si ya inicializaste la base una vez, borra el contenido de `db-data` antes de repetir la restauracion.

## 3. Ajustar variables del job

Copia [wordpress.nomad.vars.hcl.example](/Users/loko_/sitios/cerveceriastammtisch.com.ar/nomad/wordpress.nomad.vars.hcl.example) y completalo con secretos reales.

Campos importantes:

- `db_password`: usa una clave nueva. No reutilices la del `wp-config.php` actual.
- `wp_home` y `wp_siteurl`: deja el dominio final que va a publicar Nomad.
- Si vas a publicar primero en una URL temporal, usa esa URL y luego corrige `home` y `siteurl` dentro de WordPress cuando pases al dominio final.

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

## Fallback con UpdraftPlus

Si prefieres restaurar desde plugin en vez de sembrar `wp-content` manualmente:

1. Despliega el job vacio.
2. Instala `UpdraftPlus`.
3. Copia los archivos de `public/wp-content/updraft/` al directorio `wp-content/updraft` del volumen.
4. Restaura desde el panel de WordPress.

Funciona, pero es mas lento y agrega pasos manuales. Para este caso, sembrar `wp-content` e importar SQL es mas directo.

## Riesgos a tener en cuenta

- El `wp-config.php` actual contiene credenciales viejas. No deberian reutilizarse.
- Si el dominio cambia, hay que actualizar `home`, `siteurl` y revisar contenido serializado si aparecen URLs absolutas antiguas.
- WordPress sigue requiriendo MariaDB/MySQL; el PostgreSQL que ya existe en Nomad no sirve para este sitio sin una capa de compatibilidad que no recomiendo.
- Si tu cluster usa Traefik, Caddy o Nginx, faltaria agregar etiquetas o configuracion especifica del proxy. Este job queda intencionalmente generico.
