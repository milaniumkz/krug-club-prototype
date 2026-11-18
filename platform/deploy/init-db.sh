#!/bin/sh
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=app_password="$APP_DB_PASSWORD" <<'SQL'
CREATE ROLE qazaqmetal LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER DATABASE qazaqmetal OWNER TO qazaqmetal;
ALTER SCHEMA public OWNER TO qazaqmetal;
SQL
