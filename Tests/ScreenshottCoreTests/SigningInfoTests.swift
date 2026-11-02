import Testing
@testable import ScreenshottCore

// The test runner is linker-signed (ad-hoc), so it has a real CDHash to read.
@Test func cdhashPrefixIsEightHexDigits() {
    let prefix = SigningInfo.cdhashPrefix
    #expect(prefix.count == 8)
    #expect(prefix.allSatisfy { $0.isHexDigit })
}
