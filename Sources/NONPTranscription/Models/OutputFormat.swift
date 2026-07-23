// OutputFormat.swift — formats de sortie proposés à l'utilisateur.
//
// Source unique de vérité : extension, libellé et icône par format. Neutre
// vis-à-vis des frameworks Apple (Foundation seul) — cohérent avec la future
// extraction NONPCore (ADR-0001). Voir ADR-0002.

import Foundation

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case srt        // sous-titres horodatés (montage)
    case txt        // texte brut (lecture, citation)
    case vtt        // sous-titres WebVTT (web, <track>)

    var id: String { rawValue }

    /// Extension de fichier (sans point). Distincte de `rawValue` par intention,
    /// même si elles coïncident aujourd'hui.
    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .srt: return "SRT — sous-titres horodatés"
        case .txt: return "TXT — texte brut"
        case .vtt: return "VTT — sous-titres WebVTT"
        }
    }

    /// Icône SF Symbols (réutilisée par l'écran de fin).
    var icon: String {
        switch self {
        case .srt: return "doc.text"
        case .txt: return "doc.plaintext"
        case .vtt: return "captions.bubble"
        }
    }

    /// Défaut sûr : reproduit le comportement V1 (les deux formats).
    static let defaultSet: Set<OutputFormat> = [.srt, .txt]
}

/// Un fichier réellement produit par l'export : quel format, à quelle URL.
struct ExportedOutput: Sendable, Equatable {
    let format: OutputFormat
    let url: URL
}

extension Array where Element == ExportedOutput {
    /// URL produite pour un format donné, ou nil s'il n'a pas été demandé.
    func url(for format: OutputFormat) -> URL? {
        first { $0.format == format }?.url
    }
    /// URL de toutes les sorties (pour ouverture Finder, itération d'affichage).
    var urls: [URL] { map(\.url) }
}
