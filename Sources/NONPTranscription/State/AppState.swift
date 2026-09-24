// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// AppState.swift — état observable de l'application (le « cerveau » de l'UI).
//
// Centralise tout ce que l'interface affiche et modifie : le fichier choisi,
// la langue, la qualité, l'état de chargement et les erreurs. Les vues se
// contentent d'observer cet objet et de lui envoyer des actions.
//
// À partir de l'Étape 3, cet objet déléguera la transcription à un
// TranscriptionCoordinator (le moteur reste séparé de l'état d'interface).

import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {

    // MARK: - État publié (observé par les vues)

    /// Fichier actuellement sélectionné (nil = aucune sélection).
    @Published var mediaFile: MediaFile?

    // La langue de transcription est un réglage PERSISTANT : elle vit dans
    // Preferences (au même titre que le dossier de sortie et les formats), et non
    // dans cet état de session transitoire.

    /// Qualité choisie. Par défaut : maximale (priorité à la fidélité).
    @Published var quality: QualityPreset = .maximum

    /// Vrai pendant la lecture des métadonnées d'un fichier fraîchement déposé.
    @Published var isLoadingFile = false

    /// Message d'erreur à afficher (format non pris en charge, etc.).
    @Published var errorMessage: String?

    /// Message si les outils embarqués (ffmpeg/whisper) sont introuvables.
    @Published var toolsError: String?

    /// Outils embarqués localisés au démarrage (utilisés dès l'Étape 3).
    private(set) var tools: EmbeddedTools?

    // MARK: - Initialisation

    init() {
        // Localise ffmpeg et whisper-cli dès le lancement pour signaler tout
        // problème immédiatement plutôt qu'au moment de transcrire.
        do {
            tools = try EmbeddedTools.locate()
        } catch {
            tools = nil
            toolsError = error.localizedDescription
        }
    }

    // MARK: - Propriétés dérivées

    /// Le bouton « Transcrire » est actif seulement si un fichier valide est prêt.
    var canTranscribe: Bool {
        mediaFile != nil && !isLoadingFile
    }

    // MARK: - Messages de refus

    /// Texte affiché quand l'utilisateur dépose une adresse web au lieu d'un
    /// fichier. Distinct du message de format : la cause n'est pas la même, et
    /// conseiller « convertissez votre fichier » n'aurait aucun sens ici.
    ///
    /// Formulation arrêtée le 24/09. Elle dit la raison, et pas seulement le
    /// geste : un refus devient un rappel de ce qui fait la valeur du produit.
    ///
    /// « **vos fichiers** ne partent jamais », et non « rien ne part » :
    /// l'application utilise bien Internet, une fois, pour télécharger le
    /// modèle. Une promesse trop large serait fausse.
    static let notLocalMessage =
        "NONP Transcription ne travaille que sur des fichiers présents sur votre Mac "
        + "— vos fichiers ne partent jamais sur Internet. "
        + "Enregistrez d'abord la vidéo ou l'audio, puis déposez le fichier ici."

    // MARK: - Actions

    /// Point d'entrée unique pour un fichier (glisser-déposer OU bouton Parcourir).
    /// Valide le format puis lit les métadonnées de façon asynchrone.
    func selectFile(at url: URL) {
        errorMessage = nil

        // Recevabilité décidée en un seul endroit (fonction pure, éprouvée par
        // SelfTest --url-cases). La localité passe AVANT le format : voir
        // MediaFile.rejection(for:).
        if let refus = MediaFile.rejection(for: url) {
            switch refus {
            case .notLocal:
                errorMessage = Self.notLocalMessage
            case .unsupportedFormat(let ext):
                errorMessage = "Format « .\(ext) » non pris en charge. "
                    + "Formats acceptés : MP4, MOV, AVI, MKV, MP3, WAV, M4A."
            }
            return
        }

        isLoadingFile = true
        Task {
            do {
                let file = try await MediaFileLoader.load(from: url)
                self.mediaFile = file
            } catch {
                // Le refus du chargeur (URL non locale) ne devrait jamais
                // arriver ici : la garde ci-dessus l'a déjà écarté. S'il
                // survient malgré tout, on l'AFFICHE plutôt que de le taire —
                // une barrière franchie en silence est pire qu'une barrière
                // absente, parce qu'on ne la cherche pas.
                self.errorMessage = Self.notLocalMessage
            }
            self.isLoadingFile = false
        }
    }

    /// Retire le fichier courant (revient à la zone de dépôt).
    func clearFile() {
        mediaFile = nil
        errorMessage = nil
    }

    /// Ouvre le sélecteur de fichiers natif macOS (alternative au glisser-déposer).
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.prompt = "Choisir"
        panel.message = "Sélectionnez une vidéo ou un fichier audio"

        // Restreint le sélecteur aux types connus quand c'est possible.
        let types = MediaFile.acceptedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }

        if panel.runModal() == .OK, let url = panel.url {
            selectFile(at: url)
        }
    }
}
