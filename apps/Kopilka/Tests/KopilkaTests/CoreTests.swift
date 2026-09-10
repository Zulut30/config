import Foundation
import AppKit
@testable import KopilkaCore

// Command Line Tools do not ship XCTest. These checks run against the same
// compiled core and Capture.swift as the app, using only system frameworks.
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    guard value() else { fatalError("Assertion failed at \(file):\(line)") }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(!value(), file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows {
    let left = try lhs()
    let right = try rhs()
    guard left == right else { fatalError("Expected \(right), got \(left) at \(file):\(line)") }
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value == nil, file: file, line: line)
}

@main
struct CheckRunner {
    @MainActor static func main() throws {
        let tests = CoreTests()
        tests.testRepositoryCaptureRetainsTextAndHiddenLink()
        tests.testLinksRejectUnsafeSchemesAndFalseGitHubDomains()
        try tests.testSQLitePersistsEditsTrashAndRestoreAcrossReopen()
        try tests.testClipboardRestorePreservesTypesAndDoesNotOverwriteNewCopy()
        try tests.testRichClipboardExtractsActualURL()
        print("PASS: 5 checks (SQLite persistence, links, Unicode, clipboard restore, rich text capture)")
    }
}

final class CoreTests {
    func testRepositoryCaptureRetainsTextAndHiddenLink() {
        let original = "Lidarr/Lidarr\nМенеджер музыкальной коллекции.\nСохранить на будущее."
        let note = Note(text: original, source: "Telegram", links: ["https://github.com/Lidarr/Lidarr"])
        XCTAssertEqual(note.text, original)
        XCTAssertEqual(note.title, "Lidarr/Lidarr")
        XCTAssertEqual(note.tags, ["Репозиторий"])
        XCTAssertTrue(note.matches("TELEGRAM музыкальной"))
        XCTAssertTrue(note.markdown.contains("https://github.com/Lidarr/Lidarr"))
        XCTAssertTrue(note.markdown.contains(original))
    }

    func testLinksRejectUnsafeSchemesAndFalseGitHubDomains() {
        XCTAssertNil(LinkInfo.safeURL("javascript:alert(1)"))
        XCTAssertNil(LinkInfo.safeURL("file:///etc/passwd"))
        XCTAssertNil(LinkInfo.repository("https://github.com.evil.example/owner/repo"))
        XCTAssertNil(LinkInfo.repository("https://github.com/settings/profile"))
        XCTAssertEqual(LinkInfo.repository("https://github.com/Lidarr/Lidarr.git"), "Lidarr/Lidarr")
        XCTAssertEqual(LinkInfo.links(in: "https://github.com/Lidarr/Lidarr", additional: ["https://github.com/Lidarr/Lidarr"]).count, 1)
        XCTAssertEqual(LinkInfo.tags("#Идея, идея, Работа, ,"), ["Идея", "Работа"])
    }

    func testSQLitePersistsEditsTrashAndRestoreAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Kopilka-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("notes.sqlite")
        var note = Note(text: "Текст с 'кавычками' и 🪙\nВторая строка", source: "Telegram")
        do {
            let db = try Database(url: url)
            try db.save(note)
            note.comment = "Не потерять"
            note.isPinned = true
            note.isDeleted = true
            try db.save(note)
            try XCTAssertEqual(try db.load(), [note])
        }
        let db = try Database(url: url)
        try XCTAssertEqual(try db.load(), [note])
        note.isDeleted = false
        note.isArchived = true
        try db.save(note)
        try XCTAssertEqual(try db.load().first?.comment, "Не потерять")
        try XCTAssertEqual(try db.load().first?.isArchived, true)
    }

    @MainActor
    func testClipboardRestorePreservesTypesAndDoesNotOverwriteNewCopy() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("Прежний буфер", forType: .string)
        item.setData(Data([0, 1, 2, 3]), forType: NSPasteboard.PasteboardType("com.kopilka.test"))
        board.writeObjects([item])
        let snapshot = try ClipboardSnapshot(board)
        board.clearContents(); board.setString("Выделение", forType: .string)
        let capturedCount = board.changeCount
        XCTAssertTrue(snapshot.restore(to: board, ifUnchanged: capturedCount))
        XCTAssertEqual(board.string(forType: .string), "Прежний буфер")
        XCTAssertEqual(board.data(forType: NSPasteboard.PasteboardType("com.kopilka.test")), Data([0, 1, 2, 3]))
        let beforeOtherCopy = board.changeCount
        board.clearContents(); board.setString("Новое ручное копирование", forType: .string)
        XCTAssertFalse(snapshot.restore(to: board, ifUnchanged: beforeOtherCopy))
        XCTAssertEqual(board.string(forType: .string), "Новое ручное копирование")
    }

    @MainActor
    func testRichClipboardExtractsActualURL() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let value = NSMutableAttributedString(string: "Lidarr/Lidarr")
        value.addAttribute(.link, value: URL(string: "https://github.com/Lidarr/Lidarr")!, range: NSRange(location: 0, length: value.length))
        let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        board.setData(data, forType: .rtf)
        let capture = CaptureService().readClipboard(board, source: "Telegram")
        XCTAssertEqual(capture?.text, "Lidarr/Lidarr")
        XCTAssertEqual(capture?.links, ["https://github.com/Lidarr/Lidarr"])
    }
}
