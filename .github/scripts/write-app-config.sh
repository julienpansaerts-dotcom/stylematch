#!/usr/bin/env bash
# Écrit StyleMatch/Config/AppConfig.swift à partir des variables d'environnement
# SUPABASE_URL, SUPABASE_ANON_KEY, STRIPE_PUBLISHABLE_KEY, APPLE_PAY_MERCHANT_ID.
# Une variable vide laisse la valeur actuelle du fichier.
set -euo pipefail
file="StyleMatch/Config/AppConfig.swift"

set_value() {
  local name="$1" value="$2"
  [ -n "$value" ] || return 0
  case "$value" in *'"'*|*'\'*) echo "::error::Valeur invalide pour $name"; exit 1 ;; esac
  python3 - "$file" "$name" "$value" <<'PY'
import re, sys
path, name, value = sys.argv[1:4]
source = open(path, encoding="utf-8").read()
pattern = rf'(static let {name} = )"[^"]*"'
updated, count = re.subn(pattern, lambda m: f'{m.group(1)}"{value}"', source)
if count != 1:
    sys.exit(f"{name} introuvable dans {path}")
open(path, "w", encoding="utf-8").write(updated)
PY
}

set_value supabaseURL "${SUPABASE_URL:-}"
set_value supabaseAnonKey "${SUPABASE_ANON_KEY:-}"
set_value stripePublishableKey "${STRIPE_PUBLISHABLE_KEY:-}"
set_value applePayMerchantID "${APPLE_PAY_MERCHANT_ID:-}"

if grep -q 'static let supabaseURL = ""' "$file"; then
  echo "Backend non configuré : l'app sera en mode démo."
else
  echo "Backend configuré."
fi
