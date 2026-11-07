import AppKit
import Carbon
import OrdenCore

/// Atajo global ⌃⌥O → trae Findaro al frente en la carpeta configurada (por defecto Descargas).
/// Funciona mientras Findaro esté abierta (ponla en «Abrir al iniciar sesión»).
@MainActor
enum GlobalHotKey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x4F52444E), id: 1) // 'ORDN'

    nonisolated private static let eventHandler: EventHandlerUPP = { _, event, _ in
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &id
        )
        guard status == noErr, id.signature == OSType(0x4F52444E), id.id == 1 else {
            return noErr
        }
        DispatchQueue.main.async {
            Task { @MainActor in
                GlobalHotKey.activateOrdena()
            }
        }
        return noErr
    }

    static func install() {
        uninstall()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            eventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        // ⌃⌥O
        RegisterEventHotKey(
            UInt32(kVK_ANSI_O),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    static func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    static func activateOrdena() {
        AppDelegate.showMainWindows()
        NotificationCenter.default.post(name: .ordenaOpenFolder, object: resolvedFolderPath())
    }

    /// Carpeta del atajo global: preferencia del usuario o Descargas.
    static func resolvedFolderPath() -> String {
        let store = PreferencesStore()
        if let custom = store.preferences.globalHotkeyFolderPath,
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return (custom as NSString).standardizingPath
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSString(string: "~/Downloads").expandingTildeInPath
    }

    static func defaultDownloadsPath() -> String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSString(string: "~/Downloads").expandingTildeInPath
    }
}
