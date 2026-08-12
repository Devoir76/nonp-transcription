// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
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

            Section("Formats de sortie") {
                ForEach(OutputFormat.allCases) { format in
                    Toggle(format.displayName, isOn: binding(for: format))
                        // Verrou visible : le dernier format coché n'est pas décochable.
                        .disabled(isOnlySelected(format))
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

    /// Vrai si `format` est le SEUL format actuellement coché (donc verrouillé).
    private func isOnlySelected(_ format: OutputFormat) -> Bool {
        preferences.selectedFormats == [format]
    }

    /// Liaison à cocher/décocher un format, avec garde-fou : on refuse de décocher
    /// le DERNIER format actif (au moins un toujours coché), sans re-cocher
    /// silencieusement un autre format à sa place.
    private func binding(for format: OutputFormat) -> Binding<Bool> {
        Binding(
            get: { preferences.selectedFormats.contains(format) },
            set: { isOn in
                var next = preferences.selectedFormats
                if isOn {
                    next.insert(format)
                } else {
                    guard next.count > 1 else { return }   // dernier format : verrou
                    next.remove(format)
                }
                preferences.selectedFormats = next
            }
        )
    }

    /// Libellé du dossier fixe (chemin choisi, ou invite).
    private var folderLabel: String {
        if let url = preferences.customFolderURL {
            return url.path
        }
        return "Aucun dossier choisi"
    }
}
