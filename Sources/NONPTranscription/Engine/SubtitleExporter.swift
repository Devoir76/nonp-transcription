// SubtitleExporter.swift — écriture des fichiers SRT et TXT à partir des segments.
//
// Deux règles absolues :
//  1. Fidélité : on n'altère jamais le texte des segments (aucun résumé,
//     aucune reformulation, aucune correction).
//  2. Non-destruction : on n'écrit QUE des fichiers .srt/.txt à côté de la
//     source ; le fichier source lui-même n'est jamais touché.
//
// Le format SRT est standard (HH:MM:SS,mmm), donc importable dans n'importe quel
// logiciel de montage (Premiere, DaVinci, Final Cut via plugin, etc.).

import Foundation

enum SubtitleExportError: LocalizedError {
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let detail):
            return "Impossible d'écrire les fichiers de sortie.\n\(detail)\n"
                + "Vérifiez que le dossier de la vidéo est accessible en écriture."
        }
    }
}

enum SubtitleExporter {
    /// Écrit `<source>.srt` et `<source>.txt`.
    /// Par défaut dans le dossier du fichier source ; si `outputDirectory` est
    /// fourni, les fichiers y sont écrits (le nom reste celui de la source).
    /// Renvoie les URL des deux fichiers créés.
    @discardableResult
    static func export(segments: [TranscriptSegment], sourceURL: URL,
                       outputDirectory: URL? = nil) throws
        -> (srt: URL, txt: URL) {

        // Dossier cible : personnalisé si fourni, sinon celui de la vidéo.
        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let originalBase = sourceURL.deletingPathExtension().lastPathComponent

        // Gestion des collisions : on ne réutilise un nom que si NI le .srt NI le
        // .txt n'existent déjà. Sinon on incrémente un suffixe (_2, _3, …). Le
        // même suffixe est appliqué aux deux fichiers pour qu'ils restent appariés.
        let baseName = availableBaseName(in: directory, base: originalBase)
        let srtURL = directory.appendingPathComponent(baseName + ".srt")
        let txtURL = directory.appendingPathComponent(baseName + ".txt")

        let srtContent = makeSRT(segments)
        let txtContent = makeTXT(segments)

        do {
            // Écriture atomique : pas de fichier à moitié écrit en cas d'interruption.
            try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
            try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            throw SubtitleExportError.writeFailed(error.localizedDescription)
        }

        return (srtURL, txtURL)
    }

    /// Cherche un nom de base disponible dans `directory` : d'abord `base`, puis
    /// `base_2`, `base_3`, … Un nom est considéré libre seulement si NI `.srt` NI
    /// `.txt` n'existent (les deux extensions sont vérifiées ensemble, afin que le
    /// SRT et le TXT partagent toujours le même suffixe).
    static func availableBaseName(in directory: URL, base: String) -> String {
        let fm = FileManager.default
        func taken(_ name: String) -> Bool {
            let srt = directory.appendingPathComponent(name + ".srt")
            let txt = directory.appendingPathComponent(name + ".txt")
            return fm.fileExists(atPath: srt.path) || fm.fileExists(atPath: txt.path)
        }

        if !taken(base) { return base }
        var n = 2
        while taken("\(base)_\(n)") { n += 1 }
        return "\(base)_\(n)"
    }

    // MARK: - Génération des contenus

    /// Construit le contenu SRT complet.
    static func makeSRT(_ segments: [TranscriptSegment]) -> String {
        var blocks: [String] = []
        for segment in segments {
            let block = """
            \(segment.id)
            \(timecode(segment.startMs)) --> \(timecode(segment.endMs))
            \(segment.text)
            """
            blocks.append(block)
        }
        // Un bloc SRT est séparé du suivant par une ligne vide ; fichier terminé par \n.
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Construit le contenu TXT : l'intégralité du texte, un segment par ligne.
    static func makeTXT(_ segments: [TranscriptSegment]) -> String {
        segments.map(\.text).joined(separator: "\n") + "\n"
    }

    /// Convertit des millisecondes en timecode SRT « HH:MM:SS,mmm ».
    static func timecode(_ milliseconds: Int) -> String {
        let ms = max(0, milliseconds)
        let hours = ms / 3_600_000
        let minutes = (ms % 3_600_000) / 60_000
        let seconds = (ms % 60_000) / 1000
        let millis = ms % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}
