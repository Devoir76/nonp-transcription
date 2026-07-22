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
            // Dossier de sortie personnalisé optionnel (--out <dossier>).
            var outDir: URL? = nil
            if let j = args.firstIndex(of: "--out"), j + 1 < args.count {
                outDir = URL(fileURLWithPath: args[j + 1], isDirectory: true)
            }
            runBlocking {
                await runPipeline(inputPath: path, language: lang,
                                  reveal: reveal, outputDirectory: outDir)
            }
        }

        if let i = args.firstIndex(of: "--selftest-cancel"), i + 1 < args.count {
            let path = args[i + 1]
            runBlocking { await runCancelTest(inputPath: path) }
        }

        // Persistance des réglages : écriture (process 1) puis lecture (process 2).
        if let i = args.firstIndex(of: "--prefs-write"), i + 1 < args.count {
            let path = args[i + 1]
            runBlocking { await prefsWrite(path) }
        }
        if args.contains("--prefs-read") {
            runBlocking { await prefsRead() }
        }
        // Résolution du dossier de sortie effectif (teste le repli si dossier absent).
        if let i = args.firstIndex(of: "--resolve-out"), i + 1 < args.count {
            let src = args[i + 1]
            runBlocking { await resolveOut(src) }
        }
        // BUG-007 : repli du dossier de sortie. Six cas, sans le moteur.
        if args.contains("--export-cases") {
            runBlocking { await exportCases() }
        }
    }

    /// Affiche le dossier de sortie EFFECTIF résolu par les réglages pour une source.
    private static func resolveOut(_ sourcePath: String) async -> Int32 {
        await MainActor.run {
            let p = Preferences()
            let dir = p.outputDirectory(for: URL(fileURLWithPath: sourcePath))
            print("[selftest] mode=\(p.outputMode.rawValue) "
                + "customUsable=\(p.customFolderIsUsable) → sortie=\(dir.path)")
        }
        return 0
    }

    // MARK: - Test du repli de dossier de sortie (BUG-007)

    /// Exerce le VRAI `SubtitleExporter` sur les six cas de résolution du dossier
    /// de sortie. Segments synthétiques : le moteur n'est pas sollicité, le test
    /// tient en une seconde et n'exige ni média ni modèle.
    ///
    /// NB : à exécuter en utilisateur non-root — root ignore les bits de permission,
    /// et les cas « non inscriptible » deviendraient alors des faux négatifs.
    private static func exportCases() async -> Int32 {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("nonp-bug007-\(getpid())", isDirectory: true)
        defer { forceRemove(root) }

        guard geteuid() != 0 else {
            print("[selftest] ÉCHEC : ne pas exécuter en root (permissions ignorées)")
            return 6
        }

        let segments = [
            TranscriptSegment(id: 1, startMs: 0, endMs: 1500, text: "Premier segment."),
            TranscriptSegment(id: 2, startMs: 1500, endMs: 3000, text: "Second segment.")
        ]
        var failures = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("[selftest] \(ok ? "OK  " : "ÉCHEC") — \(label)\(detail.isEmpty ? "" : " · \(detail)")")
        }

        /// Prépare un cas : un dossier vidéo contenant « sujet.mp4 », plus un dossier
        /// fixe optionnel. Renvoie (source, dossierFixe).
        func makeCase(_ name: String, fixedMode: Int16?) -> (src: URL, fixed: URL) {
            let base = root.appendingPathComponent(name, isDirectory: true)
            let videoDir = base.appendingPathComponent("video", isDirectory: true)
            let fixedDir = base.appendingPathComponent("fixe", isDirectory: true)
            try? fm.createDirectory(at: videoDir, withIntermediateDirectories: true)
            let src = videoDir.appendingPathComponent("sujet.mp4")
            fm.createFile(atPath: src.path, contents: Data("média factice".utf8))
            if let mode = fixedMode {
                try? fm.createDirectory(at: fixedDir, withIntermediateDirectories: true)
                chmod(fixedDir.path, mode_t(mode))
            }
            return (src, fixedDir)
        }
        func exists(_ dir: URL, _ name: String) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent(name).path)
        }

        // Cas 1 — dossier fixe accessible : les fichiers y vont.
        do {
            let c = makeCase("cas1", fixedMode: 0o755)
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  outputDirectory: c.fixed)
            check("1. dossier fixe accessible → écrit dans le dossier fixe",
                  out.srt.deletingLastPathComponent().path == c.fixed.path
                  && exists(c.fixed, "sujet.srt") && exists(c.fixed, "sujet.txt"),
                  out.srt.path)
        } catch {
            check("1. dossier fixe accessible", false, error.localizedDescription)
        }

        // Cas 2 — dossier fixe inexistant : repli auprès de la vidéo.
        do {
            let c = makeCase("cas2", fixedMode: nil)   // « fixe » n'est jamais créé
            let videoDir = c.src.deletingLastPathComponent()
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  outputDirectory: c.fixed)
            check("2. dossier fixe inexistant → repli auprès de la vidéo",
                  out.srt.deletingLastPathComponent().path == videoDir.path
                  && exists(videoDir, "sujet.srt") && exists(videoDir, "sujet.txt"),
                  out.srt.path)
        } catch {
            check("2. dossier fixe inexistant", false, error.localizedDescription)
        }

        // Cas 3 — dossier fixe présent mais NON inscriptible : repli, et le dossier
        //         fixe doit rester rigoureusement vide (aucune écriture partielle).
        do {
            let c = makeCase("cas3", fixedMode: 0o500)
            let videoDir = c.src.deletingLastPathComponent()
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  outputDirectory: c.fixed)
            let fixedContents = (try? fm.contentsOfDirectory(atPath: c.fixed.path)) ?? []
            check("3. dossier fixe non inscriptible → repli auprès de la vidéo",
                  out.srt.deletingLastPathComponent().path == videoDir.path
                  && exists(videoDir, "sujet.srt") && exists(videoDir, "sujet.txt"),
                  out.srt.path)
            check("3b. dossier fixe défaillant laissé vide",
                  fixedContents.isEmpty, "contenu=\(fixedContents)")
        } catch {
            check("3. dossier fixe non inscriptible", false, error.localizedDescription)
        }

        // Cas 4 — le dossier de repli lui-même est non inscriptible : échec net,
        //         aucun fichier nulle part.
        do {
            let c = makeCase("cas4", fixedMode: 0o500)
            let videoDir = c.src.deletingLastPathComponent()
            chmod(videoDir.path, 0o500)
            defer { chmod(videoDir.path, 0o755) }
            _ = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                            outputDirectory: c.fixed)
            check("4. repli non inscriptible → erreur attendue", false, "aucune erreur levée")
        } catch {
            let c4 = root.appendingPathComponent("cas4", isDirectory: true)
            let videoDir = c4.appendingPathComponent("video", isDirectory: true)
            let fixedDir = c4.appendingPathComponent("fixe", isDirectory: true)
            let produced = ((try? fm.contentsOfDirectory(atPath: videoDir.path)) ?? [])
                .filter { $0.hasSuffix(".srt") || $0.hasSuffix(".txt") }
                + ((try? fm.contentsOfDirectory(atPath: fixedDir.path)) ?? [])
            check("4. repli non inscriptible → erreur nette, aucun fichier produit",
                  produced.isEmpty, "résidus=\(produced)")
        }

        // Cas 5 — anti-collision DANS le dossier de repli : « sujet.srt » y existe
        //         déjà, le repli doit produire « sujet_2 ».
        do {
            let c = makeCase("cas5", fixedMode: 0o500)
            let videoDir = c.src.deletingLastPathComponent()
            fm.createFile(atPath: videoDir.appendingPathComponent("sujet.srt").path,
                          contents: Data("occupé".utf8))
            fm.createFile(atPath: videoDir.appendingPathComponent("sujet.txt").path,
                          contents: Data("occupé".utf8))
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  outputDirectory: c.fixed)
            let untouched = (try? String(contentsOf: videoDir.appendingPathComponent("sujet.srt"),
                                         encoding: .utf8)) == "occupé"
            check("5. anti-collision dans le dossier de repli → suffixe _2",
                  out.srt.lastPathComponent == "sujet_2.srt"
                  && out.txt.lastPathComponent == "sujet_2.txt" && untouched,
                  out.srt.lastPathComponent)
        } catch {
            check("5. anti-collision dans le repli", false, error.localizedDescription)
        }

        // Cas 6 — cohérence SRT/TXT : seul « sujet.srt » préexiste. Le TXT ne doit
        //         PAS prendre le nom libre « sujet.txt » : les deux restent appariés.
        do {
            let c = makeCase("cas6", fixedMode: 0o500)
            let videoDir = c.src.deletingLastPathComponent()
            fm.createFile(atPath: videoDir.appendingPathComponent("sujet.srt").path,
                          contents: Data("occupé".utf8))
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  outputDirectory: c.fixed)
            let sameBase = out.srt.deletingPathExtension().lastPathComponent
                == out.txt.deletingPathExtension().lastPathComponent
            check("6. SRT et TXT partagent toujours le même nom de base",
                  sameBase && out.srt.lastPathComponent == "sujet_2.srt"
                  && !exists(videoDir, "sujet.txt"),
                  "\(out.srt.lastPathComponent) / \(out.txt.lastPathComponent)")
        } catch {
            check("6. cohérence SRT/TXT", false, error.localizedDescription)
        }

        print("[selftest] bilan BUG-007 : \(failures == 0 ? "6/6 OK" : "\(failures) échec(s)")")
        return failures == 0 ? 0 : 5
    }

    /// Supprime une arborescence de test, y compris les dossiers rendus
    /// volontairement non inscriptibles (droits restaurés au préalable).
    private static func forceRemove(_ root: URL) {
        let fm = FileManager.default
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in e { chmod(url.path, 0o755) }
        }
        chmod(root.path, 0o755)
        try? fm.removeItem(at: root)
    }

    // MARK: - Test de persistance des réglages

    private static func prefsWrite(_ path: String) async -> Int32 {
        await MainActor.run {
            let p = Preferences()
            p.customFolderPath = path
            p.outputMode = .customFolder
            p.openFolderWhenDone = false
            print("[selftest] écrit → mode=\(p.outputMode.rawValue) "
                + "path=\(p.customFolderPath) open=\(p.openFolderWhenDone)")
        }
        UserDefaults.standard.synchronize()
        return 0
    }

    private static func prefsRead() async -> Int32 {
        await MainActor.run {
            let p = Preferences()
            print("[selftest] relu  → mode=\(p.outputMode.rawValue) "
                + "path=\(p.customFolderPath) open=\(p.openFolderWhenDone)")
        }
        return 0
    }

    // MARK: - Exécution synchrone (on bloque le main le temps du test, puis exit)

    private static func runBlocking(_ body: @escaping () async -> Int32) {
        let sem = DispatchSemaphore(value: 0)
        // `nonisolated(unsafe)` : accès unique après signal(), pas de course réelle.
        nonisolated(unsafe) var code: Int32 = 0
        Task {
            code = await body()
            sem.signal()
        }
        // On attend la fin en faisant tourner la run loop principale : ainsi le
        // travail isolé @MainActor (ex. lecture/écriture des réglages) peut
        // s'exécuter sans interblocage avec l'attente sur le thread principal.
        while sem.wait(timeout: .now() + 0.02) == .timedOut {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, true)
        }
        exit(code)
    }

    // MARK: - Test 1 : pipeline complet

    private static func runPipeline(inputPath: String, language: TranscriptionLanguage,
                                    reveal: Bool = false,
                                    outputDirectory: URL? = nil) async -> Int32 {
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

            // 3) Export (dossier personnalisé si fourni via --out)
            if let outputDirectory {
                print("[selftest] dossier de sortie : \(outputDirectory.path)")
            }
            let (srt, txt) = try SubtitleExporter.export(
                segments: segments, sourceURL: input, outputDirectory: outputDirectory
            )

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
