#!/bin/bash

function wait_for_postgres() {
  local seconds=$1
  local max_seconds=$2
  local timeout=$(($seconds+$max_seconds+1))

  until  psql -c '\l'; do
    if  (( $seconds > $timeout )) ; then
      echo "  Timed out waiting for success"
    fi

    echo "Postgres is unavailable - sleeping"
    sleep $seconds
  done
}

function create_database() {
  local database=$1
  local user=$2
  local schema="public"

  if ! [ "$( psql -tAc "SELECT 1 FROM pg_database WHERE datname='$database'" )" = '1' ]; then
    echo "  Creating database '$database'"
    psql <<-EOSQL
      CREATE DATABASE $database;
EOSQL
  else
    echo "  database '$database' already exists"
  fi

  psql -d "$database" <<-EOSQL
    GRANT ALL ON DATABASE $database TO $user;
    GRANT ALL ON SCHEMA $schema TO $user;
EOSQL
}

function create_postgis_extension() {
  local database=$1

  if ! [ "$( psql -d "$database" -tAc "SELECT 1 FROM pg_extension WHERE extname = 'postgis'" )" = '1' ]; then
    echo "  Creating postgis extension '$database'"
    psql -d "$database" <<-EOSQL
      CREATE EXTENSION postgis;
EOSQL
  else
    echo "  database '$database' postgis extension already exists"
  fi
}

function revoke_public() {
  local database=$1

  echo " Revoking public privileges for '$database'"
  psql -d "$database" <<-EOSQL
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    REVOKE ALL ON DATABASE $database FROM PUBLIC;
EOSQL
}

function create_admin_role() {
  local database=$1
  local role="${database}_admin"
  local schema="public"

  if ! [ "$( psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$role'" )" = '1' ]; then
    echo " Creating role '$role'"
    psql -d "$database" <<-EOSQL
      CREATE ROLE $role;
EOSQL
  else
    echo " role '$role' already exists"
  fi

  psql -d "$database" <<-EOSQL
    GRANT ALL ON DATABASE $database TO $role;
    GRANT ALL ON SCHEMA $schema to $role;

    GRANT ALL ON ALL TABLES IN SCHEMA $schema TO $role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA $schema TO $role;
    GRANT ALL ON ALL FUNCTIONS IN SCHEMA $schema TO $role;
EOSQL
}

function create_connect_role() {
  local database=$1
  local role="${database}_connect"
  local schema="public"

  if ! [ "$( psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$role'" )" = '1' ]; then
    echo " Creating role '$role'"
    psql -d "$database" <<-EOSQL
      CREATE ROLE $role;
EOSQL
  else
    echo " role '$role' already exists"
  fi

  psql -d "$database" <<-EOSQL
    GRANT CONNECT ON DATABASE $database TO $role;
    GRANT USAGE ON SCHEMA $schema to $role;

    GRANT USAGE ON ALL SEQUENCES IN SCHEMA $schema TO $role;
EOSQL
}

function create_user() {
  local user=$1
  local password=$2

  # check if user already exists
  if ! [ "$( psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$user'" )" = '1' ]; then
    echo " Creating user '$user'"
    psql <<-EOSQL
      CREATE USER $user WITH PASSWORD '$password';
EOSQL
  else
    echo " user '$user' already exists"
  fi
}

function grant_admin_role() {
  local user=$1
  local password=$2
  local database=$3
  local role="${database}_admin"
  local schema="public"

  if ! [ "$( psql -tAc "SELECT 1 FROM pg_roles WHERE pg_has_role('$user', oid, 'member') AND rolname = '$role'" )" = '1' ]; then
    echo " Assigning user '$user' role '$role'"
    psql <<-EOSQL
      GRANT $role TO $user;
EOSQL
  else
    echo " role '$role' is already assigned to user '$user'"
  fi

  PGPASSWORD="$password" psql -d "$database" -U "$user" <<-EOSQL
    ALTER DEFAULT PRIVILEGES FOR USER $user IN SCHEMA $schema GRANT ALL ON TABLES TO ${database}_admin;
    ALTER DEFAULT PRIVILEGES FOR USER $user IN SCHEMA $schema GRANT ALL ON SEQUENCES TO ${database}_admin;
    ALTER DEFAULT PRIVILEGES FOR USER $user IN SCHEMA $schema GRANT ALL ON FUNCTIONS TO ${database}_admin;
    ALTER DEFAULT PRIVILEGES FOR USER $user IN SCHEMA $schema GRANT ALL ON TYPES TO ${database}_admin;

    ALTER DEFAULT PRIVILEGES FOR USER $user IN SCHEMA $schema GRANT USAGE ON SEQUENCES TO ${database}_connect;
EOSQL
}

function grant_connect_role() {
  local user=$1
  local database=$2
  local role="${database}_connect"
  local schema="public"

  if ! [ "$( psql -tAc "SELECT 1 FROM pg_roles WHERE pg_has_role('$user', oid, 'member') AND rolname = '$role'" )" = '1' ]; then
    echo " Assigning user '$user' role '$role'"
    psql <<-EOSQL
      GRANT $role TO $user;
EOSQL
  else
    echo " role '$role' is already assigned to user '$user'"
  fi
}

#################################################################
# CONFIGURE DATABASE SETTINGS
#################################################################

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-}"
export PGDATABASE="${PGDATABASE:-postgres}"

# Databases
POSTGRES_DBS='arcloud,device_session,devices_service,identity,keycloak'

# AR Cloud
ARCLOUD_MAPPING_USER='mapping'
ARCLOUD_MAPPING_PASSWORD='<insert password>'
#
ARCLOUD_MIGRATION_USER='migration'
ARCLOUD_MIGRATION_PASSWORD='<insert password>'
#
ARCLOUD_SESSION_MANAGER_USER='session_manager'
ARCLOUD_SESSION_MANAGER_PASSWORD='<insert password>'
#
ARCLOUD_SPACE_PROXY_USER='space_proxy'
ARCLOUD_SPACE_PROXY_PASSWORD='<insert password>'
#
ARCLOUD_SPATIAL_ANCHORS_USER='spatial_anchors'
ARCLOUD_SPATIAL_ANCHORS_PASSWORD='<insert password>'
#
ARCLOUD_STREAMING_USER='streaming'
ARCLOUD_STREAMING_PASSWORD='<insert password>'
#
ARCLOUD_OBJECT_ANCHORS_API_USER='object_anchors_api'
ARCLOUD_OBJECT_ANCHORS_API_PASSWORD='<insert password>'

# Device Gateway
DEVICE_SESSION_USER='device_session'
DEVICE_SESSION_PASSWORD='<insert password>'
#
DEVICES_SERVICE_USER='devices_service'
DEVICES_SERVICE_PASSWORD='<insert password>'

# Identity
IDENTITY_USER='identity'
IDENTITY_PASSWORD='<insert password>'

# Keycloak
KEYCLOAK_USER='keycloak'
KEYCLOAK_PASSWORD='<insert password>'

#################################################################
# NO NEED TO EDIT BELOW THIS LINE
#################################################################

wait_for_postgres 3 60

for POSTGRES_DB in $(tr ',' ' ' <<< "$POSTGRES_DBS" | sed -e's/  */ /g' ); do
  create_database "$POSTGRES_DB" "$PGUSER"
  revoke_public "$POSTGRES_DB"
  create_admin_role "$POSTGRES_DB"
  create_connect_role "$POSTGRES_DB"
done

# AR Cloud
create_postgis_extension "arcloud"
#
create_user "${ARCLOUD_MAPPING_USER}" "${ARCLOUD_MAPPING_PASSWORD}"
grant_connect_role "${ARCLOUD_MAPPING_USER}" "arcloud"
#
create_user "${ARCLOUD_MIGRATION_USER}" "${ARCLOUD_MIGRATION_PASSWORD}"
grant_admin_role "${ARCLOUD_MIGRATION_USER}" "${ARCLOUD_MIGRATION_PASSWORD}" "arcloud"
#
create_user "${ARCLOUD_SESSION_MANAGER_USER}" "${ARCLOUD_SESSION_MANAGER_PASSWORD}"
grant_connect_role "${ARCLOUD_SESSION_MANAGER_USER}" "arcloud"
#
create_user "${ARCLOUD_SPACE_PROXY_USER}" "${ARCLOUD_SPACE_PROXY_PASSWORD}"
grant_connect_role "${ARCLOUD_SPACE_PROXY_USER}" "arcloud"
#
create_user "${ARCLOUD_SPATIAL_ANCHORS_USER}" "${ARCLOUD_SPATIAL_ANCHORS_PASSWORD}"
grant_connect_role "${ARCLOUD_SPATIAL_ANCHORS_USER}" "arcloud"
#
create_user "${ARCLOUD_STREAMING_USER}" "${ARCLOUD_STREAMING_PASSWORD}"
grant_connect_role "${ARCLOUD_STREAMING_USER}" "arcloud"
#
create_user "${ARCLOUD_OBJECT_ANCHORS_API_USER}" "${ARCLOUD_OBJECT_ANCHORS_API_PASSWORD}"
grant_connect_role "${ARCLOUD_OBJECT_ANCHORS_API_USER}" "arcloud"

# Device Gateway
create_user "${DEVICE_SESSION_USER}" "${DEVICE_SESSION_PASSWORD}"
grant_admin_role "${DEVICE_SESSION_USER}" "${DEVICE_SESSION_PASSWORD}" "device_session"
#
create_user "${DEVICES_SERVICE_USER}" "${DEVICES_SERVICE_PASSWORD}"
grant_admin_role "${DEVICES_SERVICE_USER}" "${DEVICES_SERVICE_PASSWORD}" "devices_service"

# Identity
create_user "${IDENTITY_USER}" "${IDENTITY_PASSWORD}"
grant_admin_role "${IDENTITY_USER}" "${IDENTITY_PASSWORD}" "identity"

# Keycloak
create_user "${KEYCLOAK_USER}" "${KEYCLOAK_PASSWORD}"
grant_admin_role "${KEYCLOAK_USER}" "${KEYCLOAK_PASSWORD}" "keycloak"
