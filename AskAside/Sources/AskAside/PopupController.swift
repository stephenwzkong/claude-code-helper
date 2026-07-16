import AppKit
import SwiftUI
import Combine

/// Owns the floating popup: shows a small icon near a selection, expands into the chat
/// panel on click, and tears everything down on dismiss.
@MainActor
final class PopupController: ObservableObject {
    /// Drives the SwiftUI view between the collapsed icon and the full chat.
    @Published var isExpanded = false

    let session: ChatSession

    private var panel: FloatingPanel?
    private var escMonitor: Any?
    private var clickAwayMonitor: Any?

    private let collapsedSize = NSSize(width: 44, height: 36)
    private let expandedSize = NSSize(width: 380, height: 460)

    init(session: ChatSession) {
        self.session = session
    }

    // MARK: - Presentation

    /// Show the collapsed icon near a captured selection.
    func showIcon(selectedText: String, at screenPoint: NSPoint, sourceBundleId: String?) {
        // Only attach the Claude Code conversation as context when the selection came from a
        // terminal/editor; a browser or other app defaults to no context.
        session.reset(selectedText: selectedText,
                      useContext: ContextApps.isContextApp(sourceBundleId))
        isExpanded = false
        let panel = ensurePanel()
        let origin = NSPoint(x: screenPoint.x + 8, y: screenPoint.y - collapsedSize.height - 8)
        panel.setContentSize(collapsedSize)
        panel.setFrameOrigin(clamp(origin: origin, size: collapsedSize))
        panel.orderFront(nil) // visible but not key — don't steal focus yet
    }

    /// Open the chat directly (used by the menu's "Open chat" for testing without a selection).
    func showChatCentered() {
        session.reset(selectedText: "", useContext: true)
        _ = ensurePanel()
        expand(anchorTopLeft: centeredTopLeft())
    }

    /// Grow from icon to chat and take key focus so the user can type.
    func expand(anchorTopLeft: NSPoint? = nil) {
        let panel = ensurePanel()
        isExpanded = true
        let topLeft = anchorTopLeft ?? NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(expandedSize)
        let origin = NSPoint(x: topLeft.x, y: topLeft.y - expandedSize.height)
        panel.setFrameOrigin(clamp(origin: origin, size: expandedSize))
        // Activate so the panel reliably comes forward and the text field takes focus,
        // even when triggered from the menu bar while another app is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func dismiss() {
        removeDismissMonitors()
        panel?.orderOut(nil)
        isExpanded = false
    }

    // MARK: - Panel construction

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: collapsedSize))
        let root = PopupRootView(controller: self, session: session)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    // MARK: - Dismiss handling

    private func installDismissMonitors() {
        removeDismissMonitors()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismiss()
                return nil
            }
            return event
        }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
        }
    }

    private func removeDismissMonitors() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        escMonitor = nil
        clickAwayMonitor = nil
    }

    // MARK: - Geometry

    /// Keep a window of `size` fully on the screen that contains the mouse.
    private func clamp(origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        var x = origin.x, y = origin.y
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func centeredTopLeft() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.midX - expandedSize.width / 2
        let y = screen.midY + expandedSize.height / 2
        return NSPoint(x: x, y: y)
    }
}
