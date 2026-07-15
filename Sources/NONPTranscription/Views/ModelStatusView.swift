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
            if installed {
                readyRow
            } else if isBusyOnThisModel {
                progressRow
            } else {
                promptRow
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model) { _, _ in refresh() }
        .onChange(of: downloader.phase) { _, _ in refresh() }
    }

    // MARK: - Variantes d'affichage

    private var readyRow: some View {
        Label("Modèle \(model.displayName) prêt", systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(downloader.phase == .verifying
                     ? "Vérification…"
                     : "Téléchargement de \(model.displayName)…")
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
