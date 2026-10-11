#!/usr/bin/env bash
# Validates supabase/migrations + seed + SQL tests on a throwaway PostGIS container.
# Usage: scripts/validate_sql.sh   (requires Docker)
set -euo pipefail
cd "$(dirname "$0")/.."
NAME=pickleball-sql-check
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=postgres postgis/postgis:15-3.4 >/dev/null
trap 'docker rm -f "$NAME" >/dev/null' EXIT
until docker logs "$NAME" 2>&1 | grep -q "PostgreSQL init process complete"; do sleep 1; done
until docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
run() { docker exec -i "$NAME" psql -v ON_ERROR_STOP=1 -q -U postgres -d postgres "$@"; }
run < supabase/tests/local_stub.sql
for f in supabase/migrations/*.sql; do echo "→ $f"; run < "$f"; done
echo "→ seed.sql"; run < supabase/seed.sql > /dev/null
for f in supabase/tests/*_test.sql; do echo "→ $f"; run < "$f"; done
echo "SQL validation passed"
