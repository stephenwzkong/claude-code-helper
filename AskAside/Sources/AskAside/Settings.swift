import Foundation
import Combine

/// Which model backend answers questions.
enum Backend: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case openAICompatible = "OpenAI-compatible"
    var id: String { rawValue }
}

/// User preferences. Simple values persist in UserDefaults; secrets (API key) go in Keychain.
final class AppSettings: ObservableObject {
    private enum Keys {
        static let backend = "backend"
        static let claudeModel = "claudeModel"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
        static let contextTurns = "contextTurns"
        static let selectionMonitorEnabled = "selectionMonitorEnabled"
    }
    private static let apiKeyAccount = "openai-compatible-api-key"

    /// Active model backend.
    @Published var backend: Backend {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: Keys.backend) }
    }

    /// Model alias for Claude Code (`claude --model`): "sonnet", "opus", "haiku", etc.
    @Published var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: Keys.claudeModel) }
    }

    /// Base URL for an OpenAI-compatible endpoint (OpenAI, OpenRouter, Groq, Ollama, …).
    @Published var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
    }

    /// Model name for the OpenAI-compatible endpoint (e.g. "gpt-4o-mini", "llama3.1").
    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }

    /// API key for the OpenAI-compatible endpoint — stored in the Keychain, not UserDefaults.
    @Published var openAIApiKey: String {
        didSet { Keychain.set(openAIApiKey, account: Self.apiKeyAccount) }
    }

    /// How many recent transcript turns to include as context.
    @Published var contextTurns: Int {
        didSet { UserDefaults.standard.set(contextTurns, forKey: Keys.contextTurns) }
    }

    /// Whether the global select-to-ask monitor is active.
    @Published var selectionMonitorEnabled: Bool {
        didSet { UserDefaults.standard.set(selectionMonitorEnabled, forKey: Keys.selectionMonitorEnabled) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.backend: Backend.claudeCode.rawValue,
            Keys.claudeModel: "sonnet",
            Keys.openAIBaseURL: "https://api.openai.com/v1",
            Keys.openAIModel: "gpt-4o-mini",
            Keys.contextTurns: 12,
            Keys.selectionMonitorEnabled: true,
        ])
        self.backend = Backend(rawValue: defaults.string(forKey: Keys.backend) ?? "") ?? .claudeCode
        self.claudeModel = defaults.string(forKey: Keys.claudeModel) ?? "sonnet"
        self.openAIBaseURL = defaults.string(forKey: Keys.openAIBaseURL) ?? "https://api.openai.com/v1"
        self.openAIModel = defaults.string(forKey: Keys.openAIModel) ?? "gpt-4o-mini"
        self.openAIApiKey = Keychain.get(Self.apiKeyAccount)
        self.contextTurns = defaults.integer(forKey: Keys.contextTurns)
        self.selectionMonitorEnabled = defaults.bool(forKey: Keys.selectionMonitorEnabled)
    }

    /// The model name to send, based on the active backend.
    var activeModel: String {
        backend == .claudeCode ? claudeModel : openAIModel
    }

    /// Build the provider for the active backend.
    func makeProvider() -> ModelProvider {
        switch backend {
        case .claudeCode:
            return ClaudeCLIProvider()
        case .openAICompatible:
            return OpenAICompatibleProvider(baseURL: openAIBaseURL, apiKey: openAIApiKey)
        }
    }

    static let claudeModels = ["sonnet", "opus", "haiku"]
}
