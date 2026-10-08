import Foundation
import SQLite3

actor TranslationDiskCache {
    private var database: OpaquePointer?
    private let url: URL
    private var lastCleanup = Date.distantPast
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) { self.url = url }
    deinit { if let database { sqlite3_close(database) } }

    private func open() -> OpaquePointer? {
        if let database { return database }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        database = handle
        sqlite3_busy_timeout(handle, 40)
        for sql in ["PRAGMA page_size=4096", "PRAGMA max_page_count=32768", "PRAGMA journal_mode=DELETE",
                    "PRAGMA journal_size_limit=1048576", "PRAGMA cache_size=-512", "PRAGMA mmap_size=0",
                    "PRAGMA temp_store=FILE", "PRAGMA secure_delete=ON",
                    "CREATE TABLE IF NOT EXISTS translations (key BLOB PRIMARY KEY, value BLOB NOT NULL, created REAL NOT NULL, touched REAL NOT NULL)",
                    "CREATE INDEX IF NOT EXISTS translations_touched ON translations(touched)"] {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                sqlite3_close(handle)
                database = nil
                return nil
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return handle
    }
    private func bind(_ data: Data, statement: OpaquePointer?, index: Int32) {
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
    }
    func get(_ key: Data, cutoff: TimeInterval, now: TimeInterval) -> (Data, TimeInterval)? {
        guard let database = open() else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value, created FROM translations WHERE key=? AND created>? AND created<=?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(key, statement: statement, index: 1)
        sqlite3_bind_double(statement, 2, cutoff)
        sqlite3_bind_double(statement, 3, now)
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, count <= 64_000 else { return nil }
        let result = Data(bytes: bytes, count: count)
        let created = sqlite3_column_double(statement, 1)
        var touch: OpaquePointer?
        if sqlite3_prepare_v2(database, "UPDATE translations SET touched=? WHERE key=?", -1, &touch, nil) == SQLITE_OK {
            sqlite3_bind_double(touch, 1, now)
            bind(key, statement: touch, index: 2)
            sqlite3_step(touch)
        }
        sqlite3_finalize(touch)
        return (result, created)
    }
    func put(_ data: Data, key: Data, created: TimeInterval, cutoff: TimeInterval) {
        guard data.count <= 64_000, let database = open() else { return }
        if Date().timeIntervalSince(lastCleanup) >= 3600 {
            expire(before: cutoff)
            lastCleanup = Date()
        }
        var prune: OpaquePointer?
        if sqlite3_prepare_v2(database, "DELETE FROM translations WHERE key IN (SELECT key FROM translations WHERE key<>? ORDER BY touched DESC LIMIT -1 OFFSET 9999)", -1, &prune, nil) == SQLITE_OK {
            bind(key, statement: prune, index: 1)
            sqlite3_step(prune)
        }
        sqlite3_finalize(prune)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO translations VALUES (?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(key, statement: statement, index: 1)
        bind(data, statement: statement, index: 2)
        sqlite3_bind_double(statement, 3, created)
        sqlite3_bind_double(statement, 4, created)
        if sqlite3_step(statement) == SQLITE_FULL {
            sqlite3_reset(statement)
            for _ in 0..<32 {
                sqlite3_exec(database, "DELETE FROM translations WHERE key IN (SELECT key FROM translations ORDER BY touched LIMIT 1)", nil, nil, nil)
            }
            sqlite3_step(statement)
        }
    }
    func expire(before cutoff: TimeInterval) {
        guard let database = open() else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM translations WHERE key IN (SELECT key FROM translations WHERE created<=? LIMIT 8)", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff)
        while sqlite3_step(statement) == SQLITE_DONE {
            if sqlite3_changes(database) == 0 { break }
            sqlite3_reset(statement)
        }
    }
    func clear() {
        if let database { sqlite3_close(database); self.database = nil }
        for suffix in ["", "-journal", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
}
