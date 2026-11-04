#!/bin/bash
# Exécuté une seule fois, à l'initialisation du volume : une base et un rôle dédiés
# par service, pour qu'aucun service ne puisse lire les données d'un autre.
set -euo pipefail

create_db() {
  local name="$1" password="$2"
  psql -v ON_ERROR_STOP=1 -v name="$name" -v password="$password" \
       --username "$POSTGRES_USER" --dbname postgres <<'SQL'
CREATE ROLE :"name" LOGIN PASSWORD :'password';
CREATE DATABASE :"name" OWNER :"name";
REVOKE ALL ON DATABASE :"name" FROM PUBLIC;
SQL
}

create_db keycloak  "$PG_PASSWORD_KEYCLOAK"
create_db litellm   "$PG_PASSWORD_LITELLM"
create_db openwebui "$PG_PASSWORD_OPENWEBUI"
create_db langfuse  "$PG_PASSWORD_LANGFUSE"
