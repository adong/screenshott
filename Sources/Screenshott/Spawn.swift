import Darwin
import Dispatch
import Foundation

/// Runs a workflow step's program out of process, so third-party code that crashes or
/// hangs can't take a capture down with it (#10).
///
/// Responsibility is disclaimed: macOS normally files a child's privacy permissions
/// under the app that started it, so a script could use Screenshott's Screen Recording
/// grant (and, after M5, Accessibility) to watch the screen at any time. Disclaimed, the
/// child counts as its own app and has to ask for those itself. The script already has
/// the image; it doesn't need them.
enum Spawn {
    struct Result: Sendable {
        /// The exit status, or nil when a signal ended it.
        var status: Int32?
        var signal: Int32?
        var stdout: Data
        var stderr: Data
        var timedOut: Bool

        /// The last line of stderr, for a failure message.
        var errorLine: String {
            String(decoding: stderr, as: UTF8.self)
                .split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case disclaimUnavailable
        case pipe(Int32)
        case spawn(Int32)

        var description: String {
            switch self {
            case .disclaimUnavailable:
                "this macOS has no responsibility_spawnattrs_setdisclaim, so steps would share Screenshott's permissions"
            case .pipe(let code): "pipe failed: \(String(cString: strerror(code)))"
            case .spawn(let code): String(cString: strerror(code))
            }
        }
    }

    /// stdout and stderr past this are read and dropped, so a chatty child never blocks.
    static let outputLimit = 1 << 20

    /// The private libsystem call iTerm2 and LLDB use (`posix_spawnattr_t *, int`).
    /// Looked up at run time: on a macOS without it, steps refuse to run rather than
    /// quietly sharing the grant.
    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    private static let setDisclaim: SetDisclaim? = {
        // RTLD_DEFAULT is ((void *)-2) on Darwin; Swift can't import the macro.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
        else { return nil }
        return unsafeBitCast(symbol, to: SetDisclaim.self)
    }()

    /// Runs `executable` in `directory` with exactly `environment`, feeds it `input` on
    /// stdin and waits for it. Past `timeout` its process group gets SIGTERM, then SIGKILL
    /// two seconds later. Blocks the calling thread: call it from a detached task.
    static func run(
        _ executable: String, arguments: [String], environment: [String: String], directory: String,
        input: Data, timeout: Duration, disclaim: Bool = true
    ) throws(Failure) -> Result {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Only the three pipes are inherited; signals start from their defaults; the
        // child leads a new process group, so a timeout reaches its children too.
        let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETPGROUP
        posix_spawnattr_setflags(&attributes, Int16(flags))
        var everySignal = ~sigset_t(0), noSignals = sigset_t(0)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setpgroup(&attributes, 0)
        if disclaim {
            guard let setDisclaim, setDisclaim(&attributes, 1) == 0 else { throw .disclaimUnavailable }
        }

        var stdinPipe: [Int32] = [-1, -1], stdoutPipe: [Int32] = [-1, -1], stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            let code = errno
            for fd in stdinPipe + stdoutPipe + stderrPipe where fd >= 0 { close(fd) }
            throw .pipe(code)
        }
        // Our ends stay out of any other child this app starts (Process, NSWorkspace).
        for fd in [stdinPipe[1], stdoutPipe[0], stderrPipe[0]] { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        // A child that exits without reading stdin must not kill us with SIGPIPE.
        _ = fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, stdinPipe[0], 0)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], 1)
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&fileActions, directory)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for p in argv { free(p) }
            for p in envp { free(p) }
        }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &fileActions, &attributes, argv, envp)
        for fd in [stdinPipe[0], stdoutPipe[1], stderrPipe[1]] { close(fd) }
        guard spawned == 0 else {
            for fd in [stdinPipe[1], stdoutPipe[0], stderrPipe[0]] { close(fd) }
            throw .spawn(spawned)
        }

        let out = Collected(), err = Collected()
        let io = DispatchGroup()
        let (writeEnd, outEnd, errEnd) = (stdinPipe[1], stdoutPipe[0], stderrPipe[0])
        DispatchQueue.global().async(group: io) {
            input.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let n = write(writeEnd, bytes.baseAddress! + offset, bytes.count - offset)
                    if n < 0, errno == EINTR { continue }
                    if n <= 0 { break }
                    offset += n
                }
            }
            close(writeEnd)
        }
        DispatchQueue.global().async(group: io) { out.read(outEnd) }
        DispatchQueue.global().async(group: io) { err.read(errEnd) }

        var waitStatus: Int32 = 0
        var timedOut = false
        var killAt: ContinuousClock.Instant?
        let deadline = ContinuousClock.now + timeout
        while true {
            let reaped = waitpid(pid, &waitStatus, WNOHANG)
            if reaped == pid || (reaped == -1 && errno != EINTR) { break }
            let now = ContinuousClock.now
            if !timedOut, now >= deadline {
                timedOut = true
                kill(-pid, SIGTERM)
                killAt = now + .seconds(2)
            } else if let at = killAt, now >= at {
                kill(-pid, SIGKILL)
                killAt = nil
            }
            usleep(10_000)
        }
        // A grandchild left in the group could hold the pipes open; it goes too.
        if io.wait(timeout: .now() + 2) == .timedOut {
            kill(-pid, SIGKILL)
            _ = io.wait(timeout: .now() + 1)
        }

        // <sys/wait.h>'s WIFEXITED / WEXITSTATUS / WTERMSIG are macros Swift can't import.
        let low = waitStatus & 0x7f
        return Result(
            status: low == 0 ? (waitStatus >> 8) & 0xff : nil, signal: low == 0 ? nil : low,
            stdout: out.data, stderr: err.data, timedOut: timedOut
        )
    }
}

/// One pipe's bytes, filled on a reader thread and read after the dispatch group
/// finishes, which orders the two.
private final class Collected: @unchecked Sendable {
    private(set) var data = Data()

    func read(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            if n <= 0 { break }
            if data.count < Spawn.outputLimit { data.append(contentsOf: buffer[0..<min(n, Spawn.outputLimit - data.count)]) }
        }
        close(fd)
    }
}
