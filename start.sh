#!/bin/bash

set -e

PAPERLESS_PORT=8000
PAPERLESS_UID=1000
PAPERLESS_GID=1000
PAPERLESS_VERSION=2.10.0
PAPERLESS_TIME_ZONE=America/Chicago
PAPERLESS_OCR_LANGUAGE=eng
PAPERLESS_URL=https://localhost:8000
PAPERLESS_SECRET_KEY=chamgemechamgemechamgemechamgemechamgemechamgemechamgemechamgeme

REDIS_VERSION=6
REDIS_PORT=6379

POSTGRESQL_VERSION=13
POSTGRESQL_PORT=5432
POSTGRES_USER=paperless
POSTGRESQL_DB=paperless
POSTGRESQL_PASSWORD=paperlesschangeme

echo "Creating Paperless Pod..."
podman pod create --replace --name paperless \
  -p ${PAPERLESS_PORT}:${PAPERLESS_PORT}

echo "Starting Redis..."
podman volume create paperless-redis 2> /dev/null ||:
podman create --replace --pod paperless \
  --restart=unless-stopped \
  --name paperless-redis \
  --volume paperless-redis:/data:Z \
  docker.io/library/redis:${REDIS_VERSION}
podman start paperless-redis

echo "Starting PostgreSQL..."
podman volume create paperless-postgresql 2> /dev/null ||:
podman create --replace --pod paperless \
  --restart=unless-stopped \
  --name paperless-postgresql \
  --expose ${POSTGRESQL_PORT} \
  -e POSTGRES_USER=${POSTGRES_USER} \
  -e POSTGRES_PASSWORD=${POSTGRESQL_PASSWORD} \
  --volume paperless-postgresql:/var/lib/postgresql/data:Z \
  docker.io/library/postgres:${POSTGRESQL_VERSION}
podman start paperless-postgresql

echo "Starting Gotenberg..."
podman create --replace --pod paperless \
  --restart=unless-stopped \
  --name paperless-gotenberg \
  -e CHROMIUM_DISABLE_ROUTES=1 \
  docker.io/gotenberg/gotenberg:7
podman start paperless-gotenberg

echo "Starting Tika..."
podman create --replace --pod paperless \
  --restart=unless-stopped \
  --name paperless-tika \
  docker.io/apache/tika
podman start paperless-tika

echo "Starting Paperless..."
podman create --replace --pod paperless \
  --name paperless-webserver \
  --restart=unless-stopped \
  --stop-timeout=90 \
  --health-cmd='["curl", "-f", "http://localhost:8000"]' \
  --health-retries=5 \
  --health-start-period=60s \
  --health-timeout=10s \
  -e PAPERLESS_REDIS=redis://localhost:${REDIS_PORT} \
  -e PAPERLESS_DBHOST=localhost \
  -e PAPERLESS_DBNAME=${POSTGRES_USER} \
  -e PAPERLESS_DBPASS=${POSTGRESQL_PASSWORD} \
  -e PAPERLESS_TIKA_ENABLED=1 \
  -e PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://localhost:3000 \
  -e PAPERLESS_TIKA_ENDPOINT=http://localhost:9998 \
  -e PAPERLESS_URL=${PAPERLESS_URL} \
  -e USERMAP_UID=${PAPERLESS_UID} \
  -e USERMAP_GID=${PAPERLESS_GID} \
  -e PAPERLESS_SECRET_KEY=${PAPERLESS_SECRET_KEY} \
  -e PAPERLESS_TIME_ZONE=${PAPERLESS_TIME_ZONE} \
  -e PAPERLESS_OCR_LANGUAGE=${PAPERLESS_OCR_LANGUAGE} \
  -v paperless-data:/usr/src/paperless/data:Z \
  -v paperless-media:/usr/src/paperless/media:Z \
  -v paperless-consume:/usr/src/paperless/consume:U,z \
  -v ${PWD}/export:/usr/src/paperless/export:U,Z \
  ghcr.io/paperless-ngx/paperless-ngx:${PAPERLESS_VERSION}
podman start paperless-webserver

