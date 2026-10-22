import Foundation
import SQLite3

/// A tiny wrapper around the SQLite C library.
///
/// Browsers, Mail and macOS itself keep history, cookies and permissions in
/// SQLite databases. We only need to run a few statements, so this stays small.
final class SQLiteDB {
    private var handle: OpaquePointer?

    /// Opens a database.
    /// - Parameter immutable: open read-only without touching lock/WAL files
    ///   (safe to use while the owning app is running).
    init?(path: String, readOnly: Bool = false, immutable: Bool = false) {
        var flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        var target = path
        if immutable {
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            target = URL(fileURLWithPath: path).absoluteString + "?immutable=1"
        }
        guard sqlite3_open_v2(target, &handle, flags, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        sqlite3_busy_timeout(handle, 3000)
    }

    deinit { sqlite3_close(handle) }

    /// Runs a statement that returns no rows. Returns false (with the error) if it failed.
    @discardableResult
    func execute(_ sql: String) -> (ok: Bool, error: String?) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error \(rc)"
            sqlite3_free(errorMessage)
            return (false, message)
        }
        return (true, nil)
    }

    /// Runs a query and returns every row as an array of optional strings.
    func rows(_ sql: String) -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String?]] = []
        let columns = sqlite3_column_count(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String?] = []
            for index in 0..<columns {
                if let text = sqlite3_column_text(statement, index) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
            result.append(row)
        }
        return result
    }

    /// Returns the first column of the first row as a number.
    func scalar(_ sql: String) -> Int64? {
        guard let value = rows(sql).first?.first ?? nil else { return nil }
        return Int64(value) ?? Double(value).map { Int64($0) }
    }

    /// True if a table with this name exists.
    func hasTable(_ name: String) -> Bool {
        (scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='\(name)'") ?? 0) > 0
    }
}
