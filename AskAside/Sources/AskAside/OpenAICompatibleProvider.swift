import Foundation

/// Model backend for any OpenAI-compatible `/chat/completions` endpoint. One provider
/// covers OpenAI, OpenRouter, Groq, Together, Fireworks, and local servers like Ollama
/// or LM Studio — the user just sets the base URL, API key, and model name.
struct OpenAICompatibleProvider: ModelProvider {
    let baseURL: String
    let apiKey: String

    enum ProviderError: LocalizedError {
        case missingConfig(String)
        case badURL
        case http(Int, String)
        case badOutput

        var errorDescription: String? {
            switch self {
            case .missingConfig(let m): return m
            case .badURL:               return "The API base URL isn't valid."
            case .http(let code, let m): return "Request failed (HTTP \(code)): \(m)"
            case .badOutput:            return "Couldn't parse the model's response."
            }
        }
    }

    func send(_ request: ChatRequest) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ProviderError.missingConfig("Add an API key in Settings to use this model.")
        }
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.missingConfig("Set a model name in Settings.")
        }
        guard let url = endpoint() else { throw ProviderError.badURL }

        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        for turn in request.turns {
            messages.append(["role": turn.role.rawValue, "content": turn.text])
        }
        let body: [String: Any] = [
            "model": request.model,
            "messages": messages,
            "stream": false,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderError.http(status, Self.errorMessage(from: data))
        }
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw ProviderError.badOutput }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalize the base URL (with or without trailing slash / `/v1`) to the completions path.
    private func endpoint() -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/chat/completions")
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["error"] as? String { return msg }
        }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "unknown error"
    }
}
