import AppKit

/// Running processes: heavy consumers and hung (not responding) apps.
enum ProcessService {

    /// Reads all processes with `ps` (CPU %, resident memory, user, name).
    static func sample() -> [ProcessSample] {
        let output = Shell.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,user=,comm="], timeout: 10).output
        var samples: [ProcessSample] = []
        for line in output.split(separator: "\n") {
            // pid, cpu, rss and user never contain spaces; the name may.
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]), let cpu = Double(fields[1]),
                  let rssKB = Int64(fields[2]) else { continue }
            samples.append(ProcessSample(pid: pid, name: String(fields[4]), cpu: cpu,
                                         memoryBytes: rssKB * 1024, user: String(fields[3])))
        }
        return samples
    }

    /// Better names for app processes ("Google Chrome Helper (Renderer)" stays as is,
    /// but "Safari" etc. get their display name).
    static func displayNames() -> [Int32: String] {
        var names: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName { names[app.processIdentifier] = name }
        }
        return names
    }

    /// Asks a process to quit (graceful) or kills it (force).
    static func quit(pid: Int32, force: Bool) -> (ok: Bool, message: String) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let ok = force ? app.forceTerminate() : app.terminate()
            return (ok, ok ? "" : "The app refused to quit.")
        }
        if kill(pid, force ? SIGKILL : SIGTERM) == 0 { return (true, "") }
        let reason = errno == EPERM ? "This process belongs to the system or another user." : String(cString: strerror(errno))
        return (false, reason)
    }

    // MARK: - Hung apps

    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias IsUnresponsiveFn = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
    private typealias MainConnectionFn = @convention(c) () -> Int32

    /// macOS has no public API for "Not Responding". Activity Monitor uses the
    /// WindowServer call `CGSEventIsAppUnresponsive`, which we load dynamically.
    /// If it's ever unavailable we simply report no hung apps.
    private static let functions: (GetProcessForPIDFn, IsUnresponsiveFn, MainConnectionFn)? = {
        guard let appServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let getPSN = dlsym(appServices, "GetProcessForPID") else { return nil }
        let main = dlopen(nil, RTLD_NOW)
        guard let unresponsive = dlsym(main, "CGSEventIsAppUnresponsive"),
              let connection = dlsym(main, "CGSMainConnectionID") else { return nil }
        return (unsafeBitCast(getPSN, to: GetProcessForPIDFn.self),
                unsafeBitCast(unresponsive, to: IsUnresponsiveFn.self),
                unsafeBitCast(connection, to: MainConnectionFn.self))
    }()

    struct HungApp: Identifiable, Hashable {
        var id: Int32 { pid }
        var pid: Int32
        var name: String
        var bundleURL: URL?
    }

    /// Regular (Dock) apps that WindowServer reports as not responding.
    static func hungApps() -> [HungApp] {
        guard let (getPSN, isUnresponsive, mainConnection) = functions else { return [] }
        let connection = mainConnection()
        var result: [HungApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            var psn = ProcessSerialNumber()
            guard getPSN(app.processIdentifier, &psn) == noErr else { continue }
            if isUnresponsive(connection, &psn) {
                result.append(HungApp(pid: app.processIdentifier, name: app.localizedName ?? "App", bundleURL: app.bundleURL))
            }
        }
        return result
    }
}
