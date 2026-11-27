#!/usr/bin/env bash
# Base créée à la main (SQL collé dans le SQL Editor de Supabase) ?
#
# Si la migration initiale n'est pas dans l'historique des migrations mais que
# la base contient déjà TOUT son schéma, on l'enregistre comme appliquée pour
# que `supabase db push` ne tente pas de tout recréer. Si la base n'est que
# partiellement créée, on s'arrête avec la liste de ce qui manque.
#
# Cible : le projet lié (SUPABASE_DB_PASSWORD), ou SUPABASE_DB_URL pour tester
# sur une base PostgreSQL locale.
set -euo pipefail
cd "$(dirname "$0")/../.."

version="20261105000000"
if [ -n "${SUPABASE_DB_URL:-}" ]; then
  db_target=(--remote="$SUPABASE_DB_URL")
  query_target=(--remote="$SUPABASE_DB_URL")
else
  db_target=(--remote --password "$SUPABASE_DB_PASSWORD")
  query_target=(--remote)
fi

history=$(supabase migration list "${db_target[@]}" --output-format json 2>/dev/null)
already=$(python3 -c '
import json, sys
data = json.load(sys.stdin)
print(any(m.get("remote") == sys.argv[1] for m in data.get("migrations", [])))
' "$version" <<<"$history")
if [ "$already" = "True" ]; then
  echo "Migration initiale déjà enregistrée dans l'historique."
  exit 0
fi

result=$(supabase db query "${query_target[@]}" --read-only -f supabase/tests/verify_schema.sql --output-format json 2>/dev/null)
read -r present missing_count missing < <(python3 -c '
import json, sys
row = json.load(sys.stdin)["rows"][0]
print(row["present_count"], row["missing_count"], row["missing"] or "-")
' <<<"$result")

if [ "$present" -eq 0 ]; then
  echo "Base vide : la migration initiale va être appliquée."
elif [ "$missing_count" -eq 0 ]; then
  echo "::notice::Le schéma complet a déjà été créé à la main : migration $version enregistrée comme appliquée."
  supabase migration repair "$version" --status applied "${db_target[@]}" --yes
else
  echo "::error::La base est partiellement créée ($present objets présents, $missing_count manquants : $missing)."
  echo "::error::Dans Supabase › SQL Editor, relance le contenu de supabase/migrations/${version}_initial_schema.sql sur une base vide, ou supprime les objets créés puis relance ce workflow."
  exit 1
fi
