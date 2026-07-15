// ContentView.swift — vue principale, assemble toute l'interface (Étape 1).
//
// Compose : en-tête · (zone de dépôt OU carte fichier) · message d'erreur
// éventuel · menus Langue et Qualité · bouton Transcrire.
// Le bouton est volontairement inactif à ce stade : le moteur arrive à l'Étape 3.

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    /// Gère le téléchargement du modèle (partagé avec ModelStatusView).
    @StateObject private var downloader = ModelDownloader()

    /// Orchestre le traitement (extraction → transcription → export).
    @StateObject private var coordinator = TranscriptionCoordinator()

    /// Suivi local du survol d'un fichier au-dessus de la fenêtre (retour visuel).
    @State private var isDropTargeted = false

    /// Vrai si le modèle correspondant à la qualité choisie est installé.
    @State private var modelInstalled = false

    /// Modèle requis pour la qualité actuellement sélectionnée.
    private var currentModel: WhisperModel {
        WhisperModel.forPreset(state.quality)
    }

    /// Conditions réunies pour pouvoir transcrire (fichier + modèle + outils).
    private var readyToTranscribe: Bool {
        state.canTranscribe && modelInstalled && state.toolsError == nil
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            // Alerte bloquante si les binaires embarqués sont introuvables.
            if let toolsError = state.toolsError {
                Label(toolsError, systemImage: "wrench.and.screwdriver")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Contenu principal selon l'état du traitement.
            content
        }
        .padding(28)
        .frame(width: 520)
        // Glisser-déposer actif sur toute la fenêtre — mais ignoré pendant un
        // traitement en cours (pour ne pas changer de fichier en plein travail).
        .dropDestination(for: URL.self) { urls, _ in
            guard !coordinator.isRunning, let url = urls.first else { return false }
            coordinator.reset()
            state.selectFile(at: url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    /// Aiguille l'affichage : repos / progression / fin.
    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .preparing, .transcribing, .exporting:
            TranscriptionProgressView(coordinator: coordinator)

        case .finished(let directory, let srt, let txt):
            TranscriptionDoneView(
                directory: directory, srt: srt, txt: txt,
                onNewFile: {
                    coordinator.reset()
                    state.clearFile()
                }
            )

        default:
            // .idle, .cancelled, .failed → interface de préparation
            idleContent
        }
    }

    /// Interface de préparation (dépôt de fichier + options + bouton Transcrire).
    @ViewBuilder
    private var idleContent: some View {
        // Zone de dépôt tant qu'aucun fichier ; sinon la carte d'info fichier.
        if let file = state.mediaFile {
            FileInfoView(file: file, onRemove: { state.clearFile() })
        } else {
            DropZoneView(
                isLoading: state.isLoadingFile,
                isTargeted: isDropTargeted,
                onBrowse: { state.presentOpenPanel() }
            )
        }

        // Message d'erreur d'un traitement précédent (échec).
        if case .failed(let message) = coordinator.phase {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Message d'erreur de sélection (format non pris en charge, etc.).
        if let error = state.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        optionsRow

        // État du modèle requis (prêt, ou à télécharger avec progression).
        ModelStatusView(
            model: currentModel,
            downloader: downloader,
            installedChanged: { modelInstalled = $0 }
        )

        transcribeButton
    }

    // MARK: - Sous-vues

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("NONP Transcription")
                    .font(.title3.weight(.semibold))
                Text("Transcription locale, fidèle, sans limite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Les deux menus déroulants : Langue et Qualité.
    private var optionsRow: some View {
        VStack(spacing: 14) {
            // Langue
            HStack {
                Text("Langue")
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("", selection: $state.language) {
                    ForEach(TranscriptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
            }

            // Qualité (avec explication sous le menu)
            HStack(alignment: .top) {
                Text("Qualité")
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Picker("", selection: $state.quality) {
                        ForEach(QualityPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text(state.quality.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private var transcribeButton: some View {
        Button {
            // Lance le traitement. `tools` est garanti non nil quand
            // toolsError == nil (condition de readyToTranscribe).
            guard let file = state.mediaFile, let tools = state.tools else { return }
            coordinator.start(
                mediaFile: file,
                language: state.language,
                quality: state.quality,
                tools: tools
            )
        } label: {
            Text("Transcrire")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!readyToTranscribe)
        .help(transcribeHint)
    }

    /// Message d'aide contextuel du bouton Transcrire.
    private var transcribeHint: String {
        if state.toolsError != nil { return "Outils embarqués manquants" }
        if state.mediaFile == nil { return "Déposez d'abord un fichier" }
        if !modelInstalled { return "Téléchargez d'abord le modèle \(currentModel.displayName)" }
        return "Lancer la transcription"
    }
}
