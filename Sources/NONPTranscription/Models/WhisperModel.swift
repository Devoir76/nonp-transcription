// WhisperModel.swift — catalogue des modèles Whisper téléchargeables.
//
// Chaque modèle connaît son nom de fichier GGML, son URL de téléchargement
// (dépôt officiel ggerganov/whisper.cpp sur Hugging Face) et sa taille exacte
// en octets (vérifiée le 2026-07-15). La taille sert à valider l'intégrité
// après téléchargement.

import Foundation

struct WhisperModel: Identifiable, Sendable, Equatable {
    let id: String            // ex. "large-v3"
    let displayName: String   // ex. "large-v3"
    let fileName: String      // ex. "ggml-large-v3.bin"
    let downloadURL: URL
    let sizeBytes: Int64      // taille exacte attendue
    let sha256: String        // empreinte SHA-256 de référence (voir docs/MODEL_MANIFEST.md)

    /// Taille lisible (ex. « 2,88 Go »).
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    // MARK: - Catalogue

    static let largeV3 = WhisperModel(
        id: "large-v3",
        displayName: "large-v3",
        fileName: "ggml-large-v3.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
        sizeBytes: 3_095_033_483,
        sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
    )

    static let largeV3Turbo = WhisperModel(
        id: "large-v3-turbo",
        displayName: "large-v3-turbo",
        fileName: "ggml-large-v3-turbo.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        sizeBytes: 1_624_555_275,
        sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    )

    static let all: [WhisperModel] = [largeV3, largeV3Turbo]

    /// Modèle associé à un niveau de qualité.
    static func forPreset(_ preset: QualityPreset) -> WhisperModel {
        switch preset {
        case .maximum: return largeV3
        case .fast:    return largeV3Turbo
        }
    }
}
