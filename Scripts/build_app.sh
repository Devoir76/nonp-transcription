#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https:#mozilla.org/MPL/2.0/.
# build_app.sh — compile l'app avec SwiftPM et l'assemble en bundle .app.
#
# Pourquoi ce script ? Sans Xcode complet, SwiftPM produit seulement un binaire
# en ligne de commande. macOS a besoin d'un bundle « .app » (dossier structuré
# avec Info.plist) pour lancer une vraie application graphique. Ce script fait
# le pont : il compile, crée la structure du bundle, y place le binaire et
# l'Info.plist, puis (optionnellement) lance l'app.
#
# Usage :
#   ./Scripts/build_app.sh            → build de TEST (identifiant .test) dans dist/
#   ./Scripts/build_app.sh --run      → idem puis lance l'application
#   ./Scripts/build_app.sh --debug    → compilation debug (plus rapide)
#   ./Scripts/build_app.sh --release  → build de PRODUCTION (identifiant normal)
#
# Pourquoi deux identifiants ?
# Deux bundles portant le MÊME CFBundleIdentifier sont indiscernables pour
# LaunchServices : macOS lance alors la copie de /Applications même quand on
# double-clique sur celle de dist/, et ce silencieusement. La build de test
# reçoit donc « com.nonp.transcription.test » pour rester totalement
# indépendante de la version installée. --release conserve l'identifiant de
# production (à utiliser uniquement pour installer une version de référence).

set -euo pipefail

# --- Emplacements ---------------------------------------------------------
# Racine du projet = dossier parent de ce script (robuste aux espaces du chemin).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="NONP Transcription"          # nom affiché du bundle
EXECUTABLE_NAME="NONPTranscription"    # doit correspondre à CFBundleExecutable
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# --- Options --------------------------------------------------------------
CONFIG="release"
DO_RUN="no"
FLAVOR="test"                          # test (défaut) | production
for arg in "$@"; do
    case "$arg" in
        --run)     DO_RUN="yes" ;;
        --debug)   CONFIG="debug" ;;
        --release) FLAVOR="production" ;;
        *) echo "Option inconnue : $arg" >&2; exit 1 ;;
    esac
done

# Identifiant appliqué au bundle selon le type de build.
if [[ "$FLAVOR" == "test" ]]; then
    BUNDLE_ID="com.nonp.transcription.test"
else
    BUNDLE_ID="com.nonp.transcription"
fi

# --- 1) Compilation SwiftPM ----------------------------------------------
echo "▸ Compilation ($CONFIG)…"
swift build -c "$CONFIG"

BUILD_BIN="$(swift build -c "$CONFIG" --show-bin-path)/$EXECUTABLE_NAME"
if [[ ! -f "$BUILD_BIN" ]]; then
    echo "✗ Binaire introuvable : $BUILD_BIN" >&2
    exit 1
fi

# --- 2) Assemblage du bundle .app ----------------------------------------
echo "▸ Assemblage du bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Applique l'identifiant correspondant au type de build (avant signature).
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"

# Icône de l'application (si présente).
if [[ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Logo affiché dans l'en-tête de la fenêtre. Absent du bundle (ou build lancée
# hors bundle, en debug), l'interface retombe sur l'icône système « waveform ».
if [[ -f "$PROJECT_ROOT/Resources/nonp_header_logo.png" ]]; then
    cp "$PROJECT_ROOT/Resources/nonp_header_logo.png" \
       "$APP_BUNDLE/Contents/Resources/nonp_header_logo.png"
fi

# --- 2b) Binaires embarqués (ffmpeg + whisper.cpp) -----------------------
# Les deux outils sont liés STATIQUEMENT : il suffit de les copier dans
# Resources/bin. Ils ne dépendent que de frameworks Apple et de libz du système.
#
# Historique (ADR-0005) : jusqu'à la V1.2.1, ffmpeg était un binaire dynamique
# accompagné de 18 dylibs dans Resources/lib, relocalisées par dylibbundler vers
# @executable_path/../lib. Le passage à un ffmpeg LGPL statique a supprimé le
# dossier lib/ (37 Mo) et toute l'étape de relocalisation. Ne pas les réintroduire
# sans revenir sur l'ADR : la structure bin/lib côte à côte n'est plus requise.
if [[ -d "$PROJECT_ROOT/Vendor/bin" ]]; then
    echo "▸ Copie des binaires embarqués (ffmpeg + whisper)…"
    mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
    cp "$PROJECT_ROOT/Vendor/bin/"* "$APP_BUNDLE/Contents/Resources/bin/"
    chmod +x "$APP_BUNDLE/Contents/Resources/bin/"*

    # Garde-fou : une dépendance dynamique NON système signalerait un binaire
    # mal construit (retour à un ffmpeg dynamique, dylib oubliée…). Le bundle
    # serait alors cassé chez l'utilisateur, mais fonctionnel sur cette machine —
    # panne invisible ici, d'où la vérification au build.
    for tool in "$APP_BUNDLE/Contents/Resources/bin/"*; do
        if otool -L "$tool" | tail -n +2 \
             | grep -vE '/usr/lib/|/System/Library/' | grep -q .; then
            echo "✗ $(basename "$tool") dépend d'une bibliothèque non système :" >&2
            otool -L "$tool" | tail -n +2 | grep -vE '/usr/lib/|/System/Library/' >&2
            exit 1
        fi
    done
    echo "  ✓ binaires autonomes (frameworks Apple + libz uniquement)"
else
    echo "  ⚠️  Vendor/bin introuvable — build sans moteur embarqué (interface seule)."
fi

# --- 2c) Textes de licence embarqués -------------------------------------
# Obligation LGPL-2.1 §4 : le binaire FFmpeg redistribué doit être accompagné du
# texte de sa licence — son propre avis interne (« ffmpeg -L ») renvoie d'ailleurs
# à une copie que l'utilisateur doit avoir reçue. Jusqu'à la 1.2.2 incluse, ces
# textes ne vivaient que dans le dépôt et sur la page de téléchargement : le ZIP
# distribué n'en contenait aucun.
#
# Source de vérité = les fichiers du dépôt, copiés ici au build. Aucune copie
# n'est maintenue dans Resources/ : elle divergerait en silence.
echo "▸ Copie des textes de licence…"
LICENSES_DST="$APP_BUNDLE/Contents/Resources/Licenses"
mkdir -p "$LICENSES_DST"

# « chemin source dans le dépôt : nom dans le bundle »
LICENSE_FILES=(
    "LICENSE:LICENSE"
    "Licenses/COPYING.LGPLv2.1:COPYING.LGPLv2.1"
    "THIRD_PARTY_NOTICES.md:THIRD_PARTY_NOTICES.md"
)
for entry in "${LICENSE_FILES[@]}"; do
    src="$PROJECT_ROOT/${entry%%:*}"
    dst="$LICENSES_DST/${entry##*:}"
    if [[ ! -s "$src" ]]; then
        echo "✗ Texte de licence manquant ou vide : ${entry%%:*}" >&2
        echo "  Le bundle ne peut pas être distribué sans lui (LGPL-2.1 §4)." >&2
        exit 1
    fi
    cp "$src" "$dst"
done

# Garde-fou final : un dossier absent ou vide arrête la build. Sans lui, une
# erreur de chemin produirait un bundle non conforme, silencieusement.
if [[ ! -d "$LICENSES_DST" || -z "$(ls -A "$LICENSES_DST")" ]]; then
    echo "✗ Contents/Resources/Licenses absent ou vide — build interrompue." >&2
    exit 1
fi
echo "  ✓ ${#LICENSE_FILES[@]} textes de licence embarqués"

# --- 3) Signature ad-hoc --------------------------------------------------
# Signature locale « ad-hoc » : suffisante pour un usage personnel quotidien,
# évite les blocages Gatekeeper au lancement local. (Pas de compte développeur requis.)
echo "▸ Signature ad-hoc…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "  (signature ad-hoc ignorée — non bloquant en local)"
}

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")
echo "✓ Application prête : $APP_BUNDLE"
if [[ "$FLAVOR" == "test" ]]; then
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │ BUILD DE TEST — version $VERSION — identifiant $BUNDLE_ID"
    echo "  │ Indépendante de la version installée dans /Applications.      │"
    echo "  │ Ne PAS installer telle quelle : utiliser --release pour cela. │"
    echo "  └──────────────────────────────────────────────────────────────┘"
else
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │ BUILD DE PRODUCTION — version $VERSION — identifiant $BUNDLE_ID"
    echo "  │ Destinée à remplacer la version de référence (/Applications). │"
    echo "  └──────────────────────────────────────────────────────────────┘"
fi

# --- 4) Lancement optionnel ----------------------------------------------
if [[ "$DO_RUN" == "yes" ]]; then
    echo "▸ Lancement…"
    open "$APP_BUNDLE"
fi
