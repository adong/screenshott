import CoreGraphics
import Foundation
import Testing
@testable import ScreenshottCore

private func temporaryStore() throws -> ProjectStore {
    // $TMPDIR first, for runs where the system temporary folder isn't writable.
    let temporary = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.temporaryDirectory
    let root = temporary.appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return ProjectStore(root: root)
}

private let pngName = "Screenshott 2026-11-02 at 09.41.27.png"

@Test func projectFolderIsNamedAfterThePNG() throws {
    let store = try temporaryStore()
    #expect(store.folder(forPNGNamed: pngName).lastPathComponent == "Screenshott 2026-11-02 at 09.41.27")
}

@Test func savedProjectLoadsBackWithItsOriginals() throws {
    let store = try temporaryStore()
    let id = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 4, height: 2), scale: 2, imageID: id)
    doc.add(Annotation(kind: .pixelate, start: .zero, end: CGPoint(x: 2, y: 2), size: 0, cover: .solid))
    let png = try #require(PNGEncoder.data(from: patternImage(width: 4, height: 2), scale: 2))
    try store.save(doc, forPNGNamed: pngName) { $0 == id ? png : nil }

    let project = try #require(try store.load(forPNGNamed: pngName))
    #expect(project.document == doc)
    let original = try #require(project.originals[id])
    #expect(try Data(contentsOf: original) == png)
}

@Test func originalsAreWrittenOnceAndDroppedWhenTheirCaptureLeaves() throws {
    let store = try temporaryStore()
    let first = UUID(), second = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 4, height: 2), scale: 1, imageID: first)
    doc.images.append(CanvasImage(id: second, pixelSize: PixelSize(width: 4, height: 2), origin: PixelPoint(x: 0, y: 2)))
    let png = PNGEncoder.data(from: patternImage(width: 4, height: 2), scale: 1)!
    var asked: [UUID] = []
    try store.save(doc, forPNGNamed: pngName) { asked.append($0); return png }
    try store.save(doc, forPNGNamed: pngName) { asked.append($0); return png }
    #expect(Set(asked) == [first, second])
    #expect(asked.count == 2)

    doc.images.removeLast()
    try store.save(doc, forPNGNamed: pngName) { _ in png }
    let files = try FileManager.default.contentsOfDirectory(atPath: store.folder(forPNGNamed: pngName).path)
    #expect(Set(files) == ["project.json", "\(first.uuidString).png"])
}

@Test func savingFailsWithoutAnOriginalToWrite() throws {
    let store = try temporaryStore()
    let doc = EditorDocument(imageSize: PixelSize(width: 4, height: 2), scale: 1)
    #expect(throws: ProjectStore.Failure.self) { try store.save(doc, forPNGNamed: pngName) { _ in nil } }
}

@Test func aPNGThatWasNeverEditedHasNoProject() throws {
    #expect(try temporaryStore().load(forPNGNamed: pngName) == nil)
}

@Test func aProjectFromANewerBuildIsRefused() throws {
    let store = try temporaryStore()
    var doc = EditorDocument(imageSize: PixelSize(width: 4, height: 2), scale: 1)
    doc.version = EditorDocument.formatVersion + 1
    let png = PNGEncoder.data(from: patternImage(width: 4, height: 2), scale: 1)!
    try store.save(doc, forPNGNamed: pngName) { _ in png }
    #expect(throws: ProjectStore.Failure.newerFormat(doc.version)) { try store.load(forPNGNamed: pngName) }
}

@Test func imageFileReadsScaleFromDPI() throws {
    let image = patternImage(width: 6, height: 4)
    let retinaPNG = try #require(PNGEncoder.data(from: image, scale: 2))
    let retina = try #require(ImageFile.load(retinaPNG))
    #expect(retina.scale == 2)
    #expect(retina.image.width == 6)
    let plainPNG = try #require(PNGEncoder.data(from: image, scale: 1))
    let plain = try #require(ImageFile.load(plainPNG))
    #expect(plain.scale == 1)
}
