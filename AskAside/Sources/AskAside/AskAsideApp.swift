import SwiftUI
import AppKit

@main
struct AskAsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("Ask Aside", systemImage: "sparkle.magnifyingglass") {
            Button("Open chat") { appState.popup.showChatCentered() }
                .keyboardShortcut("j", modifiers: [.command, .shift])

            Divider()

            Toggle("Select-to-ask", isOn: Binding(
                get: { appState.settings.selectionMonitorEnabled },
                set: { appState.settings.selectionMonitorEnabled = $0 }
            ))

            if !appState.accessibilityTrusted {
                Button("Grant Accessibility access…") { appState.requestAccessibility() }
            }

            if #available(macOS 14.0, *) {
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
            } else {
                Button("Settings…") { openSettingsWindow() }
                    .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            Button("Quit Ask Aside") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: appState.settings, appState: appState)
        }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // `showSettingsWindow:` is available on macOS 13+.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no dock icon, don't steal focus.
        NSApp.setActivationPolicy(.accessory)

        let state = AppState.shared
        state.startMonitoring()

        // Prompt for Accessibility on first launch so selection capture can work.
        if !SelectionMonitor.isTrusted {
            SelectionMonitor.requestTrust()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshAccessibilityStatus()
    }
}
