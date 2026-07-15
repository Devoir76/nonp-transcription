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

    /// Langue choisie. Par défaut : détection automatique.
    @Published var language: TranscriptionLanguage = .auto

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

    // MARK: - Actions

    /// Point d'entrée unique pour un fichier (glisser-déposer OU bouton Parcourir).
    /// Valide le format puis lit les métadonnées de façon asynchrone.
    func selectFile(at url: URL) {
        errorMessage = nil

        guard MediaFile.isAccepted(url) else {
            let ext = url.pathExtension.isEmpty ? "inconnu" : url.pathExtension.lowercased()
            errorMessage = "Format « .\(ext) » non pris en charge. "
                + "Formats acceptés : MP4, MOV, AVI, MKV, MP3, WAV, M4A."
            return
        }

        isLoadingFile = true
        Task {
            let file = await MediaFileLoader.load(from: url)
            self.mediaFile = file
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
