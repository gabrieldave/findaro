import AppKit
import Foundation

/// Empaqueta un PNG *ya aprobado* a AppIcon.icns.
/// No dibuja, no recorta, no recolorea y no llama a Python/Pillow.
/// Uso: swift scripts/generate-findaro-icon.swift Resources [png-aprobado.png]
/// Si no hay PNG aprobado y ya existe AppIcon.icns, no hace nada (conserva el arte).

let args = Array(CommandLine.arguments.dropFirst())
let outputDirectory = args.first ?? "Resources"
let approvedPNG = args.count > 1 ? args[1] : nil
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icnsURL = outputURL.appendingPathComponent("AppIcon.icns")
let fm = FileManager.default

guard let approvedPNG else {
    if fm.fileExists(atPath: icnsURL.path) {
        print("Conservado AppIcon.icns existente (sin regenerar arte): \(icnsURL.path)")
        exit(0)
    }
    fputs("ERROR: falta PNG aprobado y no hay AppIcon.icns.\n", stderr)
    fputs("Entrega el PNG de dirección y ejecuta:\n", stderr)
    fputs("  swift scripts/generate-findaro-icon.swift Resources /ruta/al/icono-aprobado.png\n", stderr)
    exit(1)
}

let pngURL = URL(fileURLWithPath: approvedPNG)
guard fm.fileExists(atPath: pngURL.path) else {
    fatalError("No existe el PNG aprobado: \(pngURL.path)")
}

// Solo reescala a tamaños macOS (iconutil) sin alterar el arte más allá del resize necesario.
let iconset = outputURL.appendingPathComponent("Findaro.iconset", isDirectory: true)
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, dimension) in variants {
    let destination = iconset.appendingPathComponent(name)
    let sips = Process()
    sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    sips.arguments = ["-z", "\(dimension)", "\(dimension)", pngURL.path, "--out", destination.path]
    try sips.run()
    sips.waitUntilExit()
    guard sips.terminationStatus == 0 else { fatalError("sips failed for \(name)") }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Findaro icon packaged from approved PNG: \(icnsURL.path)")
