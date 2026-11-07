import AppKit
import Foundation

/// Genera AppIcon.icns desde el master PNG de producción.
/// Primero ejecuta process-findaro-icon.py (quita marco blanco y hace full-bleed).

let outputDirectory = CommandLine.arguments.dropFirst().first ?? "Resources"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

// 1) Procesar arte: sin marco blanco, canvas lleno.
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let processScript = cwd.appendingPathComponent("scripts/process-findaro-icon.py")
guard FileManager.default.fileExists(atPath: processScript.path) else {
    fatalError("No está \(processScript.path) — corre desde la raíz del repo")
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["python3", processScript.path, outputDirectory]
process.currentDirectoryURL = cwd
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("process-findaro-icon.py failed — no se generó master limpio")
}

let pngURL = outputURL.appendingPathComponent("findaro-icon-master.png")
guard FileManager.default.fileExists(atPath: pngURL.path) else {
    fatalError("Falta findaro-icon-master.png tras el procesado")
}

let iconset = outputURL.appendingPathComponent("Findaro.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

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
        let sips = Process()
        sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        sips.arguments = ["-z", "\(dimension)", "\(dimension)", pngURL.path, "--out", destination.path]
        try sips.run()
        sips.waitUntilExit()
        guard sips.terminationStatus == 0 else { fatalError("sips failed for \(name)") }
    }
}

let icnsURL = outputURL.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Findaro production icon: \(icnsURL.path)")
