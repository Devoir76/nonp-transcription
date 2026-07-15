// Preferences.swift — réglages de l'application, conservés entre les lancements.
//
// Persistance via UserDefaults (mécanisme standard macOS) : les réglages sont
// automatiquement sauvegardés à chaque modification et rechargés au démarrage.
//
// Réglages gérés :
//  • le dossier de sortie (à côté de la vidéo — défaut — ou un dossier fixe) ;
//  • l'ouverture automatique du dossier de sortie en fin de transcription.

import Foundation
import AppKit

@MainActor
final class Preferences: ObservableObject {

    /// Où enregistrer les fichiers SRT/TXT.
    enum OutputMode: String {
        case sourceFolder   // à côté de la vidéo (comportement V1, défaut)
        case customFolder   // dans un dossier fixe choisi par l'utilisateur
    }

    // MARK: - Réglages publiés (l'UI les observe ; toute modif est sauvegardée)

    @Published var outputMode: OutputMode {
        didSet { defaults.set(outputMode.rawValue, forKey: Keys.outputMode) }
    }

    /// Chemin du dossier fixe (vide tant qu'aucun n'est choisi).
    @Published var customFolderPath: String {
        didSet { defaults.set(customFolderPath, forKey: Keys.customFolderPath) }
    }

    /// Ouvrir automatiquement le dossier de sortie à la fin.
    @Published var openFolderWhenDone: Bool {
        didSet { defaults.set(openFolderWhenDone, forKey: Keys.openFolderWhenDone) }
    }

    // MARK: - Stockage

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let outputMode = "outputMode"
        static let customFolderPath = "customFolderPath"
        static let openFolderWhenDone = "openFolderWhenDone"
    }

    init() {
        // Rechargement des valeurs sauvegardées (avec des défauts sûrs).
        let savedMode = defaults.string(forKey: Keys.outputMode)
        outputMode = savedMode.flatMap(OutputMode.init) ?? .sourceFolder
        customFolderPath = defaults.string(forKey: Keys.customFolderPath) ?? ""
        // Par défaut : on ouvre le dossier à la fin (comportement attendu).
        openFolderWhenDone = (defaults.object(forKey: Keys.openFolderWhenDone) as? Bool) ?? true
    }

    // MARK: - Dossier de sortie

    /// URL du dossier fixe, si un chemin valide est défini.
    var customFolderURL: URL? {
        guard !customFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customFolderPath, isDirectory: true)
    }

    /// Vrai si le mode « dossier fixe » est actif ET le dossier est réellement utilisable.
    var customFolderIsUsable: Bool {
        guard let url = customFolderURL else { return false }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Dossier de sortie EFFECTIF pour une source donnée.
    /// Retombe sur le dossier de la vidéo si le dossier fixe est absent/invalide
    /// (robustesse : un dossier supprimé ou un disque débranché ne bloque pas).
    func outputDirectory(for sourceURL: URL) -> URL {
        if outputMode == .customFolder, customFolderIsUsable, let dir = customFolderURL {
            return dir
        }
        return sourceURL.deletingLastPathComponent()
    }

    // MARK: - Sélection du dossier fixe

    /// Ouvre le sélecteur de dossier natif et mémorise le choix.
    func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Choisissez le dossier où enregistrer les transcriptions"

        if panel.runModal() == .OK, let url = panel.url {
            customFolderPath = url.path
            outputMode = .customFolder
        }
    }
}
