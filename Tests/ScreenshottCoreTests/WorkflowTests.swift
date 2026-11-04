import CoreGraphics
import Foundation
import Testing
@testable import ScreenshottCore

private func manifest(_ json: String, files: Set<String> = ["run.sh", "icon.png"]) throws(WorkflowError) -> WorkflowManifest {
    try WorkflowManifest.load(Data(json.utf8)) { files.contains($0) }
}

private func problem(_ json: String, files: Set<String> = ["run.sh"]) -> WorkflowError? {
    do {
        _ = try manifest(json, files: files)
        return nil
    } catch {
        return error
    }
}

private func steps(_ steps: String) -> String {
    #"{"id": "com.example.test", "name": "Test", "steps": [\#(steps)]}"#
}

@Test func readsEveryStepType() throws {
    let m = try manifest("""
        {"format": 1, "id": "com.example.all", "name": " All Steps ", "version": "2.1", "author": "Me",
         "description": "Does everything.", "icon": "icon.png", "steps": [
            {"type": "script", "path": "run.sh", "args": ["--fast"], "timeout": 5},
            {"type": "shortcut", "name": "Resize"},
            {"type": "open-url", "url": "https://example.com/?f={filename}"},
            {"type": "action", "action": "copy"}
        ]}
        """)
    #expect(m.name == "All Steps")
    #expect(m.version == "2.1")
    #expect(m.summary == "Does everything.")
    #expect(m.steps == [
        .script(path: "run.sh", arguments: ["--fast"], timeout: 5),
        .shortcut(name: "Resize"),
        .openURL(template: "https://example.com/?f={filename}"),
        .action(.copyOnly),
    ])
    #expect(m.scripts == ["run.sh"])
}

@Test func fillsDefaults() throws {
    let m = try manifest(steps(#"{"type": "script", "path": "run.sh"}"#))
    #expect(m.format == 1)
    #expect(m.version == "1.0")
    #expect(m.steps == [.script(path: "run.sh", arguments: [], timeout: WorkflowManifest.defaultTimeout)])
}

@Test func rejectsWhatItCantRun() {
    #expect(problem("not json") == .unreadable("not valid JSON"))
    #expect(problem(#"{"id": 7}"#) == .unreadable("wrong type at id"))
    #expect(problem(#"{"format": 2, "id": "a", "name": "A", "steps": []}"#) == .unsupportedFormat(2))
    #expect(problem(#"{"name": "A"}"#) == .missing("id"))
    #expect(problem(#"{"id": "a", "name": "  "}"#) == .missing("name"))
    #expect(problem(#"{"id": "a", "name": "A", "steps": []}"#) == .noSteps)
    #expect(problem(steps(#"{"type": "teleport"}"#)) == .unknownStepType(step: 1, "teleport"))
    #expect(problem(steps(#"{"path": "run.sh"}"#)) == .missingStepField(step: 1, "type"))
    #expect(problem(steps(#"{"type": "shortcut"}"#)) == .missingStepField(step: 1, "name"))
    #expect(problem(steps(#"{"type": "action", "action": "standard"}"#)) == .unknownAction(step: 1, "standard"))
    #expect(problem(steps(#"{"type": "script", "path": "run.sh", "timeout": 0}"#)) == .timeoutOutOfRange(step: 1, 0))
}

@Test func stepNumbersCountFromOne() {
    #expect(problem(steps(#"{"type": "action", "action": "copy"}, {"type": "action", "action": "fly"}"#))
        == .unknownAction(step: 2, "fly"))
}

@Test func ids() {
    for good in ["com.example.upload", "a", "my_flow-2"] { #expect(WorkflowManifest.isValidID(good)) }
    for bad in ["", ".hidden", "../up", "a/b", "with space", "é", String(repeating: "a", count: 101)] {
        #expect(!WorkflowManifest.isValidID(bad))
    }
    #expect(problem(#"{"id": "../up", "name": "A", "steps": []}"#) == .invalidID("../up"))
}

@Test func scriptsStayInsideTheBundle() {
    for path in ["/bin/sh", "~/x.sh", "../x.sh", "a/../../x.sh", "a//b.sh", ""] {
        #expect(problem(steps(#"{"type": "script", "path": "\#(path)"}"#)) == .pathOutsideBundle(path))
    }
    #expect(problem(steps(#"{"type": "script", "path": "missing.sh"}"#)) == .fileMissing("missing.sh"))
    #expect(problem(#"{"id": "a", "name": "A", "icon": "icon.png", "steps": []}"#, files: []) == .fileMissing("icon.png"))
    #expect(WorkflowManifest.isSafeRelativePath("scripts/run.sh"))
}

@Test func urlStepsAreCheckedAtInstall() {
    #expect(problem(steps(#"{"type": "open-url", "url": "https://x.com/{nope}"}"#))
        == .badURL(step: 1, URLTemplate.Problem.unknownPlaceholder("nope").message))
    #expect(problem(steps(#"{"type": "open-url", "url": "https://x.com/{path"}"#))
        == .badURL(step: 1, URLTemplate.Problem.unclosedBrace.message))
    #expect(problem(steps(#"{"type": "open-url", "url": "no scheme"}"#))
        == .badURL(step: 1, URLTemplate.Problem.notAURL.message))
}

@Test func confirmationSaysWhatEachStepDoes() throws {
    let m = try manifest(steps("""
        {"type": "script", "path": "run.sh", "args": ["-v"]}, {"type": "shortcut", "name": "Resize"},
        {"type": "open-url", "url": "https://x.com/{filename}"}, {"type": "action", "action": "save"}
        """))
    #expect(m.steps.map(\.description) == [
        "Run the script “run.sh -v”", "Run the Shortcut “Resize”", "Open https://x.com/{filename}",
        "Save it to the screenshots folder",
    ])
}

@Test func templateValuesCantBreakOutOfTheURL() throws {
    let url = try URLTemplate.expand(
        "https://x.com/search?q={filename}&w={width}", values: ["filename": "a b&c=d?.png", "width": "10"]
    )
    #expect(url.absoluteString == "https://x.com/search?q=a%20b%26c%3Dd%3F.png&w=10")
    let file = try URLTemplate.expand("file://{path}", values: ["path": "/Users/me/My Shots/a.png"])
    #expect(file.path == "/Users/me/My Shots/a.png")
}

private let input = WorkflowInput(
    image: "/Users/me/Pictures/Screenshott/a b.png", width: 640, height: 480, scale: 2, preset: "captureArea",
    capturedAt: Date(timeIntervalSince1970: 1_793_000_000), workflow: "com.example.test", step: 2,
    outputDirectory: "/tmp/out"
)

@Test func inputGoesInAsEnvironment() {
    let env = input.environment
    #expect(env["SCREENSHOTT_IMAGE"] == "/Users/me/Pictures/Screenshott/a b.png")
    #expect(env["SCREENSHOTT_WIDTH"] == "640")
    #expect(env["SCREENSHOTT_SCALE"] == "2")
    #expect(env["SCREENSHOTT_PRESET"] == "captureArea")
    #expect(env["SCREENSHOTT_STEP"] == "2")
    #expect(env["SCREENSHOTT_OUTPUT_DIR"] == "/tmp/out")
    #expect(env["SCREENSHOTT_CAPTURED_AT"] == input.capturedAt)
    var menu = input
    menu.preset = nil
    #expect(menu.environment["SCREENSHOTT_PRESET"] == nil)
}

@Test func inputGoesInAsJSON() throws {
    let decoded = try JSONDecoder().decode(WorkflowInput.self, from: input.json)
    #expect(decoded == input)
    #expect(String(decoding: input.json, as: UTF8.self).contains(#""image":"/Users/me/Pictures/Screenshott/a b.png""#))
    #expect(input.templateValues["filename"] == "a b.png")
}

@Test func outputSaysWhatToDoNext() throws {
    #expect(try WorkflowOutput.parse(Data()) == WorkflowOutput())
    #expect(try WorkflowOutput.parse(Data(" \n".utf8)) == WorkflowOutput())
    let full = try WorkflowOutput.parse(Data("""
        {"clipboard": "https://x.com/1", "notify": "Uploaded", "open": "https://x.com/1", "image": "new.png"}
        """.utf8))
    #expect(full == WorkflowOutput(clipboard: "https://x.com/1", notify: "Uploaded", open: "https://x.com/1", image: "new.png"))
    let partial = try WorkflowOutput.parse(Data(#"{"notify": null, "clipbaord": "typo"}"#.utf8))
    #expect(partial.notify == nil)
    #expect(partial.ignored == ["clipbaord"])
}

@Test func outputMustBeOneObjectOfStrings() {
    #expect(throws: WorkflowOutput.Problem.notAnObject("uploading…")) { try WorkflowOutput.parse(Data("uploading…".utf8)) }
    #expect(throws: WorkflowOutput.Problem.notAnObject("[1]")) { try WorkflowOutput.parse(Data("[1]".utf8)) }
    #expect(throws: WorkflowOutput.Problem.notAString("open")) { try WorkflowOutput.parse(Data(#"{"open": 3}"#.utf8)) }
}

@Test func workflowsAreActionsToo() {
    #expect(CaptureAction(name: "workflow:com.example.up") == .workflow("com.example.up"))
    #expect(CaptureAction.workflow("com.example.up").name == "workflow:com.example.up")
    #expect(CaptureAction(name: "workflow:../up") == nil)
}

@Test func aRemovedWorkflowFallsBackToTheDefault() {
    let area = PresetID.captureArea.preset
    #expect(area.action(stored: "workflow:com.example.up", installedWorkflows: ["com.example.up"]) == .workflow("com.example.up"))
    #expect(area.action(stored: "workflow:com.example.up", installedWorkflows: []) == .standard)
}

@Test func theShippedExamplesInstall() throws {
    let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Examples/Workflows")
    let folders = try FileManager.default.contentsOfDirectory(
        at: examples, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
    ).filter(\.hasDirectoryPath)
    #expect(folders.count == 3)
    for folder in folders {
        let data = try Data(contentsOf: folder.appendingPathComponent(WorkflowManifest.fileName))
        let m = try WorkflowManifest.load(data) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        #expect(m.id.hasPrefix("com.screenshott.example."))
        for script in m.scripts {
            #expect(FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent(script).path))
        }
    }
}

// MARK: - Action bar

@Test func barSitsBelowTheSelectionRightAligned() {
    let frame = ActionBarLayout.frame(
        size: CGSize(width: 300, height: 30), below: CGRect(x: 400, y: 300, width: 500, height: 200),
        in: CGSize(width: 1512, height: 982)
    )
    #expect(frame == CGRect(x: 600, y: 262, width: 300, height: 30))
}

@Test func barGoesAboveWhenTheSelectionTouchesTheBottom() {
    let frame = ActionBarLayout.frame(
        size: CGSize(width: 300, height: 30), below: CGRect(x: 100, y: 10, width: 200, height: 200),
        in: CGSize(width: 1512, height: 982)
    )
    // Right-aligned would start left of the screen, so it stops at the edge.
    #expect(frame == CGRect(x: 0, y: 218, width: 300, height: 30))
}

@Test func barGoesInsideAFullScreenSelection() {
    let frame = ActionBarLayout.frame(
        size: CGSize(width: 300, height: 30), below: CGRect(x: 0, y: 0, width: 1512, height: 982),
        in: CGSize(width: 1512, height: 982)
    )
    #expect(frame == CGRect(x: 1212, y: 8, width: 300, height: 30))
}

@Test func barItemsLineUp() {
    let items = ActionBarLayout.items(widths: [50, 70], height: 30)
    #expect(items == [CGRect(x: 4, y: 4, width: 50, height: 22), CGRect(x: 56, y: 4, width: 70, height: 22)])
    #expect(ActionBarLayout.width(of: [50, 70]) == 130)
}
