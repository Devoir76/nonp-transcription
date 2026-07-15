// AudioExtractor.swift — conversion d'un média en WAV 16 kHz mono.
//
// Whisper n'accepte que du PCM 16 kHz mono. Cette couche prépare l'audio à
// partir de n'importe quel format d'entrée (y compris MKV/AVI) via ffmpeg.
// Le protocole permettra, demain, de remplacer ffmpeg par une autre source
// (ex. AVFoundation) sans toucher au reste.

import Foundation

/// Abstraction de l'extraction audio (point d'extension futur).
protocol AudioExtractor {
    /// Convertit `input` en WAV 16 kHz mono et renvoie l'URL du fichier produit.
    func extractAudio(from input: URL) async throws -> URL
}

enum AudioExtractionError: LocalizedError {
    case ffmpegFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegFailed(let detail):
            return "Échec de l'extraction audio.\n\(detail)"
        }
    }
}

/// Implémentation basée sur le ffmpeg embarqué.
struct FFmpegAudioExtractor: AudioExtractor {
    let ffmpeg: URL

    func extractAudio(from input: URL) async throws -> URL {
        // Fichier de sortie temporaire (nettoyé après la transcription).
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonp-\(UUID().uuidString).wav")

        // Paramètres ffmpeg :
        //   -vn            : ignorer la vidéo
        //   -ac 1          : 1 canal (mono)
        //   -ar 16000      : 16 kHz (attendu par Whisper)
        //   -c:a pcm_s16le : PCM 16 bits (WAV standard)
        //   -y             : écraser la sortie si elle existe
        let args = [
            "-hide_banner", "-nostdin", "-y",
            "-i", input.path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            outputURL.path
        ]

        do {
            try await ProcessRunner.run(executable: ffmpeg, arguments: args) { _ in
                // ffmpeg est rapide ; on n'exploite pas sa progression fine ici.
            }
        } catch {
            throw AudioExtractionError.ffmpegFailed(error.localizedDescription)
        }

        return outputURL
    }
}
