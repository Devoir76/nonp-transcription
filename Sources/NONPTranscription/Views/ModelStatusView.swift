// ModelStatusView.swift — état du modèle requis + téléchargement avec progression.
//
// Affiche, pour le modèle correspondant à la qualité choisie :
//  • soit « modèle prêt » (déjà téléchargé),
//  • soit une invite de téléchargement avec barre de progression et bouton Annuler.
// Informe le parent (ContentView) de l'état d'installation pour piloter le
// bouton « Transcrire ».

import SwiftUI

struct ModelStatusView: View {
    let model: WhisperModel
    @ObservedObject var downloader: ModelDownloader
    /// Rappel appelé quand l'état « installé / non installé » change.
    let installedChanged: (Bool) -> Void

    @State private var installed = false

    /// Vrai si le téléchargeur travaille actuellement SUR CE modèle.
    private var isBusyOnThisModel: Bool {
        downloader.model?.id == model.id &&
        (downloader.phase == .downloading || downloader.phase == .verifying)
    }

    var body: some View {
        Group {
            if isBusyOnThisModel {          // téléchargement OU vérification
                progressRow
            } else if isFailedOnThisModel { // non conforme / erreur d'intégrité
                failedRow
            } else if installed {
                readyRow                    // + bouton « Vérifier maintenant »
            } else {
                promptRow
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model) { _, _ in refresh() }
        .onChange(of: downloader.phase) { _, _ in refresh() }
    }

    /// Vrai si le téléchargeur est en échec (intégrité/erreur) SUR CE modèle.
    private var isFailedOnThisModel: Bool {
        guard downloader.model?.id == model.id else { return false }
        if case .failed = downloader.phase { return true }
        return false
    }

    // MARK: - Variantes d'affichage

    private var readyRow: some View {
        HStack {
            Label("Modèle \(model.displayName) prêt", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Spacer()
            Button("Vérifier maintenant") { downloader.verifyInstalled(model) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Recalcule l'empreinte SHA-256 et la compare à la référence")
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Modèle présent mais non conforme (empreinte invalide) ou erreur de vérif.
    private var failedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Modèle \(model.displayName) non conforme")
                    .font(.callout)
                Text(failureMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Re-télécharger") { downloader.start(model) }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
    }

    /// Message porté par l'état d'échec du téléchargeur.
    private var failureMessage: String {
        if case .failed(let msg) = downloader.phase { return msg }
        return "Fichier non conforme."
    }

    private var promptRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Modèle \(model.displayName) requis")
                    .font(.callout)
                Text("Téléchargement unique · \(model.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Télécharger") { downloader.start(model) }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private var progressRow: some View {
        if downloader.phase == .verifying {
            verifyingRow          // hachage : indéterminé, pas d'octets, non annulable
        } else {
            downloadingRow        // téléchargement : rendu ACTUEL, strictement inchangé
        }
    }

    /// Vérification d'empreinte : indicateur INDÉTERMINÉ (le SHA-256 ne télécharge
    /// aucun octet et n'a pas de progression fine). Aucun compteur, aucun %, pas
    /// d'« Annuler » (rien à interrompre proprement côté hachage).
    private var verifyingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Vérification de l'empreinte du modèle…")
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    /// Téléchargement : barre déterminée + octets + pourcentage + Annuler.
    /// Rendu identique à l'ancien `progressRow` en phase .downloading.
    private var downloadingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Téléchargement de \(model.displayName)…")
                    .font(.callout)
                Spacer()
                Button("Annuler") { downloader.cancel() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            ProgressView(value: downloader.fractionCompleted)
            Text(progressDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: - Aides

    private var progressDetail: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        let received = f.string(fromByteCount: downloader.receivedBytes)
        let total = f.string(fromByteCount: downloader.totalBytes)
        let pct = Int((downloader.fractionCompleted * 100).rounded())
        return "\(received) / \(total)  ·  \(pct) %"
    }

    /// Recalcule l'état d'installation et prévient le parent.
    private func refresh() {
        let now = ModelStore.isInstalled(model)
        if now != installed { installed = now }
        installedChanged(now)
    }
}
