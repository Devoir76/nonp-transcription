// TranscriptionCoordinator.swift — orchestration complète d'une transcription.
//
// Enchaîne : extraction audio (ffmpeg) → transcription (whisper) → export
// (SRT + TXT) → ouverture du dossier. Publie l'avancement pour l'interface
// (phase, progression, temps écoulé, temps restant estimé, nom du modèle).
//
// Robustesse :
//  • Annulation propre : termine les sous-processus ffmpeg/whisper (via
//    ProcessRunner) et supprime le WAV temporaire.
//  • Nettoyage : le WAV temporaire est toujours supprimé (succès, échec, annulation).
//  • Non-destruction : n'écrit que les .srt/.txt ; ne touche jamais la source.

import Foundation
import AppKit

@MainActor
final class TranscriptionCoordinator: ObservableObject {

    /// Étapes du traitement.
    enum Phase: Equatable {
        case idle
        case preparing                          // extraction audio (indéterminé)
        case transcribing(fraction: Double)     // transcription (0…1)
        case exporting                          // écriture SRT/TXT
        case finished(directory: URL, srt: URL, txt: URL)
        case failed(String)
        case cancelled
    }

    // MARK: - État observé
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var estimatedRemaining: TimeInterval?
    @Published private(set) var modelName: String = ""

    /// Vrai pendant un traitement (extraction, transcription ou export).
    var isRunning: Bool {
        switch phase {
        case .preparing, .transcribing, .exporting: return true
        default: return false
        }
    }

    // MARK: - Interne
    private var work: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var startDate: Date?
    private var transcribeStartDate: Date?

    // MARK: - Démarrage

    func start(
        mediaFile: MediaFile,
        language: TranscriptionLanguage,
        quality: QualityPreset,
        tools: EmbeddedTools,
        outputDirectory: URL,
        openWhenDone: Bool
    ) {
        guard !isRunning else { return }

        let model = WhisperModel.forPreset(quality)
        let modelPath = ModelStore.localURL(for: model)
        modelName = model.displayName
        estimatedRemaining = nil
        transcribeStartDate = nil
        phase = .preparing
        startClock()

        let sourceURL = mediaFile.url
        work = Task { [weak self] in
            await self?.run(
                sourceURL: sourceURL,
                language: language,
                quality: quality,
                modelPath: modelPath,
                tools: tools,
                outputDirectory: outputDirectory,
                openWhenDone: openWhenDone
            )
        }
    }

    /// Annule le traitement en cours (termine les sous-processus).
    func cancel() {
        work?.cancel()
    }

    /// Réinitialise à l'état de départ (après « Nouveau fichier »).
    func reset() {
        guard !isRunning else { return }
        phase = .idle
        elapsed = 0
        estimatedRemaining = nil
    }

    // MARK: - Pipeline

    private func run(
        sourceURL: URL,
        language: TranscriptionLanguage,
        quality: QualityPreset,
        modelPath: URL,
        tools: EmbeddedTools,
        outputDirectory: URL,
        openWhenDone: Bool
    ) async {
        let extractor = FFmpegAudioExtractor(ffmpeg: tools.ffmpeg)
        let engine = WhisperCppEngine(whisperCLI: tools.whisperCLI)
        var temporaryWAV: URL?

        do {
            // 1) Extraction audio → WAV 16 kHz mono
            let wav = try await extractor.extractAudio(from: sourceURL)
            temporaryWAV = wav
            try Task.checkCancellation()

            // 2) Transcription
            transcribeStartDate = Date()
            phase = .transcribing(fraction: 0)
            let segments = try await engine.transcribe(
                wavURL: wav,
                modelPath: modelPath,
                language: language,
                quality: quality
            ) { [weak self] fraction in
                // Callback possiblement hors du main actor : on repasse dessus.
                Task { @MainActor in self?.updateTranscriptionProgress(fraction) }
            }
            try Task.checkCancellation()

            // 3) Export SRT + TXT dans le dossier de sortie choisi.
            //    L'exportateur se replie auprès de la vidéo si ce dossier est
            //    devenu inaccessible : les URL renvoyées font foi.
            phase = .exporting
            let (srt, txt) = try SubtitleExporter.export(
                segments: segments, sourceURL: sourceURL,
                outputDirectory: outputDirectory
            )

            // 4) Nettoyage du temporaire + fin
            removeTemporary(temporaryWAV)
            stopClock()
            // Dossier RÉELLEMENT utilisé, et non celui demandé : après un repli,
            // les deux diffèrent.
            phase = .finished(directory: srt.deletingLastPathComponent(),
                              srt: srt, txt: txt)

            // 5) Ouverture automatique du dossier de sortie (si le réglage l'autorise)
            if openWhenDone {
                NSWorkspace.shared.activateFileViewerSelecting([srt, txt])
            }

        } catch {
            // Nettoyage systématique du WAV temporaire.
            removeTemporary(temporaryWAV)
            stopClock()
            // Distinguer annulation et véritable échec (un processus terminé par
            // annulation renvoie une erreur non nulle qu'il ne faut pas afficher).
            if Task.isCancelled {
                phase = .cancelled
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Progression & horloge

    private func updateTranscriptionProgress(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        phase = .transcribing(fraction: clamped)
        updateETA(fraction: clamped)
    }

    private func startClock() {
        startDate = Date()
        elapsed = 0
        clock = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self, let start = self.startDate else { return }
                    self.elapsed = Date().timeIntervalSince(start)
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0,5 s
            }
        }
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
    }

    /// Supprime le fichier WAV temporaire s'il existe (sans jamais lever d'erreur).
    private func removeTemporary(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Estime le temps restant à partir de l'avancement de la transcription.
    private func updateETA(fraction: Double) {
        guard let tStart = transcribeStartDate, fraction > 0.03 else {
            estimatedRemaining = nil
            return
        }
        let spent = Date().timeIntervalSince(tStart)
        let total = spent / fraction
        estimatedRemaining = max(0, total - spent)
    }
}
