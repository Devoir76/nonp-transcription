#!/bin/bash
# test_bug007.sh — repli du dossier de sortie (BUG-007).
#
# Compile en debug et exerce le VRAI SubtitleExporter sur les six cas de
# résolution du dossier de sortie. Aucun média, aucun modèle, aucun appel au
# moteur : quelques secondes, dont l'essentiel est la compilation.
#
# Usage : ./Scripts/test_bug007.sh
# Sortie : 0 si les six cas passent.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(id -u)" -eq 0 ]; then
    echo "Refus : ne pas exécuter en root (les bits de permission y sont ignorés,"
    echo "les cas « non inscriptible » deviendraient des faux négatifs)."
    exit 6
fi

echo "== Compilation (debug) =="
swift build 2>&1 | tail -5

BIN="$(swift build --show-bin-path)/NONPTranscription"
echo
echo "== Cas de repli du dossier de sortie =="
"$BIN" --export-cases
