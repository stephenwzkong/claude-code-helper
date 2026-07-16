import SwiftUI

/// Switches between the collapsed icon and the expanded chat, based on controller state.
struct PopupRootView: View {
    @ObservedObject var controller: PopupController
    @ObservedObject var session: ChatSession

    var body: some View {
        Group {
            if controller.isExpanded {
                ChatPanelView(controller: controller, session: session)
            } else {
                CollapsedIconView { controller.expand() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The tiny "ask" bubble shown right after a selection.
struct CollapsedIconView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}

/// The full ephemeral chat.
struct ChatPanelView: View {
    @ObservedObject var controller: PopupController
    @ObservedObject var session: ChatSession
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contextBar
            Divider()
            if !session.selectedText.isEmpty {
                selectionPreview
                Divider()
            }
            transcript
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
            Text("Ask Aside").font(.callout.weight(.semibold))
            Spacer()
            Button {
                controller.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var contextLabel: String {
        if !session.useContext { return "No context" }
        return session.contextSource?.projectName ?? "No conversation found"
    }

    /// Shows which conversation is used as context (or "No context"), with a picker to
    /// switch or turn context off, before the chat starts. Makes the source visible
    /// instead of silent — including the auto "no context" case for browser selections.
    private var contextBar: some View {
        HStack(spacing: 6) {
            Image(systemName: session.useContext
                  ? "bubble.left.and.text.bubble.right.fill" : "bubble.left")
                .font(.caption2).foregroundStyle(.secondary)

            if session.isContextLocked {
                Text(contextLabel)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Menu {
                    Button("No context") { session.disableContext() }
                    if !session.availableConversations.isEmpty {
                        Divider()
                        ForEach(session.availableConversations) { ref in
                            Button {
                                session.selectConversation(ref)
                            } label: {
                                Text("\(ref.projectName)  ·  \(Self.relativeTime(ref.modified))")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(contextLabel).font(.caption2).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer(minLength: 0)
            if session.useContext, let src = session.contextSource {
                Text(Self.relativeTime(src.modified))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private static func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var selectionPreview: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "text.quote").foregroundStyle(.secondary).font(.caption)
            Text(session.selectedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.messages.isEmpty && !session.isLoading {
                        Text(session.selectedText.isEmpty
                             ? "Ask a quick question about your current Claude Code conversation."
                             : "Ask about the selected text.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    }
                    ForEach(session.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if session.isLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.footnote).foregroundStyle(.secondary)
                        }.id("loading")
                    }
                    if let errorText = session.errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: session.isLoading) { loading in
                if loading { withAnimation { proxy.scrollTo("loading", anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = draft
        draft = ""
        session.send(text)
        inputFocused = true
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 32) }
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    message.role == .user ? AnyShapeStyle(Color.accentColor.opacity(0.9))
                                          : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }
}
