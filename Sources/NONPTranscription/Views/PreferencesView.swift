// PreferencesView.swift — fenêtre Réglages (menu « Réglages… », ⌘,).
//
// Permet de choisir le dossier de sortie (à côté de la vidéo, ou un dossier
// fixe mémorisé) et d'activer/désactiver l'ouverture automatique du dossier
// en fin de transcription. Les réglages sont persistés par Preferences.

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section("Dossier de sortie") {
                Picker("Enregistrer les fichiers", selection: $preferences.outputMode) {
                    Text("À côté de la vidéo").tag(Preferences.OutputMode.sourceFolder)
                    Text("Dans un dossier fixe").tag(Preferences.OutputMode.customFolder)
                }
                .pickerStyle(.radioGroup)

                // Détails du dossier fixe (visible surtout en mode « dossier fixe »).
                if preferences.outputMode == .customFolder {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(folderLabel)
                            .font(.callout)
                            .foregroundStyle(preferences.customFolderURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choisir…") { preferences.chooseCustomFolder() }
                    }

                    // Avertissement si le dossier choisi n'est plus accessible.
                    if preferences.customFolderURL != nil && !preferences.customFolderIsUsable {
                        Label("Dossier introuvable — les fichiers seront enregistrés à côté de la vidéo.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Toggle("Ouvrir le dossier à la fin de la transcription",
                       isOn: $preferences.openFolderWhenDone)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Libellé du dossier fixe (chemin choisi, ou invite).
    private var folderLabel: String {
        if let url = preferences.customFolderURL {
            return url.path
        }
        return "Aucun dossier choisi"
    }
}
