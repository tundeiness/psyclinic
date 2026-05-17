#!/bin/bash
set -e

rm -f /app/tmp/pids/server.pid

echo "Waiting for PostgreSQL at ${DATABASE_HOST}:${DATABASE_PORT:-5432}..."
until pg_isready -h "${DATABASE_HOST}" -p "${DATABASE_PORT:-5432}" -U "${DATABASE_USERNAME}" >/dev/null 2>&1; do
  sleep 1
done
echo "PostgreSQL is up."

# Create the database if it does not exist, load schema, run migrations.
bundle exec rails db:prepare

# Seed only if requested AND not in the test environment. Seeding the
# test DB pollutes it with fixed records that collide with factory data.
if [ "${SEED_ON_BOOT:-true}" = "true" ] && [ "${RAILS_ENV}" != "test" ]; then
  bundle exec rails db:seed
fi

exec "$@"
