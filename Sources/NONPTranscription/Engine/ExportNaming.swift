// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// ExportNaming.swift — construction du nom de base des fichiers exportés.
//
// Un export porte le code de la langue de l'AUDIO avant l'extension :
//   <base>_<code>.<ext>   →   entretien_fr.srt, interview_en.txt
//
// L'application ne traduit pas : le suffixe décrit donc la langue parlée dans
// le fichier source, jamais une langue cible. Le code vient du résultat
// canonique du moteur (langue détectée, ou langue imposée par l'utilisateur).
//
// Fonction PURE, sans accès disque : c'est le point unique où le nom se décide,
// afin qu'il soit testable sans lancer de transcription (cf. SelfTest
// --naming-cases). L'anti-collision, elle, reste dans SubtitleExporter — elle a
// besoin du système de fichiers.
//
// Règle de repli : à défaut de code exploitable, on n'invente RIEN. Le fichier
// garde son nom nu (`<base>.<ext>`) plutôt que de porter un « _xx », un
// « _unknown » ou un « _auto » qui affirmerait une langue non établie.

import Foundation

enum ExportNaming {

    /// Normalise le code renvoyé par le moteur en code ISO 639-1 utilisable
    /// comme suffixe, ou `nil` si rien d'exploitable.
    ///
    /// Acceptés : deux lettres ASCII, casse et espaces indifférents (« FR » →
    /// « fr »). Rejetés : `nil`, chaîne vide, « auto » (le moteur n'a pas
    /// tranché), et tout code hors ISO 639-1 — dont les codes à trois lettres
    /// de whisper qui n'ont pas d'équivalent à deux (« yue », cantonais) :
    /// mieux vaut aucun suffixe qu'un suffixe d'une autre nomenclature.
    static func normalizedLanguageCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return code
    }

    /// Nom de base des fichiers exportés, extension exclue.
    ///
    /// - Parameters:
    ///   - source: nom du fichier média, sans extension (« entretien »).
    ///   - languageCode: code brut issu du résultat de transcription.
    ///
    /// Le nom source est repris tel quel : s'il se termine déjà par « _fr », on
    /// obtient « entretien_fr_fr ». C'est délibéré — deviner qu'un suffixe
    /// existant désigne une langue serait une correction automatique du nom
    /// choisi par l'utilisateur, et le résultat resterait ambigu (« _it » peut
    /// être une abréviation quelconque). Prévisible plutôt que malin.
    static func baseName(source: String, languageCode: String?) -> String {
        guard let code = normalizedLanguageCode(languageCode) else { return source }
        return "\(source)_\(code)"
    }
}
