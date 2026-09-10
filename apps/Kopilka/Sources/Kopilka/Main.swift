import AppKit
import SwiftUI
import KopilkaCore

@main
enum KopilkaMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let capture = CaptureService()
    let hotKeys = HotKeyManager()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var composer: NSPanel?
    var toast: NSPanel?
    var toastTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Копилка"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.975, green: 0.962, blue: 0.935, alpha: 1)
        window.minSize = NSSize(width: 980, height: 650)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LibraryView(model: model))
        window.center()
        window.setFrameAutosaveName("KopilkaLibrary")
        model.showWindow = { [weak self] in self?.openLibrary() }
        model.showToast = { [weak self] title, detail in self?.showToast(title, detail) }
        model.captureAction = { [weak self] comment in self?.captureSelection(comment: comment) }
        model.newNoteAction = { [weak self] in self?.showComposer(nil) }
        model.clipboardAction = { [weak self] in self?.saveClipboard() }
        hotKeys.onKey = { [weak self] id in
            Task { @MainActor in
                switch id {
                case 1: self?.captureSelection(comment: false)
                case 2: self?.captureSelection(comment: true)
                case 3: self?.openLibrary()
                default: break
                }
            }
        }
        model.hotKeyWarnings = hotKeys.register()
        configureMenus()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        model.selectedID = model.visibleNotes.first?.id
        openLibrary()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openLibrary(); return true }

    @objc func openLibrary() {
        model.refreshPermissions()
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func newNote() { showComposer(nil) }
    @objc func settings() { openLibrary(); model.settingsVisible = true }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func saveClipboard() {
        guard let value = capture.readClipboard() else { showToast("В буфере нет текста", "Скопируйте текст или ссылку и повторите."); return }
        model.insert(value)
    }
    @objc func saveSelectionMenu() { captureSelection(comment: false) }

    func captureSelection(comment: Bool) {
        guard capture.isTrusted else {
            openLibrary()
            model.settingsVisible = true
            capture.requestPermission()
            return
        }
        Task { @MainActor in
            do {
                let value = try await capture.captureSelection()
                if comment { showComposer(value) }
                else { model.insert(value) }
            } catch { showToast("Не удалось сохранить", error.localizedDescription) }
        }
    }

    func showComposer(_ value: CapturedText?) {
        if let composer, composer.isVisible { composer.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 550, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Быстро сохранить"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ComposerView(text: value?.text ?? "", source: value?.source ?? "Вручную", save: { [weak self, weak panel] text, comment in
            guard let self else { return }
            let note = Note(text: text, source: value?.source ?? "Вручную", links: value?.links ?? [], comment: comment)
            if self.model.save(note) {
                self.model.navigate(.inbox)
                self.model.selectedID = note.id
                panel?.close()
                self.showToast("Сохранено в Копилку", note.title)
            }
        }, cancel: { [weak panel] in panel?.close() }))
        composer = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showToast(_ title: String, _ detail: String) {
        toastTask?.cancel()
        toast?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 355, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 24)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(3)
                }
                Spacer(minLength: 0)
            }.padding(18).frame(width: 355, height: 100).background(Palette.paper, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(Palette.ink)
        )
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.maxX - 375, y: frame.maxY - 118)) }
        panel.orderFrontRegardless()
        toast = panel
        toastTask = Task { @MainActor [weak panel] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func configureMenus() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "Копилка")
        appMenu.addItem(item("Настройки…", #selector(settings), key: ","))
        appMenu.addItem(.separator())
        let services = NSMenu()
        let servicesItem = NSMenuItem(title: "Службы", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Завершить Копилку", #selector(quit), key: "q"))
        let root = NSMenuItem(); root.submenu = appMenu; main.addItem(root)
        let file = NSMenu(title: "Заметки")
        file.addItem(item("Новая заметка", #selector(newNote), key: "n"))
        file.addItem(item("Сохранить из буфера", #selector(saveClipboard), key: "v", modifiers: [.command, .shift]))
        file.addItem(item("Открыть Копилку", #selector(openLibrary)))
        let fileRoot = NSMenuItem(); fileRoot.submenu = file; main.addItem(fileRoot)
        let edit = NSMenu(title: "Правка")
        for (title, selector, key) in [("Отменить", "undo:", "z"), ("Вырезать", "cut:", "x"), ("Копировать", "copy:", "c"), ("Вставить", "paste:", "v"), ("Выделить всё", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        let editRoot = NSMenuItem(); editRoot.submenu = edit; main.addItem(editRoot)
        let windows = NSMenu(title: "Окно")
        windows.addItem(NSMenuItem(title: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windows.addItem(NSMenuItem(title: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        let windowRoot = NSMenuItem(); windowRoot.submenu = windows; main.addItem(windowRoot)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windows
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Копилка")
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        statusItem.button?.toolTip = "Копилка: быстро сохранить текст"
        let statusMenu = NSMenu()
        statusMenu.addItem(item("Открыть Копилку   ⌃⇧I", #selector(openLibrary)))
        statusMenu.addItem(item("Сохранить из буфера", #selector(saveClipboard)))
        statusMenu.addItem(item("Новая заметка…", #selector(newNote)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(item("Настройки…", #selector(settings)))
        statusMenu.addItem(item("Завершить Копилку", #selector(quit)))
        statusItem.menu = statusMenu
    }

    @objc func captureText(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let value = capture.readClipboard(pboard, source: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Службы macOS") else {
            error.pointee = "Нет текста для сохранения."; return
        }
        model.insert(value)
    }
}
