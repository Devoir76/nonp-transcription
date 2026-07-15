// DropZoneView.swift — grande zone « Déposez votre vidéo ici ».
//
// Affichée tant qu'aucun fichier n'est sélectionné. Gère le retour visuel
// pendant le survol d'un fichier et propose un bouton « Parcourir… » comme
// alternative au glisser-déposer. Le traitement réel du fichier est délégué
// à AppState (cette vue ne fait que de l'affichage + relais d'actions).

import SwiftUI

struct DropZoneView: View {
    /// Vrai quand un fichier est en cours de lecture (affiche un indicateur).
    let isLoading: Bool
    /// Vrai quand un fichier est survolé au-dessus de la zone (retour visuel).
    let isTargeted: Bool
    /// Action déclenchée par le bouton « Parcourir… ».
    let onBrowse: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
                )

            VStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                    Text("Lecture du fichier…")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                    Text("Déposez votre vidéo ici")
                        .font(.headline)

                    Text("MP4 · MOV · AVI · MKV · MP3 · WAV · M4A")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Parcourir…", action: onBrowse)
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .frame(height: 200)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}
