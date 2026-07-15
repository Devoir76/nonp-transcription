// ProcessRunner.swift — exécution d'un sous-processus avec lecture ligne par ligne.
//
// Base commune à l'extraction (ffmpeg) et à la transcription (whisper-cli).
// Lit la sortie standard ET la sortie d'erreur au fil de l'eau (indispensable
// pour suivre la progression), et s'arrête proprement si la tâche est annulée.

import Foundation

enum ProcessRunnerError: LocalizedError {
    case nonZeroExit(code: Int32, tail: String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let tail):
            return "Le sous-processus s'est terminé avec le code \(code).\n\(tail)"
        }
    }
}

enum ProcessRunner {
    /// Lance `executable` avec `arguments`. Chaque ligne de sortie (stdout + stderr)
    /// est transmise à `onLine`. Lève une erreur si le code de sortie n'est pas 0.
    ///
    /// - Note : `onLine` peut être appelé depuis un thread quelconque.
    static func run(
        executable: URL,
        arguments: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Conserve les dernières lignes d'erreur pour un message utile en cas d'échec.
        let errorTail = LineBuffer(capacity: 20)

        try process.run()

        // Si la tâche Swift est annulée, on termine le processus.
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                // Lecture stdout (l'itération peut lever à la fin du flux : on l'ignore).
                group.addTask {
                    do {
                        for try await line in outPipe.fileHandleForReading.bytes.lines {
                            onLine(line)
                        }
                    } catch { /* fin de flux ou lecture interrompue */ }
                }
                // Lecture stderr (whisper y écrit sa progression et ses logs).
                group.addTask {
                    do {
                        for try await line in errPipe.fileHandleForReading.bytes.lines {
                            errorTail.append(line)
                            onLine(line)
                        }
                    } catch { /* fin de flux ou lecture interrompue */ }
                }
                await group.waitForAll()
            }
            process.waitUntilExit()
        } onCancel: {
            process.terminate()
        }

        let status = process.terminationStatus
        if status != 0 {
            throw ProcessRunnerError.nonZeroExit(code: status, tail: errorTail.joined())
        }
    }
}

/// Petit tampon circulaire thread-safe pour garder les N dernières lignes.
private final class LineBuffer: @unchecked Sendable {
    private let capacity: Int
    private var lines: [String] = []
    private let lock = NSLock()

    init(capacity: Int) { self.capacity = capacity }

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    func joined() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
