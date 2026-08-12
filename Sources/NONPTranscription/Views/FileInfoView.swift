// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// FileInfoView.swift — carte d'information sur le fichier sélectionné.
//
// Remplace la zone de dépôt une fois un fichier choisi. Affiche le nom, la
// durée et la taille (cahier des charges), avec un bouton pour retirer le
// fichier et en déposer un autre.

import SwiftUI

struct FileInfoView: View {
    let file: MediaFile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Label(file.formattedDuration, systemImage: "clock")
                    Text("·").foregroundStyle(.tertiary)
                    Label(file.formattedSize, systemImage: "internaldrive")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Retirer le fichier")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    /// Icône selon que le fichier est plutôt audio ou vidéo.
    private var icon: String {
        switch file.fileExtension {
        case "mp3", "wav", "m4a": return "waveform"
        default:                  return "film"
        }
    }
}
