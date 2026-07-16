import Foundation

/// A single conversation turn extracted from a Claude Code transcript.
struct Turn {
    let role: String   // "user" or "assistant"
    let text: String
}

/// A selectable reference to a recent Claude Code conversation (for the source picker).
struct ConversationRef: Identifiable, Hashable {
    let url: URL          // transcript .jsonl
    let cwdPath: String   // decoded working directory the session ran in
    let modified: Date

    var id: URL { url }
    var projectName: String { URL(fileURLWithPath: cwdPath).lastPathComponent }
}

/// The context gathered for a side-question.
struct ConversationContext {
    let projectPath: String    // encoded project dir name the transcript came from
    let transcriptURL: URL
    let turns: [Turn]

    /// Render the turns as a plain-text transcript suitable for a prompt.
    func rendered() -> String {
        turns.map { turn in
            let who = turn.role == "assistant" ? "Assistant" : "User"
            return "\(who): \(turn.text)"
        }.joined(separator: "\n\n")
    }
}

/// Locates the active Claude Code transcript and extracts a trimmed context window.
///
/// Claude Code stores each session as JSONL at
/// `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`. The active session's
/// file is the most-recently-modified one. We exclude our own side-chat sessions
/// (run under a dedicated working dir) so the tool never reads its own transcript.
struct ContextLoader {
    /// Per-message character cap so one giant message can't dominate the window.
    private let perMessageCharCap = 4000

    private var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Find the newest transcript across all projects, excluding AskAside's own sessions.
    func latestTranscriptURL() -> URL? {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, date: Date)?
        for dir in projectDirs {
            // Skip our own side-chat project dir (see ClaudeClient.workingDirectory).
            if dir.lastPathComponent.lowercased().contains("askaside") { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if newest == nil || date > newest!.date {
                    newest = (file, date)
                }
            }
        }
        return newest?.url
    }

    /// Load the latest conversation, keeping the last `maxTurns` text turns.
    func latestContext(maxTurns: Int) -> ConversationContext? {
        guard let url = latestTranscriptURL() else { return nil }
        return context(from: url, maxTurns: maxTurns)
    }

    /// Load a specific transcript, keeping the last `maxTurns` text turns.
    func context(from url: URL, maxTurns: Int) -> ConversationContext? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var turns: [Turn] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let turn = parseLine(String(line)) else { continue }
            turns.append(turn)
        }
        let trimmed = Array(turns.suffix(maxTurns))
        guard !trimmed.isEmpty else { return nil }
        return ConversationContext(
            projectPath: url.deletingLastPathComponent().lastPathComponent,
            transcriptURL: url,
            turns: trimmed
        )
    }

    /// List the most recent conversations (newest first) for the source picker,
    /// excluding AskAside's own side-chat sessions.
    func recentConversations(limit: Int) -> [ConversationRef] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var refs: [ConversationRef] = []
        for dir in projectDirs {
            if dir.lastPathComponent.lowercased().contains("askaside") { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let cwd = firstCwd(in: file) ?? decodeProjectDir(dir.lastPathComponent)
                refs.append(ConversationRef(url: file, cwdPath: cwd, modified: modified))
            }
        }
        return Array(refs.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// Read only the first chunk of a transcript to find its `cwd` field cheaply.
    private func firstCwd(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let range = text.range(of: "\"cwd\":\"") else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let cwd = String(rest[..<end])
        return cwd.isEmpty ? nil : cwd
    }

    /// Fallback label when no cwd is found: turn "-Users-name-Documents-foo" into a path-ish string.
    private func decodeProjectDir(_ name: String) -> String {
        "/" + name.split(separator: "-").joined(separator: "/")
    }

    /// Parse one JSONL line into a Turn, or nil if it carries no user/assistant text.
    private func parseLine(_ line: String) -> Turn? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let role = message["role"] as? String,
              role == "user" || role == "assistant"
        else { return nil }

        let text = extractText(from: message["content"])
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return Turn(role: role, text: String(clean.prefix(perMessageCharCap)))
    }

    /// Content may be a plain string or an array of blocks; keep only human-readable text.
    private func extractText(from content: Any?) -> String {
        if let s = content as? String { return s }
        guard let blocks = content as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for block in blocks {
            let type = block["type"] as? String
            if type == "text", let t = block["text"] as? String {
                parts.append(t)
            }
            // Skip tool_use / tool_result / thinking blocks — they're noise for a side-question.
        }
        return parts.joined(separator: "\n")
    }
}
