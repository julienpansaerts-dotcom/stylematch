#!/usr/bin/env python3
"""Affiche l'identifiant d'un simulateur iPhone disponible (le plus récent iOS)."""
import json
import re
import subprocess
import sys

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]


def version(runtime: str) -> tuple:
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


for runtime in sorted((r for r in devices if "iOS" in r), key=version, reverse=True):
    iphones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    if iphones:
        print(iphones[0]["udid"])
        print(f"{iphones[0]['name']} ({runtime})", file=sys.stderr)
        sys.exit(0)

sys.exit("Aucun simulateur iPhone disponible")
