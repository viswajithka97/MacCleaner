import Foundation

/// The result of running a command-line tool.
struct ShellResult {
    var exitCode: Int32
    var output: String
    var error: String

    var succeeded: Bool { exitCode == 0 }

    /// stdout and stderr together, trimmed. Handy for showing in the UI.
    var combinedOutput: String {
        [output, error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Runs command-line tools (like `tmutil`, `codesign` or `brew`) safely.
///
/// We always pass arguments as an array (never through a shell string) so
/// file names with spaces or quotes can't be misinterpreted.
enum Shell {

    /// Runs a tool and waits for it to finish (blocking the *current* thread).
    /// Only call this from background code, never from the main thread.
    @discardableResult
    static func run(_ executable: String,
                    _ arguments: [String] = [],
                    input: String? = nil,
                    environment: [String: String]? = nil,
                    timeout: TimeInterval = 120) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        process.standardInput = inPipe

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, output: "", error: "Could not start \(executable): \(error.localizedDescription)")
        }

        if let input, let data = input.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()

        // Kill the process if it runs too long so a stuck tool never hangs the app.
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        // Read both pipes concurrently: reading one at a time can deadlock when
        // the other pipe's buffer fills up.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timer.cancel()

        return ShellResult(exitCode: process.terminationStatus,
                           output: String(decoding: outData, as: UTF8.self),
                           error: String(decoding: errData, as: UTF8.self))
    }

    /// Async version: runs on a background thread so the UI stays responsive.
    /// Cancelling the calling Task terminates the process.
    static func runAsync(_ executable: String,
                         _ arguments: [String] = [],
                         input: String? = nil,
                         environment: [String: String]? = nil,
                         timeout: TimeInterval = 600) async -> ShellResult {
        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = runTracked(executable, arguments, input: input,
                                            environment: environment, timeout: timeout, box: box)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Same as `run` but registers the process so it can be cancelled.
    private static func runTracked(_ executable: String, _ arguments: [String], input: String?,
                                   environment: [String: String]?, timeout: TimeInterval,
                                   box: ProcessBox) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe
        do { try process.run() } catch {
            return ShellResult(exitCode: -1, output: "", error: "Could not start \(executable): \(error.localizedDescription)")
        }
        box.set(process)
        if let input, let data = input.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()

        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timer.cancel()
        return ShellResult(exitCode: process.terminationStatus,
                           output: String(decoding: outData, as: UTF8.self),
                           error: String(decoding: errData, as: UTF8.self))
    }

    /// Wraps a string in single quotes for use inside a `/bin/sh` command line.
    /// `it's` becomes `'it'\''s'`.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Finds a tool such as `brew` in the usual install locations.
    static func which(_ name: String) -> String? {
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                          NSHomeDirectory() + "/.cargo/bin", NSHomeDirectory() + "/.local/bin"]
        for dir in candidates {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// The numeric user id of the person running the app (used by launchctl).
    static var uid: uid_t { getuid() }
}

/// Holds a running Process so a cancellation handler on another thread can stop it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        if cancelled, process.isRunning { process.terminate() }
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}
