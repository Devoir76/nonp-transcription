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
//   NONPTranscription --prefs-cases                 (persistance, même process)
//   NONPTranscription --prefs-write                 (persistance, process 1/2)
//   NONPTranscription --prefs-read                  (persistance, process 2/2)

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

        // Persistance des réglages : aller-retour dans le MÊME process (cache).
        if args.contains("--prefs-cases") {
            runBlocking { await prefsCases() }
        }
        // Persistance CROSS-PROCESS : écriture (process 1) puis lecture (process 2).
        // Seul test qui exerce le vrai mode d'échec de BUG-006 — la persistance
        // adossée au disque, entre deux lancements distincts.
        if args.contains("--prefs-write") {
            runBlocking { await prefsWrite() }
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
        var total = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            total += 1
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
                                                  formats: [.srt, .txt], outputDirectory: c.fixed)
            check("1. dossier fixe accessible → écrit dans le dossier fixe",
                  out.url(for: .srt)!.deletingLastPathComponent().path == c.fixed.path
                  && exists(c.fixed, "sujet.srt") && exists(c.fixed, "sujet.txt"),
                  out.url(for: .srt)!.path)
        } catch {
            check("1. dossier fixe accessible", false, error.localizedDescription)
        }

        // Cas 2 — dossier fixe inexistant : repli auprès de la vidéo.
        do {
            let c = makeCase("cas2", fixedMode: nil)   // « fixe » n'est jamais créé
            let videoDir = c.src.deletingLastPathComponent()
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  formats: [.srt, .txt], outputDirectory: c.fixed)
            check("2. dossier fixe inexistant → repli auprès de la vidéo",
                  out.url(for: .srt)!.deletingLastPathComponent().path == videoDir.path
                  && exists(videoDir, "sujet.srt") && exists(videoDir, "sujet.txt"),
                  out.url(for: .srt)!.path)
        } catch {
            check("2. dossier fixe inexistant", false, error.localizedDescription)
        }

        // Cas 3 — dossier fixe présent mais NON inscriptible : repli, et le dossier
        //         fixe doit rester rigoureusement vide (aucune écriture partielle).
        do {
            let c = makeCase("cas3", fixedMode: 0o500)
            let videoDir = c.src.deletingLastPathComponent()
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  formats: [.srt, .txt], outputDirectory: c.fixed)
            let fixedContents = (try? fm.contentsOfDirectory(atPath: c.fixed.path)) ?? []
            check("3. dossier fixe non inscriptible → repli auprès de la vidéo",
                  out.url(for: .srt)!.deletingLastPathComponent().path == videoDir.path
                  && exists(videoDir, "sujet.srt") && exists(videoDir, "sujet.txt"),
                  out.url(for: .srt)!.path)
            check("3b. dossier fixe défaillant laissé vide",
                  fixedContents.isEmpty, "contenu=\(fixedContents)")
        } catch {
            check("3. dossier fixe non inscriptible", false, error.localizedDescription)
        }

        // Cas 4 — le dossier de repli lui-même est non inscriptible : échec net,
        //         aucun fichier nulle part, ET message désignant le BON dossier.
        do {
            let c = makeCase("cas4", fixedMode: 0o500)
            let videoDir = c.src.deletingLastPathComponent()
            chmod(videoDir.path, 0o500)
            defer { chmod(videoDir.path, 0o755) }
            _ = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                            formats: [.srt, .txt], outputDirectory: c.fixed)
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

            // BUG-008 : le message doit nommer le dossier de la VIDÉO (seul dossier
            // réellement tenté au moment de l'échec final) et JAMAIS le dossier fixe.
            let msg = error.localizedDescription
            check("4b. message → nomme le dossier réellement tenté (vidéo)",
                  msg.contains(videoDir.path), msg.replacingOccurrences(of: "\n", with: " ⏎ "))
            check("4c. message → ne mentionne PAS le dossier fixe non tenté",
                  !msg.contains(fixedDir.path))
            check("4d. message → structure attendue",
                  msg.hasPrefix("Impossible d'écrire les fichiers de sortie dans :\n")
                  && msg.contains("\nVérifiez que ce dossier est accessible en écriture.\n")
                  && msg.contains("\nDétail technique : "))
            check("4e. message → ne dit plus « le dossier de la vidéo »",
                  !msg.contains("dossier de la vidéo"))
        }

        // Cas 7 — dossier de la vidéo directement non inscriptible (mode « à côté de
        //         la vidéo », aucun dossier fixe) : le message doit le nommer, lui.
        do {
            let c = makeCase("cas7", fixedMode: nil)
            let videoDir = c.src.deletingLastPathComponent()
            chmod(videoDir.path, 0o500)
            defer { chmod(videoDir.path, 0o755) }
            _ = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                            formats: [.srt, .txt], outputDirectory: nil)
            check("7. dossier vidéo non inscriptible → erreur attendue", false,
                  "aucune erreur levée")
        } catch {
            let videoDir = root.appendingPathComponent("cas7", isDirectory: true)
                .appendingPathComponent("video", isDirectory: true)
            let msg = error.localizedDescription
            check("7. dossier vidéo non inscriptible → message nommant ce dossier",
                  msg.contains(videoDir.path),
                  msg.replacingOccurrences(of: "\n", with: " ⏎ "))
            check("7b. détail technique présent (message Cocoa conservé)",
                  msg.contains("Détail technique : ")
                  && msg.split(separator: ":").last?.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty == false)
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
                                                  formats: [.srt, .txt], outputDirectory: c.fixed)
            let untouched = (try? String(contentsOf: videoDir.appendingPathComponent("sujet.srt"),
                                         encoding: .utf8)) == "occupé"
            check("5. anti-collision dans le dossier de repli → suffixe _2",
                  out.url(for: .srt)!.lastPathComponent == "sujet_2.srt"
                  && out.url(for: .txt)!.lastPathComponent == "sujet_2.txt" && untouched,
                  out.url(for: .srt)!.lastPathComponent)
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
                                                  formats: [.srt, .txt], outputDirectory: c.fixed)
            let sameBase = out.url(for: .srt)!.deletingPathExtension().lastPathComponent
                == out.url(for: .txt)!.deletingPathExtension().lastPathComponent
            check("6. SRT et TXT partagent toujours le même nom de base",
                  sameBase && out.url(for: .srt)!.lastPathComponent == "sujet_2.srt"
                  && !exists(videoDir, "sujet.txt"),
                  "\(out.url(for: .srt)!.lastPathComponent) / \(out.url(for: .txt)!.lastPathComponent)")
        } catch {
            check("6. cohérence SRT/TXT", false, error.localizedDescription)
        }

        print("[selftest] bilan BUG-007 + BUG-008 : "
            + (failures == 0 ? "\(total)/\(total) OK" : "\(failures)/\(total) échec(s)"))

        // Cas VTT (Phase 2) — packaging WebVTT à partir des mêmes segments
        // synthétiques. Bilan SÉPARÉ : n'entre PAS dans le décompte BUG-007 + BUG-008
        // ci-dessus (qui reste à 13/13).
        let vtt = Checker()
        do {
            let c = makeCase("casVTT", fixedMode: 0o755)
            let out = try SubtitleExporter.export(segments: segments, sourceURL: c.src,
                                                  formats: [.vtt], outputDirectory: c.fixed)
            let url = out.url(for: .vtt)
            let content = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            let tcLines = content.split(separator: "\n").filter { $0.contains("-->") }
            vtt.check("V1. un seul fichier .vtt produit",
                      out.count == 1 && url?.pathExtension == "vtt", url?.lastPathComponent ?? "nil")
            vtt.check("V2. entête WEBVTT en tête", content.hasPrefix("WEBVTT"))
            vtt.check("V3. timecodes en « . », jamais « , »",
                      !tcLines.isEmpty && tcLines.allSatisfy { $0.contains(".") && !$0.contains(",") })
            vtt.check("V4. un cue par segment (\(segments.count))", tcLines.count == segments.count)

            // V5 — échappement WebVTT : seul point qui réécrit les octets du texte
            // (§7). Un segment dont le texte est exactement « < & > » doit ressortir
            // « &lt; &amp; &gt; ». Le contains() épingle À LA FOIS la présence de
            // l'échappement ET l'ordre « & d'abord » : si « < » était échappé avant
            // « & », le « & » de « &lt; » serait re-échappé en « &amp;lt; » et la
            // chaîne attendue n'apparaîtrait pas.
            let escSeg = [TranscriptSegment(id: 1, startMs: 0, endMs: 1000, text: "< & >")]
            let escCase = makeCase("casVTTesc", fixedMode: 0o755)
            let escOut = try SubtitleExporter.export(segments: escSeg, sourceURL: escCase.src,
                                                     formats: [.vtt], outputDirectory: escCase.fixed)
            let escContent = escOut.url(for: .vtt)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            vtt.check("V5. échappement WebVTT (< & > → &lt; &amp; &gt;, & traité en premier)",
                      escContent.contains("&lt; &amp; &gt;"))
        } catch {
            vtt.check("V. export VTT", false, error.localizedDescription)
        }
        let vttCode = vtt.report("format VTT (Phase 2)")

        // Durée MKV/AVI (parsing) — teste la fonction PURE parseFFmpegDuration sur
        // des chaînes fixes. Aucun sous-processus, aucun fichier. Bilan SÉPARÉ.
        let dur = Checker()
        let d1 = MediaDurationProbe.parseFFmpegDuration(
            "  Duration: 00:00:03.51, start: 0.000000, bitrate: 77 kb/s")
        dur.check("D1. « 00:00:03.51 » → ~3.51",
                  d1.map { abs($0 - 3.51) < 0.02 } == true, String(describing: d1))
        dur.check("D2. « Duration: N/A » → nil",
                  MediaDurationProbe.parseFFmpegDuration("  Duration: N/A, start: 0") == nil)
        dur.check("D3. chaîne sans « Duration: » → nil",
                  MediaDurationProbe.parseFFmpegDuration("Stream #0:0: Audio: pcm_s16le") == nil)
        dur.check("D4. « 01:02:03.00 » → 3723.0",
                  MediaDurationProbe.parseFFmpegDuration("Duration: 01:02:03.00, bitrate: 1 kb/s") == 3723.0)
        let durCode = dur.report("durée MKV/AVI (parsing)")

        return (failures == 0 && vttCode == 0 && durCode == 0) ? 0 : 5
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

    // MARK: - Test de persistance des réglages (BUG-006)

    /// Suite de test à NOM FIXE : partagée entre le process d'écriture et celui
    /// de lecture. Jamais le domaine standard — les réglages réels de
    /// l'utilisateur ne sont touchés par aucun de ces tests.
    private static let prefsSuite = "com.nonp.transcription.selftest"

    /// Valeurs témoins de l'aller-retour cross-process. Le chemin est fictif :
    /// aucun dossier réel de l'utilisateur n'apparaît jamais ici.
    private static let probeMode: Preferences.OutputMode = .customFolder
    private static let probePath = "/tmp/nonp-selftest-crossprocess"
    private static let probeOpen = false
    /// Témoin de formats : volontairement un SEUL format (≠ défaut {SRT,TXT}),
    /// pour prouver qu'un choix restreint survit au changement de process.
    private static let probeFormats: Set<OutputFormat> = [.srt]

    /// Petit compteur d'assertions, commun aux blocs de persistance.
    private final class Checker {
        var total = 0, failures = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            total += 1
            if !ok { failures += 1 }
            print("[selftest] \(ok ? "OK  " : "ÉCHEC") — \(label)"
                + (detail.isEmpty ? "" : " · \(detail)"))
        }
        func report(_ title: String) -> Int32 {
            print("[selftest] bilan \(title) : "
                + (failures == 0 ? "\(total)/\(total) OK" : "\(failures)/\(total) échec(s)"))
            return failures == 0 ? 0 : 7
        }
    }

    /// Snapshot des trois clés du domaine RÉEL, pour prouver qu'aucun test de
    /// persistance ne l'altère.
    private static func standardSnapshot() -> String {
        ["outputMode", "customFolderPath", "openFolderWhenDone", "selectedFormats"]
            .map { "\($0)=\(String(describing: UserDefaults.standard.object(forKey: $0)))" }
            .joined(separator: " ")
    }

    /// Aller-retour vérifié sur les trois réglages, dans une suite ISOLÉE et un
    /// SEUL process : valide la cohérence écriture → relecture (cache).
    /// Ne prouve rien sur la persistance disque — c'est le rôle du cross-process.
    private static func prefsCases() async -> Int32 {
        let suiteName = "\(prefsSuite)-\(getpid())"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            print("[selftest] ÉCHEC : suite de test non créée")
            return 7
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let k = Checker()
        let before = standardSnapshot()

        await MainActor.run {
            // Valeurs d'origine dans la suite, à restaurer en fin de test.
            let origin = Preferences(defaults: suite)
            let o0 = origin.outputMode, o1 = origin.customFolderPath
            let o2 = origin.openFolderWhenDone, o3 = origin.selectedFormats

            let a = Preferences(defaults: suite)

            // 1 — outputMode, dans les deux sens.
            a.outputMode = .customFolder
            k.check("1. outputMode écrit → relu à l'identique",
                    Preferences(defaults: suite).outputMode == .customFolder)
            a.outputMode = .sourceFolder
            k.check("1b. outputMode rebasculé → relu à l'identique",
                    Preferences(defaults: suite).outputMode == .sourceFolder)

            // 2 — customFolderPath (valeur connue, jamais un chemin réel).
            let probe = "/tmp/nonp-selftest-\(getpid())"
            a.customFolderPath = probe
            k.check("2. customFolderPath écrit → relu à l'identique",
                    Preferences(defaults: suite).customFolderPath == probe)
            a.customFolderPath = ""
            k.check("2b. customFolderPath vidé → relu vide",
                    Preferences(defaults: suite).customFolderPath.isEmpty)

            // 3 — openFolderWhenDone : les DEUX valeurs. `false` est le cas
            //     piégeux — une clé à sa valeur par défaut peut être absente.
            a.openFolderWhenDone = false
            k.check("3. openFolderWhenDone=false écrit → relu false",
                    Preferences(defaults: suite).openFolderWhenDone == false)
            k.check("3b. openFolderWhenDone=false stocké EXPLICITEMENT",
                    suite.object(forKey: "openFolderWhenDone") != nil)
            a.openFolderWhenDone = true
            k.check("3c. openFolderWhenDone=true écrit → relu true",
                    Preferences(defaults: suite).openFolderWhenDone == true)

            // 3d — selectedFormats : choix restreint {SRT} relu à l'identique,
            //       puis retour au couple {SRT,TXT}.
            a.selectedFormats = [.srt]
            k.check("3d. selectedFormats={SRT} écrit → relu à l'identique",
                    Preferences(defaults: suite).selectedFormats == [.srt])
            a.selectedFormats = [.srt, .txt]
            k.check("3e. selectedFormats={SRT,TXT} écrit → relu à l'identique",
                    Preferences(defaults: suite).selectedFormats == [.srt, .txt])
            // 3f — repli sur le défaut si la clé stockée est corrompue (jamais vide).
            suite.set(["xxx", "zzz"], forKey: "selectedFormats")
            k.check("3f. selectedFormats corrompu → repli sur défaut {SRT,TXT}",
                    Preferences(defaults: suite).selectedFormats == OutputFormat.defaultSet)

            // 4 — indépendance des clés (constat du cycle 5 de la campagne 19/07).
            a.customFolderPath = probe
            a.outputMode = .customFolder
            a.openFolderWhenDone = false
            let b = Preferences(defaults: suite)
            b.outputMode = .sourceFolder
            let c = Preferences(defaults: suite)
            k.check("4. quitter le mode dossier fixe CONSERVE customFolderPath",
                    c.customFolderPath == probe, c.customFolderPath)
            k.check("4b. ... et n'altère pas openFolderWhenDone",
                    c.openFolderWhenDone == false)

            // 5 — restauration des valeurs d'origine, puis vérification.
            let r = Preferences(defaults: suite)
            r.outputMode = o0; r.customFolderPath = o1; r.openFolderWhenDone = o2
            r.selectedFormats = o3
            let back = Preferences(defaults: suite)
            k.check("5. valeurs d'origine restaurées",
                    back.outputMode == o0 && back.customFolderPath == o1
                    && back.openFolderWhenDone == o2 && back.selectedFormats == o3)
        }

        // 5b — contrôle réel : le domaine de l'utilisateur n'a pas bougé.
        let after = standardSnapshot()
        k.check("5b. domaine standard inchangé par le test", before == after,
                before == after ? "" : "avant=[\(before)] après=[\(after)]")

        return k.report("persistance même-process (BUG-006)")
    }

    /// Process 1/2 — écrit les valeurs témoins dans la suite isolée à nom fixe.
    /// PAS de `synchronize()` : le parcours GUI ne l'appelle jamais, et la fiche
    /// BUG-006 note que son usage rendait l'ancien test non représentatif.
    private static func prefsWrite() async -> Int32 {
        guard let suite = UserDefaults(suiteName: prefsSuite) else {
            print("[selftest] ÉCHEC : suite de test non créée")
            return 7
        }
        let k = Checker()
        let before = standardSnapshot()

        await MainActor.run {
            let p = Preferences(defaults: suite)
            p.outputMode = probeMode
            p.customFolderPath = probePath
            p.openFolderWhenDone = probeOpen
            p.selectedFormats = probeFormats
            k.check("W1. outputMode écrit en mémoire", p.outputMode == probeMode)
            k.check("W2. customFolderPath écrit en mémoire", p.customFolderPath == probePath)
            k.check("W3. openFolderWhenDone écrit en mémoire", p.openFolderWhenDone == probeOpen)
            k.check("W5. selectedFormats écrit en mémoire", p.selectedFormats == probeFormats)
        }

        let after = standardSnapshot()
        k.check("W4. domaine standard inchangé par l'écriture", before == after,
                before == after ? "" : "avant=[\(before)] après=[\(after)]")
        return k.report("persistance cross-process 1/2 — écriture")
    }

    /// Process 2/2 — relit la suite isolée dans un process NEUF : c'est le seul
    /// test qui exerce la persistance adossée au disque, entre deux lancements.
    private static func prefsRead() async -> Int32 {
        guard let suite = UserDefaults(suiteName: prefsSuite) else {
            print("[selftest] ÉCHEC : suite de test non créée")
            return 7
        }
        let k = Checker()
        let before = standardSnapshot()

        await MainActor.run {
            let p = Preferences(defaults: suite)
            k.check("R1. outputMode a survécu au changement de process",
                    p.outputMode == probeMode, p.outputMode.rawValue)
            k.check("R2. customFolderPath a survécu au changement de process",
                    p.customFolderPath == probePath,
                    "longueur=\(p.customFolderPath.count)")
            k.check("R3. openFolderWhenDone a survécu au changement de process",
                    p.openFolderWhenDone == probeOpen,
                    String(p.openFolderWhenDone))
            k.check("R4. openFolderWhenDone=false présent EXPLICITEMENT",
                    suite.object(forKey: "openFolderWhenDone") != nil)
            k.check("R6. selectedFormats a survécu au changement de process",
                    p.selectedFormats == probeFormats,
                    p.selectedFormats.map(\.rawValue).sorted().joined(separator: "+"))
        }

        let after = standardSnapshot()
        k.check("R5. domaine standard inchangé par la lecture", before == after,
                before == after ? "" : "avant=[\(before)] après=[\(after)]")

        // Nettoyage : la suite ne survit pas au test.
        UserDefaults.standard.removePersistentDomain(forName: prefsSuite)
        return k.report("persistance cross-process 2/2 — lecture")
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
            let outputs = try SubtitleExporter.export(
                segments: segments, sourceURL: input,
                formats: [.srt, .txt], outputDirectory: outputDirectory
            )

            // 4) Nettoyage du temporaire
            try? FileManager.default.removeItem(at: wav)

            // Rapport
            print("[selftest] segments : \(segments.count)")
            for out in outputs {
                print("[selftest] \(out.format.rawValue.uppercased()) : \(out.url.path)")
            }
            print("[selftest] wav nettoyé : \(!exists(wav))")

            // Vérifie que la source n'a pas changé.
            let sourceAfter = fingerprint(input)
            let sourceIntact = (sourceBefore == sourceAfter)
            print("[selftest] source intacte : \(sourceIntact) (\(sourceBefore))")

            // Ouverture automatique du dossier (même appel que le coordinateur).
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting(outputs.urls)
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
