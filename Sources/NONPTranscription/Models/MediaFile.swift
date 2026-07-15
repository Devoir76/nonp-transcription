// MediaFile.swift — représentation d'un fichier média déposé par l'utilisateur.
//
// Ce modèle est volontairement « pur » (aucune logique d'interface) : il décrit
// un fichier et sait se présenter (taille, durée formatées). Il pourra être
// réutilisé tel quel par le moteur de transcription et le futur traitement par lots.

import Foundation
import AVFoundation

struct MediaFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64
    /// Durée en secondes. `nil` si elle n'a pas pu être lue à ce stade
    /// (certains formats comme MKV/AVI seront lus via ffmpeg à l'Étape 2).
    let duration: Double?

    // MARK: - Formats acceptés (cahier des charges)

    /// Extensions autorisées, en minuscules. Source unique de vérité.
    static let acceptedExtensions: Set<String> = [
        "mp4", "mov", "avi", "mkv",   // vidéo
        "mp3", "wav", "m4a"           // audio
    ]

    /// Vrai si l'URL pointe vers un format pris en charge.
    static func isAccepted(_ url: URL) -> Bool {
        acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Présentation

    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    /// Taille lisible (ex. « 245,3 Mo »).
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    /// Durée lisible (ex. « 1:23:45 » ou « 4:07 »), ou un tiret si inconnue.
    var formattedDuration: String {
        guard let duration, duration > 0 else { return "—" }
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
