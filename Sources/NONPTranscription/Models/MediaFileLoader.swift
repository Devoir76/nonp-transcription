// MediaFileLoader.swift — lecture des métadonnées d'un fichier (taille + durée).
//
// Séparé de MediaFile pour garder le modèle « pur ». La lecture de durée passe
// par AVFoundation (framework système, natif Apple Silicon), qui gère MP4, MOV,
// M4A, MP3, WAV. Pour MKV/AVI, AVFoundation peut échouer : la durée restera
// `nil` et sera résolue plus tard via ffmpeg (Étape 2). C'est volontaire et sans
// gravité — l'app reste fidèle à une montée en puissance étape par étape.

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

        return MediaFile(url: url, sizeBytes: size, duration: duration)
    }
}
