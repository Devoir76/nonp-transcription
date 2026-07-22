#!/bin/bash
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

# --- 2b) Binaires embarqués (ffmpeg + whisper.cpp) -----------------------
# On place les outils dans Resources/bin et leurs bibliothèques dans
# Resources/lib. ffmpeg a été relocalisé (dylibbundler) pour chercher ses
# bibliothèques via @executable_path/../lib : depuis Resources/bin, cela
# pointe vers Resources/lib. La structure bin/lib côte à côte est donc requise.
if [[ -d "$PROJECT_ROOT/Vendor/bin" ]]; then
    echo "▸ Copie des binaires embarqués (ffmpeg + whisper)…"
    mkdir -p "$APP_BUNDLE/Contents/Resources/bin" "$APP_BUNDLE/Contents/Resources/lib"
    cp "$PROJECT_ROOT/Vendor/bin/"* "$APP_BUNDLE/Contents/Resources/bin/"
    cp "$PROJECT_ROOT/Vendor/lib/"*.dylib "$APP_BUNDLE/Contents/Resources/lib/" 2>/dev/null || true
    chmod +x "$APP_BUNDLE/Contents/Resources/bin/"*
else
    echo "  ⚠️  Vendor/bin introuvable — build sans moteur embarqué (interface seule)."
fi

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
