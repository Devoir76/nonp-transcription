// NONPTranscriptionApp.swift — point d'entrée de l'application.
//
// C'est ici que démarre l'app. On utilise le cycle de vie SwiftUI moderne
// (@main + App). Une seule fenêtre, non redimensionnable au-delà du contenu,
// pour rester fidèle à l'esprit « très sobre » du cahier des charges.

import SwiftUI

@main
struct NONPTranscriptionApp: App {

    init() {
        // Mode test headless (--selftest …) : exécute le pipeline et quitte.
        // Sans effet en usage normal.
        SelfTest.maybeRun()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // La fenêtre s'ajuste à la taille du contenu (design épuré, une seule fenêtre).
        .windowResizability(.contentSize)
        // On retire l'onglet « Nouvelle fenêtre » : l'app n'a qu'une fenêtre.
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
