#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# build_whisper.sh — reconstruit le whisper-cli embarqué.
#
# Pendant de Scripts/build_ffmpeg_lgpl.sh, et pour la même raison : une
# procédure recopiée à la main dans une documentation n'est pas une procédure.
# Mesuré le 24/09 — celle de docs/DEVELOPMENT.md disait « git clone --depth 1 »,
# ce qui récupère HEAD et non le commit consigné : la suivre aujourd'hui
# compilerait une AUTRE source que celle qui est embarquée et annoncée.
#
# Usage :
#   ./Scripts/build_whisper.sh [dossier-de-travail]
#
# Le binaire produit est laissé dans <dossier-de-travail>/whisper.cpp/build/bin/.
# Rien n'est installé, rien n'est copié dans Vendor/ : l'installation dans le
# dépôt reste un geste MANUEL et délibéré, comme pour FFmpeg.
#
# Prérequis : macOS arm64, outils Xcode en ligne de commande, cmake, git.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Source amont : un COMMIT, pas une branche -----------------------------
# L'identifiant complet, jamais abrégé : un identifiant court peut devenir
# ambigu quand le dépôt grossit, et il ne se vérifie pas aussi bien.
# Cette valeur est la MÊME que celle annoncée dans THIRD_PARTY_NOTICES.md.
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"
WHISPER_COMMIT="080bbbe85230f624f0b52127f1ae1218247989f9"
WHISPER_VERSION="1.9.1"   # ce que déclare le CMakeLists.txt à ce commit

# --- Cible et SDK : FIXÉS ICI, jamais laissés à l'environnement -------------
# Même raison que dans build_ffmpeg_lgpl.sh : le binaire de la 1.2.3 déclarait
# « minos 26.0 », la version de la machine qui l'avait compilé, alors que
# l'application déclare 14.0. Le SDK se choisit par la même logique que
# l'application, pour que les trois Mach-O du bundle partagent le même.
MACOSX_DEPLOYMENT_TARGET="14.0"
export MACOSX_DEPLOYMENT_TARGET

source "$SCRIPT_DIR/sdk_macos.sh"
choisir_sdk_macos || exit 1
SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export SDKROOT="$SDK_PATH"

WORK="${1:-$PROJECT_ROOT/.whisper-build}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

echo "▸ Dossier de travail   : ${WORK}"
echo "▸ Cible de déploiement : macOS ${MACOSX_DEPLOYMENT_TARGET}"
echo "▸ SDK employé          : $(plutil -extract Version raw "$SDK_PATH/SDKSettings.plist" 2>/dev/null || echo '?')"

# --- 1) Récupération du commit exact ---------------------------------------
# On ne clone PAS une branche : on va chercher un objet précis et on vérifie
# qu'on l'a bien obtenu. Un « git clone --depth 1 » rendrait HEAD, c'est-à-dire
# une source différente à chaque exécution.
cd "$WORK"
SRC="$WORK/whisper.cpp"
if [[ ! -d "$SRC/.git" ]]; then
    echo "▸ Récupération du commit ${WHISPER_COMMIT}…"
    rm -rf "$SRC"
    mkdir -p "$SRC"
    git -C "$SRC" init -q .
    git -C "$SRC" remote add origin "$WHISPER_REPO"
fi
git -C "$SRC" fetch -q --depth 1 origin "$WHISPER_COMMIT"
git -C "$SRC" checkout -q FETCH_HEAD

# Garde : a-t-on bien la source annoncée ? Sans cela, une erreur de réseau ou
# un dépôt déplacé produirait un binaire qu'on croirait être celui du commit.
OBTENU="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$OBTENU" != "$WHISPER_COMMIT" ]]; then
    echo "✗ Commit obtenu : ${OBTENU}" >&2
    echo "  Commit attendu : ${WHISPER_COMMIT}" >&2
    echo "  La source n'est pas celle qui est annoncée — arrêt." >&2
    exit 1
fi
echo "  ✓ commit ${OBTENU}"

# Garde : la version déclarée par la source doit être celle qu'on annonce dans
# THIRD_PARTY_NOTICES.md. Les deux se lisent, aucune ne se suppose.
VERSION_SOURCE="$(awk -F'VERSION ' '/^project\(.*VERSION /{print $2}' "$SRC/CMakeLists.txt" | tr -d ')' | head -1)"
if [[ "$VERSION_SOURCE" != "$WHISPER_VERSION" ]]; then
    echo "✗ La source déclare la version ${VERSION_SOURCE}, ce script annonce ${WHISPER_VERSION}." >&2
    echo "  Mettre les deux d'accord avant de fabriquer." >&2
    exit 1
fi
echo "  ✓ version déclarée par la source : ${VERSION_SOURCE}"

# --- 2) Compilation --------------------------------------------------------
# Options reprises telles quelles de la procédure d'origine : statique, Metal
# embarqué, ni tests ni serveur. S'y ajoutent la cible, le SDK, et la
# neutralisation des chemins de build.
#
# -ffile-prefix-map : ggml grave le chemin de chaque fichier source dans ses
# assertions (GGML_ASSERT emploie __FILE__), et ces chaînes vivent dans le CODE
# — strip ne les retire PAS. Mesuré le 24/09 : sans cette option, le binaire
# porte 21 chemins absolus nommant le dossier personnel de la machine de
# fabrication. Avec elle, les chemins deviennent « whisper.cpp/ggml/src/… »,
# la forme exacte qu'avait le binaire de la 1.2.3.
#
# Effet de bord bienvenu : le binaire ne dépend plus de l'endroit où on le
# compile. Deux machines, deux dossiers de travail, le même résultat.
PREFIX_MAP="-ffile-prefix-map=${WORK}/="
echo "▸ Configuration…"
cd "$SRC"
cmake -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DGGML_METAL=ON \
      -DGGML_METAL_EMBED_LIBRARY=ON \
      -DWHISPER_BUILD_TESTS=OFF \
      -DWHISPER_BUILD_SERVER=OFF \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
      -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
      -DCMAKE_C_FLAGS="$PREFIX_MAP" \
      -DCMAKE_CXX_FLAGS="$PREFIX_MAP" > /dev/null

echo "▸ Compilation…"
cmake --build build -j --config Release --target whisper-cli > /dev/null

BIN="$SRC/build/bin/whisper-cli"
if [[ ! -x "$BIN" ]]; then
    echo "✗ Binaire introuvable : ${BIN}" >&2
    exit 1
fi

# --- 3) Gardes sur le binaire produit --------------------------------------
# Une dépendance non système signalerait un binaire non autonome, qui casserait
# chez l'utilisateur tout en fonctionnant ici — panne invisible au moment du build.
if otool -L "$BIN" | tail -n +2 | grep -vE '/usr/lib/|/System/Library/' | grep -q .; then
    echo "✗ Dépendance non système :" >&2
    otool -L "$BIN" | tail -n +2 | grep -vE '/usr/lib/|/System/Library/' >&2
    exit 1
fi
echo "  ✓ binaire autonome (frameworks Apple uniquement)"

MINOS_OBTENU="$(vtool -show-build "$BIN" 2>/dev/null | awk '$1=="minos"{print $2}')"
if [[ "$MINOS_OBTENU" != "$MACOSX_DEPLOYMENT_TARGET" ]]; then
    echo "✗ Binaire marqué « minos ${MINOS_OBTENU} », cible demandée ${MACOSX_DEPLOYMENT_TARGET}." >&2
    echo "  La cible n'a pas été prise en compte — ne pas embarquer ce binaire." >&2
    exit 1
fi
echo "  ✓ minos ${MINOS_OBTENU} · sdk $(vtool -show-build "$BIN" 2>/dev/null | awk '$1=="sdk"{print $2}')"

# Garde : aucun chemin de la machine de fabrication dans le binaire. Ces chaînes
# vivent dans le CODE, pas dans la table de débogage : strip ne les retire pas,
# et build_app.sh refuserait le bundle. Autant le voir ici.
# « || true » indispensable : grep sans correspondance rend 1, et sous
# « set -o pipefail » cela tuerait le script au moment même où le contrôle
# réussit. Un garde-fou qui s'auto-détruit quand tout va bien n'en est pas un.
PERSO="$(LC_ALL=C grep -oaF "$HOME" "$BIN" 2>/dev/null | wc -l | tr -d ' ')" || true
if [[ "${PERSO:-0}" -ne 0 ]]; then
    echo "✗ Le binaire porte ${PERSO} occurrence(s) du dossier personnel." >&2
    echo "  -ffile-prefix-map n'a pas pris — ne pas embarquer ce binaire." >&2
    exit 1
fi
echo "  ✓ aucun chemin de la machine de fabrication"

echo
echo "✓ Binaire prêt : ${BIN}"
echo "  taille  : $(stat -f '%z' "$BIN") octets"
echo "  SHA-256 : $(shasum -a 256 "$BIN" | cut -d' ' -f1)"
echo
echo "  Pour l'embarquer (geste manuel et délibéré) :"
echo "    cp \"${BIN}\" \"${PROJECT_ROOT}/Vendor/bin/whisper-cli\""
echo "    puis mettre à jour l'empreinte dans THIRD_PARTY_NOTICES.md"
echo "    et refabriquer : ./Scripts/build_app.sh --release"
