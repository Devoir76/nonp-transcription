// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// NONPTranscriptionApp.swift — point d'entrée de l'application.
//
// C'est ici que démarre l'app. On utilise le cycle de vie SwiftUI moderne
// (@main + App). Une seule fenêtre, non redimensionnable au-delà du contenu,
// pour rester fidèle à l'esprit « très sobre » du cahier des charges.

import SwiftUI

@main
struct NONPTranscriptionApp: App {

    // Réglages partagés entre la fenêtre principale et la fenêtre Réglages.
    @StateObject private var preferences = Preferences()

    init() {
        // Mode test headless (--selftest …) : exécute le pipeline et quitte.
        // Sans effet en usage normal.
        SelfTest.maybeRun()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
        }
        // La fenêtre s'ajuste à la taille du contenu (design épuré, une seule fenêtre).
        .windowResizability(.contentSize)
        // On retire l'onglet « Nouvelle fenêtre » : l'app n'a qu'une fenêtre.
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Fenêtre Réglages : ajoute automatiquement l'entrée de menu
        // « Réglages… » (⌘,) dans le menu de l'application.
        Settings {
            PreferencesView()
                .environmentObject(preferences)
        }
    }
}
