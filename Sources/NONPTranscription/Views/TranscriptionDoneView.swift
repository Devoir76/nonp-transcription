// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// TranscriptionDoneView.swift — écran de fin « Transcription terminée ».
//
// Affiche la confirmation, les deux fichiers créés, et propose d'ouvrir le
// dossier ou de traiter un nouveau fichier.

import SwiftUI

struct TranscriptionDoneView: View {
    let directory: URL
    let outputs: [ExportedOutput]
    let onNewFile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.green)

            Text("Transcription terminée")
                .font(.title3.weight(.semibold))

            // Rappel des fichiers produits (un par format choisi)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(outputs, id: \.url) { out in
                    Label(out.url.lastPathComponent, systemImage: out.format.icon)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            HStack(spacing: 12) {
                Button {
                    // Ré-ouvre le dossier avec les fichiers sélectionnés.
                    NSWorkspace.shared.activateFileViewerSelecting(outputs.urls)
                } label: {
                    Label("Ouvrir le dossier", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onNewFile()
                } label: {
                    Text("Nouveau fichier")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
