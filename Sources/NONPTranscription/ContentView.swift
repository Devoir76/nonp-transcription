// ContentView.swift — vue principale, assemble toute l'interface (Étape 1).
//
// Compose : en-tête · (zone de dépôt OU carte fichier) · message d'erreur
// éventuel · options Langue de l'audio et Qualité · bouton Transcrire.
// Le bouton est volontairement inactif à ce stade : le moteur arrive à l'Étape 3.

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    /// Réglages persistants (dossier de sortie, ouverture auto).
    @EnvironmentObject private var preferences: Preferences

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

    // MARK: - Langue de l'audio (affichage seul)

    /// Les deux façons de renseigner la langue. Purement d'affichage : la source
    /// de vérité reste `preferences.language` (`.auto` = détection automatique).
    private enum LanguageMode: Hashable { case auto, explicit }

    /// Langues proposées au menu : toutes sauf `.auto`, qui est devenue le
    /// bouton radio « Détecter automatiquement ».
    private static let explicitLanguages: [TranscriptionLanguage] =
        TranscriptionLanguage.allCases.filter { $0 != .auto }

    private static let languageHelp =
        "Choisissez la langue parlée dans le fichier. NONP Transcription la "
        + "retranscrit fidèlement — il ne traduit pas."

    /// Dernière langue explicite retenue, le temps de la session : sert à
    /// repeupler le menu quand on repasse de « Détecter » à « Préciser ».
    /// Volontairement NON persistée — seul `preferences.language` l'est.
    @State private var lastExplicitLanguage: TranscriptionLanguage = .french

    private var languageMode: LanguageMode {
        preferences.language == .auto ? .auto : .explicit
    }

    /// Bascule radio. Passer à « Préciser » réutilise le dernier choix connu.
    private var languageModeBinding: Binding<LanguageMode> {
        Binding(
            get: { languageMode },
            set: { mode in
                switch mode {
                case .auto:     preferences.language = .auto
                case .explicit: preferences.language = lastExplicitLanguage
                }
            }
        )
    }

    /// Sélection du menu. En mode « Détecter », le menu est inactif et se
    /// contente d'afficher le dernier choix — il n'écrit rien.
    private var explicitLanguageBinding: Binding<TranscriptionLanguage> {
        Binding(
            get: { preferences.language == .auto ? lastExplicitLanguage : preferences.language },
            set: { lang in
                guard lang != .auto else { return }
                lastExplicitLanguage = lang
                preferences.language = lang
            }
        )
    }

    /// Conditions réunies pour pouvoir transcrire (fichier + modèle + outils).
    /// Bloqué si le modèle courant est en échec d'intégrité ou en cours de vérif :
    /// on ne transcrit jamais avec un modèle dont l'empreinte n'est pas confirmée.
    private var readyToTranscribe: Bool {
        state.canTranscribe && modelInstalled && state.toolsError == nil
            && !modelIntegrityBlocked
    }

    /// Vrai si le téléchargeur signale un échec d'intégrité (ou vérifie) le modèle
    /// actuellement requis.
    private var modelIntegrityBlocked: Bool {
        guard downloader.model?.id == currentModel.id else { return false }
        switch downloader.phase {
        case .failed, .verifying: return true
        default:                  return false
        }
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

        case .finished(let directory, let outputs):
            TranscriptionDoneView(
                directory: directory, outputs: outputs,
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

        outputTargetRow

        transcribeButton
    }

    /// Rappel discret de la destination des fichiers (réglable dans les Réglages).
    private var outputTargetRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(outputTargetDescription)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var outputTargetDescription: String {
        if preferences.outputMode == .customFolder, preferences.customFolderIsUsable,
           let url = preferences.customFolderURL {
            return "Sortie : \(url.path)"
        }
        return "Sortie : à côté de la vidéo"
    }

    // MARK: - Sous-vues

    /// Logo de l'en-tête, copié dans le bundle par Scripts/build_app.sh.
    /// `nil` hors bundle (exécution directe du binaire de debug) : on retombe
    /// alors sur l'icône système, pour ne jamais présenter un en-tête vide.
    private static let headerLogo = NSImage(named: "nonp_header_logo")

    private var header: some View {
        HStack(spacing: 10) {
            headerIcon
                .frame(width: 26, height: 26)
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

    /// Le logo du produit, arrondi en rectangle continu (le squircle macOS),
    /// ou l'icône système en repli.
    @ViewBuilder
    private var headerIcon: some View {
        if let logo = Self.headerLogo {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
        }
    }

    /// Largeur de la colonne des libellés (Langue de l'audio / Qualité).
    private static let labelColumnWidth: CGFloat = 120

    /// Les deux blocs d'options : Langue de l'audio et Qualité.
    private var optionsRow: some View {
        VStack(spacing: 14) {
            // Langue de l'audio : « Détecter automatiquement » (défaut) ou une
            // langue précisée. Le libellé et l'aide disent explicitement que
            // l'app retranscrit — elle ne traduit pas.
            HStack(alignment: .top) {
                Text("Langue de l'audio")
                    .frame(width: Self.labelColumnWidth, alignment: .leading)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    // Alignement bas : le menu se pose sur la ligne « Préciser : ».
                    HStack(alignment: .bottom, spacing: 8) {
                        Picker("", selection: languageModeBinding) {
                            Text("Détecter automatiquement").tag(LanguageMode.auto)
                            Text("Préciser :").tag(LanguageMode.explicit)
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)

                        Picker("", selection: explicitLanguageBinding) {
                            ForEach(Self.explicitLanguages) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                        .disabled(languageMode == .auto)
                    }

                    Text(Self.languageHelp)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .help(Self.languageHelp)
            .onAppear {
                // Reprend le dernier choix explicite persisté, pour que le menu
                // n'affiche pas une langue au hasard après relance.
                if preferences.language != .auto {
                    lastExplicitLanguage = preferences.language
                }
            }

            // Qualité (avec explication sous le menu)
            HStack(alignment: .top) {
                Text("Qualité")
                    .frame(width: Self.labelColumnWidth, alignment: .leading)
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
                language: preferences.language,
                quality: state.quality,
                tools: tools,
                outputDirectory: preferences.outputDirectory(for: file.url),
                formats: preferences.orderedSelectedFormats,
                openWhenDone: preferences.openFolderWhenDone
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
