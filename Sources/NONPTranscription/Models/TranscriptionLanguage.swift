// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// TranscriptionLanguage.swift — langues proposées dans le menu déroulant.
//
// Chaque cas connaît son nom affiché (français) et son code Whisper.
// « Auto » = détection automatique (aucun code passé au moteur).

import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case auto
    case english
    case german
    case spanish
    case french
    case italian

    var id: String { rawValue }

    /// Libellé affiché dans le menu.
    var displayName: String {
        switch self {
        case .auto:    return "Auto"
        case .english: return "Anglais"
        case .german:  return "Allemand"
        case .spanish: return "Espagnol"
        case .french:  return "Français"
        case .italian: return "Italien"
        }
    }

    /// Code langue transmis à whisper.cpp. `nil` = détection automatique.
    var whisperCode: String? {
        switch self {
        case .auto:    return nil
        case .english: return "en"
        case .german:  return "de"
        case .spanish: return "es"
        case .french:  return "fr"
        case .italian: return "it"
        }
    }
}
