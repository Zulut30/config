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

final class DashboardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        presentDashboard()
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
        true
    }

    private func presentDashboard() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.title = "Codex Quota"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 1_180, height: 780))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
