import AppKit
import Foundation

/// Genera AppIcon.icns desde el arte oficial de Findaro.
/// Prioridad: findaro-icon-source.(png|jpg|jpeg) → findaro-icon-master.png.
/// Ya no dibuja el icono de 3 barras (identidad antigua).

let outputDirectory = CommandLine.arguments.dropFirst().first ?? "Resources"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let candidates = [
    "findaro-icon-source.png",
    "findaro-icon-source.jpg",
    "findaro-icon-source.jpeg",
    "findaro-icon-master.png"
].map { outputURL.appendingPathComponent($0) }

guard let sourceURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
    fatalError("Falta arte de icono Findaro en \(outputDirectory) (findaro-icon-source.jpg/.png)")
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("No pude leer el icono fuente: \(sourceURL.path)")
}

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create bitmap context for Findaro icon")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .copy,
    fraction: 1.0
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let pngURL = outputURL.appendingPathComponent("findaro-icon-master.png")
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode Findaro icon PNG")
}
try png.write(to: pngURL)

let iconset = outputURL.appendingPathComponent("Findaro.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// También refresca AppIcon.iconset (caché vieja del Dock a veces mira ahí).
let legacyIconset = outputURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: legacyIconset)
try FileManager.default.createDirectory(at: legacyIconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, dimension) in variants {
    for setURL in [iconset, legacyIconset] {
        let destination = setURL.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-z", "\(dimension)", "\(dimension)", pngURL.path, "--out", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { fatalError("sips failed for \(name)") }
    }
}

let icnsURL = outputURL.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Findaro icon generated from \(sourceURL.lastPathComponent): \(icnsURL.path)")
