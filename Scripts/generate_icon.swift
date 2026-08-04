#!/usr/bin/env swift
// generate_icon.swift — NEUTRALISÉ (script historique, conservé pour mémoire).
//
// Il générait l'icône de la V1.0 à la V1.2 : un carré arrondi bleu-ardoise
// avec une forme d'onde blanche, dessinés par code. Depuis la V1.2.1, l'icône
// est un jeu de fichiers versionné dans Resources/AppIcon.iconset ; ce script
// l'écraserait s'il était relancé. Il refuse donc de s'exécuter.
//
// Pour régénérer l'icône du bundle après modification de l'iconset :
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
//
// Le code de dessin est laissé intact en dessous : il documente l'icône
// d'origine et resterait le point de départ d'une icône générée.

import AppKit
import Foundation

// Garde-fou : placé AVANT toute écriture (la première, plus bas, est la
// création de Resources/AppIcon.iconset).
FileHandle.standardError.write(Data("""
    generate_icon.swift est neutralisé : il écraserait l'icône du produit.
    L'icône vit désormais dans Resources/AppIcon.iconset (fichiers versionnés).
    Pour reconstruire Resources/AppIcon.icns à partir de cet iconset :
      iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

    """.utf8))
exit(1)

// Dossier de sortie (par défaut : Resources).
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let iconsetDir = (outputDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

/// Dessine l'icône à la taille demandée et renvoie les données PNG.
func renderIcon(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Fond transparent.
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // Carré arrondi (marge = zone de sécurité recommandée par Apple).
    let margin = s * 0.08
    let rect = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = rect.width * 0.2237   // rayon « continu » proche du style macOS
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Dégradé discret bleu-ardoise.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.38, alpha: 1),
        ending:   NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.22, alpha: 1)
    )!
    gradient.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Forme d'onde : 5 barres blanches arrondies, hauteurs symétriques.
    let heights: [CGFloat] = [0.34, 0.60, 0.86, 0.60, 0.40]
    let barColor = NSColor(calibratedWhite: 0.97, alpha: 1.0)
    barColor.set()

    let zoneWidth = rect.width * 0.56
    let zoneX = rect.midX - zoneWidth / 2
    let slot = zoneWidth / CGFloat(heights.count)
    let barWidth = slot * 0.46

    for (i, hFactor) in heights.enumerated() {
        let barHeight = hFactor * rect.height * 0.66
        let x = zoneX + CGFloat(i) * slot + (slot - barWidth) / 2
        let y = rect.midY - barHeight / 2
        let bar = NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        )
        bar.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Fichiers requis par un .iconset (nom → taille en pixels).
let variants: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),      ("[email protected]", 32),
    ("icon_32x32.png", 32),      ("[email protected]", 64),
    ("icon_128x128.png", 128),   ("[email protected]", 256),
    ("icon_256x256.png", 256),   ("[email protected]", 512),
    ("icon_512x512.png", 512),   ("[email protected]", 1024),
]

for v in variants {
    let data = renderIcon(pixels: v.px)
    let path = (iconsetDir as NSString).appendingPathComponent(v.name)
    try! data.write(to: URL(fileURLWithPath: path))
}

print("Iconset généré : \(iconsetDir)")
