import SwiftUI
import AppKit
import KopilkaCore

enum Palette {
    static let paper = Color(red: 0.975, green: 0.962, blue: 0.935)
    static let sidebar = Color(red: 0.94, green: 0.925, blue: 0.89)
    static let ink = Color(red: 0.19, green: 0.23, blue: 0.20)
    static let muted = Color(red: 0.48, green: 0.49, blue: 0.44)
    static let accent = Color(red: 0.77, green: 0.30, blue: 0.17)
    static let sage = Color(red: 0.86, green: 0.90, blue: 0.83)
    static let line = Color.black.opacity(0.075)
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                if !model.accessibilityGranted { permissionBanner }
                if !model.hotKeyWarnings.isEmpty {
                    Text(model.hotKeyWarnings.joined(separator: "\n")).font(.caption).foregroundStyle(Palette.accent).padding(12)
                }
                HStack(spacing: 0) {
                    noteList.frame(width: 300)
                    Rectangle().fill(Palette.line).frame(width: 1)
                    if let note = model.selected {
                        NoteDetail(note: note, model: model).id(note.id)
                    } else { welcome }
                }
            }
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(.light)
        .frame(minWidth: 980, minHeight: 610)
        .sheet(isPresented: $model.settingsVisible) { SettingsView(model: model) }
        .alert("Копилка", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Копилка", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("Хорошо") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .onChange(of: model.search) { _, _ in
            if !model.visibleNotes.contains(where: { $0.id == model.selectedID }) { model.selectedID = model.visibleNotes.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 23)).foregroundStyle(Palette.accent)
                Text("Копилка").font(.system(size: 25, weight: .semibold, design: .serif))
            }.padding(.top, 32).padding(.bottom, 8)
            Text("Для того, что пригодится.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.bottom, 34)
            Text("БИБЛИОТЕКА").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(Palette.muted).padding(.bottom, 12)
            ForEach(Shelf.allCases) { shelf in
                Button { model.navigate(shelf) } label: {
                    HStack {
                        Image(systemName: shelf.icon).frame(width: 17)
                        Text(shelf.rawValue)
                        Spacer()
                        Text("\(model.count(shelf))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                    }
                    .font(.system(size: 12, weight: model.shelf == shelf ? .semibold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .background(model.shelf == shelf && model.selectedTag == nil ? Color.white.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, -10)
            }
            Text("ТЕГИ").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(Palette.muted).padding(.top, 28).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(Set(model.tags + ["Репозиторий", "Идея", "Прочитать", "Работа"])).sorted(), id: \.self) { tag in
                        Button { model.navigate(.all, tag: tag) } label: {
                            HStack(spacing: 8) {
                                Text("#").foregroundStyle(Palette.accent)
                                Text(tag).foregroundStyle(model.selectedTag == tag ? Palette.accent : Palette.muted)
                            }.font(.system(size: 12))
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 6) {
                Label("Хранится на этом Mac", systemImage: "internaldrive").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Button { model.settingsVisible = true } label: { Label("Настройки и сочетания", systemImage: "gearshape").font(.system(size: 11)) }.buttonStyle(.plain)
            }.padding(.bottom, 24)
        }.padding(.horizontal, 22).background(Palette.sidebar)
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedTag.map { "#" + $0 } ?? model.shelf.rawValue).font(.system(size: 28, weight: .medium, design: .serif))
                Text("\(model.visibleNotes.count) заметок в подборке").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Найти в заметках", text: $model.search).textFieldStyle(.plain).focused($searchFocused)
                Text("⌘F").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(10).frame(width: 195).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
            Button { model.newNoteAction?() } label: { Label("Заметка", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.vertical, 5) }
                .buttonStyle(.borderedProminent).keyboardShortcut("n", modifiers: .command)
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden().frame(width: 0)
        }.padding(.horizontal, 26).padding(.vertical, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
            Text("Разрешите захват выделения, чтобы сохранять по ⌃⇧N.").font(.system(size: 11))
            Spacer()
            Button("Настроить") { model.settingsVisible = true }.buttonStyle(.borderless).font(.system(size: 11, weight: .semibold))
        }.padding(.horizontal, 26).padding(.vertical, 12).background(Palette.sage.opacity(0.65))
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                if model.visibleNotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: model.search.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 27, weight: .light))
                        Text(model.search.isEmpty ? "Здесь пока тихо" : "Ничего не найдено").font(.system(size: 13, weight: .medium))
                        Text(model.search.isEmpty ? "Сохранённое появится здесь." : "Попробуйте другой запрос.").font(.system(size: 11))
                    }.foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.top, 45)
                }
                ForEach(model.visibleNotes) { note in
                    Button { model.selectedID = note.id } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Label(note.links.compactMap { LinkInfo.repository($0) }.isEmpty ? "ЗАМЕТКА" : "GITHUB", systemImage: note.links.isEmpty ? "text.alignleft" : "link")
                                    .font(.system(size: 9, weight: .semibold)).tracking(1)
                                Spacer()
                                if note.isPinned { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.accent) }
                            }.foregroundStyle(Palette.muted)
                            Text(note.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Text(note.text).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(3).multilineTextAlignment(.leading)
                            HStack {
                                Text(note.source).lineLimit(1)
                                Spacer()
                                Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                            }.font(.system(size: 9)).foregroundStyle(Palette.muted)
                        }
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.selectedID == note.id ? .white : Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(model.selectedID == note.id ? Palette.accent.opacity(0.5) : Palette.line, lineWidth: 1) }
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }.background(Palette.paper.opacity(0.5))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "tray.and.arrow.down").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(Palette.accent)
            Text("Хорошие находки.\nВ одном месте.").font(.system(size: 36, weight: .regular, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Text("Репозиторий из Telegram, полезная мысль или ссылка на потом. Выделите, сохраните и продолжайте своё дело.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("⌃ ⇧ N").font(.system(size: 20, weight: .medium, design: .monospaced)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 10))
                Text("Сохранить\nвыделенный текст").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Button { model.clipboardAction?() } label: { Label("Сохранить из буфера", systemImage: "doc.on.clipboard") }.buttonStyle(.bordered)
            Text("Без аккаунта. Заметки остаются у вас.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
        }.padding(.horizontal, 38).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct NoteDetail: View {
    let note: Note
    @ObservedObject var model: AppModel
    @State private var editing = false
    @State private var draft: Note
    @State private var tagText: String

    init(note: Note, model: AppModel) {
        self.note = note
        self.model = model
        _draft = State(initialValue: note)
        _tagText = State(initialValue: note.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Text(note.isDeleted ? "В КОРЗИНЕ" : "СОХРАНЕНО").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(Palette.muted)
                Spacer()
                Button { model.update(note) { $0.isPinned.toggle() } } label: { Image(systemName: note.isPinned ? "star.fill" : "star") }.help("В избранное")
                Button { model.export([note]) } label: { Image(systemName: "square.and.arrow.up") }.help("Экспорт в Markdown")
                if note.isDeleted {
                    Button("Восстановить") { model.update(note) { $0.isDeleted = false } }
                } else {
                    Button { model.update(note) { $0.isArchived.toggle() } } label: { Image(systemName: note.isArchived ? "tray.and.arrow.up" : "archivebox") }.help(note.isArchived ? "Вернуть во входящие" : "В архив")
                    Button { model.update(note) { $0.isDeleted = true } } label: { Image(systemName: "trash") }.help("В корзину (можно восстановить)")
                }
            }.buttonStyle(.borderless).foregroundStyle(Palette.muted).padding(.horizontal, 30).padding(.vertical, 23)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(note.title).font(.system(size: 30, weight: .medium, design: .serif)).textSelection(.enabled)
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.left")
                        Text(note.source)
                        Text("·")
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                    ForEach(note.links, id: \.self) { link in
                        if let url = LinkInfo.safeURL(link) {
                            Button { NSWorkspace.shared.open(url) } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: LinkInfo.repository(link) == nil ? "link" : "chevron.left.forwardslash.chevron.right")
                                        .font(.system(size: 21)).foregroundStyle(Palette.accent).frame(width: 35)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(LinkInfo.repository(link) ?? url.host ?? "Ссылка").font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                        Text(LinkInfo.repository(link) == nil ? link : "Репозиторий на GitHub").font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").foregroundStyle(Palette.accent)
                                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Palette.sage.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text(note.text).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if !note.comment.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("МОЙ КОММЕНТАРИЙ").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.accent)
                            Text(note.comment).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if !note.tags.isEmpty {
                        Text(note.tags.map { "#" + $0 }.joined(separator: "   ")).font(.system(size: 12)).foregroundStyle(Palette.accent).textSelection(.enabled)
                    }
                    Button { draft = note; tagText = note.tags.joined(separator: ", "); editing = true } label: { Label("Редактировать", systemImage: "pencil") }.buttonStyle(.bordered)
                }.padding(.horizontal, 30).padding(.bottom, 30).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Редактировать заметку").font(.system(size: 24, design: .serif))
                TextField("Название", text: $draft.title).textFieldStyle(.roundedBorder)
                Text("ТЕКСТ").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.text).font(.system(size: 14)).frame(minHeight: 150).border(Palette.line)
                TextField("Комментарий: зачем это сохранить?", text: $draft.comment, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder)
                TextField("Теги через запятую", text: $tagText).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Отмена") { editing = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Сохранить") {
                        draft.tags = LinkInfo.tags(tagText)
                        draft.links = LinkInfo.links(in: draft.text, additional: draft.links)
                        draft.updatedAt = Date()
                        if model.save(draft) { editing = false }
                    }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 560).background(Palette.paper)
        }
    }
}

struct ComposerView: View {
    @State var text: String
    @State private var comment = ""
    let source: String
    let save: (String, String) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(Palette.accent)
                Text("В Копилку").font(.system(size: 25, weight: .medium, design: .serif))
                Spacer()
                Text(source).font(.caption).foregroundStyle(Palette.muted)
            }
            TextEditor(text: $text).font(.system(size: 14)).scrollContentBackground(.hidden).padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 10)).frame(height: 170)
            TextField("Зачем сохраняю? Необязательный комментарий", text: $comment, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...3)
            HStack {
                Button("Отмена", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") { save(text, comment) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(25).frame(width: 500).background(Palette.paper).tint(Palette.accent).preferredColorScheme(.light)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Маленькая привычка.\nПолезная коллекция.").font(.system(size: 27, design: .serif))
            VStack(spacing: 12) {
                shortcut("Сохранить выделение", "⌃⇧N")
                shortcut("Сохранить с комментарием", "⌃⇧⌥N")
                shortcut("Открыть Копилку", "⌃⇧I")
                shortcut("Сохранить буфер в окне Копилки", "⌘⇧V")
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.accessibilityGranted ? "Захват выделения разрешён" : "Разрешение на захват выделения", systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised")
                Text("Для горячей клавиши включите Копилку в macOS: Конфиденциальность и безопасность → Универсальный доступ. После этого вернитесь в приложение.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Открыть Универсальный доступ") {
                        CaptureService().requestPermission()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button("Проверить") { model.refreshPermissions() }
                }
            }
            Toggle("Запускать Копилку при входе в macOS", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Text("Закрытие окна оставляет значок в строке меню. Приложение читает выделение только по вашей команде.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Папка данных") { NSWorkspace.shared.open(model.dataFolder) }
                Button("Экспорт заметок") { model.export(model.notes.filter { !$0.isDeleted }) }
                Spacer()
                Button("Готово") { model.settingsVisible = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 560).background(Palette.paper).onAppear { model.refreshPermissions() }
    }
    private func shortcut(_ title: String, _ key: String) -> some View {
        HStack { Text(title).font(.system(size: 12)); Spacer(); Text(key).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.accent) }
    }
}
