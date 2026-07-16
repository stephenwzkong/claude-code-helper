import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Model backend") {
                Picker("Backend", selection: $settings.backend) {
                    ForEach(Backend.allCases) { backend in
                        Text(backend.rawValue).tag(backend)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.backend {
                case .claudeCode:
                    Picker("Model", selection: $settings.claudeModel) {
                        ForEach(AppSettings.claudeModels, id: \.self) { model in
                            Text(model.capitalized).tag(model)
                        }
                    }
                    Text("Reuses your existing Claude Code login via `claude -p` — no API key needed.")
                        .font(.caption).foregroundStyle(.secondary)

                case .openAICompatible:
                    TextField("Base URL", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API key", text: $settings.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Works with OpenAI, OpenRouter, Groq, Together, or a local server "
                         + "(Ollama/LM Studio: http://localhost:11434/v1). The key is stored in your Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Context") {
                Stepper(value: $settings.contextTurns, in: 2...40) {
                    Text("Include last \(settings.contextTurns) conversation turns")
                }
                Text("How much of your current Claude Code conversation to send as context.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Select-to-ask") {
                Toggle("Enable selection popup", isOn: $settings.selectionMonitorEnabled)
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.accessibilityTrusted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.accessibilityTrusted
                         ? "Accessibility access granted."
                         : "Accessibility access needed to capture selections.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !appState.accessibilityTrusted {
                        Button("Grant…") { appState.requestAccessibility() }
                    }
                    Button("Refresh") { appState.refreshAccessibilityStatus() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}
