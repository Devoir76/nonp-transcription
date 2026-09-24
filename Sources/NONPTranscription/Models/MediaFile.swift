// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
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

    // MARK: - Recevabilité d'une URL déposée

    /// Pourquoi une URL est refusée. `nil` = recevable.
    ///
    /// Fonction PURE, sans accès disque ni réseau : c'est le point UNIQUE où la
    /// recevabilité se décide, afin qu'elle soit éprouvable sans interface et
    /// sans média (cf. SelfTest `--url-cases`). Même intention qu'ExportNaming.
    enum Rejection: Equatable, Sendable {
        /// L'URL ne désigne pas un fichier de cette machine (adresse web, etc.).
        case notLocal
        /// Fichier local, mais extension non prise en charge. Porte l'extension
        /// telle qu'elle sera montrée à l'utilisateur (« inconnu » si absente).
        case unsupportedFormat(String)
    }

    /// Décide de la recevabilité d'une URL déposée.
    ///
    /// **L'ordre compte.** La localité est contrôlée AVANT le format : une
    /// adresse web dont le chemin se termine par une extension connue
    /// franchirait sinon le filtre. Mesuré le 24/09 — une telle adresse était
    /// acceptée comme un fichier, et le lecteur de métadonnées d'AVFoundation
    /// ouvrait alors une connexion TLS de deux minutes vers l'hôte distant.
    /// C'est contraire à l'invariant « tout en local ».
    static func rejection(for url: URL) -> Rejection? {
        guard url.isFileURL else { return .notLocal }
        let ext = url.pathExtension.lowercased()
        guard acceptedExtensions.contains(ext) else {
            return .unsupportedFormat(ext.isEmpty ? "inconnu" : ext)
        }
        return nil
    }

    /// Vrai si l'URL est recevable — fichier LOCAL et format pris en charge.
    ///
    /// Défini PAR `rejection(for:)`, et non à côté : deux prédicats voisins de
    /// sens opposé finissent toujours par diverger. C'est cette divergence qui a
    /// laissé passer une adresse web en 1.2.3 — l'ancien `isAccepted` ne jugeait
    /// que l'extension, et rien ne rappelait qu'il ne jugeait que cela.
    static func isAccepted(_ url: URL) -> Bool {
        rejection(for: url) == nil
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
