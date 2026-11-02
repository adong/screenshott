import Foundation
import Security

public enum SigningInfo {
    /// First 8 hex digits of this process's CDHash. An ad-hoc signed app's TCC grants
    /// are keyed to this hash, so logging it at launch shows whether a rebuild really
    /// produced new code — a cached `swift build` re-signs identical bytes.
    public static var cdhashPrefix: String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else { return "unsigned" }
        return unique.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// "0.1.0 (1)" from the bundle's Info.plist, or "dev" under `swift run`.
    public static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let short = info["CFBundleShortVersionString"] as? String else { return "dev" }
        return "\(short) (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
}
