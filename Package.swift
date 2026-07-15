// swift-tools-version: 5.9
// Package.swift — description du projet pour Swift Package Manager.
// On construit une application macOS SwiftUI sans avoir besoin d'Xcode complet :
// SwiftPM compile un exécutable, puis notre script Scripts/build_app.sh
// l'assemble en un véritable bundle .app lançable.

import PackageDescription

let package = Package(
    name: "NONPTranscription",
    // macOS 14 minimum (API onChange moderne). Votre Mac est en macOS 26.
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Cible exécutable = le binaire de l'application.
        .executableTarget(
            name: "NONPTranscription",
            path: "Sources/NONPTranscription"
        )
    ]
)
