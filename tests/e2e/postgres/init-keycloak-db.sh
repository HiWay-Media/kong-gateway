#!/bin/sh
# One Postgres, two databases: Kong's and Keycloak's. They are separate schemas in production too,
# and sharing one database here would let a migration from either side hide a conflict.
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-SQL
  CREATE DATABASE keycloak;
  GRANT ALL PRIVILEGES ON DATABASE keycloak TO $POSTGRES_USER;
SQL
