// TranscriptSegment.swift — un segment de transcription horodaté.
//
// C'est l'unité de base produite par le moteur : un intervalle de temps + le
// texte exact prononcé. Volontairement neutre (ni SRT ni TXT) : l'export dans
// différents formats se fait ensuite (SubtitleExporter, Étape 4), et les futures
// fonctions (traduction, découpage) manipuleront aussi ces segments.

import Foundation

struct TranscriptSegment: Identifiable, Sendable, Equatable {
    let id: Int
    /// Début du segment, en millisecondes depuis le début du média.
    let startMs: Int
    /// Fin du segment, en millisecondes.
    let endMs: Int
    /// Texte exact du segment (aucune reformulation, aucun résumé).
    let text: String
}
