import AppKit
import Carbon.HIToolbox
import ScreenshottCore
import SwiftUI

/// A shortcut well: click it, type a combo. Esc cancels, Delete clears. AppKit because
/// a recorder needs the virtual key code, which SwiftUI's key events don't carry.
final class ShortcutField: NSView {
    var shortcut: Shortcut? { didSet { update() } }
    /// Called with the new shortcut (nil = cleared) when recording ends with one.
    var onRecord: ((Shortcut?) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var recording = false {
        didSet {
            // Our own hotkeys would swallow the very combo being typed.
            if recording { HotKeys.pause() } else { HotKeys.resume() }
            update()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if recording {
            recording = false
        } else {
            window?.makeFirstResponder(self)
            recording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        if recording { recording = false }
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, recording { recording = false }
        super.viewWillMove(toWindow: newWindow)
    }

    // ⌘ combos arrive here before keyDown, and the window would act on some of them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let modifiers = Shortcut.carbonModifiers(fromCocoa: event.modifierFlags.rawValue)
        switch Int(event.keyCode) {
        case kVK_Escape where modifiers == 0:
            recording = false
        case kVK_Delete where modifiers == 0, kVK_ForwardDelete where modifiers == 0:
            finish(with: nil)
        default:
            let typed = event.characters(byApplyingModifiers: [])?.uppercased() ?? "?"
            let key = Shortcut.label(forKeyCode: UInt32(event.keyCode)) ?? typed
            finish(with: Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key))
        }
    }

    private func finish(with shortcut: Shortcut?) {
        // Resume the old hotkeys before the new one is bound, so its status is real.
        recording = false
        onRecord?(shortcut)
    }

    private func update() {
        if recording {
            label.stringValue = "Type shortcut…"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = shortcut?.displayString ?? "Record Shortcut"
            label.textColor = shortcut == nil ? .secondaryLabelColor : .labelColor
        }
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = recording ? 2 : 1
    }

    override var wantsUpdateLayer: Bool { true }
}

/// SwiftUI wrapper; `onRecord` gets the typed shortcut, nil when cleared.
struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: Shortcut?
    var onRecord: (Shortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutField {
        let field = ShortcutField()
        field.shortcut = shortcut
        field.onRecord = onRecord
        return field
    }

    func updateNSView(_ field: ShortcutField, context: Context) {
        field.shortcut = shortcut
        field.onRecord = onRecord
    }
}
