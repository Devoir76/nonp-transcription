#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https:#mozilla.org/MPL/2.0/.
# test_bug007.sh — repli du dossier de sortie (BUG-007, BUG-008)
#                  + persistance des réglages (BUG-006).
#
# Le nom du script est CONSERVÉ pour ne pas casser la traçabilité des journaux de
# campagne, alors que son périmètre s'est élargi. Question ouverte au bilan.
#
# Compile en debug, puis exerce successivement :
#   1. le VRAI SubtitleExporter sur les cas de résolution du dossier de sortie ;
#   2. la persistance des réglages dans un même process (cohérence écriture/relecture) ;
#   3. la persistance entre DEUX process distincts — seul test qui exerce le vrai
#      mode d'échec de BUG-006, la persistance adossée au disque entre deux lancements.
#
# Les tests de persistance écrivent dans une suite UserDefaults ISOLÉE
# (com.nonp.transcription.selftest*), JAMAIS dans les réglages réels de
# l'utilisateur ; chaque bloc vérifie d'ailleurs que le domaine standard est
# resté inchangé, et la suite est supprimée en fin de test.
#
# Aucun média, aucun modèle, aucun appel au moteur : quelques secondes, dont
# l'essentiel est la compilation.
#
# Usage : ./Scripts/test_bug007.sh
# Sortie : 0 si TOUS les cas passent (repli + persistance).

set -euo pipefail

# Les suites UserDefaults de test laissent derrière elles un plist vide (cfprefsd
# vide le domaine mais conserve le fichier). On le supprime quoi qu'il arrive.
# Le motif « .selftest* » ne peut pas atteindre les domaines réels
# « com.nonp.transcription.plist » ni « com.nonp.transcription.test.plist ».
trap 'rm -f ~/Library/Preferences/com.nonp.transcription.selftest*.plist' EXIT

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

echo
echo "== Persistance des réglages — même process (suite isolée) =="
"$BIN" --prefs-cases

echo
echo "== Persistance des réglages — cross-process (suite isolée) =="
"$BIN" --prefs-write
"$BIN" --prefs-read
