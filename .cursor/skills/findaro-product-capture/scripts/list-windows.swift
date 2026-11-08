import Foundation
import CoreGraphics

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
    fputs("No fue posible consultar la lista de ventanas.\n", stderr)
    exit(1)
}
var found = 0
for window in windows {
    let owner = (window[kCGWindowOwnerName as String] as? String ?? "")
    guard owner.localizedCaseInsensitiveContains("findaro") || owner == "Orden" else { continue }
    let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
    guard layer == 0 else { continue }
    let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
    let title = (window[kCGWindowName as String] as? String ?? "").replacingOccurrences(of: "\t", with: " ")
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = (bounds["Width"] as? NSNumber)?.intValue ?? 0
    let height = (bounds["Height"] as? NSNumber)?.intValue ?? 0
    guard width >= 320 && height >= 260 else { continue }
    print("\(id)\t\(owner)\t\(width)x\(height)\t\(title)")
    found += 1
}
if found == 0 {
    fputs("No hay ventanas visibles de FINDARO. Abre la aplicación y repite la prueba.\n", stderr)
    exit(2)
}
