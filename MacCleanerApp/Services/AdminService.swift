import AppKit
import Combine

/// What the admin sheet shows the user before anything runs as root.
struct AdminRequest: Identifiable {
    let id = UUID()
    var title: String
    /// Plain-language explanation of what will happen.
    var explanation: String
    /// The exact commands, for the curious.
    var commands: [String]
    var needsPassword: Bool
}

/// Runs commands with administrator privileges.
///
/// How it works:
/// 1. Before any admin command, `requestApproval` shows a sheet explaining it.
/// 2. The first time in a session, the sheet also asks for your password. It is
///    checked with AppleScript (`do shell script ... with administrator privileges`
///    via NSAppleScript) and then kept **in memory only** until you quit.
/// 3. Commands then run through `/usr/bin/osascript` (the same AppleScript
///    command) on a background thread so the window never freezes.
@MainActor
final class AdminService: ObservableObject {
    static let shared = AdminService()

    @Published var request: AdminRequest?
    @Published var errorMessage: String?
    @Published var isValidating = false

    private var continuation: CheckedContinuation<Bool, Never>?

    private init() {}

    /// Shows the explanation sheet and waits for the user. Returns true if approved
    /// (and a valid password is available).
    func requestApproval(title: String, explanation: String, commands: [String]) async -> Bool {
        // Only one sheet at a time: wait for any pending one to finish.
        while request != nil {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        errorMessage = nil
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.request = AdminRequest(title: title, explanation: explanation, commands: commands,
                                        needsPassword: !AdminVault.hasPassword)
        }
    }

    /// Called by the sheet's "Continue" button.
    func approve(password: String) {
        guard let request else { return }
        if !request.needsPassword {
            finish(true)
            return
        }
        isValidating = true
        // Validate with NSAppleScript: a harmless `/usr/bin/true` as root.
        let ok = Self.validate(password: password)
        isValidating = false
        if ok {
            AdminVault.store(password)
            finish(true)
        } else {
            errorMessage = "That password didn't work. Use the password you log in to this Mac with (your account must be an administrator)."
        }
    }

    func cancel() { finish(false) }

    /// Forgets the password (Settings → "Forget administrator password").
    func forgetPassword() { AdminVault.clear() }

    private func finish(_ approved: Bool) {
        request = nil
        continuation?.resume(returning: approved)
        continuation = nil
    }

    private static func validate(password: String) -> Bool {
        let source = "do shell script \"/usr/bin/true\" user name \"\(appleScriptEscape(NSUserName()))\" password \"\(appleScriptEscape(password))\" with administrator privileges"
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        return error == nil
    }

    // MARK: - Running commands (background safe)

    /// Runs a /bin/sh command line as root. Call `requestApproval` first.
    nonisolated static func run(_ shellLine: String) async -> ShellResult {
        guard let password = AdminVault.password else {
            return ShellResult(exitCode: -1, output: "", error: "Administrator access was not approved.")
        }
        let script = "do shell script \"\(appleScriptEscape(shellLine))\" user name \"\(appleScriptEscape(NSUserName()))\" password \"\(appleScriptEscape(password))\" with administrator privileges"
        // The script (with the password) goes in through stdin, so it never appears in `ps`.
        var result = await Shell.runAsync("/usr/bin/osascript", ["-"], input: script, timeout: 3600)
        // `do shell script` turns newlines into carriage returns.
        result.output = result.output.replacingOccurrences(of: "\r", with: "\n")
        if !result.succeeded {
            result.error = cleanAppleScriptError(result.error)
        }
        return result
    }

    /// Escapes a string for use inside an AppleScript "..." literal.
    nonisolated static func appleScriptEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// "0:42: execution error: rm: x: Permission denied (1)" -> "rm: x: Permission denied"
    nonisolated private static func cleanAppleScriptError(_ text: String) -> String {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = message.range(of: "execution error: ") {
            message = String(message[range.upperBound...])
        }
        if let paren = message.range(of: #" \(-?\d+\)$"#, options: .regularExpression) {
            message.removeSubrange(paren)
        }
        return message.replacingOccurrences(of: "\r", with: "\n")
    }
}

/// Holds the admin password in memory for this session only (never written to disk).
enum AdminVault {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: String?

    static var password: String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    static var hasPassword: Bool { password != nil }

    static func store(_ value: String) {
        lock.lock(); stored = value; lock.unlock()
    }

    static func clear() {
        lock.lock(); stored = nil; lock.unlock()
    }
}
