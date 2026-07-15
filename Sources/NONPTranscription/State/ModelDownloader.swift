// ModelDownloader.swift — téléchargement d'un modèle avec barre de progression.
//
// Utilise URLSessionDownloadTask (adapté aux gros fichiers de plusieurs Go :
// écriture directe sur disque, faible empreinte mémoire). Les callbacks du
// délégué arrivent hors du thread principal ; on repasse sur le main actor pour
// mettre à jour l'état observé par SwiftUI.

import Foundation

@MainActor
final class ModelDownloader: NSObject, ObservableObject {

    /// Étapes du cycle de téléchargement.
    enum Phase: Equatable {
        case idle
        case downloading
        case verifying          // contrôle de la taille après téléchargement
        case done
        case failed(String)
    }

    // MARK: - État observé par l'interface
    @Published var phase: Phase = .idle
    @Published var receivedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0

    /// Modèle en cours de téléchargement (nil si aucun).
    private(set) var model: WhisperModel?

    /// Fraction téléchargée (0…1).
    var fractionCompleted: Double {
        totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
    }

    // MARK: - Interne
    private var task: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Destination lue dans un callback non isolé : accès contrôlé, usage simple.
    nonisolated(unsafe) private var destinationURL: URL?

    // MARK: - Actions

    /// Démarre le téléchargement d'un modèle. Sans effet si déjà en cours.
    func start(_ model: WhisperModel) {
        guard phase != .downloading, phase != .verifying else { return }
        self.model = model
        self.destinationURL = ModelStore.localURL(for: model)
        self.receivedBytes = 0
        self.totalBytes = model.sizeBytes
        self.phase = .downloading

        let task = session.downloadTask(with: model.downloadURL)
        self.task = task
        task.resume()
    }

    /// Annule le téléchargement en cours et revient à l'état initial.
    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        receivedBytes = 0
    }
}

// MARK: - URLSessionDownloadDelegate
// Les méthodes du délégué sont non isolées (appelées par URLSession) : on y fait
// le strict nécessaire, puis on repasse sur le main actor pour l'état SwiftUI.
extension ModelDownloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            self.receivedBytes = totalBytesWritten
            // Le serveur peut ne pas annoncer la taille ; on garde alors l'attendue.
            if totalBytesExpectedToWrite > 0 {
                self.totalBytes = totalBytesExpectedToWrite
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // IMPORTANT : le fichier temporaire est supprimé dès le retour de cette
        // méthode. On le déplace donc immédiatement, de façon synchrone.
        guard let destination = destinationURL else { return }
        let fm = FileManager.default
        var moveError: String?
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
        } catch {
            moveError = error.localizedDescription
        }

        Task { @MainActor in
            if let moveError {
                self.phase = .failed("Enregistrement impossible : \(moveError)")
                return
            }
            self.verifyAndFinish()
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        // Appelé aussi en cas de succès (error == nil) : on ne traite ici que l'échec.
        guard let error else { return }
        // Annulation volontaire : déjà géré par cancel().
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor in
            if self.phase == .downloading {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Vérifie la taille du fichier téléchargé et conclut.
    private func verifyAndFinish() {
        phase = .verifying
        guard let model else { phase = .idle; return }
        if ModelStore.isInstalled(model) {
            phase = .done
        } else {
            // Taille inattendue → fichier corrompu/incomplet : on le supprime.
            try? FileManager.default.removeItem(at: ModelStore.localURL(for: model))
            phase = .failed("Fichier téléchargé incomplet ou corrompu. Réessayez.")
        }
    }
}
