import AppKit
import ApplicationServices

/// Watches for text-selection gestures anywhere on screen and reports the selected text.
///
/// macOS doesn't hand a live selection to another app, so we capture it EuDic-style, using
/// two mechanisms for reliability:
///   1. Accessibility (`AXSelectedText`) — reads the selection directly from the focused
///      element. Instant, no clipboard involved. Works in many native apps and browsers.
///   2. Synthetic ⌘C fallback — for apps that don't expose AX selection (e.g. terminals):
///      copy, read the pasteboard, then restore the previous clipboard contents.
/// Requires the Accessibility permission (for global monitoring + synthetic keystrokes).
final class SelectionMonitor {

    /// Called on the main thread with the captured text, the screen location of the cursor,
    /// and the bundle id of the app the selection came from (nil if unknown).
    var onSelection: ((String, NSPoint, String?) -> Void)?

    /// Gate from settings; when false the monitor stays installed but does nothing.
    var isEnabled = true

    private var upMonitor: Any?
    private var dragMonitor: Any?
    private var downMonitor: Any?
    private var didDrag = false
    private var downLocation: NSPoint?

    /// A tiny drag still counts as a selection; anything past this is "dragged".
    private let dragThreshold: CGFloat = 4

    // MARK: - Lifecycle

    func start() {
        guard upMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.didDrag = false
            self?.downLocation = NSEvent.mouseLocation
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.didDrag = true
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }
    }

    func stop() {
        [upMonitor, dragMonitor, downMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        upMonitor = nil; dragMonitor = nil; downMonitor = nil
    }

    // MARK: - Accessibility permission

    /// Whether the app is trusted for Accessibility (needed for capture to work).
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompt the user to grant Accessibility access (opens System Settings pane).
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Gesture detection

    private func handleMouseUp(_ event: NSEvent) {
        guard isEnabled, Self.isTrusted else { return }

        let upLocation = NSEvent.mouseLocation
        // Treat it as a selection if the user dragged (flag OR moved far enough) or
        // multi-clicked (double = word, triple = line). Distance is checked directly so a
        // dropped/coalesced drag event doesn't cause us to miss the gesture.
        let movedFarEnough = downLocation.map { hypot($0.x - upLocation.x, $0.y - upLocation.y) > dragThreshold } ?? false
        let isSelectionGesture = didDrag || movedFarEnough || event.clickCount >= 2
        didDrag = false
        guard isSelectionGesture else { return }

        // Which app owns the selection — captured now, before any async work. Our app is an
        // accessory and never activates, so the frontmost app is still the source.
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Let the target app finish updating its own selection before we read it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if let text = self.captureSelection(), !text.isEmpty {
                self.onSelection?(text, upLocation, sourceBundleId)
            }
        }
    }

    // MARK: - Capture (AX fast-path, then ⌘C fallback)

    private func captureSelection() -> String? {
        if let text = axSelectedText() { return text }
        return copySelection()
    }

    /// Read the selection straight from the focused UI element via Accessibility.
    private func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = focused else { return nil }
        let element = focusedElement as! AXUIElement

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Synthesize ⌘C, read the pasteboard, then restore the prior contents.
    private func copySelection() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let changeCountBefore = pasteboard.changeCount

        postCommandC()

        // Poll for the target app to write the copied text.
        var copied: String?
        let deadline = Date().addingTimeInterval(0.40)
        while Date() < deadline {
            if pasteboard.changeCount != changeCountBefore {
                copied = pasteboard.string(forType: .string)
                break
            }
            usleep(15_000) // 15ms
        }

        restore(saved, to: pasteboard)
        return copied?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Post a full ⌘-down, C-down, C-up, ⌘-up sequence. Posting the real modifier key
    /// (not just the command flag) is what makes the copy register in apps that inspect
    /// the actual modifier state, such as terminals.
    private func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 0x37 // left Command
        let cKey: CGKeyCode = 0x08   // 'c'

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand

        let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        cDown?.flags = .maskCommand

        let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        cUp?.flags = .maskCommand

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        let tap: CGEventTapLocation = .cghidEventTap
        cmdDown?.post(tap: tap)
        cDown?.post(tap: tap)
        cUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }

    // MARK: - Pasteboard save / restore

    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        var copies: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            copies.append(copy)
        }
        return copies
    }

    private func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
