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
    /// `directory` est le dossier dans lequel l'écriture a RÉELLEMENT été tentée —
    /// jamais un dossier simplement envisagé. Le message ne doit orienter l'utilisateur
    /// que vers un emplacement effectivement mis en cause (cf. BUG-008).
    case writeFailed(directory: URL, detail: String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let directory, let detail):
            return "Impossible d'écrire les fichiers de sortie dans :\n"
                + "\(directory.path)\n"
                + "Vérifiez que ce dossier est accessible en écriture.\n"
                + "Détail technique : \(detail)"
        }
    }
}

enum SubtitleExporter {
    /// Écrit `<source>.srt` et `<source>.txt`.
    /// Par défaut dans le dossier du fichier source ; si `outputDirectory` est
    /// fourni, les fichiers y sont écrits (le nom reste celui de la source).
    ///
    /// Repli : si le dossier demandé est absent ou non inscriptible, on écrit
    /// auprès de la vidéo plutôt que d'interrompre le traitement. Une transcription
    /// coûte plusieurs minutes de calcul ; un dossier de destination devenu
    /// inaccessible ne doit pas la jeter. L'anti-collision est entièrement
    /// recalculée dans le dossier de repli.
    ///
    /// Renvoie les URL des deux fichiers réellement créés — l'appelant ne doit
    /// donc jamais supposer qu'ils se trouvent dans `outputDirectory`.
    @discardableResult
    static func export(segments: [TranscriptSegment], sourceURL: URL,
                       outputDirectory: URL? = nil) throws
        -> (srt: URL, txt: URL) {

        // Dossier de repli : toujours celui de la vidéo.
        let fallback = sourceURL.deletingLastPathComponent()
        // Dossier cible : personnalisé si fourni, sinon le repli lui-même.
        let preferred = outputDirectory ?? fallback
        let originalBase = sourceURL.deletingPathExtension().lastPathComponent

        let srtContent = makeSRT(segments)
        let txtContent = makeTXT(segments)

        // Le dossier demandé est-il déjà le dossier de repli ? Alors il n'y a qu'une
        // seule destination possible : on ne la tente qu'une fois, à l'étape 2.
        let preferredIsFallback =
            preferred.standardizedFileURL.path == fallback.standardizedFileURL.path

        // 1) Tentative dans le dossier demandé, s'il diffère du repli et qu'il est
        //    inscriptible : inutile d'échouer pour le découvrir. Un échec ici n'est
        //    jamais rapporté à l'utilisateur — il déclenche le repli, qui seul décide
        //    du sort de l'export.
        if !preferredIsFallback, isWritableDirectory(preferred) {
            if let pair = try? writePair(srt: srtContent, txt: txtContent,
                                         in: preferred, base: originalBase) {
                return pair
            }
            // Échec (course : volume démonté, disque plein…) → on se replie.
        }

        // 2) Écriture auprès de la vidéo — repli, ou tentative unique si c'était déjà
        //    la destination demandée. Anti-collision recalculée sur place.
        //    C'est le SEUL point de levée : l'erreur ne peut donc désigner qu'un
        //    dossier dans lequel on a effectivement tenté d'écrire (BUG-008).
        do {
            return try writePair(srt: srtContent, txt: txtContent,
                                 in: fallback, base: originalBase)
        } catch {
            throw SubtitleExportError.writeFailed(directory: fallback,
                                                  detail: error.localizedDescription)
        }
    }

    /// Écrit le couple SRT/TXT dans `directory` sous un nom de base disponible.
    /// Garantie de non-écriture partielle : si le second fichier échoue, le premier
    /// est retiré, afin de ne jamais laisser un SRT orphelin dans un dossier où le
    /// repli va de toute façon produire le couple complet.
    private static func writePair(srt srtContent: String, txt txtContent: String,
                                  in directory: URL, base: String) throws
        -> (srt: URL, txt: URL) {

        // Gestion des collisions : on ne réutilise un nom que si NI le .srt NI le
        // .txt n'existent déjà. Sinon on incrémente un suffixe (_2, _3, …). Le
        // même suffixe est appliqué aux deux fichiers pour qu'ils restent appariés.
        let baseName = availableBaseName(in: directory, base: base)
        let srtURL = directory.appendingPathComponent(baseName + ".srt")
        let txtURL = directory.appendingPathComponent(baseName + ".txt")

        // Écriture atomique : pas de fichier à moitié écrit en cas d'interruption.
        try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
        do {
            try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: srtURL)
            throw error
        }

        return (srtURL, txtURL)
    }

    /// Vrai si `url` désigne un dossier existant et inscriptible.
    static func isWritableDirectory(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
        else { return false }
        return fm.isWritableFile(atPath: url.path)
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
