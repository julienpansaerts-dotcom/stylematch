#!/usr/bin/env python3
"""Vérifie la configuration App Store Connect avant l'export.

Utilise la clé API pour interroger App Store Connect et affiche un message
clair si la clé est refusée, si l'identifiant (Bundle ID) n'est pas enregistré
ou si l'app n'existe pas encore dans App Store Connect.

Variables d'environnement : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, TEAM_ID.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"


def fail(message: str) -> None:
    print(f"::error::{message}")
    sys.exit(1)


def token() -> str:
    with open(os.environ["ASC_KEY_PATH"], "r", encoding="utf-8") as handle:
        private_key = handle.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def get(path: str, params: dict, bearer: str) -> dict:
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {bearer}"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")
        if error.code == 401:
            fail(
                "Clé API refusée par App Store Connect (401). Vérifie les secrets ASC_KEY_ID, "
                "ASC_ISSUER_ID et ASC_KEY_P8 (contenu complet du fichier .p8), et que la clé "
                "est une « Clé d'équipe » non révoquée."
            )
        if error.code == 403:
            fail(
                "Clé API sans droits suffisants (403). Crée une clé d'équipe avec l'accès « Admin ». "
                f"Détail : {body}"
            )
        fail(f"Erreur App Store Connect {error.code} sur {path} : {body}")
    return {}


def main() -> None:
    bundle_id = os.environ["BUNDLE_ID"]
    team_id = os.environ.get("TEAM_ID", "")
    bearer = token()

    bundle_ids = get("bundleIds", {"filter[identifier]": bundle_id, "limit": 5}, bearer).get("data", [])
    exact = [b for b in bundle_ids if b["attributes"].get("identifier") == bundle_id]
    if exact:
        seed = exact[0]["attributes"].get("seedId", "")
        print(f"✅ Bundle ID {bundle_id} enregistré (préfixe d'équipe : {seed}).")
        if seed and team_id and seed != team_id:
            print(
                f"::warning::Le préfixe du Bundle ID ({seed}) diffère du secret APPLE_TEAM_ID ({team_id}). "
                "Vérifie le Team ID dans developer.apple.com › Membership details."
            )
    else:
        print(f"::warning::Bundle ID {bundle_id} introuvable sur developer.apple.com (Identifiers).")

    apps = get("apps", {"filter[bundleId]": bundle_id, "limit": 5}, bearer).get("data", [])
    if not apps:
        print("Apps visibles avec cette clé dans App Store Connect :")
        for other in get("apps", {"limit": 50}, bearer).get("data", []):
            print(f"  • « {other['attributes'].get('name')} » — Bundle ID : {other['attributes'].get('bundleId')}")
        print("Bundle IDs enregistrés sur developer.apple.com :")
        for other in get("bundleIds", {"limit": 50}, bearer).get("data", []):
            print(f"  • {other['attributes'].get('identifier')} ({other['attributes'].get('name')})")
        fail(
            f"Aucune app avec le Bundle ID {bundle_id} dans App Store Connect. "
            "Crée-la sur https://appstoreconnect.apple.com/apps › + › Nouvelle app "
            f"(Identifiant de lot : {bundle_id}). Enregistrer l'identifiant sur "
            "developer.apple.com ne suffit pas."
        )
    app = apps[0]
    print(f"✅ App trouvée dans App Store Connect : « {app['attributes'].get('name')} » (id {app['id']}).")


if __name__ == "__main__":
    main()
