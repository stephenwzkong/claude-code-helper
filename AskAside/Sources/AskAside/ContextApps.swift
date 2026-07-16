import Foundation

/// Classifies the app a selection came from. A selection made in a terminal or code editor
/// is likely FROM a Claude Code session, so the conversation transcript is relevant context.
/// Selections elsewhere (browsers, notes, chat apps) default to "no context" — just the
/// selected text and the question.
enum ContextApps {
    /// Exact bundle identifiers of terminals / editors that commonly host Claude Code.
    private static let bundleIds: Set<String> = [
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "org.tabby",
        // Editors with integrated terminals
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
    ]

    /// Bundle-id prefixes to match whole families (e.g. all JetBrains IDEs).
    private static let bundlePrefixes: [String] = [
        "com.jetbrains.",
        "com.google.android.studio",
    ]

    /// True when a selection from `bundleId` should carry the Claude Code conversation as
    /// context. A nil bundle id (e.g. the menu's "Open chat", with no source app) defaults
    /// to true — the user opened it deliberately over their work.
    static func isContextApp(_ bundleId: String?) -> Bool {
        guard let id = bundleId else { return true }
        if bundleIds.contains(id) { return true }
        return bundlePrefixes.contains { id.hasPrefix($0) }
    }
}
