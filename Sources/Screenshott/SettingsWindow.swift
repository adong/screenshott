import AppKit
import ScreenshottCore
import ServiceManagement
import SwiftUI

/// Settings: presets and their shortcuts, where captures go, what happens after a
/// capture, installed workflows. SwiftUI for
/// this cold UI (decision 8), hosted in a plain window because the app runs on the
/// AppKit lifecycle.
@MainActor
final class SettingsWindowController: NSWindowController {
    private(set) var model: SettingsModel!

    convenience init(preferences: Preferences, shortcuts: ShortcutCenter, presets: PresetSettings, workflows: WorkflowStore) {
        let model = SettingsModel(shortcuts: shortcuts)
        let hosting = NSHostingController(rootView: SettingsView(
            preferences: preferences, shortcuts: shortcuts, presets: presets, workflows: workflows, model: model
        ))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "Screenshott Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        self.model = model
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
    enum Tab: Hashable { case presets, general, workflows }

    @Published var tab = Tab.presets
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
    @ObservedObject var presets: PresetSettings
    @ObservedObject var workflows: WorkflowStore
    @ObservedObject var model: SettingsModel

    var body: some View {
        // Tabs, because seven presets and the rest don't fit a laptop screen in one form.
        TabView(selection: $model.tab) {
            presetsTab.tabItem { Text("Presets") }.tag(SettingsModel.Tab.presets)
            generalTab.tabItem { Text("General") }.tag(SettingsModel.Tab.general)
            workflowsTab.tabItem { Text("Workflows") }.tag(SettingsModel.Tab.workflows)
        }
        .padding(.top, 6)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var presetsTab: some View {
        Form {
            Section {
                ForEach(PresetID.allCases) { id in
                    presetRow(id)
                }
            } footer: {
                Text("""
                    Each shortcut runs a preset. Click a shortcut, then type the new one; Delete clears it, \
                    Esc cancels. In the overlay, Enter runs the preset’s action; ⌘C copies only, ⌘S saves as, \
                    E opens the editor.
                    """)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var workflowsTab: some View {
        Form {
            Section {
                if workflows.installed.isEmpty {
                    Text("No workflows yet.").foregroundStyle(.secondary)
                }
                ForEach(workflows.installed) { workflow in
                    workflowRow(workflow)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Install…") { workflows.chooseAndInstall() }
                        Button("Open Folder") { workflows.openFolder() }
                    }
                    Text("""
                        A workflow runs after a capture: scripts, Apple Shortcuts, URLs and built-in actions. \
                        Double-click a .screenshottworkflow file to install one. Run it from the overlay’s action \
                        bar (1–9), a thumbnail’s menu or the menu bar, or make it a preset’s Then.
                        """)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func workflowRow(_ workflow: InstalledWorkflow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = workflow.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "bolt.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workflow.name)
                    Text(workflow.manifest.version).font(.caption).foregroundStyle(.secondary)
                }
                if let summary = workflow.manifest.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Text(workflow.manifest.steps.map(\.description).joined(separator: " → "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([workflow.folder])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            Button {
                workflows.remove(workflow)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move to Trash")
        }
    }

    private var generalTab: some View {
        Form {
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
    }

    /// A plain HStack: LabeledContent drops the AppKit well below its label, since the
    /// well has no text baseline to line up with. Under it, what the preset does next.
    private func presetRow(_ action: PresetID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            shortcutRow(action)
            HStack(spacing: 8) {
                Text("Then").foregroundStyle(.secondary)
                if action.preset.hasConfigurableAction {
                    Picker("Then", selection: Binding(
                        get: { presets.action(for: action) }, set: { presets.setAction($0, for: action) }
                    )) {
                        ForEach(CaptureAction.presetChoices, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                        if !workflows.installed.isEmpty {
                            Divider()
                            ForEach(workflows.installed) { workflow in
                                Text(workflow.name).tag(CaptureAction.workflow(workflow.id))
                            }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text("Stitch, then show the thumbnail").foregroundStyle(.secondary)
                }
                if action.preset.delay > 0 {
                    Picker("Countdown", selection: Binding(
                        get: { presets.delay(for: action) }, set: { presets.setDelay($0, for: action) }
                    )) {
                        ForEach(Preset.delayChoices, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .font(.callout)
        }
    }

    private func shortcutRow(_ action: PresetID) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                Text(action.preset.summary).font(.caption).foregroundStyle(.secondary)
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
            .help(action.defaultShortcut.map { "Reset to \($0.displayString)" } ?? "Reset to no shortcut")
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
