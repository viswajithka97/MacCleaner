import Foundation
import Combine

/// Talks to macOS via AppleScript `do shell script ... with administrator privileges`.
/// The system caches the password for a while; we also remember that the user
/// already approved admin work this session so the UI can skip repeating the explanation.
@MainActor
final class AdminPrivileges: ObservableObject {
    static let shared = AdminPrivileges()

    @Published private(set) var unlockedThisSession = false
    @Published var lastExplanation: String = ""
    @Published var lastError: String?

    func run(command: String, explanation: String) async throws -> String {
        lastExplanation = explanation
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        let output: String = try await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw NSError(domain: "AdminPrivileges", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not build AppleScript."])
            }
            let result = script.executeAndReturnError(&error)
            if let error {
                let message = error[NSAppleScript.errorMessage] as? String ?? String(describing: error)
                throw NSError(domain: "AdminPrivileges", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
            return result.stringValue ?? ""
        }.value
        unlockedThisSession = true
        lastError = nil
        return output
    }

    func runIfNeeded(command: String, explanation: String, requiresAdmin: Bool) async throws -> String {
        if requiresAdmin {
            return try await run(command: command, explanation: explanation)
        }
        let result = try ProcessRunner.runShell(command)
        if result.exitCode != 0 {
            throw NSError(domain: "AdminPrivileges", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }
        return result.stdout
    }
}
