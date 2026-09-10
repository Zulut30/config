import Foundation
import CSQLite

public final class Database {
    private var db: OpaquePointer?
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(db)
            db = nil
            throw DatabaseError(message: message)
        }
        sqlite3_busy_timeout(db, 3000)
        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL, modified REAL NOT NULL);")
        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    public func load() throws -> [Note] {
        let statement = try prepare("SELECT payload FROM notes ORDER BY modified DESC;")
        defer { sqlite3_finalize(statement) }
        var notes: [Note] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure() }
            guard let bytes = sqlite3_column_blob(statement, 0) else { throw DatabaseError(message: "Empty note record") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            notes.append(try JSONDecoder().decode(Note.self, from: data))
        }
        return notes
    }

    public func save(_ note: Note) throws {
        let statement = try prepare("INSERT INTO notes(id,payload,modified) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,modified=excluded.modified;")
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let data = try JSONEncoder().encode(note)
        guard sqlite3_bind_text(statement, 1, note.id.uuidString, -1, transient) == SQLITE_OK else { throw failure() }
        let bound = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        guard bound == SQLITE_OK, sqlite3_bind_double(statement, 3, note.updatedAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func failure() -> DatabaseError { DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
}

public struct DatabaseError: LocalizedError {
    public let message: String
    public var errorDescription: String? { "Не удалось сохранить или прочитать заметки: \(message)" }
}
