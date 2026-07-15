// TranscriptionEngine.swift — abstraction du moteur + implémentation whisper.cpp.
//
// Le protocole TranscriptionEngine isole le reste de l'app du moteur concret.
// C'est LA couture d'évolutivité : demain, remplacer whisper.cpp par WhisperKit
// ou un autre moteur ne demandera qu'une nouvelle implémentation de ce protocole,
// sans rien changer à l'interface ni à la coordination.

import Foundation

/// Contrat d'un moteur de transcription : d'un WAV vers des segments horodatés.
protocol TranscriptionEngine {
    /// Transcrit `wavURL` (16 kHz mono) et renvoie les segments.
    /// - Parameter onProgress: fraction 0…1, appelée au fil du traitement.
    func transcribe(
        wavURL: URL,
        modelPath: URL,
        language: TranscriptionLanguage,
        quality: QualityPreset,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> [TranscriptSegment]
}

enum TranscriptionEngineError: LocalizedError {
    case jsonMissing
    case jsonUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .jsonMissing:
            return "La transcription n'a produit aucun résultat exploitable."
        case .jsonUnreadable(let detail):
            return "Résultat de transcription illisible.\n\(detail)"
        }
    }
}

/// Implémentation basée sur le binaire whisper-cli (whisper.cpp) embarqué.
struct WhisperCppEngine: TranscriptionEngine {
    let whisperCLI: URL

    func transcribe(
        wavURL: URL,
        modelPath: URL,
        language: TranscriptionLanguage,
        quality: QualityPreset,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> [TranscriptSegment] {

        // Préfixe de sortie temporaire : whisper écrira <prefix>.json
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonp-\(UUID().uuidString)")
        let jsonURL = prefix.appendingPathExtension("json")

        // Construction des arguments (fidélité maximale, aucune traduction).
        var args = [
            "-m", modelPath.path,       // modèle GGML
            "-f", wavURL.path,          // audio d'entrée
            "-oj",                      // sortie JSON (segments + offsets ms)
            "-of", prefix.path,         // préfixe des fichiers de sortie
            "--print-progress"          // pour suivre l'avancement
        ]

        // Langue : code explicite, ou "auto" pour la détection automatique.
        args += ["-l", language.whisperCode ?? "auto"]

        // Qualité maximale = recherche par faisceau (beam search), plus fidèle.
        // Rapide = décodage glouton par défaut (plus rapide).
        if quality == .maximum {
            args += ["-bs", "5"]
        }
        // NB : on ne passe jamais -tr (pas de traduction) ni d'option qui
        // supprimerait du contenu : la transcription reste fidèle.

        // Exécution + suivi de progression via les lignes de log.
        try await ProcessRunner.run(executable: whisperCLI, arguments: args) { line in
            if let fraction = Self.parseProgress(line) {
                onProgress(fraction)
            }
        }

        // Lecture et décodage du JSON produit.
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw TranscriptionEngineError.jsonMissing
        }
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let segments: [TranscriptSegment]
        do {
            let data = try Data(contentsOf: jsonURL)
            let decoded = try JSONDecoder().decode(WhisperJSON.self, from: data)
            segments = decoded.transcription.enumerated().map { index, item in
                TranscriptSegment(
                    id: index + 1,
                    startMs: item.offsets.from,
                    endMs: item.offsets.to,
                    // On retire seulement l'espace d'amorce (artefact du modèle) :
                    // ce n'est pas une reformulation, le contenu reste intact.
                    text: item.text.trimmingCharacters(in: .whitespaces)
                )
            }
        } catch {
            throw TranscriptionEngineError.jsonUnreadable(error.localizedDescription)
        }

        onProgress(1.0)
        return segments
    }

    /// Extrait la fraction (0…1) d'une ligne « … progress = N% ».
    static func parseProgress(_ line: String) -> Double? {
        guard let range = line.range(of: "progress =") else { return nil }
        let tail = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let digits = tail.prefix { $0.isNumber }
        guard let value = Int(digits) else { return nil }
        return Double(value) / 100.0
    }
}

// MARK: - Décodage du JSON whisper.cpp (seuls les champs utiles).
private struct WhisperJSON: Decodable {
    let transcription: [Item]

    struct Item: Decodable {
        let offsets: Offsets
        let text: String
    }
    struct Offsets: Decodable {
        let from: Int   // début en millisecondes
        let to: Int     // fin en millisecondes
    }
}
