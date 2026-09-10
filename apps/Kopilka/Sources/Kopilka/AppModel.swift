import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import KopilkaCore

enum Shelf: String, CaseIterable, Identifiable {
    case inbox = "Входящие", all = "Все заметки", pinned = "Избранное", archive = "Архив", trash = "Корзина"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .all: return "square.grid.2x2"
        case .pinned: return "star"
        case .archive: return "archivebox"
        case .trash: return "trash"
        }
    }
    func includes(_ note: Note) -> Bool {
        if self == .trash { return note.isDeleted }
        guard !note.isDeleted else { return false }
        switch self {
        case .inbox: return !note.isArchived
        case .all: return true
        case .pinned: return note.isPinned
        case .archive: return note.isArchived
        case .trash: return false
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID?
    @Published var shelf: Shelf = .inbox
    @Published var selectedTag: String?
    @Published var search = ""
    @Published var error: String?
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var hotKeyWarnings: [String] = []
    @Published var settingsVisible = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var notice: String?
    let database: Database?
    let dataFolder: URL
    var showWindow: (() -> Void)?
    var showToast: ((String, String) -> Void)?
    var captureAction: ((Bool) -> Void)?
    var newNoteAction: (() -> Void)?
    var clipboardAction: (() -> Void)?

    init() {
        dataFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kopilka", isDirectory: true)
        do {
            let store = try Database(url: dataFolder.appendingPathComponent("notes.sqlite"))
            notes = try store.load()
            database = store
        } catch {
            database = nil
            self.error = error.localizedDescription
        }
    }

    var visibleNotes: [Note] {
        notes.filter { shelf.includes($0) && (selectedTag == nil || $0.tags.contains(selectedTag!)) && $0.matches(search) }
            .sorted { a, b in a.isPinned == b.isPinned ? a.createdAt > b.createdAt : a.isPinned }
    }
    var selected: Note? { notes.first { $0.id == selectedID } }
    var tags: [String] { Array(Set(notes.filter { !$0.isDeleted }.flatMap(\.tags))).sorted() }
    func count(_ shelf: Shelf) -> Int { notes.filter { shelf.includes($0) }.count }
    func navigate(_ shelf: Shelf, tag: String? = nil) {
        self.shelf = shelf
        selectedTag = tag
        search = ""
        selectedID = visibleNotes.first?.id
    }

    @discardableResult
    func save(_ note: Note) -> Bool {
        guard let database else { error = "База заметок недоступна. Перезапустите приложение после проверки папки данных."; return false }
        do {
            try database.save(note)
            if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note }
            else { notes.insert(note, at: 0) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func insert(_ capture: CapturedText, comment: String = "") {
        let note = Note(text: capture.text, source: capture.source, links: capture.links, comment: comment)
        guard save(note) else { showWindow?(); return }
        navigate(.inbox)
        selectedID = note.id
        showToast?("Сохранено в Копилку", note.title)
    }

    func update(_ note: Note, _ edit: (inout Note) -> Void) {
        var updated = note
        edit(&updated)
        updated.updatedAt = Date()
        if save(updated), !visibleNotes.contains(where: { $0.id == selectedID }) { selectedID = visibleNotes.first?.id }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notice = "Подтвердите автозапуск Копилки в настройках macOS: Основные → Объекты входа." }
        } catch { self.error = error.localizedDescription }
    }

    func export(_ notes: [Note]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = notes.count == 1 ? "Заметка.md" : "Копилка.md"
        panel.title = "Экспорт в Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try notes.map(\.markdown).joined(separator: "\n\n---\n\n").write(to: url, atomically: true, encoding: .utf8)
            notice = "Заметки экспортированы."
        } catch { self.error = error.localizedDescription }
    }
}
