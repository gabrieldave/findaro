import AppKit
import Carbon
import OrdenCore

/// Atajo global (por defecto ⌃⌥O) → trae Findaro al frente en la carpeta configurada.
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

        let chord = resolvedChord()
        RegisterEventHotKey(
            UInt32(chord.keyCode),
            carbonModifiers(chord),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    /// Vuelve a registrar el atajo tras cambiar preferencias.
    static func reload() {
        install()
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

    static func resolvedChord() -> KeyChord {
        let overrides = PreferencesStore().preferences.keyboardHotkeyOverrides
        return AppHotkeyCatalog.resolvedChord(id: "nav.globalOpen", overrides: overrides)
            ?? KeyChord(keyCode: 31, character: "o", option: true, control: true)
    }

    private static func carbonModifiers(_ chord: KeyChord) -> UInt32 {
        var mods: UInt32 = 0
        if chord.control { mods |= UInt32(controlKey) }
        if chord.option { mods |= UInt32(optionKey) }
        if chord.shift { mods |= UInt32(shiftKey) }
        if chord.command { mods |= UInt32(cmdKey) }
        return mods
    }

    /// Carpeta del atajo global: preferencia del usuario o Descargas.
    static func resolvedFolderPath() -> String {
        let store = PreferencesStore()
        if let custom = store.preferences.globalHotkeyFolderPath,
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return (custom as NSString).standardizingPath
        }
        return defaultDownloadsPath()
    }

    static func defaultDownloadsPath() -> String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSString(string: "~/Downloads").expandingTildeInPath
    }
}
