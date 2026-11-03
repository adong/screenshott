import AppKit
import ScreenshottCore
import ServiceManagement
import SwiftUI

/// Settings: shortcuts, where captures go, what happens after a capture. SwiftUI for
/// this cold UI (decision 8), hosted in a plain window because the app runs on the
/// AppKit lifecycle.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(preferences: Preferences, shortcuts: ShortcutCenter) {
        let hosting = NSHostingController(rootView: SettingsView(
            preferences: preferences, shortcuts: shortcuts, model: SettingsModel(shortcuts: shortcuts)
        ))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "Screenshott Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        // An accessory app has to come forward itself, or the window opens behind.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The view's own state. An ObservableObject rather than @State: in this SDK @State is
/// a macro whose plugin ships only with Xcode, and we build with the Command Line Tools.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var problems: [ShortcutCenter.Action: String] = [:]
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginItemNote: String?
    private let shortcuts: ShortcutCenter

    init(shortcuts: ShortcutCenter) {
        self.shortcuts = shortcuts
    }

    func set(_ shortcut: Shortcut?, for action: ShortcutCenter.Action) {
        problems[action] = shortcuts.set(shortcut, for: action)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemNote = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Screenshott in System Settings → General → Login Items." : nil
        } catch {
            loginItemNote = error.localizedDescription
            Log.write("launch at login \(on): \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var shortcuts: ShortcutCenter
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutCenter.Action.allCases) { action in
                    shortcutRow(action)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a shortcut, then type the new one. Delete clears it, Esc cancels.")
                    .foregroundStyle(.secondary)
            }

            Section("Saving") {
                LabeledContent("Save to") {
                    HStack(spacing: 6) {
                        Text((preferences.saveDirectory.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                        Button {
                            try? FileManager.default.createDirectory(
                                at: preferences.saveDirectory, withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(preferences.saveDirectory)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Open in Finder")
                    }
                }
                Toggle(isOn: $preferences.keepRetinaResolution) {
                    Text("Keep full Retina resolution")
                    Text("Off saves captures from 2x screens at their 1x size.")
                }
            }

            Section("After Capture") {
                Toggle("Copy to clipboard", isOn: $preferences.copyToClipboard)
                Toggle("Show thumbnail", isOn: $preferences.showThumbnail)
                Toggle("Play sound", isOn: $preferences.playSound)
            }

            Section("General") {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Launch at login")
                    if let note = model.loginItemNote { Text(note) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A plain HStack: LabeledContent drops the AppKit well below its label, since the
    /// well has no text baseline to line up with.
    private func shortcutRow(_ action: ShortcutCenter.Action) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let problem = model.problems[action] {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else if shortcuts.taken.contains(action), let shortcut = shortcuts.shortcuts[action] {
                    Text("\(shortcut.displayString) is taken by another app (Shottr?).")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            ShortcutRecorder(shortcut: shortcuts.shortcuts[action]) { model.set($0, for: action) }
                .frame(width: 150, height: 24)
            Button {
                model.set(action.defaultShortcut, for: action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to \(action.defaultShortcut.displayString)")
            .disabled(shortcuts.shortcuts[action] == action.defaultShortcut)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.saveDirectory
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveDirectory = url
            Log.write("save directory = \(url.path)")
        }
    }
}
