// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// QualityPreset.swift — niveaux de qualité proposés dans le menu.
//
// « Qualité maximale » = large-v3 (fidélité maximale, décodage soigné).
// « Rapide »          = large-v3-turbo (quasi aussi précis, plus rapide).
//
// Le nom de modèle sert dès l'Étape 2 (téléchargement) et l'Étape 3 (moteur).
// L'ordre des cas définit l'ordre du menu ; la valeur par défaut (Qualité
// maximale) est fixée dans AppState, conformément à votre priorité de fidélité.

import Foundation

enum QualityPreset: String, CaseIterable, Identifiable, Sendable {
    case fast       // affiché en premier
    case maximum

    var id: String { rawValue }

    /// Libellé affiché dans le menu.
    var displayName: String {
        switch self {
        case .fast:    return "Rapide"
        case .maximum: return "Qualité maximale"
        }
    }

    /// Petite explication affichée sous le menu.
    var subtitle: String {
        switch self {
        case .fast:    return "large-v3-turbo — plus rapide, très bonne fidélité"
        case .maximum: return "large-v3 — fidélité maximale (recommandé)"
        }
    }

    /// Nom du modèle whisper.cpp associé (fichier GGML téléchargé à l'Étape 2).
    var modelName: String {
        switch self {
        case .fast:    return "large-v3-turbo"
        case .maximum: return "large-v3"
        }
    }
}
