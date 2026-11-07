import AppKit
import Foundation

let outputDirectory = CommandLine.arguments.dropFirst().first ?? "Resources"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

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

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let iconShape = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: 225, yRadius: 225)
NSGraphicsContext.saveGraphicsState()
iconShape.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.72, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.91, alpha: 1),
    NSColor(calibratedRed: 0.34, green: 0.28, blue: 0.78, alpha: 1)
])!
gradient.draw(in: bounds, angle: -35)
NSGraphicsContext.restoreGraphicsState()

iconShape.lineWidth = 10
NSColor.white.withAlphaComponent(0.24).setStroke()
iconShape.stroke()

let transform = NSAffineTransform()
transform.translateX(by: 512, yBy: 512)
transform.rotate(byDegrees: -8)
transform.translateX(by: -512, yBy: -512)
let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (286, 590, 410, 82),
    (286, 462, 338, 82),
    (286, 334, 270, 82)
]
NSGraphicsContext.saveGraphicsState()
transform.concat()
for (x, y, width, height) in bars {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: 41, yRadius: 41)
    NSColor.white.withAlphaComponent(y == 590 ? 1 : (y == 462 ? 0.86 : 0.70)).setFill()
    path.fill()
}
NSGraphicsContext.restoreGraphicsState()
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
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, dimension) in variants {
    let destination = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(dimension)", "\(dimension)", pngURL.path, "--out", destination.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("sips failed for \(name)") }
}
let icnsURL = outputURL.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Findaro icon generated: \(icnsURL.path)")
