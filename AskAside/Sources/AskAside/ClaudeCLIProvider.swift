import Foundation

/// Model backend that reuses the user's existing Claude Code login via the headless
/// `claude -p` CLI — no API key, no extra billing.
///
/// Stateless: each call sends the full turn history as a single prompt and runs a throwaway
/// session in `~/.askaside`, so it never touches the user's main task transcript. It also
/// loads only project/local settings, so it doesn't inherit the user's global hooks or
/// CLAUDE.md (which would otherwise hijack the answer).
struct ClaudeCLIProvider: ModelProvider {

    enum ProviderError: LocalizedError {
        case binaryNotFound
        case launchFailed(String)
        case claudeError(String)
        case badOutput

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "Couldn't find the `claude` command. Install Claude Code and make sure it's on your PATH."
            case .launchFailed(let m): return "Failed to launch claude: \(m)"
            case .claudeError(let m):  return m
            case .badOutput:           return "Couldn't parse the response from claude."
            }
        }
    }

    /// Load only project/local settings, NOT the user's global config (hooks, CLAUDE.md).
    /// Auth (keychain/OAuth) is unaffected, so the Claude Code login still works.
    private static let isolationArgs = ["--setting-sources", "project,local"]

    func send(_ request: ChatRequest) async throws -> String {
        let args = [
            "-p", Self.promptText(from: request.turns),
            "--output-format", "json",
            "--model", request.model,
            "--append-system-prompt", request.system,
        ] + Self.isolationArgs
        return try await Self.run(args)
    }

    /// Render the turn history into a single prompt. The first user turn already carries the
    /// conversation context + selection; later turns are folded in as labeled text.
    private static func promptText(from turns: [ChatTurn]) -> String {
        if turns.count == 1 { return turns[0].text }
        var parts: [String] = []
        for turn in turns.dropLast() {
            let who = turn.role == .assistant ? "Assistant" : "User"
            parts.append("\(who): \(turn.text)")
        }
        if let last = turns.last {
            parts.append("User: \(last.text)\n\nAnswer the last question.")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Process plumbing

    private static var workingDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".askaside", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func run(_ args: [String]) async throws -> String {
        guard let binaryURL = resolveClaudeBinary() else { throw ProviderError.binaryNotFound }
        let workDir = workingDirectory

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = binaryURL
                process.arguments = args
                process.currentDirectoryURL = workDir

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = augmentedPATH(existing: env["PATH"])
                process.environment = env

                let stdout = Pipe(); let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProviderError.launchFailed(error.localizedDescription))
                    return
                }

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                do {
                    let text = try parse(outData, errData, exitCode: process.terminationStatus)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func parse(_ outData: Data, _ errData: Data, exitCode: Int32) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            let err = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if exitCode != 0 {
                throw ProviderError.claudeError(err.isEmpty ? "claude exited with code \(exitCode)." : err)
            }
            throw ProviderError.badOutput
        }
        if let isError = obj["is_error"] as? Bool, isError {
            throw ProviderError.claudeError((obj["result"] as? String) ?? "claude reported an error.")
        }
        guard let result = obj["result"] as? String else { throw ProviderError.badOutput }
        return result
    }

    // MARK: - Binary / PATH resolution

    private static let commonBinDirs = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "\(NSHomeDirectory())/.claude/local",
    ]

    static func resolveClaudeBinary() -> URL? {
        let fm = FileManager.default
        for dir in commonBinDirs {
            let candidate = "\(dir)/claude"
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        if let path = shellResolve("command -v claude"), fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func shellResolve(_ command: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    static func augmentedPATH(existing: String?) -> String {
        var parts = existing?.split(separator: ":").map(String.init) ?? []
        for dir in commonBinDirs where !parts.contains(dir) {
            parts.append(dir)
        }
        return parts.joined(separator: ":")
    }
}
