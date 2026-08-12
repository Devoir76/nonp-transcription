// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// ModelStore.swift — emplacement et présence des modèles sur le disque.
//
// Les modèles (plusieurs Go) sont stockés dans Application Support, PAS dans le
// dossier du projet : ils restent hors de la synchronisation cloud (ProtonDrive)
// et survivent aux reconstructions de l'app.
//
//   ~/Library/Application Support/NONP Transcription/Models/ggml-large-v3.bin

import Foundation

enum ModelStore {
    /// Dossier de stockage des modèles (créé si nécessaire).
    static var directory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport
            .appendingPathComponent("NONP Transcription", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// Emplacement local (téléchargé ou non) d'un modèle.
    static func localURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    /// Vrai si le modèle est présent ET de la bonne taille (contrôle d'intégrité simple).
    static func isInstalled(_ model: WhisperModel) -> Bool {
        let url = localURL(for: model)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value
        else { return false }
        return size == model.sizeBytes
    }
}
