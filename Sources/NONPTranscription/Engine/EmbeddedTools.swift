// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// EmbeddedTools.swift — localisation des binaires embarqués (ffmpeg, whisper-cli).
//
// Les outils sont copiés dans NONP Transcription.app/Contents/Resources/bin/
// par build_app.sh. Ce type les retrouve à l'exécution et vérifie leur présence.
// C'est le point d'entrée unique vers les exécutables : le reste du code ne
// manipule que des URL fournies ici (couplage faible, testable).

import Foundation

/// Erreur explicite si un outil embarqué est introuvable (message affichable tel quel).
enum EmbeddedToolsError: LocalizedError {
    case toolMissing(name: String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let name):
            return "L'outil embarqué « \(name) » est introuvable dans l'application. "
                + "Reconstruisez l'app avec Scripts/build_app.sh."
        }
    }
}

struct EmbeddedTools {
    let ffmpeg: URL
    let whisperCLI: URL

    /// Localise les binaires. Cherche d'abord dans le bundle (.app), puis, en
    /// dernier recours, dans le dossier Vendor/ du projet (utile en développement).
    static func locate() throws -> EmbeddedTools {
        let ffmpeg = try resolve(toolName: "ffmpeg")
        let whisper = try resolve(toolName: "whisper-cli")
        return EmbeddedTools(ffmpeg: ffmpeg, whisperCLI: whisper)
    }

    /// Cherche un binaire dans les emplacements candidats et vérifie qu'il est exécutable.
    private static func resolve(toolName: String) throws -> URL {
        for base in candidateBinDirs() {
            let candidate = base.appendingPathComponent(toolName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw EmbeddedToolsError.toolMissing(name: toolName)
    }

    /// Dossiers où chercher les binaires, du plus probable au moins probable.
    private static func candidateBinDirs() -> [URL] {
        var dirs: [URL] = []

        // 1) Dans le bundle applicatif : Contents/Resources/bin
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("bin", isDirectory: true))
        }

        // 2) Repli développement : remonter jusqu'à trouver Vendor/bin
        //    (cas où l'on exécute le binaire brut via SwiftPM, hors .app).
        var dir = Bundle.main.bundleURL
        for _ in 0..<6 {
            let vendorBin = dir.appendingPathComponent("Vendor/bin", isDirectory: true)
            if FileManager.default.fileExists(atPath: vendorBin.path) {
                dirs.append(vendorBin)
            }
            dir = dir.deletingLastPathComponent()
        }

        return dirs
    }
}
