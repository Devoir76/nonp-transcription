// MediaFileLoader.swift — lecture des métadonnées d'un fichier (taille + durée).
//
// Séparé de MediaFile pour garder le modèle « pur ». La lecture de durée passe
// d'abord par AVFoundation (framework système, natif Apple Silicon), qui gère
// MP4, MOV, M4A, MP3, WAV. Pour les conteneurs qu'AVFoundation ne sait pas lire
// (MKV, AVI), un REPLI lit la durée via le ffmpeg embarqué (MediaDurationProbe).
// Le repli ne se déclenche que si AVFoundation n'a rien renvoyé : le chemin natif
// rapide est préservé pour tous les formats déjà pris en charge.

import Foundation
import AVFoundation

enum MediaFileLoader {
    /// Construit un `MediaFile` en lisant taille et durée. Ne lève jamais
    /// d'erreur : en cas de souci, la durée vaut simplement `nil`.
    static func load(from url: URL) async -> MediaFile {
        // Taille du fichier via les attributs du système de fichiers.
        let size: Int64 = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }()

        // Durée via AVFoundation (API asynchrone moderne).
        var duration: Double? = nil
        let asset = AVURLAsset(url: url)
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 {
                duration = seconds
            }
        }

        // Repli best-effort : AVFoundation échoue sur MKV/AVI → durée via le ffmpeg
        // DÉJÀ embarqué (lecture d'entête, sans décodage). Le chemin nominal
        // (MP4/MOV/MP3/M4A/WAV) n'est JAMAIS concerné : le repli ne se déclenche
        // que si AVFoundation n'a rien renvoyé. Ne lève jamais : nil si indisponible.
        if duration == nil, let tools = try? EmbeddedTools.locate() {
            duration = await MediaDurationProbe.probeDuration(of: url, ffmpeg: tools.ffmpeg)
        }

        return MediaFile(url: url, sizeBytes: size, duration: duration)
    }
}
