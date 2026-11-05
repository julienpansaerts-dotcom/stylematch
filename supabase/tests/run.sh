#!/usr/bin/env bash
# Applique la migration sur une base PostgreSQL locale vierge puis lance les tests.
# Usage : PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
db="stylematch_test_$$"
psql -v ON_ERROR_STOP=1 -q -c "create database $db"
trap 'psql -q -c "drop database if exists $db" >/dev/null' EXIT
psql -v ON_ERROR_STOP=1 -q -d "$db" -f supabase/tests/supabase_stubs.sql 2>/dev/null
for migration in supabase/migrations/*.sql; do
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$migration"
done
psql -v ON_ERROR_STOP=1 -q -o /dev/null -d "$db" -f supabase/tests/purchase_flow_test.sql
