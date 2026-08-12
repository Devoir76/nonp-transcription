// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// TranscriptionProgressView.swift — affichage pendant le traitement.
//
// Montre l'étape en cours, la barre de progression, le temps écoulé, le temps
// restant estimé, le nom du modèle utilisé, et un bouton d'annulation.

import SwiftUI

struct TranscriptionProgressView: View {
    @ObservedObject var coordinator: TranscriptionCoordinator

    var body: some View {
        VStack(spacing: 16) {
            // Titre de l'étape en cours
            Text(phaseTitle)
                .font(.headline)

            // Fichier en cours de traitement (répond au manque du test du 22/07).
            if let name = coordinator.mediaName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Barre : indéterminée pendant extraction/export, précise en transcription.
            switch coordinator.phase {
            case .transcribing(let fraction):
                ProgressView(value: fraction)
                Text("\(Int((fraction * 100).rounded())) %")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            default:
                ProgressView()
                    .progressViewStyle(.linear)
            }

            // Temps écoulé / restant
            HStack {
                Label("Écoulé : \(Self.format(coordinator.elapsed))", systemImage: "clock")
                Spacer()
                if let remaining = coordinator.estimatedRemaining {
                    Label("Restant : ~\(Self.format(remaining))", systemImage: "hourglass")
                } else {
                    Label("Restant : estimation…", systemImage: "hourglass")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            // Modèle utilisé
            Text("Modèle Whisper : \(coordinator.modelName)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button(role: .cancel) {
                coordinator.cancel()
            } label: {
                Text("Annuler")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var phaseTitle: String {
        switch coordinator.phase {
        case .preparing:    return "Extraction de l'audio…"
        case .transcribing: return "Transcription en cours…"
        case .exporting:    return "Écriture des fichiers…"
        default:            return "Traitement…"
        }
    }

    /// Formate une durée en « m:ss » (ou « h:mm:ss » au-delà d'une heure).
    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
