import AppKit
import Foundation
import SwiftUI

private let showsDashboardOnLaunch = CommandLine.arguments.contains("--show-dashboard")

struct RateLimitWindow: Codable {
    let usedPercent: Int
    let durationMinutes: Int
    let resetDate: Date?
}

struct ModelUsage: Codable {
    let id: String
    let name: String
    let weekly: RateLimitWindow?
    let short: RateLimitWindow?
}

struct ModelWorkStat: Codable {
    let model: String
    let completedTasks: Int
    let activeSeconds: Int
    let outputTokens: Int
    let loadSharePercent: Int
}

struct CodexSnapshot: Codable {
    let primary: ModelUsage
    let models: [ModelUsage]
    let resetCreditCount: Int
    let fetchedAt: Date
    let taskStats: [ModelWorkStat]?
}

private enum UsageError: LocalizedError {
    case codexNotFound
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "Codex CLI не найден"
        case .timedOut: return "Codex не ответил вовремя"
        case .invalidResponse: return "Codex вернул неполный ответ"
        }
    }
}

private final class CodexUsageProvider {
    func fetch(completion: @escaping (Result<CodexSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                completion(.success(try self.readSnapshot()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func readSnapshot() throws -> CodexSnapshot {
        let codexPath = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let codexPath else { throw UsageError.codexNotFound }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var bufferedData = Data()
        var requestWasSent = false
        var finished = false
        var response: Result<CodexSnapshot, Error>?

        func send(_ value: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))
        }

        func finish(_ result: Result<CodexSnapshot, Error>) {
            guard !finished else { return }
            finished = true
            response = result
            semaphore.signal()
        }

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            lock.lock()
            defer { lock.unlock() }
            bufferedData.append(chunk)

            while let newline = bufferedData.firstRange(of: Data([0x0A])) {
                let line = bufferedData.subdata(in: bufferedData.startIndex..<newline.lowerBound)
                bufferedData.removeSubrange(bufferedData.startIndex..<newline.upperBound)

                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = message["id"] as? Int else {
                    continue
                }

                if id == 1, !requestWasSent {
                    requestWasSent = true
                    send(["method": "initialized", "params": [:]])
                    send(["id": 2, "method": "account/rateLimits/read", "params": NSNull()])
                    continue
                }

                guard id == 2 else { continue }
                do {
                    guard let result = message["result"] as? [String: Any] else {
                        throw UsageError.invalidResponse
                    }
                    finish(.success(try Self.snapshot(from: result)))
                } catch {
                    finish(.failure(error))
                }
            }
        }

        try process.run()
        send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "CodexQuota", "version": "1.3"],
                "capabilities": ["experimentalApi": true]
            ]
        ])

        if semaphore.wait(timeout: .now() + 8) == .timedOut {
            lock.lock()
            finish(.failure(UsageError.timedOut))
            lock.unlock()
        }

        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()

        lock.lock()
        defer { lock.unlock() }
        guard let response else { throw UsageError.invalidResponse }
        return try response.get()
    }

    private static func snapshot(from result: [String: Any]) throws -> CodexSnapshot {
        guard let primaryLimit = result["rateLimits"] as? [String: Any] else {
            throw UsageError.invalidResponse
        }

        var limits: [String: [String: Any]] = [:]
        if let rawLimits = result["rateLimitsByLimitId"] as? [String: Any] {
            for (id, rawLimit) in rawLimits {
                if let limit = rawLimit as? [String: Any] {
                    limits[id] = limit
                }
            }
        }
        if limits["codex"] == nil { limits["codex"] = primaryLimit }

        let models = limits.compactMap { id, limit -> ModelUsage? in
            let windows = [window(from: limit["primary"]), window(from: limit["secondary"])]
            let weekly = windows.compactMap { $0 }.first { $0.durationMinutes >= 10_000 }
            let short = windows.compactMap { $0 }.first { $0.durationMinutes < 10_000 }
            guard weekly != nil || short != nil else { return nil }

            let name = (limit["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (id == "codex" ? "Codex" : id)
            return ModelUsage(id: id, name: name, weekly: weekly, short: short)
        }
        .sorted { ($0.weekly?.usedPercent ?? 0) > ($1.weekly?.usedPercent ?? 0) }

        guard let primary = models.first(where: { $0.id == "codex" }) ?? models.first else {
            throw UsageError.invalidResponse
        }

        let resetCreditCount = ((result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int) ?? 0
        return CodexSnapshot(
            primary: primary,
            models: models,
            resetCreditCount: resetCreditCount,
            fetchedAt: Date(),
            taskStats: taskStats()
        )
    }

    private static func window(from value: Any?) -> RateLimitWindow? {
        guard let value = value as? [String: Any],
              let usedPercent = value["usedPercent"] as? Int,
              let durationMinutes = value["windowDurationMins"] as? Int else {
            return nil
        }

        let resetDate = (value["resetsAt"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return RateLimitWindow(usedPercent: usedPercent, durationMinutes: durationMinutes, resetDate: resetDate)
    }

    private static func taskStats() -> [ModelWorkStat] {
        let sessionsRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        let calendar = Calendar.current
        var turnModels: [String: String] = [:]
        var turnOutputTokens: [String: Int] = [:]
        var completedTurns: [(id: String, model: String, seconds: Int)] = []

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }

            let directory = sessionsRoot
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            guard let files = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let file as URL in files where file.pathExtension == "jsonl" {
                guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for line in contents.split(separator: "\n") {
                    guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let eventType = event["type"] as? String,
                          let payload = event["payload"] as? [String: Any] else { continue }

                    if eventType == "turn_context",
                       let turnID = payload["turn_id"] as? String,
                       let model = payload["model"] as? String {
                        turnModels[turnID] = model
                    }

                    if eventType == "token_usage_record",
                       let turnID = payload["turn_id"] as? String,
                       let usage = payload["turn_token_usage"] as? [String: Any],
                       let outputTokens = usage["output_tokens"] as? Int {
                        turnOutputTokens[turnID] = max(turnOutputTokens[turnID] ?? 0, outputTokens)
                    }

                    if eventType == "event_msg",
                       payload["type"] as? String == "task_complete",
                       let turnID = payload["turn_id"] as? String,
                       let model = turnModels[turnID],
                       let durationMs = payload["duration_ms"] as? Int {
                        completedTurns.append((
                            id: turnID,
                            model: model,
                            seconds: max(0, durationMs / 1_000)
                        ))
                    }
                }
            }
        }

        var totals: [String: (tasks: Int, seconds: Int, outputTokens: Int)] = [:]
        for turn in completedTurns {
            let current = totals[turn.model] ?? (tasks: 0, seconds: 0, outputTokens: 0)
            totals[turn.model] = (
                tasks: current.tasks + 1,
                seconds: current.seconds + turn.seconds,
                outputTokens: current.outputTokens + (turnOutputTokens[turn.id] ?? 0)
            )
        }

        let totalOutputTokens = totals.values.reduce(0) { $0 + $1.outputTokens }
        return totals.map { model, total in
            ModelWorkStat(
                model: model,
                completedTasks: total.tasks,
                activeSeconds: total.seconds,
                outputTokens: total.outputTokens,
                loadSharePercent: totalOutputTokens > 0
                    ? Int((Double(total.outputTokens) / Double(totalOutputTokens) * 100).rounded())
                    : 0
            )
        }
        .sorted {
            $0.activeSeconds == $1.activeSeconds
                ? $0.completedTasks > $1.completedTasks
                : $0.activeSeconds > $1.activeSeconds
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageProvider = CodexUsageProvider()
    private let dashboardState = DashboardState()
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var dashboardWindow: NSWindow?
    private var snapshot: CodexSnapshot? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "snapshot") else { return nil }
            return try? JSONDecoder().decode(CodexSnapshot.self, from: data)
        }
        set {
            guard let snapshot = newValue,
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(data, forKey: "snapshot")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.isVisible = true
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        if let snapshot {
            dashboardState.snapshot = snapshot
            show(snapshot, error: nil)
        } else {
            item.button?.title = "..."
            item.button?.toolTip = "Codex: обновление лимитов"
            item.menu = menu(error: nil)
        }

        refresh()
        refreshTimer = Timer.scheduledTimer(timeInterval: 600, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)

        if showsDashboardOnLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.showDashboard()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    @objc private func refresh() {
        usageProvider.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.dashboardState.snapshot = snapshot
                    self.writeStatusFile(snapshot)
                    self.show(snapshot, error: nil)
                case .failure(let error):
                    if let snapshot = self.snapshot {
                        self.show(snapshot, error: error.localizedDescription)
                    } else {
                        self.statusItem?.button?.title = "--"
                        self.statusItem?.button?.toolTip = "Codex: лимиты недоступны"
                        self.statusItem?.menu = self.menu(error: error.localizedDescription)
                    }
                }
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showDashboard() {
        if dashboardWindow == nil {
            let view = QuotaDashboard(state: dashboardState) { [weak self] in
                self?.refresh()
            }
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Codex Quota"
            window.setContentSize(NSSize(width: 790, height: 720))
            window.minSize = NSSize(width: 700, height: 600)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            dashboardWindow = window
        }

        dashboardWindow?.center()
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func show(_ snapshot: CodexSnapshot, error: String?) {
        let remaining = 100 - (snapshot.primary.weekly?.usedPercent ?? 0)
        statusItem?.button?.title = "\(min(100, max(0, remaining)))%"
        statusItem?.button?.toolTip = "Codex: осталось \(min(100, max(0, remaining)))% недельного лимита"
        statusItem?.isVisible = true
        statusItem?.menu = menu(snapshot: snapshot, error: error)
    }

    private func writeStatusFile(_ snapshot: CodexSnapshot) {
        let remaining = min(100, max(0, 100 - (snapshot.primary.weekly?.usedPercent ?? 0)))
        let models: [[String: Any]] = snapshot.models.map { model in
            let weeklyResetAt: Any = model.weekly?.resetDate.map { Int($0.timeIntervalSince1970) } ?? NSNull()
            let shortResetAt: Any = model.short?.resetDate.map { Int($0.timeIntervalSince1970) } ?? NSNull()
            return [
                "name": model.name,
                "weeklyUsedPercent": model.weekly?.usedPercent ?? NSNull(),
                "weeklyResetAt": weeklyResetAt,
                "shortUsedPercent": model.short?.usedPercent ?? NSNull(),
                "shortDurationMinutes": model.short?.durationMinutes ?? NSNull(),
                "shortResetAt": shortResetAt,
            ]
        }
        let taskStats: [[String: Any]] = (snapshot.taskStats ?? []).map { stat in
            [
                "model": stat.model,
                "completedTasks": stat.completedTasks,
                "activeSeconds": stat.activeSeconds,
                "outputTokens": stat.outputTokens,
                "loadSharePercent": stat.loadSharePercent,
            ]
        }
        let payload: [String: Any] = [
            "remainingPercent": remaining,
            "updatedAt": Int(snapshot.fetchedAt.timeIntervalSince1970),
            "primaryResetAt": snapshot.primary.weekly?.resetDate.map { Int($0.timeIntervalSince1970) } ?? NSNull(),
            "resetCreditCount": snapshot.resetCreditCount,
            "models": models,
            "taskStats": taskStats,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/CodexQuota", isDirectory: true)
        let file = directory.appendingPathComponent("status.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private func menu(snapshot: CodexSnapshot, error: String?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem("Открыть панель", action: #selector(showDashboard), keyEquivalent: ""))
        menu.addItem(.separator())
        let remaining = 100 - (snapshot.primary.weekly?.usedPercent ?? 0)
        menu.addItem(disabled("Осталось на неделю: \(min(100, max(0, remaining)))%"))
        if let weekly = snapshot.primary.weekly {
            menu.addItem(disabled("Codex: \(resetDescription(for: weekly))"))
        }

        let creditText = snapshot.resetCreditCount == 0
            ? "Сбросы лимита: нет"
            : "Сбросы лимита: доступно \(snapshot.resetCreditCount)"
        menu.addItem(disabled(creditText))
        menu.addItem(.separator())
        menu.addItem(disabled("Расход по моделям"))

        for model in snapshot.models {
            if let weekly = model.weekly {
                menu.addItem(disabled("\(model.name): \(weekly.usedPercent)% за неделю"))
                menu.addItem(disabled("  Сброс: \(resetDescription(for: weekly))"))
            }
            if let short = model.short {
                menu.addItem(disabled("\(model.name): \(short.usedPercent)% за \(short.durationMinutes / 60) ч."))
            }
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Нагрузка моделей: доля по сгенерированным токенам"))
        for stat in snapshot.taskStats ?? [] {
            menu.addItem(disabled("\(stat.model): ~\(stat.loadSharePercent)% нагрузки, \(stat.completedTasks) задач, \(stat.outputTokens.formatted()) токенов"))
        }
        menu.addItem(disabled(updateDescription(for: snapshot)))
        if let error {
            menu.addItem(disabled("Не удалось обновить: \(error)"))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Обновить", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(actionItem("Выйти", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func menu(error: String?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem("Открыть панель", action: #selector(showDashboard), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(disabled(error ?? "Загрузка лимитов..."))
        menu.addItem(.separator())
        menu.addItem(actionItem("Обновить", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(actionItem("Выйти", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func resetDescription(for window: RateLimitWindow) -> String {
        guard let resetDate = window.resetDate else { return "время неизвестно" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: resetDate)) (\(relativeTime(until: resetDate)))"
    }

    private func relativeTime(until date: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: date)
        if (components.day ?? 0) > 0 {
            return "через \(components.day ?? 0) д. \(components.hour ?? 0) ч."
        }
        if (components.hour ?? 0) > 0 {
            return "через \(components.hour ?? 0) ч. \(components.minute ?? 0) мин."
        }
        return "через \(max(0, components.minute ?? 0)) мин."
    }

    private func updateDescription(for snapshot: CodexSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Обновлено: \(formatter.string(from: snapshot.fetchedAt))"
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
private let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
