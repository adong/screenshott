import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey — the one global-hotkey
/// API that needs no Accessibility permission. M2 replaces the fixed combos with
/// user-recorded ones.
@MainActor
enum HotKeys {
    private static let signature: OSType = 0x5353_4854  // 'SSHT'
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef] = []
    private static var handlerInstalled = false

    /// Returns the Carbon status. `eventHotKeyExistsErr` (-9878) means another app
    /// already owns the combo — Shottr ships with ⌘⇧1 / ⌘⇧2.
    @discardableResult
    static func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> OSStatus {
        installHandlerIfNeeded()
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            actions[id] = action
            refs.append(ref)
        }
        return status
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            // Handlers on the application target run on the main thread.
            MainActor.assumeIsolated { HotKeys.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private static func fire(_ id: UInt32) {
        actions[id]?()
    }
}
