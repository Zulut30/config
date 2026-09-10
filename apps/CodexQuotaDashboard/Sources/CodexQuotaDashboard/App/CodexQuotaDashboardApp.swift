import AppKit
import SwiftUI

@main
struct CodexQuotaDashboardApp: App {
    @NSApplicationDelegateAdaptor(DashboardAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Codex Quota", id: "dashboard") {
            DashboardView()
                .frame(minWidth: 1_020, minHeight: 700)
        }
        .defaultSize(width: 1_180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class DashboardAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    private let quotaURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/CodexQuota/status.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshStatusItem()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItem()
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--show-dashboard") {
            presentDashboard()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentDashboard()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        let image = NSImage(
            systemSymbolName: "chart.bar.xaxis",
            accessibilityDescription: "Codex Quota"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.toolTip = "Codex Quota: открыть панель"
        statusItem = item
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        guard
            let data = try? Data(contentsOf: quotaURL),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = payload["remainingPercent"] as? NSNumber
        else {
            button.title = "--"
            return
        }
        let percent = max(0, min(100, value.intValue))
        button.title = "\(percent)%"
        button.toolTip = "Codex: осталось \(percent)% недельного лимита"
    }

    @objc private func statusItemClicked() {
        refreshStatusItem()
        presentDashboard()
    }

    private func presentDashboard() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.title = "Codex Quota"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1_180, height: 780))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
