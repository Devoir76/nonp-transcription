#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# build_ffmpeg_lgpl.sh — reconstruit le FFmpeg embarqué (LGPL-2.1+, statique).
#
# Ce script EST la procédure de « source correspondante » exigée par la LGPL §4 :
# il permet à quiconque de reconstruire — éventuellement depuis des sources
# FFmpeg modifiées — un binaire équivalent à celui qui est redistribué.
# Contexte : docs/adr/0005-ffmpeg-lgpl-et-licence-mpl.md
# Détail   : docs/BUILDING_FFMPEG.md
#
# Usage :
#   ./Scripts/build_ffmpeg_lgpl.sh [dossier-de-travail]
#
# Le binaire produit est laissé dans <dossier-de-travail>/ffmpeg-8.1.2/ffmpeg.
# Rien n'est installé, rien n'est copié dans Vendor/ : l'installation dans le
# dépôt reste un geste MANUEL et délibéré (le binaire embarqué est versionné).
#
# Prérequis : macOS arm64 + outils Xcode en ligne de commande (clang, make).
# Ni Homebrew, ni pkg-config, ni nasm ne sont nécessaires.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FFMPEG_VERSION="8.1.2"
TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
UPSTREAM_URL="https://ffmpeg.org/releases/${TARBALL}"
TARBALL_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"

# Liste figée des décodeurs audio (220). Elle est VOLONTAIREMENT figée dans un
# fichier plutôt que régénérée : elle avait été produite depuis l'ancien binaire
# GPL, qui n'existe plus. Sans ce fichier, le build ne serait plus reproductible.
DECODER_LIST="$SCRIPT_DIR/ffmpeg-audio-decoders.txt"

# --- Cible et SDK : FIXÉS ICI, jamais laissés à l'environnement -------------
# Mesuré le 24/09 : les binaires embarqués de la 1.2.3 déclaraient « minos 26.0 »
# — la version de la machine qui les avait compilés — alors que l'application
# déclare 14.0 et que la page de téléchargement promet « macOS 14 ou plus
# récent ». Personne ne l'avait décidé : aucune cible n'était fixée, et clang
# avait pris celle du système.
#
# Le SDK se choisit par la MÊME logique que l'application (Scripts/sdk_macos.sh),
# pour que les trois Mach-O du bundle soient compilés contre le même. Le laisser
# à l'environnement reproduirait exactement le défaut qu'on corrige : deux
# variables pour une.
MACOSX_DEPLOYMENT_TARGET="14.0"
export MACOSX_DEPLOYMENT_TARGET

source "$SCRIPT_DIR/sdk_macos.sh"
choisir_sdk_macos || exit 1
SDK_PATH="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export SDKROOT="$SDK_PATH"
echo "▸ Cible de déploiement : macOS $MACOSX_DEPLOYMENT_TARGET"
echo "▸ SDK employé          : $(plutil -extract Version raw "$SDK_PATH/SDKSettings.plist" 2>/dev/null || echo '?')"

WORK="${1:-$PROJECT_ROOT/.ffmpeg-build}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

echo "▸ Dossier de travail : $WORK"

# --- 1) Source amont ------------------------------------------------------
cd "$WORK"
if [[ ! -f "$TARBALL" ]]; then
    echo "▸ Téléchargement de ${TARBALL}…"
    curl -fL -o "$TARBALL" "$UPSTREAM_URL"
else
    echo "▸ Archive déjà présente — réutilisée."
fi

echo "▸ Vérification de l'empreinte…"
ACTUAL_SHA="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
if [[ "$ACTUAL_SHA" != "$TARBALL_SHA256" ]]; then
    echo "✗ Empreinte SHA-256 incorrecte." >&2
    echo "  attendue : $TARBALL_SHA256" >&2
    echo "  obtenue  : $ACTUAL_SHA" >&2
    exit 1
fi
echo "  ✓ $TARBALL_SHA256"

rm -rf "ffmpeg-${FFMPEG_VERSION}"
tar xf "$TARBALL"
cd "ffmpeg-${FFMPEG_VERSION}"

# --- 2) Configuration -----------------------------------------------------
if [[ ! -f "$DECODER_LIST" ]]; then
    echo "✗ Liste des décodeurs introuvable : $DECODER_LIST" >&2
    exit 1
fi
AUDIO_DEC="$(paste -sd, - < "$DECODER_LIST")"
echo "▸ Décodeurs audio demandés : $(wc -l < "$DECODER_LIST" | tr -d ' ')"

# NOTE : --disable-everything doit précéder les --enable-* (l'ordre compte).
# Chaque option est justifiée dans docs/BUILDING_FFMPEG.md.
# --prefix est VOLONTAIREMENT omis : on ne fait pas `make install`, le binaire est
# pris dans le dossier de build. L'omettre évite d'inscrire un chemin de machine
# dans la chaîne de configuration gravée dans le binaire — chaîne publique, que
# `ffmpeg -version` affiche et que docs/BUILDING_FFMPEG.md reproduit à l'identique.
echo "▸ Configuration (LGPL, audio seul, statique)…"
./configure \
  --disable-gpl --disable-nonfree \
  --disable-autodetect --enable-zlib \
  --enable-static --disable-shared \
  --disable-doc --disable-debug --disable-network \
  --disable-ffplay --disable-ffprobe \
  --disable-avdevice \
  --disable-videotoolbox --disable-audiotoolbox --disable-sdl2 \
  --disable-everything \
  --enable-demuxer=mov,matroska,avi,mp3,wav,aac,ac3,eac3,dts,flac,ogg,asf,mpegts,mpegps,flv,aiff,au,caf,w64,wv,ape,tta,amr,mpc,mpc8,dsf,voc,rm,iff \
  --enable-decoder="$AUDIO_DEC" \
  --enable-parser=aac,aac_latm,ac3,dca,flac,mpegaudio,opus,vorbis,cook,dolby_e,gsm,mlp,sbc,tak,xma,amr,misc4 \
  --enable-bsf=aac_adtstoasc,extract_extradata,null \
  --enable-filter=aresample,aformat,anull,atrim,aselect,channelmap,pan,volume \
  --enable-muxer=wav,pcm_s16le \
  --enable-encoder=pcm_s16le,pcm_f32le,pcm_s24le,pcm_u8 \
  --enable-protocol=file,pipe

# Neuf décodeurs ADPCM/AHX de jeux vidéo sont GPL-only : configure les refuse et
# le signale. C'est ATTENDU, aucun n'est atteignable depuis les formats acceptés.

# --- 3) Compilation -------------------------------------------------------
echo "▸ Compilation…"
make -j"$(sysctl -n hw.ncpu)"

# --- 4) Contrôles de conformité ------------------------------------------
echo "▸ Contrôles…"

if ! ./ffmpeg -hide_banner -L 2>&1 | grep -q "Lesser General Public"; then
    echo "✗ Le binaire ne se déclare pas LGPL." >&2
    exit 1
fi
echo "  ✓ licence : LGPL"

if ./ffmpeg -version 2>/dev/null | grep -q -- "--enable-gpl"; then
    echo "✗ Le binaire contient des composants GPL." >&2
    exit 1
fi
echo "  ✓ aucun composant GPL"

if otool -L ./ffmpeg | tail -n +2 | grep -vE '/usr/lib/|/System/Library/' | grep -q .; then
    echo "✗ Dépendance non système détectée :" >&2
    otool -L ./ffmpeg | tail -n +2 | grep -vE '/usr/lib/|/System/Library/' >&2
    exit 1
fi
echo "  ✓ aucune dépendance non système"

echo
echo "✓ Binaire prêt : $PWD/ffmpeg"
echo "  taille  : $(stat -f%z ./ffmpeg) octets"
echo "  SHA-256 : $(shasum -a 256 ./ffmpeg | cut -d' ' -f1)"

# --- Garde : le binaire porte-t-il la cible demandée ? ----------------------
# Un binaire marqué d'une version minimale plus élevée que celle annoncée au
# téléchargement est un binaire qu'on ne sait pas si l'utilisateur peut lancer.
MINOS_OBTENU="$(vtool -show-build ./ffmpeg 2>/dev/null | awk '$1=="minos"{print $2}')"
if [[ "$MINOS_OBTENU" != "$MACOSX_DEPLOYMENT_TARGET" ]]; then
    echo "✗ Binaire marqué « minos $MINOS_OBTENU », cible demandée $MACOSX_DEPLOYMENT_TARGET." >&2
    echo "  La cible n'a pas été prise en compte — ne pas embarquer ce binaire." >&2
    exit 1
fi
echo "  ✓ minos $MINOS_OBTENU · sdk $(vtool -show-build ./ffmpeg 2>/dev/null | awk '$1=="sdk"{print $2}')"
echo
echo "  Pour l'embarquer (geste manuel et délibéré) :"
echo "    cp \"$PWD/ffmpeg\" \"$PROJECT_ROOT/Vendor/bin/ffmpeg\""
echo "    ./Scripts/build_app.sh --release"
