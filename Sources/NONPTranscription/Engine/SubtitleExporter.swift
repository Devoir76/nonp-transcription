// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
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
    /// Aucun format de sortie demandé — l'appelant doit toujours en fournir au
    /// moins un (l'UI garantit ce contrat via son garde-fou). Cf. ADR-0002.
    case noFormatsRequested

    var errorDescription: String? {
        switch self {
        case .writeFailed(let directory, let detail):
            return "Impossible d'écrire les fichiers de sortie dans :\n"
                + "\(directory.path)\n"
                + "Vérifiez que ce dossier est accessible en écriture.\n"
                + "Détail technique : \(detail)"
        case .noFormatsRequested:
            return "Aucun format de sortie sélectionné : rien à écrire."
        }
    }
}

enum SubtitleExporter {
    /// Écrit `<source>.<ext>` pour chacun des `formats` demandés.
    /// Par défaut dans le dossier du fichier source ; si `outputDirectory` est
    /// fourni, les fichiers y sont écrits (le nom reste celui de la source).
    ///
    /// Repli : si le dossier demandé est absent ou non inscriptible, on écrit
    /// auprès de la vidéo plutôt que d'interrompre le traitement. Une transcription
    /// coûte plusieurs minutes de calcul ; un dossier de destination devenu
    /// inaccessible ne doit pas la jeter. L'anti-collision est entièrement
    /// recalculée dans le dossier de repli.
    ///
    /// `languageCode` est le code de langue du résultat de transcription : il
    /// devient un suffixe du nom (`entretien_fr.srt`). Absent ou inexploitable,
    /// le nom reste nu (`entretien.srt`). Il n'influe QUE sur le nom : les
    /// contenus écrits sont rigoureusement les mêmes.
    ///
    /// Renvoie les sorties réellement créées (format + URL), dans l'ordre des
    /// `formats` fournis — l'appelant ne doit donc jamais supposer qu'elles se
    /// trouvent dans `outputDirectory`.
    @discardableResult
    static func export(segments: [TranscriptSegment], sourceURL: URL,
                       formats: [OutputFormat], outputDirectory: URL? = nil,
                       languageCode: String? = nil) throws
        -> [ExportedOutput] {

        // Précondition : au moins un format. L'UI le garantit (garde-fou), mais
        // l'export refuse explicitement un appel vide plutôt que de ne rien produire.
        guard !formats.isEmpty else { throw SubtitleExportError.noFormatsRequested }

        // Dossier de repli : toujours celui de la vidéo.
        let fallback = sourceURL.deletingLastPathComponent()
        // Dossier cible : personnalisé si fourni, sinon le repli lui-même.
        let preferred = outputDirectory ?? fallback
        // Nom de base = nom de la source + suffixe de langue éventuel. Décidé en
        // un seul endroit (ExportNaming), AVANT l'anti-collision : le suffixe
        // numérique s'ajoute donc au nom complet (« entretien_fr_2.srt »), et
        // les deux dossiers candidats ci-dessous partent du même nom.
        let originalBase = ExportNaming.baseName(
            source: sourceURL.deletingPathExtension().lastPathComponent,
            languageCode: languageCode)

        // Contenus pré-générés (fonctions PURES des segments) + extensions concernées.
        let contents = formats.map { (format: $0, text: makeContent($0, segments)) }
        let extensions = formats.map(\.fileExtension)

        // Le dossier demandé est-il déjà le dossier de repli ? Alors il n'y a qu'une
        // seule destination possible : on ne la tente qu'une fois, à l'étape 2.
        let preferredIsFallback =
            preferred.standardizedFileURL.path == fallback.standardizedFileURL.path

        // 1) Tentative dans le dossier demandé, s'il diffère du repli et qu'il est
        //    inscriptible : inutile d'échouer pour le découvrir. Un échec ici n'est
        //    jamais rapporté à l'utilisateur — il déclenche le repli, qui seul décide
        //    du sort de l'export.
        if !preferredIsFallback, isWritableDirectory(preferred) {
            if let out = try? writeAll(contents, in: preferred,
                                       base: originalBase, extensions: extensions) {
                return out
            }
            // Échec (course : volume démonté, disque plein…) → on se replie.
        }

        // 2) Écriture auprès de la vidéo — repli, ou tentative unique si c'était déjà
        //    la destination demandée. Anti-collision recalculée sur place.
        //    C'est le SEUL point de levée : l'erreur ne peut donc désigner qu'un
        //    dossier dans lequel on a effectivement tenté d'écrire (BUG-008).
        do {
            return try writeAll(contents, in: fallback,
                                base: originalBase, extensions: extensions)
        } catch {
            throw SubtitleExportError.writeFailed(directory: fallback,
                                                  detail: error.localizedDescription)
        }
    }

    /// Écrit tous les formats dans `directory` sous un nom de base disponible.
    /// Garantie de non-écriture partielle : si l'une des écritures échoue, TOUS
    /// les fichiers déjà écrits ce tour-ci sont retirés, afin de ne jamais laisser
    /// une sortie orpheline dans un dossier où le repli va de toute façon produire
    /// l'ensemble complet.
    private static func writeAll(_ contents: [(format: OutputFormat, text: String)],
                                 in directory: URL, base: String,
                                 extensions: [String]) throws -> [ExportedOutput] {

        // Gestion des collisions : on ne réutilise un nom que si AUCUNE des
        // extensions demandées n'existe déjà. Sinon on incrémente un suffixe
        // (_2, _3, …). Le même suffixe est appliqué à TOUS les formats pour qu'ils
        // restent appariés.
        let baseName = availableBaseName(in: directory, base: base, extensions: extensions)

        var written: [URL] = []
        var outputs: [ExportedOutput] = []
        do {
            for (format, text) in contents {
                let url = directory.appendingPathComponent(baseName + "." + format.fileExtension)
                // Écriture atomique : pas de fichier à moitié écrit en cas d'interruption.
                try text.write(to: url, atomically: true, encoding: .utf8)
                written.append(url)
                outputs.append(ExportedOutput(format: format, url: url))
            }
        } catch {
            // Aucun orphelin : on retire tout ce qui a été écrit CE tour-ci.
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return outputs
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
    /// `base_2`, `base_3`, … Un nom est considéré libre seulement si AUCUNE des
    /// `extensions` demandées n'existe (toutes vérifiées ensemble, afin que tous
    /// les formats choisis partagent toujours le même suffixe).
    static func availableBaseName(in directory: URL, base: String,
                                  extensions: [String]) -> String {
        let fm = FileManager.default
        func taken(_ name: String) -> Bool {
            extensions.contains { ext in
                fm.fileExists(atPath: directory.appendingPathComponent(name + "." + ext).path)
            }
        }

        if !taken(base) { return base }
        var n = 2
        while taken("\(base)_\(n)") { n += 1 }
        return "\(base)_\(n)"
    }

    // MARK: - Génération des contenus

    /// Aiguille vers le générateur de contenu du format demandé. Les générateurs
    /// (`makeSRT`/`makeTXT`) sont inchangés — cette fonction ne fait que router.
    static func makeContent(_ format: OutputFormat, _ segments: [TranscriptSegment]) -> String {
        switch format {
        case .srt: return makeSRT(segments)
        case .txt: return makeTXT(segments)
        case .vtt: return makeVTT(segments)
        }
    }

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

    /// Construit le contenu WebVTT : entête obligatoire « WEBVTT », puis un cue par
    /// segment (même structure que SRT : identifiant, ligne timecode, texte). Seul
    /// le séparateur de millisecondes diffère (« . »), et le texte est échappé.
    static func makeVTT(_ segments: [TranscriptSegment]) -> String {
        var blocks: [String] = []
        for segment in segments {
            let block = """
            \(segment.id)
            \(timecode(segment.startMs, separator: ".")) --> \(timecode(segment.endMs, separator: "."))
            \(escapeVTT(segment.text))
            """
            blocks.append(block)
        }
        // Entête séparée du premier cue par une ligne vide ; cues séparés par une
        // ligne vide ; fichier terminé par \n.
        return "WEBVTT\n\n" + blocks.joined(separator: "\n\n") + "\n"
    }

    /// Échappement WebVTT minimal et RÉVERSIBLE : « & » d'abord (sinon on
    /// double-échapperait les entités produites ensuite), puis « < » et « > ».
    /// Sans cela, un « < » présent dans un témoignage serait interprété comme une
    /// balise VTT et casserait le rendu. Le résultat canonique [TranscriptSegment]
    /// reste verbatim — c'est une transformation de packaging d'export (§7).
    private static func escapeVTT(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Convertit des millisecondes en timecode « HH:MM:SS<sep>mmm ».
    /// `separator` vaut « , » (SRT) par défaut ; VTT passe « . ».
    static func timecode(_ milliseconds: Int, separator: String = ",") -> String {
        let ms = max(0, milliseconds)
        let hours = ms / 3_600_000
        let minutes = (ms % 3_600_000) / 60_000
        let seconds = (ms % 60_000) / 1000
        let millis = ms % 1000
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            + separator + String(format: "%03d", millis)
    }
}
