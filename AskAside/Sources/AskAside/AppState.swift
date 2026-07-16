import AppKit
import Combine

/// Shared, app-wide services and wiring. Single instance for the whole process.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings = AppSettings()
    let contextLoader = ContextLoader()
    let popup: PopupController
    let monitor = SelectionMonitor()

    /// True once we've confirmed Accessibility access (needed for selection capture).
    @Published var accessibilityTrusted = SelectionMonitor.isTrusted

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let session = ChatSession(contextLoader: contextLoader, settings: settings)
        self.popup = PopupController(session: session)

        // Selection captured → show the icon near the cursor.
        monitor.onSelection = { [weak self] text, point, sourceBundleId in
            self?.popup.showIcon(selectedText: text, at: point, sourceBundleId: sourceBundleId)
        }
        monitor.isEnabled = settings.selectionMonitorEnabled

        // Keep the monitor's gate in sync with the setting.
        settings.$selectionMonitorEnabled
            .sink { [weak self] enabled in self?.monitor.isEnabled = enabled }
            .store(in: &cancellables)
    }

    /// Called at launch to begin watching for selections.
    func startMonitoring() {
        monitor.start()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = SelectionMonitor.isTrusted
    }

    func requestAccessibility() {
        SelectionMonitor.requestTrust()
    }
}
