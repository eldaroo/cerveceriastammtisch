FROM mariadb:10.11

COPY nomad/dist/db-init/01-restore.sql /docker-entrypoint-initdb.d/01-restore.sql
