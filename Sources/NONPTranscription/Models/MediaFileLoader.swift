// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
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

/// Refus opposé par le chargeur. Une seule cause aujourd'hui : l'URL n'est pas
/// locale. Le message est affichable tel quel.
enum MediaFileLoaderError: LocalizedError, Equatable {
    case notLocal

    var errorDescription: String? {
        switch self {
        case .notLocal:
            return "Cette adresse ne désigne pas un fichier de cet ordinateur."
        }
    }
}

enum MediaFileLoader {
    /// Construit un `MediaFile` en lisant taille et durée.
    ///
    /// Ne lève **qu'une seule** erreur : une URL non locale. Tout le reste reste
    /// tolérant comme avant — une durée illisible vaut simplement `nil`.
    static func load(from url: URL) async throws -> MediaFile {
        // DÉFENSE EN PROFONDEUR — jamais d'actif AVFoundation sur une URL distante.
        //
        // AVURLAsset va CHERCHER ce qu'on lui donne : sur une adresse web, il
        // ouvre une connexion réseau pour lire les métadonnées. Mesuré le 24/09
        // sur la 1.2.3 — une connexion TLS de deux minutes vers un hôte distant,
        // contraire à l'invariant « tout en local ».
        //
        // Ce chargeur REFUSE, il ne rend pas une fiche vide. Rendre un MediaFile
        // de taille nulle et de durée inconnue reproduirait exactement l'état
        // trompeur observé à l'écran le 24/09 — « Zéro ko », durée « — », et un
        // bouton « Transcrire » actif sur un fichier qui n'existe pas. Une
        // barrière qui laisse passer un objet vide n'est qu'une demi-barrière.
        //
        // AppState.selectFile refuse déjà ces URL en amont. Cette garde-ci existe
        // pour qu'un SECOND appelant — traitement par lots, reprise de session —
        // ne rouvre pas la brèche sans s'en apercevoir.
        guard url.isFileURL else { throw MediaFileLoaderError.notLocal }

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
