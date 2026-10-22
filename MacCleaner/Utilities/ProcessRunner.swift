import Foundation

struct ProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

enum ProcessRunner {
    /// Runs a command without a shell so arguments stay literal.
    @discardableResult
    static func run(_ launchPath: String, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval = 120) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw NSError(domain: "ProcessRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out: \(launchPath)"])
        }

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func which(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let result = try? run("/usr/bin/which", arguments: [name]), result.exitCode == 0 {
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    static func runShell(_ command: String) throws -> ProcessResult {
        try run("/bin/zsh", arguments: ["-lc", command])
    }
}
