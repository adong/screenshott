import AppKit
import ScreenshottCore

/// `open dist/Screenshott.app --args --verify-disclaim <probe>` checks #10's promise that
/// workflow steps don't inherit Screenshott's Screen Recording grant. It runs the probe
/// (Tools/TCCProbe, which prints what `CGPreflightScreenCaptureAccess()` says) twice —
/// spawned plainly and spawned the way workflow steps are — logs both answers and quits.
/// scripts/verify-disclaim.sh builds the probe and reads the log. A normal launch never
/// gets here.
@MainActor
enum DisclaimCheck {
    static var probe: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--verify-disclaim"), arguments.indices.contains(flag + 1) else {
            return nil
        }
        return arguments[flag + 1]
    }

    static func run(probe: String) async {
        let parent = Permissions.hasScreenCapture
        var answers: [String] = []
        for disclaim in [false, true] {
            do {
                let result = try await Task.detached {
                    try Spawn.run(
                        probe, arguments: [], environment: [:], directory: "/", input: Data(),
                        timeout: .seconds(10), disclaim: disclaim
                    )
                }.value
                let answer = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                answers.append("\(disclaim ? "disclaimed" : "inherited")=\(answer)")
            } catch {
                answers.append("\(disclaim ? "disclaimed" : "inherited")=error(\(error))")
            }
        }
        Log.write("verify-disclaim parent screenCapture=\(parent) \(answers.joined(separator: " "))")
        Log.write("verify-disclaim done")
        NSApp.terminate(nil)
    }
}
