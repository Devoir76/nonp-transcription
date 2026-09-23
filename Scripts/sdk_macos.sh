#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# ┌─ ORIGINE ────────────────────────────────────────────────────────────────┐
# │ Copié TEL QUEL depuis NONP Habillage (~/Developer/NONP-Habillage-App/    │
# │ Scripts/sdk_macos.sh, fichier du 20/09/2026, commit b3b7a58,             │
# │ SHA-256 2a1ede18…2683a) le 23/09/2026, pour la release 1.2.4.            │
# │                                                                          │
# │ Copie et non lien ni sous-module : chaque dépôt doit se fabriquer seul.  │
# │ Le corps est inchangé — toute correction faite d'un côté est à reporter  │
# │ de l'autre à la main, tant que le contournement dure.                    │
# │                                                                          │
# │ RAISON D'ÊTRE ICI. Mesuré le 23/09 : la 1.2.3 publiée porte « sdk 26.5 » │
# │ dans son LC_BUILD_VERSION, Habillage aussi. Une build faite avec le      │
# │ système de build par défaut de SwiftPM porte « sdk 14.0 » — et macOS     │
# │ règle une partie des métriques d'AppKit sur ce marquage. Sans ce         │
# │ fichier, la 1.2.4 ne compilerait pas du tout (plugin SwiftUIMacros       │
# │ absent), et si elle compilait, elle changerait de métriques alors        │
# │ qu'elle ne doit RIEN changer d'autre que le nettoyage.                   │
# │                                                                          │
# │ Les passages ci-dessous qui nomment verifier.sh, images_reference.sh ou  │
# │ campagne_parite.sh décrivent les scripts d'Habillage : ici, seul         │
# │ build_app.sh appelle ce fichier.                                         │
# └──────────────────────────────────────────────────────────────────────────┘
#
# sdk_macos.sh — choisit un SDK macOS capable de compiler SwiftUI.
#
# ┌─ CONTOURNEMENT DATÉ — À RETIRER ─────────────────────────────────────────┐
# │ Constaté le 17/09/2026, Command Line Tools 27.0 (Swift 6.4), macOS 27.   │
# └──────────────────────────────────────────────────────────────────────────┘
#
# LA CAUSE. Le SDK macOS 27.0 déclare `@State` — et les autres propriétés
# SwiftUI — comme des MACROS, dont l'implémentation est un plugin de
# compilateur, `SwiftUIMacros`. Les Command Line Tools 27.0 livrent ce SDK mais
# pas ce plugin : une recherche sur tout le disque ne l'a trouvé nulle part, sur
# une machine sans Xcode. Toute compilation SwiftUI échoue alors sur :
#
#   external macro implementation type 'SwiftUIMacros.StateMacro' could not be
#   found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
#
# Le code n'y est pour rien : `main` compilait le 07/09 et ne compile plus sans
# que rien n'ait changé dans le dépôt.
#
# LE CONTOURNEMENT. Les mêmes Command Line Tools installent aussi le SDK macOS
# 26.5, où `@State` n'est pas une macro. On vérifie donc d'abord que le SDK par
# défaut compile un fichier SwiftUI minimal ; s'il échoue SUR CETTE ERREUR-LÀ,
# on se replie sur le plus récent des autres SDK qui y parvient, et on le dit.
#
# ── LE SYSTÈME DE BUILD DÉCIDE DU MARQUAGE, LE MARQUAGE DÉCIDE D'APPKIT ──────
#
# Découvert le 17/09/2026, en cherchant pourquoi l'accueil mesurait 369 points
# au lieu de 377. C'est le genre de chose qu'on ne retrouve pas deux fois.
#
# 1. Chaque binaire porte dans son en-tête (LC_BUILD_VERSION) le numéro du SDK
#    contre lequel il a été compilé. `otool -l <binaire>` le montre, à la
#    ligne `sdk`.
#
# 2. macOS règle une partie de l'apparence d'AppKit et de SwiftUI sur CE
#    numéro — pas sur le SDK réellement utilisé, pas sur la version du
#    système. Un binaire marqué d'un vieux SDK reçoit d'anciennes métriques.
#
# 3. C'est le SYSTÈME DE BUILD qui écrit ce numéro. Le nouveau système de
#    SwiftPM, par défaut depuis Swift 6.4, compile bien contre le SDK 26.5 mais
#    inscrit « sdk 14.0 » — la version minimale du projet. `--sdk` n'y change
#    rien. L'ancien, `--build-system native`, inscrit « sdk 26.5 ».
#
# Mesuré sur cette machine (macOS 27.0), avec le même code :
#
#   système de build   marquage   ascenseur permanent   accueil
#   nouveau            sdk 14.0   15 points             369 points
#   native             sdk 26.5   17 points             377 points
#
# Le binaire du 07/09 — ancien système, marqué 26.5 — mesure 377 sur ce même
# macOS 27 : le système d'exploitation n'y est pour rien.
#
# CE QUI EST CONCERNÉ. Toute build produite par le nouveau système depuis
# l'installation des Command Line Tools 27.0, le 12/09. Dans ce dépôt, aucune
# n'a abouti avant le 17/09 — la compilation échouait sur la macro —, et la
# première date du 17/09 à 16:12 : ce sont donc toutes les builds du 17/09
# antérieures à ce correctif. Y compris les deux builds de test sur lesquelles
# le correctif de la colonne des réglages (bb2238a) a été vérifié à l'œil, et
# la vérification qui l'a étalonné : ascenseur de 15 points, alors qu'il en
# fait 17 avec le bon marquage. Cet étalonnage a été repris sur
# fix/colonne-metriques-reelles : colonne de 365 points, réserve de 17.
#
# LA PARADE. Les scripts compilent avec `--build-system native` — la chaîne
# qui a produit toutes les builds validées jusqu'au 07/09 —, et
# `verifier_marquage_sdk` contrôle après chaque compilation que le binaire est
# marqué du SDK qu'on a choisi. Un marquage faux arrête le script : des mesures
# prises sous d'autres métriques ne valent rien, et l'erreur ne se voit pas.
#
# L'option est dépréciée (SwiftPM l'annonce à chaque appel). Peu importe : elle
# part avec le reste du contournement.
#
# ── QUAND LE RETIRER ────────────────────────────────────────────────────────
#
# Le jour où le script annonce « SDK par défaut… aucun contournement » —
# Command Line Tools corrigés, ou Xcode complet sélectionné. Retirer alors le
# repli, les appels des trois scripts (build_app.sh, verifier.sh,
# images_reference.sh) et la ligne du README.
#
# MAIS garder `verifier_marquage_sdk` tant que le nouveau système de build n'a
# pas été éprouvé : s'il marque encore mal avec le SDK par défaut, abandonner
# `--build-system native` rouvrirait le défaut en silence.
#
# ── USAGE ───────────────────────────────────────────────────────────────────
#
#   source "$SCRIPT_DIR/sdk_macos.sh"
#   choisir_sdk_macos || exit 1
#   swift build -c release "${OPTIONS_SWIFT_BUILD[@]}"
#   BINAIRE="$(swift build -c release "${OPTIONS_SWIFT_BUILD[@]}" --show-bin-path)/NONPHabillage"
#   verifier_marquage_sdk "$BINAIRE" || exit 1
#
# Les mêmes options pour `--show-bin-path` : les deux systèmes de build ne
# rangent pas leurs produits au même endroit.
#
# SDKROOT déjà défini est respecté : il est éprouvé, jamais remplacé en silence.

# Options de `swift build`, communes à tous les scripts. Voir « La parade ».
OPTIONS_SWIFT_BUILD=(--build-system native)

# Compile — vérification des types seulement — un fichier SwiftUI qui utilise
# `@State`. Rend 0 si le SDK passe ; sinon écrit la sortie du compilateur dans
# le fichier donné en second argument.
_sonde_swiftui() {
    local sdk="$1" sortie="$2" source
    source="$(mktemp -t nonp-sonde-sdk).swift"
    cat > "$source" <<'SWIFT'
import SwiftUI
struct SondeSDK: View {
    @State private var n = 0
    var body: some View { Text("\(n)") }
}
SWIFT
    local rc=0
    xcrun swiftc -typecheck -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" \
        "$source" > "$sortie" 2>&1 || rc=$?
    rm -f "$source" "${source%.swift}"
    return "$rc"
}

# « macOS 26.5 » d'après le SDK lui-même.
_version_sdk() {
    local v
    v="$(plutil -extract Version raw "$1/SDKSettings.plist" 2>/dev/null)" || v="?"
    echo "macOS $v"
}

# L'erreur connue : un plugin de macro introuvable.
_erreur_de_macro() {
    grep -q "external macro implementation type .* could not be found" "$1"
}

choisir_sdk_macos() {
    echo "▸ Choix du SDK macOS…"
    echo "  · système de build : ${OPTIONS_SWIFT_BUILD[*]} — il décide du marquage du"
    echo "    binaire, donc des métriques d'AppKit (voir Scripts/sdk_macos.sh)"
    local journal
    journal="$(mktemp -t nonp-sonde-sdk-journal)"

    # 1. SDKROOT imposé : on l'éprouve, on ne le remplace pas.
    if [[ -n "${SDKROOT:-}" ]]; then
        if _sonde_swiftui "$SDKROOT" "$journal"; then
            echo "  ✓ SDK imposé par SDKROOT : $(_version_sdk "$SDKROOT") ($SDKROOT)"
            rm -f "$journal"
            return 0
        fi
        echo "✗ SDKROOT désigne un SDK qui ne compile pas SwiftUI : $SDKROOT" >&2
        grep -m1 "error:" "$journal" | sed 's/^.*error: /error: /; s/^/    /' >&2
        echo "  Retirer SDKROOT pour laisser le script choisir, ou désigner un" >&2
        echo "  SDK macOS 26.x." >&2
        rm -f "$journal"
        return 1
    fi

    # 2. Le SDK par défaut.
    local defaut
    defaut="$(xcrun --sdk macosx --show-sdk-path)"
    if _sonde_swiftui "$defaut" "$journal"; then
        echo "  ✓ SDK par défaut : $(_version_sdk "$defaut") ($defaut) — aucun contournement"
        rm -f "$journal"
        return 0
    fi

    # Une autre erreur que celle qu'on sait contourner : ne rien masquer. La
    # compilation la montrera en entier.
    if ! _erreur_de_macro "$journal"; then
        echo "  ⚠️  La sonde SwiftUI échoue sur le SDK par défaut ($defaut)," >&2
        echo "     mais pas sur l'erreur de macro connue. Aucun repli :" >&2
        grep -m1 "error:" "$journal" | sed 's/^.*error: /error: /; s/^/     /' >&2
        rm -f "$journal"
        return 0
    fi

    echo "  ⚠️  SDK par défaut inutilisable : $(_version_sdk "$defaut") ($defaut)"
    echo "     Il déclare @State comme une macro, et ces Command Line Tools ne"
    echo "     livrent pas le plugin SwiftUIMacros qui l'implémente."

    # 3. Les autres SDK du même dossier : vrais dossiers seulement (les liens
    #    MacOSX.sdk, MacOSX27.sdk… désignent les mêmes), du plus récent au plus
    #    ancien.
    local dossier reel_defaut
    reel_defaut="$(cd "$defaut" && pwd -P)"
    dossier="$(dirname "$reel_defaut")"
    local candidats
    candidats="$(
        for sdk in "$dossier"/MacOSX*.sdk; do
            [[ -d "$sdk" && ! -L "$sdk" && "$sdk" != "$reel_defaut" ]] || continue
            printf '%s\t%s\n' "$(plutil -extract Version raw "$sdk/SDKSettings.plist" 2>/dev/null || echo 0)" "$sdk"
        done | sort -t. -k1,1nr -k2,2nr -k3,3nr | cut -f2
    )"

    local sdk
    while IFS= read -r sdk; do
        [[ -n "$sdk" ]] || continue
        if _sonde_swiftui "$sdk" "$journal"; then
            export SDKROOT="$sdk"
            echo "  ✓ Repli sur $(_version_sdk "$sdk") ($sdk) — sonde SwiftUI réussie"
            echo "     Contournement daté du 17/09/2026, à retirer quand le SDK par"
            echo "     défaut compilera de nouveau : voir Scripts/sdk_macos.sh."
            rm -f "$journal"
            return 0
        fi
    done <<< "$candidats"

    # 4. Rien d'utilisable : expliquer, et nommer les issues.
    cat >&2 <<MESSAGE
✗ Aucun SDK macOS ne permet de compiler SwiftUI sur cette machine.

  Le SDK par défaut ($(_version_sdk "$defaut")) déclare @State et les autres
  propriétés SwiftUI comme des macros. Leur implémentation, le plugin
  SwiftUIMacros, n'est pas livrée par ces Command Line Tools, et aucun autre
  SDK de $dossier
  ne compile SwiftUI. Le code du projet n'est pas en cause.

  Issues :
    1. Désigner un SDK macOS 26.x conservé ailleurs :
         SDKROOT=~/MacOSX26.5.sdk $0
    2. Installer Xcode complet, puis le sélectionner :
         sudo xcode-select -s /Applications/Xcode.app
    3. Installer des Command Line Tools qui livrent ce plugin, quand Apple
       les publiera.

  Détail : Scripts/sdk_macos.sh (contournement daté du 17/09/2026).
MESSAGE
    rm -f "$journal"
    return 1
}

# Le SDK effectivement choisi : SDKROOT s'il est posé, le SDK par défaut sinon.
_sdk_choisi() {
    if [[ -n "${SDKROOT:-}" ]]; then echo "$SDKROOT"
    else xcrun --sdk macosx --show-sdk-path
    fi
}

# « 26.5.0 » et « 26.5 » désignent le même SDK.
_version_courte() {
    local v="$1"
    while [[ "$v" == *.0 ]]; do v="${v%.0}"; done
    echo "$v"
}

# Contrôle que le binaire est marqué du SDK choisi. Voir « Le système de build
# décide du marquage » en tête de fichier.
verifier_marquage_sdk() {
    local binaire="$1" sdk attendu inscrit
    sdk="$(_sdk_choisi)"
    attendu="$(plutil -extract Version raw "$sdk/SDKSettings.plist" 2>/dev/null || echo "?")"
    inscrit="$(otool -l "$binaire" 2>/dev/null \
        | awk '/LC_BUILD_VERSION/ { dans = 1 } dans && $1 == "sdk" { print $2; exit }')"

    if [[ -n "$inscrit" && "$(_version_courte "$inscrit")" == "$(_version_courte "$attendu")" ]]; then
        echo "  ✓ Binaire marqué « sdk $inscrit », comme le SDK utilisé"
        return 0
    fi
    cat >&2 <<MESSAGE
✗ Binaire marqué « sdk ${inscrit:-illisible} », mais compilé avec le SDK macOS $attendu.
    $binaire

  macOS règle une partie de l'apparence d'AppKit sur ce marquage : ce binaire
  tournerait avec les métriques d'un autre SDK, et ses mesures de disposition
  ne vaudraient rien. C'est le système de build qui écrit ce marquage.

  Voir Scripts/sdk_macos.sh, « Le système de build décide du marquage ».
MESSAGE
    return 1
}
