// SelfTest.swift — harnais de test headless du pipeline réel.
//
// Activé uniquement si l'app est lancée avec des arguments de test ; invisible
// en usage normal. Il exécute EXACTEMENT les mêmes composants que l'interface
// (FFmpegAudioExtractor, WhisperCppEngine, SubtitleExporter), ce qui permet de
// valider le cœur du produit en ligne de commande, sans piloter la fenêtre.
//
// Usages :
//   NONPTranscription --selftest <fichier> [--lang-en]
//   NONPTranscription --selftest-cancel <fichier>   (teste l'annulation propre)

import Foundation
import AppKit   // pour NSWorkspace (ouverture du dossier), via --reveal

enum SelfTest {

    /// À appeler au tout début du lancement. Ne fait rien en usage normal.
    static func maybeRun() {
        let args = CommandLine.arguments

        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
            let path = args[i + 1]
            let lang: TranscriptionLanguage = args.contains("--lang-en") ? .english : .auto
            let reveal = args.contains("--reveal")
            runBlocking { await runPipeline(inputPath: path, language: lang, reveal: reveal) }
        }

        if let i = args.firstIndex(of: "--selftest-cancel"), i + 1 < args.count {
            let path = args[i + 1]
            runBlocking { await runCancelTest(inputPath: path) }
        }
    }

    // MARK: - Exécution synchrone (on bloque le main le temps du test, puis exit)

    private static func runBlocking(_ body: @escaping () async -> Int32) {
        let sem = DispatchSemaphore(value: 0)
        // `nonisolated(unsafe)` : accès unique après signal(), pas de course réelle.
        nonisolated(unsafe) var code: Int32 = 0
        Task.detached {
            code = await body()
            sem.signal()
        }
        sem.wait()
        exit(code)
    }

    // MARK: - Test 1 : pipeline complet

    private static func runPipeline(inputPath: String, language: TranscriptionLanguage,
                                    reveal: Bool = false) async -> Int32 {
        let input = URL(fileURLWithPath: inputPath)
        print("[selftest] entrée : \(input.path)")

        // Empreinte du fichier source AVANT (pour prouver qu'il n'est pas modifié).
        let sourceBefore = fingerprint(input)

        do {
            let tools = try EmbeddedTools.locate()
            // Chemins réellement résolus : preuve que l'app utilise SES binaires.
            print("[selftest] ffmpeg résolu  : \(tools.ffmpeg.path)")
            print("[selftest] whisper résolu : \(tools.whisperCLI.path)")
            let model = WhisperModel.largeV3
            guard ModelStore.isInstalled(model) else {
                print("[selftest] ÉCHEC : modèle large-v3 absent")
                return 2
            }
            let modelPath = ModelStore.localURL(for: model)
            let extractor = FFmpegAudioExtractor(ffmpeg: tools.ffmpeg)
            let engine = WhisperCppEngine(whisperCLI: tools.whisperCLI)

            // 1) Extraction
            let wav = try await extractor.extractAudio(from: input)
            print("[selftest] wav temporaire : \(wav.lastPathComponent) (existe=\(exists(wav)))")

            // 2) Transcription
            let segments = try await engine.transcribe(
                wavURL: wav, modelPath: modelPath,
                language: language, quality: .maximum
            ) { _ in }

            // 3) Export
            let (srt, txt) = try SubtitleExporter.export(segments: segments, sourceURL: input)

            // 4) Nettoyage du temporaire
            try? FileManager.default.removeItem(at: wav)

            // Rapport
            print("[selftest] segments : \(segments.count)")
            print("[selftest] SRT : \(srt.path)")
            print("[selftest] TXT : \(txt.path)")
            print("[selftest] wav nettoyé : \(!exists(wav))")

            // Vérifie que la source n'a pas changé.
            let sourceAfter = fingerprint(input)
            let sourceIntact = (sourceBefore == sourceAfter)
            print("[selftest] source intacte : \(sourceIntact) (\(sourceBefore))")

            // Ouverture automatique du dossier (même appel que le coordinateur).
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([srt, txt])
                print("[selftest] ouverture du dossier demandée (Finder)")
            }

            return (sourceIntact && !exists(wav)) ? 0 : 4
        } catch {
            print("[selftest] ÉCHEC : \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - Test 2 : annulation propre (aucun processus résiduel)

    private static func runCancelTest(inputPath: String) async -> Int32 {
        let input = URL(fileURLWithPath: inputPath)
        do {
            let tools = try EmbeddedTools.locate()
            let modelPath = ModelStore.localURL(for: WhisperModel.largeV3)
            let extractor = FFmpegAudioExtractor(ffmpeg: tools.ffmpeg)
            let engine = WhisperCppEngine(whisperCLI: tools.whisperCLI)

            let wav = try await extractor.extractAudio(from: input)

            // Lance la transcription puis l'annule au bout de 4 s.
            let job = Task {
                try await engine.transcribe(
                    wavURL: wav, modelPath: modelPath,
                    language: .auto, quality: .maximum
                ) { _ in }
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            print("[selftest] annulation en cours…")
            job.cancel()
            _ = await job.result           // attend le dénouement (terminaison du process)

            try? FileManager.default.removeItem(at: wav)

            // Un éventuel whisper-cli résiduel serait détecté ici.
            let residual = pgrep("whisper-cli") + pgrep("ffmpeg")
            print("[selftest] processus résiduels après annulation : \(residual.isEmpty ? "AUCUN" : residual)")
            return residual.isEmpty ? 0 : 3
        } catch {
            print("[selftest] ÉCHEC : \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - Utilitaires

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Empreinte simple (taille + date de modification) pour détecter toute altération.
    private static func fingerprint(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "taille=\(size) mtime=\(Int(mod))"
    }

    /// Retourne les PID (chaîne) des processus dont le nom correspond, ou "".
    private static func pgrep(_ name: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", name]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
