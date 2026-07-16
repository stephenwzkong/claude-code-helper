import Foundation

/// One turn in a side-chat, as sent to a model backend.
struct ChatTurn {
    enum Role: String { case user, assistant }
    let role: Role
    let text: String
}

/// A stateless request to a model backend: a system directive plus the full turn history
/// (the last turn is the new user question). Providers are stateless — they receive the
/// whole history each call — so any backend (CLI or HTTP) works the same way.
struct ChatRequest {
    let system: String
    let turns: [ChatTurn]
    let model: String
}

/// A pluggable model backend. Implementations: `ClaudeCLIProvider` (reuses Claude Code),
/// `OpenAICompatibleProvider` (any OpenAI-compatible HTTP endpoint).
protocol ModelProvider {
    func send(_ request: ChatRequest) async throws -> String
}
