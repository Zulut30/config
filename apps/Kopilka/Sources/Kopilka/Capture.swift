import AppKit
import ApplicationServices
import Carbon
import KopilkaCore

struct CapturedText {
    let text: String
    let links: [String]
    let source: String
}

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int

    init(_ board: NSPasteboard) throws {
        changeCount = board.changeCount
        var total = 0
        items = try (board.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw CaptureError.message("Буфер содержит отложенные данные. Сохраните их или скопируйте нужный текст вручную.")
                }
                total += data.count
                guard total <= 32 * 1024 * 1024 else {
                    throw CaptureError.message("В буфере большой файл. Используйте «Сохранить из буфера» после ручного копирования текста.")
                }
                values[type] = data
            }
            return values
        }
    }

    @discardableResult
    func restore(to board: NSPasteboard, ifUnchanged expected: Int) -> Bool {
        guard board.changeCount == expected else { return false }
        board.clearContents()
        let copies = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !copies.isEmpty { return board.writeObjects(copies) }
        return true
    }
}

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

@MainActor
final class CaptureService {
    private var capturing = false
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readClipboard(_ board: NSPasteboard = .general, source: String = "Буфер обмена") -> CapturedText? {
        var rich: NSAttributedString?
        if let rtf = board.data(forType: .rtf) {
            rich = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        var links = [String]()
        rich?.enumerateAttribute(.link, in: NSRange(location: 0, length: rich?.length ?? 0)) { value, _, _ in
            if let url = value as? URL { links.append(url.absoluteString) }
            else if let value = value as? String { links.append(value) }
        }
        if let rawURL = board.string(forType: .URL) { links.append(rawURL) }
        // Extract hrefs without loading HTML or any remote resources.
        if let html = board.string(forType: .html),
           let regex = try? NSRegularExpression(pattern: "(?i)href\\s*=\\s*[\"'](https?://[^\"']+)[\"']") {
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let range = Range(match.range(at: 1), in: html) {
                    links.append(String(html[range]).replacingOccurrences(of: "&amp;", with: "&"))
                }
            }
        }
        let text = (board.string(forType: .string) ?? rich?.string ?? links.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return CapturedText(text: text, links: LinkInfo.links(in: text, additional: links), source: source)
    }

    func captureSelection() async throws -> CapturedText {
        guard !capturing else { throw CaptureError.message("Предыдущее выделение ещё сохраняется.") }
        guard isTrusted else { throw CaptureError.message("Разрешите «Копилке» Универсальный доступ, чтобы копировать выделение по горячей клавише.") }
        guard let sourceApp = NSWorkspace.shared.frontmostApplication,
              sourceApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw CaptureError.message("Выделите текст в другом приложении и нажмите Control + Shift + N.")
        }
        capturing = true
        defer { capturing = false }
        let appElement = AXUIElementCreateApplication(sourceApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        var elementValue: CFTypeRef?
        var selectedText: String?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &elementValue) == .success,
           let elementValue, CFGetTypeID(elementValue) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(elementValue, to: AXUIElement.self)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            if (subrole as? String) == "AXSecureTextField" { throw CaptureError.message("Поля паролей не сохраняются.") }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success {
                selectedText = value as? String
            }
        }
        // Wait only during a capture, so held shortcut modifiers do not alter Cmd+C.
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskControl, .maskShift, .maskAlternate, .maskCommand]).isEmpty { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskControl, .maskShift, .maskAlternate, .maskCommand]).isEmpty else {
            throw CaptureError.message("Отпустите клавиши сочетания и попробуйте ещё раз.")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourceApp.processIdentifier else {
            throw CaptureError.message("Активное приложение изменилось. Повторите сохранение.")
        }
        let board = NSPasteboard.general
        let snapshot = try ClipboardSnapshot(board)
        guard board.changeCount == snapshot.changeCount else { throw CaptureError.message("Буфер изменился. Повторите сохранение.") }
        let eventSource = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            throw CaptureError.message("Не удалось отправить команду копирования.")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 20_000_000)
            if board.changeCount != snapshot.changeCount {
                let copyCount = board.changeCount
                let captured = readClipboard(board, source: sourceApp.localizedName ?? "Приложение")
                snapshot.restore(to: board, ifUnchanged: copyCount)
                guard let captured else { throw CaptureError.message("В выделении нет текста или ссылки.") }
                return captured
            }
        }
        if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedText(text: text, links: [], source: sourceApp.localizedName ?? "Приложение")
        }
        throw CaptureError.message("Приложение не скопировало выделение. В Telegram можно скопировать сообщение или ссылку и выбрать «Сохранить из буфера» в меню «Копилки».")
    }
}

final class HotKeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onKey: ((UInt32) -> Void)?

    func register() -> [String] {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return noErr }
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            manager.onKey?(key.id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return ["Не удалось подключить глобальные сочетания: \(status)"] }
        let bindings: [(UInt32, UInt32, UInt32, String)] = [
            (1, UInt32(kVK_ANSI_N), UInt32(controlKey | shiftKey), "Control + Shift + N"),
            (2, UInt32(kVK_ANSI_N), UInt32(controlKey | shiftKey | optionKey), "Control + Shift + Option + N"),
            (3, UInt32(kVK_ANSI_I), UInt32(controlKey | shiftKey), "Control + Shift + I")
        ]
        var failures: [String] = []
        for (id, code, modifiers, label) in bindings {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x4B504C4B, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { refs.append(ref) }
            else { failures.append("\(label) занято другим приложением (\(result)).") }
        }
        return failures
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
