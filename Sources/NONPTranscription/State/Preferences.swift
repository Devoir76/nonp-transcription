// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Preferences.swift — réglages de l'application, conservés entre les lancements.
//
// Persistance via UserDefaults (mécanisme standard macOS) : les réglages sont
// automatiquement sauvegardés à chaque modification et rechargés au démarrage.
//
// Réglages gérés :
//  • le dossier de sortie (à côté de la vidéo — défaut — ou un dossier fixe) ;
//  • l'ouverture automatique du dossier de sortie en fin de transcription.
//
// Journalisation de diagnostic (BUG-006) : chaque écriture et chaque relecture
// des trois réglages est tracée dans la journalisation unifiée de macOS via
// os_log. Tout reste LOCAL — aucun réseau, aucun fichier créé. Le chemin du
// dossier n'est jamais journalisé en clair : seule une empreinte tronquée,
// non réversible, est publique. Voir PRIVACY.md.

import Foundation
import AppKit
import os
import CryptoKit

/// Sous-système de journalisation. Dérivé de l'identifiant de bundle : il suit
/// donc automatiquement un futur changement de nom. Le repli couvre le binaire
/// nu du harnais de test, qui n'a pas de bundle.
private let prefsLogSubsystem = Bundle.main.bundleIdentifier ?? "com.nonp.transcription"

/// Journal dédié : filtrable par `log show --predicate 'category == "preferences"'`.
private let prefsLog = Logger(subsystem: prefsLogSubsystem, category: "preferences")

/// Empreinte courte et non réversible, pour comparer une valeur écrite et une
/// valeur relue SANS jamais exposer le chemin de l'utilisateur.
private func fingerprint(_ s: String) -> String {
    guard !s.isEmpty else { return "vide" }
    let hex = SHA256.hash(data: Data(s.utf8)).prefix(4)
        .map { String(format: "%02x", $0) }.joined()
    return "\(hex)/\(s.count)"
}

@MainActor
final class Preferences: ObservableObject {

    /// Où enregistrer les fichiers SRT/TXT.
    enum OutputMode: String {
        case sourceFolder   // à côté de la vidéo (comportement V1, défaut)
        case customFolder   // dans un dossier fixe choisi par l'utilisateur
    }

    // MARK: - Réglages publiés (l'UI les observe ; toute modif est sauvegardée)

    @Published var outputMode: OutputMode {
        didSet {
            defaults.set(outputMode.rawValue, forKey: Keys.outputMode)
            trace(Keys.outputMode, wrote: outputMode.rawValue,
                  reread: defaults.string(forKey: Keys.outputMode))
        }
    }

    /// Chemin du dossier fixe (vide tant qu'aucun n'est choisi).
    @Published var customFolderPath: String {
        didSet {
            defaults.set(customFolderPath, forKey: Keys.customFolderPath)
            tracePath(Keys.customFolderPath, wrote: customFolderPath,
                      reread: defaults.string(forKey: Keys.customFolderPath))
        }
    }

    /// Ouvrir automatiquement le dossier de sortie à la fin.
    @Published var openFolderWhenDone: Bool {
        didSet {
            defaults.set(openFolderWhenDone, forKey: Keys.openFolderWhenDone)
            trace(Keys.openFolderWhenDone, wrote: String(openFolderWhenDone),
                  reread: (defaults.object(forKey: Keys.openFolderWhenDone)
                           as? Bool).map(String.init))
        }
    }

    /// Langue de transcription choisie. Persistée ; défaut .auto (détection
    /// automatique) — comportement V1 au premier lancement préservé. On stocke la
    /// rawValue stable (jamais le displayName localisé).
    @Published var language: TranscriptionLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            trace(Keys.language, wrote: language.rawValue,
                  reread: defaults.string(forKey: Keys.language))
        }
    }

    /// Formats de sortie choisis. Défaut {SRT, TXT} = comportement V1.
    /// Stocké en UserDefaults comme tableau de rawValue (un Set n'y va pas
    /// directement) ; relu vers un Set, jamais vide (repli sur le défaut).
    @Published var selectedFormats: Set<OutputFormat> {
        didSet {
            defaults.set(selectedFormats.map(\.rawValue).sorted(),
                         forKey: Keys.selectedFormats)
            trace(Keys.selectedFormats,
                  wrote: Self.canonical(selectedFormats),
                  reread: defaults.stringArray(forKey: Keys.selectedFormats)
                            .map { Self.canonical(Set($0.compactMap(OutputFormat.init))) })
        }
    }

    // MARK: - Stockage

    private let defaults: UserDefaults
    private enum Keys {
        static let outputMode = "outputMode"
        static let customFolderPath = "customFolderPath"
        static let openFolderWhenDone = "openFolderWhenDone"
        static let selectedFormats = "selectedFormats"
        static let language = "language"
    }

    /// `defaults` est injectable UNIQUEMENT pour les tests (domaine isolé).
    /// En usage normal, le comportement est strictement inchangé.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Rechargement des valeurs sauvegardées (avec des défauts sûrs).
        let savedMode = defaults.string(forKey: Keys.outputMode)
        outputMode = savedMode.flatMap(OutputMode.init) ?? .sourceFolder
        customFolderPath = defaults.string(forKey: Keys.customFolderPath) ?? ""
        // Par défaut : on ouvre le dossier à la fin (comportement attendu).
        openFolderWhenDone = (defaults.object(forKey: Keys.openFolderWhenDone) as? Bool) ?? true
        // Formats : relus depuis le tableau de rawValue ; repli sur le défaut sûr
        // {SRT, TXT} si absent OU corrompu (jamais un ensemble vide).
        let savedFormats = defaults.stringArray(forKey: Keys.selectedFormats)
            .map { Set($0.compactMap(OutputFormat.init)) }
        selectedFormats = (savedFormats?.isEmpty == false) ? savedFormats! : OutputFormat.defaultSet
        // Langue : rawValue relue ; repli sûr sur .auto si absente ou inconnue.
        let savedLang = defaults.string(forKey: Keys.language)
        language = savedLang.flatMap(TranscriptionLanguage.init) ?? .auto
        traceLoad()
    }

    // MARK: - Journalisation de diagnostic (BUG-006)

    /// Trace une écriture non sensible et son verdict de relecture immédiate.
    /// La relecture est une lecture pure : aucun effet de bord.
    private func trace(_ key: String, wrote: String, reread: String?) {
        let verdict = (reread == wrote) ? "conforme" : "DIVERGENT"
        prefsLog.notice("""
            écriture clé=\(key, privacy: .public) \
            valeur=\(wrote, privacy: .public) \
            relecture=\(verdict, privacy: .public)
            """)
    }

    /// Représentation canonique et stable d'un ensemble de formats (pour la trace
    /// et la comparaison écriture/relecture) : rawValues triées, jointes par « + ».
    private static func canonical(_ formats: Set<OutputFormat>) -> String {
        formats.map(\.rawValue).sorted().joined(separator: "+")
    }

    /// Idem, pour une valeur SENSIBLE : empreinte en public, brut en privé.
    private func tracePath(_ key: String, wrote: String, reread: String?) {
        let verdict = (reread == wrote) ? "conforme" : "DIVERGENT"
        prefsLog.notice("""
            écriture clé=\(key, privacy: .public) \
            empreinte=\(fingerprint(wrote), privacy: .public) \
            relecture=\(verdict, privacy: .public) \
            valeur=\(wrote, privacy: .private)
            """)
    }

    /// Trace l'état des trois clés au chargement : PRÉSENTE ou ABSENTE.
    /// Trois « absente » après une relance, c'est la signature de BUG-006.
    private func traceLoad() {
        func state(_ key: String) -> String {
            defaults.object(forKey: key) == nil ? "absente" : "présente"
        }
        let m = state(Keys.outputMode), p = state(Keys.customFolderPath)
        let o = state(Keys.openFolderWhenDone), f = state(Keys.selectedFormats)
        let l = state(Keys.language)
        prefsLog.notice("""
            chargement \
            outputMode=\(m, privacy: .public)/\(self.outputMode.rawValue, privacy: .public) \
            customFolderPath=\(p, privacy: .public)/\(fingerprint(self.customFolderPath), privacy: .public) \
            openFolderWhenDone=\(o, privacy: .public)/\(String(self.openFolderWhenDone), privacy: .public) \
            selectedFormats=\(f, privacy: .public)/\(Self.canonical(self.selectedFormats), privacy: .public) \
            language=\(l, privacy: .public)/\(self.language.rawValue, privacy: .public)
            """)
    }

    // MARK: - Formats de sortie

    /// Formats choisis dans l'ordre canonique (celui d'`allCases`), pour l'export.
    /// L'ordre est indépendant de l'ordre de stockage dans UserDefaults.
    var orderedSelectedFormats: [OutputFormat] {
        OutputFormat.allCases.filter { selectedFormats.contains($0) }
    }

    // MARK: - Dossier de sortie

    /// URL du dossier fixe, si un chemin valide est défini.
    var customFolderURL: URL? {
        guard !customFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customFolderPath, isDirectory: true)
    }

    /// Vrai si le mode « dossier fixe » est actif ET le dossier est réellement utilisable.
    /// « Utilisable » = il existe, c'est bien un dossier, ET il est inscriptible.
    /// L'inscriptibilité est indispensable : un dossier en lecture seule est visible
    /// et listable, mais y écrire échoue — sans ce contrôle, le traitement s'arrête
    /// au lieu de se replier auprès de la vidéo.
    var customFolderIsUsable: Bool {
        guard let url = customFolderURL else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue && fm.isWritableFile(atPath: url.path)
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
