// MediaDurationProbe.swift — repli de lecture de durée via le ffmpeg embarqué.
//
// AVFoundation échoue à lire la durée de certains conteneurs (MKV, AVI). Ce
// probe lit l'entête du conteneur avec `ffmpeg -i` (RAPIDE : aucun décodage) et
// extrait la ligne « Duration: … » de stderr. C'est une métadonnée d'affichage,
// hors du pipeline de transcription. Best-effort : ne lève jamais, renvoie nil
// si la durée est introuvable.

import Foundation

enum MediaDurationProbe {

    /// Lit la durée (en secondes) via le ffmpeg embarqué, ou nil si indisponible.
    /// `ffmpeg -i` SANS fichier de sortie termine avec un code ≠ 0 (« At least one
    /// output file… ») : c'est ATTENDU. On ignore le code et on parse stderr, que
    /// l'on accumule intégralement via `onLine` (indépendant du tail de ProcessRunner).
    static func probeDuration(of url: URL, ffmpeg: URL) async -> Double? {
        let sink = OutputSink()
        // -nostdin : ne pas attendre l'entrée ; -i seul : lecture d'entête, pas de décodage.
        try? await ProcessRunner.run(
            executable: ffmpeg,
            arguments: ["-hide_banner", "-nostdin", "-i", url.path]
        ) { line in
            sink.append(line)
        }
        return parseFFmpegDuration(sink.text())
    }

    /// Extrait la durée d'une sortie ffmpeg. Fonction PURE et testable.
    /// « Duration: HH:MM:SS.ff » (jamais localisé) → secondes ; « N/A » ou ligne
    /// absente/malformée → nil.
    static func parseFFmpegDuration(_ stderr: String) -> Double? {
        let pattern = #"Duration:\s*(\d+):(\d{2}):(\d{2})\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: stderr,
                                       range: NSRange(stderr.startIndex..., in: stderr)),
              let hR = Range(m.range(at: 1), in: stderr),
              let mR = Range(m.range(at: 2), in: stderr),
              let sR = Range(m.range(at: 3), in: stderr),
              let fR = Range(m.range(at: 4), in: stderr),
              let h  = Double(stderr[hR]),
              let mm = Double(stderr[mR]),
              let ss = Double(stderr[sR]) else { return nil }
        let frac = Double("0." + String(stderr[fR])) ?? 0
        let total = h * 3600 + mm * 60 + ss + frac
        return total > 0 ? total : nil
    }
}

/// Accumulateur thread-safe : `onLine` de ProcessRunner peut être appelé depuis
/// n'importe quel thread.
private final class OutputSink: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()
    func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    func text() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
}
