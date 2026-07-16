import Foundation
import Combine

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

/// Ephemeral, in-memory chat for a single popup. Discarded when the popup closes.
///
/// The first turn injects the conversation context and the selected text; later turns just
/// carry the new question. The full history is re-sent to the model backend each turn
/// (stateless), so any provider — Claude Code CLI or an OpenAI-compatible endpoint — works
/// identically. Nothing is written to the user's main task transcript.
@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMessage] = []          // for display
    @Published var selectedText: String = ""
    @Published var isLoading = false
    @Published var errorText: String?

    /// Recent conversations available as context, and the one currently chosen.
    @Published var availableConversations: [ConversationRef] = []
    @Published var contextSource: ConversationRef?

    /// Whether to send any conversation context at all. Off by default for selections made
    /// outside a terminal/editor (e.g. a browser).
    @Published var useContext: Bool = true

    private let contextLoader: ContextLoader
    private let settings: AppSettings

    /// The history sent to the model. The first user turn carries the context preamble; the
    /// displayed `messages` show only the user's typed question.
    private var modelTurns: [ChatTurn] = []

    private static let systemDirective = """
    You are a quick side-assistant answering a small follow-up question, often about an \
    ongoing Claude Code conversation. Answer concisely and directly. Prefer 1–4 sentences \
    unless more detail is clearly needed. Do not use tools or read files; answer from the \
    provided context and your own knowledge.
    """

    init(contextLoader: ContextLoader, settings: AppSettings) {
        self.contextLoader = contextLoader
        self.settings = settings
    }

    /// Reset for a brand-new popup with the given selection (may be empty).
    /// `useContext` decides whether the Claude Code conversation is attached by default.
    func reset(selectedText: String, useContext: Bool) {
        messages = []
        modelTurns = []
        errorText = nil
        isLoading = false
        self.selectedText = selectedText
        self.useContext = useContext
        availableConversations = contextLoader.recentConversations(limit: 15)
        contextSource = useContext ? availableConversations.first : nil
    }

    /// Switch which conversation is used as context (only meaningful before the first turn).
    func selectConversation(_ ref: ConversationRef) {
        guard messages.isEmpty else { return }
        useContext = true
        contextSource = ref
    }

    /// Answer with no conversation context (only meaningful before the first turn).
    func disableContext() {
        guard messages.isEmpty else { return }
        useContext = false
        contextSource = nil
    }

    /// True once the chat has started and the context source is locked in.
    var isContextLocked: Bool { !messages.isEmpty }

    func send(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        let isFirstTurn = modelTurns.isEmpty
        let selection = selectedText
        let contextTurns = settings.contextTurns
        let wantsContext = useContext
        let sourceURL = contextSource?.url

        // What the model sees for this user turn.
        let modelText: String
        if isFirstTurn {
            let context: ConversationContext? = wantsContext
                ? (sourceURL.flatMap { contextLoader.context(from: $0, maxTurns: contextTurns) }
                   ?? contextLoader.latestContext(maxTurns: contextTurns))
                : nil
            modelText = Self.buildFirstPrompt(question: trimmed, selection: selection, context: context)
        } else {
            modelText = trimmed
        }

        messages.append(ChatMessage(role: .user, text: trimmed))
        modelTurns.append(ChatTurn(role: .user, text: modelText))
        errorText = nil
        isLoading = true

        let request = ChatRequest(system: Self.systemDirective,
                                  turns: modelTurns,
                                  model: settings.activeModel)
        let provider = settings.makeProvider()

        Task {
            do {
                let answer = try await provider.send(request)
                self.modelTurns.append(ChatTurn(role: .assistant, text: answer))
                self.messages.append(ChatMessage(role: .assistant, text: answer))
            } catch {
                // Roll back the unanswered user turn so a retry doesn't duplicate it.
                if !self.modelTurns.isEmpty { self.modelTurns.removeLast() }
                self.errorText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            self.isLoading = false
        }
    }

    /// Compose the first prompt: conversation context, the selected text, then the question.
    static func buildFirstPrompt(question: String, selection: String,
                                 context: ConversationContext?) -> String {
        var parts: [String] = []
        if let context {
            parts.append("""
            Here is recent context from my ongoing Claude Code conversation:

            <conversation>
            \(context.rendered())
            </conversation>
            """)
        }
        let sel = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sel.isEmpty {
            parts.append("I selected this text and want to ask about it:\n\n<selection>\n\(sel)\n</selection>")
        }
        parts.append("My question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}
