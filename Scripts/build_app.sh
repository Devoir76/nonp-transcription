#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
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
#   ./Scripts/build_app.sh --verifier <bundle.app>
#                                     → passe les GARDES sur un bundle existant,
#                                       sans rien compiler ni modifier.
#
# Pourquoi --verifier ? Une garde dont on n'a jamais vu l'échec n'est pas une
# garde. Cette option permet de la braquer sur un bundle connu pour être fautif
# (par exemple la 1.2.3 publiée) et de vérifier qu'elle s'arrête bien. Elle ne
# fabrique rien : c'est une lecture.
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
VERIFY_ONLY=""                         # chemin d'un .app à contrôler, sans fabriquer
attend_chemin="no"
for arg in "$@"; do
    if [[ "$attend_chemin" == "yes" ]]; then
        VERIFY_ONLY="$arg"; attend_chemin="no"; continue
    fi
    case "$arg" in
        --run)      DO_RUN="yes" ;;
        --debug)    CONFIG="debug" ;;
        --release)  FLAVOR="production" ;;
        --verifier) attend_chemin="yes" ;;
        *) echo "Option inconnue : $arg" >&2; exit 1 ;;
    esac
done
if [[ "$attend_chemin" == "yes" ]]; then
    echo "✗ --verifier attend le chemin d'un bundle .app" >&2
    exit 1
fi

# Identifiant appliqué au bundle selon le type de build.
if [[ "$FLAVOR" == "test" ]]; then
    BUNDLE_ID="com.nonp.transcription.test"
else
    BUNDLE_ID="com.nonp.transcription"
fi

# --- 0) Choix du SDK macOS ------------------------------------------------
# Contournement daté du 17/09/2026, repris d'Habillage : les Command Line Tools
# 27.0 livrent un SDK où @State est une macro, mais pas le plugin qui
# l'implémente. Le fichier choisit un SDK qui compile, impose le système de
# build qui MARQUE correctement le binaire, et fournit les deux gardes de
# marquage. Tout le détail — et la condition de retrait — y est écrit.
source "$SCRIPT_DIR/sdk_macos.sh"

# --- 0b) Gardes de fabrication -------------------------------------------
# Elles portent sur le bundle ASSEMBLÉ — celui qui part dans le ZIP — et non sur
# les sources ni sur le binaire nu. C'est précisément l'angle mort qui a laissé
# passer les deux défauts de la 1.2.3 : le harnais de test ne voit que le binaire
# compilé par SwiftPM, jamais le .app.
#
# Aucune garde n'affiche la VALEUR d'un chemin personnel : seulement des comptes.

# Nombre d'occurrences du dossier personnel dans un fichier. On compte les
# OCCURRENCES (grep -o) et non les lignes : un binaire n'a pas de lignes, et
# quarante chemins collés dans la même « ligne » compteraient pour un seul.
compter_dossier_personnel() {
    local n
    n=$(LC_ALL=C grep -oaF "$HOME" "$1" 2>/dev/null | wc -l | tr -d ' ') || true
    echo "${n:-0}"
}

# Entrées de débogage restantes. N_OSO porte le chemin absolu de chaque .o,
# N_SO celui du dossier des sources : les deux nomment la machine de fabrication.
# Mesuré sur la 1.2.3 publiée : 29 OSO + 88 SO, et 58 occurrences du dossier
# personnel, TOUTES dans la table des chaînes de symboles — aucune dans le code.
compter_stabs() {
    nm -pa "$1" 2>/dev/null | grep -cE ' (OSO|SO) ' || true
}

# Contrôle d'un Mach-O : plus aucune entrée de débogage, plus aucun chemin perso.
verifier_macho() {
    local f="$1" stabs occ
    stabs=$(compter_stabs "$f")
    occ=$(compter_dossier_personnel "$f")
    echo "    $(basename "$f") : entrées OSO/SO $stabs · occurrences du dossier personnel $occ"
    [[ "$stabs" -eq 0 && "$occ" -eq 0 ]]
}

# TOUS les Mach-O du bundle, quels qu'ils soient : le jour où un binaire s'ajoute
# à Resources/bin, il est contrôlé sans qu'on ait à penser à l'inscrire ici.
verifier_chemins_bundle() {
    local bundle="$1" f n=0 defauts=0
    echo "▸ Garde des chemins (tous les Mach-O du bundle)…"
    while IFS= read -r f; do
        file -b "$f" | grep -q 'Mach-O' || continue
        n=$((n + 1))
        verifier_macho "$f" || defauts=$((defauts + 1))
    done < <(find "$bundle" -type f)

    if [[ "$n" -eq 0 ]]; then
        echo "✗ Aucun Mach-O trouvé dans le bundle — contrôle sans objet, build interrompue." >&2
        return 1
    fi
    if [[ "$defauts" -ne 0 ]]; then
        echo "✗ $defauts Mach-O sur $n portent encore une table de débogage ou un" >&2
        echo "  chemin de la machine de fabrication — build interrompue." >&2
        echo "  (dsymutil puis strip -S doivent précéder la signature.)" >&2
        return 1
    fi
    echo "  ✓ $n Mach-O contrôlés : aucune entrée de débogage, aucun chemin personnel"
}

# Garde de langue. Mesuré le 22/09 sur NONP Habillage : sans langue déclarée,
# macOS tient l'application pour anglaise et affiche en anglais les menus qu'il
# fournit — Édition, Fenêtre, Aide, « Réglages… », « Quitter ». L'application
# n'en déclare aucun elle-même : ils viennent tous de macOS. Deux clés suffisent,
# sans dossier fr.lproj — vérifié à l'écran.
verifier_langue_francaise() {
    local plist="$1" region langues
    region=$(plutil -extract CFBundleDevelopmentRegion raw "$plist" 2>/dev/null || true)
    langues=$(plutil -extract CFBundleLocalizations json -o - "$plist" 2>/dev/null || true)
    if [[ "$region" != "fr" ]] || ! grep -q '"fr"' <<< "$langues"; then
        echo "✗ L'Info.plist du bundle ne déclare pas le français" >&2
        echo "  (CFBundleDevelopmentRegion = « ${region:-absent} »," \
             "CFBundleLocalizations = ${langues:-absent}) — build interrompue." >&2
        echo "  Sans cette déclaration, les menus fournis par macOS s'affichent" \
             "en anglais." >&2
        return 1
    fi
    echo "  ✓ langue déclarée : français (menus de macOS en français)"
}

# Marquage du bundle assemblé. `verifier_marquage_sdk` (sdk_macos.sh) contrôle
# le binaire nu sorti de SwiftPM ; celle-ci contrôle celui qui part vraiment,
# après strip — un chaînon qui manquerait sinon.
#
# Seul l'exécutable de l'application est contrôlé. Les moteurs de Resources/bin
# sont versionnés, redistribués à l'identique et portent le marquage de leur
# propre compilation : le leur n'a pas à coïncider avec le SDK du jour.
verifier_marquage_bundle() {
    local bundle="$1" exe
    exe=$(plutil -extract CFBundleExecutable raw "$bundle/Contents/Info.plist" 2>/dev/null || true)
    if [[ -z "$exe" || ! -f "$bundle/Contents/MacOS/$exe" ]]; then
        echo "✗ Exécutable introuvable dans le bundle — contrôle impossible." >&2
        return 1
    fi
    verifier_marquage_sdk "$bundle/Contents/MacOS/$exe"
}

# Garde de version minimale et de SDK — sur TOUS les Mach-O du bundle.
#
# Mesuré le 24/09 sur la 1.2.3 publiée : l'exécutable déclarait « minos 14.0 »,
# les deux moteurs embarqués « minos 26.0 » — la version de la machine qui les
# avait compilés. Personne ne l'avait décidé : aucune cible n'était fixée. La
# page de téléchargement promet pourtant « macOS 14 ou plus récent ».
#
# Un binaire dont la version minimale dépasse celle du système se lance quand
# même (mesuré), mais il peut appeler des API absentes — et alors il échoue au
# lancement, chez l'utilisateur, pas ici. Ce que cette garde vérifie n'est donc
# pas une promesse de fonctionnement : c'est que le bundle dit d'une seule voix
# ce qu'il exige, et que cette voix est celle de l'Info.plist.
verifier_version_minimale() {
    local bundle="$1" f
    local attendu sdk_attendu n=0 defauts=0
    attendu=$(plutil -extract LSMinimumSystemVersion raw "$bundle/Contents/Info.plist" 2>/dev/null || true)
    if [[ -z "$attendu" ]]; then
        echo "✗ LSMinimumSystemVersion absent de l'Info.plist — rien à comparer." >&2
        return 1
    fi
    # Le SDK de référence est celui de l'exécutable de l'application : c'est lui
    # que la fabrication vient de produire, et les moteurs doivent le suivre.
    local exe
    exe=$(plutil -extract CFBundleExecutable raw "$bundle/Contents/Info.plist" 2>/dev/null || true)
    sdk_attendu=$(vtool -show-build "$bundle/Contents/MacOS/$exe" 2>/dev/null | awk '$1=="sdk"{print $2}')

    echo "▸ Garde de version minimale (attendu : minos $attendu · sdk $sdk_attendu)…"
    while IFS= read -r f; do
        file -b "$f" | grep -q 'Mach-O' || continue
        n=$((n + 1))
        local m s
        m=$(vtool -show-build "$f" 2>/dev/null | awk '$1=="minos"{print $2}')
        s=$(vtool -show-build "$f" 2>/dev/null | awk '$1=="sdk"{print $2}')
        echo "    $(basename "$f") : minos $m · sdk $s"
        [[ "$m" == "$attendu" && "$s" == "$sdk_attendu" ]] || defauts=$((defauts + 1))
    done < <(find "$bundle" -type f)

    if [[ "$defauts" -ne 0 ]]; then
        echo "✗ $defauts Mach-O sur $n ne déclarent pas la même version minimale" >&2
        echo "  ou le même SDK que l'application — build interrompue." >&2
        echo "  Refabriquer les moteurs : Scripts/build_ffmpeg_lgpl.sh et Scripts/build_whisper.sh." >&2
        return 1
    fi
    echo "  ✓ $n Mach-O déclarent tous minos $attendu et sdk $sdk_attendu"
}

# Signature : contrôlée APRÈS le strip, qui l'invalide et le dit lui-même.
verifier_signature() {
    codesign --verify --deep --strict "$1" 2>/dev/null || {
        echo "✗ Signature invalide — build interrompue." >&2
        echo "  (strip invalide la signature : codesign doit venir APRÈS.)" >&2
        return 1
    }
    echo "  ✓ signature vérifiée (--deep --strict)"
}

# Mode contrôle seul : on braque les gardes sur un bundle existant et on sort.
# Rien n'est compilé, rien n'est modifié — c'est une lecture.
if [[ -n "$VERIFY_ONLY" ]]; then
    if [[ ! -d "$VERIFY_ONLY" ]]; then
        echo "✗ Bundle introuvable : $VERIFY_ONLY" >&2
        exit 1
    fi
    echo "▸ Contrôle seul, aucune fabrication."
    # Le SDK est choisi même ici : la garde de marquage a besoin de savoir à
    # quoi comparer. La sonde ne fait qu'une vérification de types, elle ne
    # produit aucun binaire.
    choisir_sdk_macos || exit 1
    echec=0
    verifier_chemins_bundle "$VERIFY_ONLY"               || echec=1
    echo "▸ Garde de marquage SDK…"
    verifier_marquage_bundle "$VERIFY_ONLY"              || echec=1
    verifier_version_minimale "$VERIFY_ONLY"             || echec=1
    echo "▸ Garde de langue…"
    verifier_langue_francaise "$VERIFY_ONLY/Contents/Info.plist" || echec=1
    echo "▸ Garde de signature…"
    verifier_signature "$VERIFY_ONLY"                    || echec=1
    if [[ "$echec" -ne 0 ]]; then
        echo "✗ Ce bundle ne passerait PAS la fabrication." >&2
        exit 1
    fi
    echo "✓ Ce bundle passe toutes les gardes."
    exit 0
fi

# --- 1) Compilation SwiftPM ----------------------------------------------
# Fabrication DÉTERMINISTE — mesuré le 24/09.
#
# Deux fabrications du même arbre rendaient deux CDHash différents. La cause
# n'était pas un hasard : l'éditeur de liens calcule le LC_UUID sur le contenu,
# carte de débogage comprise, et chaque entrée N_OSO porte l'HORODATAGE de son
# fichier objet. Deux compilations, deux horodatages, donc deux UUID — et comme
# la signature couvre l'UUID, deux CDHash. Mesuré : chemins OSO identiques,
# seules les dates changeaient ; 29 entrées, 29 octets de différence.
#
# `strip` retire ensuite ces entrées, mais trop tard : l'UUID est déjà gravé.
#
# ZERO_AR_DATE=1 fait écrire 0 à la place de ces horodatages. La variable n'est
# documentée dans aucune page de manuel ; elle est lue par le `ld` d'Apple, dont
# le binaire porte la chaîne. Mesuré avec : dates OSO à zéro, même UUID, même
# CDHash, binaires IDENTIQUES octet pour octet sur deux fabrications.
#
# Fixé ICI et non dans l'environnement : un réglage qu'on oublie de poser rend
# un bundle qu'on ne saura pas rattacher à un commit.
export ZERO_AR_DATE=1

choisir_sdk_macos || exit 1

echo "▸ Compilation ($CONFIG)…"
swift build -c "$CONFIG" "${OPTIONS_SWIFT_BUILD[@]}"

# Les MÊMES options pour --show-bin-path : les deux systèmes de build ne rangent
# pas leurs produits au même endroit.
BUILD_BIN="$(swift build -c "$CONFIG" "${OPTIONS_SWIFT_BUILD[@]}" --show-bin-path)/$EXECUTABLE_NAME"
if [[ ! -f "$BUILD_BIN" ]]; then
    echo "✗ Binaire introuvable : $BUILD_BIN" >&2
    exit 1
fi

# Marquage du binaire nu, au plus près de sa production : si le système de build
# a inscrit un autre SDK que celui qu'on a choisi, rien de ce qui suit ne vaut.
verifier_marquage_sdk "$BUILD_BIN" || exit 1

# --- 2) Assemblage du bundle .app ----------------------------------------
echo "▸ Assemblage du bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Applique l'identifiant correspondant au type de build (avant signature).
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"

# Garde de langue, sur l'Info.plist du bundle assemblé (pas sur la source).
echo "▸ Garde de langue…"
verifier_langue_francaise "$APP_BUNDLE/Contents/Info.plist" || exit 1

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

# --- 2d) Table de débogage : trois gestes, dans cet ordre ------------------
# Mesuré le 21/09 sur la 1.2.3 PUBLIÉE : son binaire portait 29 entrées N_OSO,
# 88 entrées N_SO et 58 occurrences du dossier personnel de la machine de
# fabrication — toutes dans la table des chaînes de symboles, aucune dans le
# code. Rien ne fuyait par le dépôt : la fuite naissait au build.
#
#   1. dsymutil — extrait la table AVANT de la détruire. Après le strip elle est
#      perdue, et plus aucun rapport de plantage ne sera symbolisable.
#   2. strip -S — retire la table du binaire. Mesuré : 58 → 0 occurrences,
#      117 → 0 entrées OSO/SO. Le strip complet ne retire rien de plus côté fuite.
#   3. codesign — EN DERNIER : strip invalide la signature et le dit lui-même en
#      avertissement. Signer avant le strip, c'est livrer un bundle que macOS
#      déclare « endommagé ».
#
# Le dSYM ne va NI dans dist/ NI dans le ZIP : il porte exactement les mêmes
# chemins. Il vit hors dépôt, à côté des traces de session, pour permettre de
# symboliser un rapport de plantage après coup.
#
# Seul le binaire de l'application est strippé. Les moteurs embarqués sont
# versionnés dans Vendor/bin et redistribués À L'IDENTIQUE — leurs empreintes
# SHA-256 sont publiées dans THIRD_PARTY_NOTICES.md. Mesuré : ils ne portent
# déjà aucune entrée de débogage ni aucun chemin personnel. La garde les
# contrôle quand même, elle ne les modifie pas.
DSYM_DIR="${NONP_DSYM_DIR:-$HOME/Developer/NONP-traces/dsym}"
BIN_APP="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

echo "▸ Extraction de la table de débogage…"
mkdir -p "$DSYM_DIR"
if dsymutil "$BIN_APP" -o "$DSYM_DIR/$EXECUTABLE_NAME-$FLAVOR.dSYM" 2>/dev/null; then
    echo "  ✓ dSYM conservé hors dépôt"
else
    echo "  ⚠️  dsymutil n'a rien produit — poursuite, le strip reste nécessaire"
fi

echo "▸ Retrait de la table de débogage…"
strip -S "$BIN_APP"

# --- 2e) Gardes sur le bundle assemblé ------------------------------------
# Placées AVANT la signature : un bundle fautif ne doit même pas être signé.
verifier_chemins_bundle "$APP_BUNDLE" || exit 1
echo "▸ Garde de marquage SDK…"
verifier_marquage_bundle "$APP_BUNDLE" || exit 1
verifier_version_minimale "$APP_BUNDLE" || exit 1

# --- 3) Signature ad-hoc --------------------------------------------------
# Signature locale « ad-hoc » : suffisante pour un usage personnel quotidien,
# évite les blocages Gatekeeper au lancement local. (Pas de compte développeur requis.)
# APRÈS le strip, jamais avant : voir l'ordre des trois gestes ci-dessus.
echo "▸ Signature ad-hoc…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "  (signature ad-hoc ignorée — non bloquant en local)"
}
verifier_signature "$APP_BUNDLE" || exit 1

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
