// FileHasher.swift — empreinte SHA-256 d'un fichier, calculée par blocs.
//
// Ne charge JAMAIS le fichier entier en mémoire (les modèles pèsent des Go) :
// lecture par blocs de ~1 Mo, hachage incrémental via CryptoKit. Asynchrone,
// exécuté hors du thread principal. Best-effort typé : renvoie l'empreinte hex,
// ou lève une erreur claire si la lecture échoue.

import Foundation
import CryptoKit

enum FileHashError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            return "Lecture impossible pour le calcul d'empreinte : \(detail)"
        }
    }
}

enum FileHasher {
    /// SHA-256 de `url`, en hexadécimal minuscule. `blockSize` : taille de lecture
    /// par bloc (défaut 1 Mo). Exécuté sur un exécuteur de fond.
    static func sha256Hex(of url: URL, blockSize: Int = 1 << 20) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle: FileHandle
            do { handle = try FileHandle(forReadingFrom: url) }
            catch { throw FileHashError.unreadable(error.localizedDescription) }
            defer { try? handle.close() }

            var hasher = SHA256()
            while true {
                let chunk: Data
                do { chunk = try handle.read(upToCount: blockSize) ?? Data() }
                catch { throw FileHashError.unreadable(error.localizedDescription) }
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
