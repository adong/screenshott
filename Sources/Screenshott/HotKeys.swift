import Carbon.HIToolbox
import ScreenshottCore

/// System-wide shortcuts through Carbon's RegisterEventHotKey — the one global-hotkey
/// API that needs no Accessibility permission. Each slot can be rebound at any time.
@MainActor
enum HotKeys {
    private static let signature: OSType = 0x5353_4854  // 'SSHT'
    private static var actions: [UInt32: () -> Void] = [:]
    private static var bound: [UInt32: Shortcut] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var handlerInstalled = false
    private static var paused = false

    /// Binds slot `id` to `shortcut`, replacing what it had; nil just unbinds. Returns
    /// the Carbon status — `eventHotKeyExistsErr` (-9878) means another app owns it.
    @discardableResult
    static func bind(_ id: UInt32, to shortcut: Shortcut?, action: @escaping () -> Void) -> OSStatus {
        installHandlerIfNeeded()
        unregister(id)
        actions[id] = action
        bound[id] = shortcut
        guard let shortcut, !paused else { return noErr }
        return register(id, shortcut)
    }

    /// While Settings records a new shortcut the current ones must stay quiet, or
    /// pressing one would take a screenshot instead of being recorded.
    static func pause() {
        guard !paused else { return }
        paused = true
        for id in Array(refs.keys) { unregister(id) }
    }

    static func resume() {
        guard paused else { return }
        paused = false
        for (id, shortcut) in bound { register(id, shortcut) }
    }

    @discardableResult
    private static func register(_ id: UInt32, _ shortcut: Shortcut) -> OSStatus {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref { refs[id] = ref }
        return status
    }

    private static func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
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
