# Ask Aside

A macOS menu-bar app for asking **quick side-questions** about your current Claude Code
conversation — without cluttering the main task thread.

Select any text on screen (e.g. a term in Claude's answer), a small popup appears near your
cursor, you ask a question, and you get an answer that understands the current conversation.
Close it and your main task thread is untouched.

## How it works

- **Selection capture (EuDic-style):** a global mouse-up watcher captures the selected text
  by synthesizing ⌘C and restoring your clipboard afterward (terminals don't expose their
  selection any other way).
- **Context:** reads the most-recently-modified transcript under `~/.claude/projects/…`,
  and sends a trimmed window of recent turns as context.
- **Model backend (pluggable):** defaults to `claude -p`, reusing your existing Claude Code
  login (**no API key**). Or switch to any **OpenAI-compatible** endpoint (OpenAI, OpenRouter,
  Groq, Together, or a local Ollama/LM Studio server) with a base URL + model + API key. The
  key is stored in the macOS **Keychain**. See `ModelProvider.swift` for the abstraction.
- **Isolation:** each popup runs as its own throwaway `claude` session id in a dedicated
  working dir (`~/.askaside`), so it **never writes to your main task transcript**. Follow-up
  turns `--resume` that same session while the popup is open; closing it discards everything.
  It also runs with `--setting-sources project,local`, so it does **not** inherit your global
  `~/.claude/settings.json` hooks or `~/.claude/CLAUDE.md` — those would otherwise hijack the
  answer (e.g. a Stop hook) while auth (keychain) still works.
- **Context source picker:** the popup header shows which conversation is being used and lets
  you switch, since "most-recent transcript" can guess wrong (e.g. while you're building this
  tool, the most-recent session *is* this one).

## Build

Requires the Xcode Command Line Tools (Swift 5.9+). No full Xcode needed.

```bash
./build.sh            # produces AskAside.app (ad-hoc signed)
open AskAside.app     # launches into the menu bar (no dock icon)
```

## First-run setup

1. Launch the app — a sparkle-magnifier icon appears in your menu bar.
2. Grant **Accessibility** access when prompted (System Settings → Privacy & Security →
   Accessibility → enable **AskAside**). This is required to capture selections. After
   granting, quit and relaunch.

## Usage

- **Select-to-ask:** select text (drag, or double/triple-click), click the popup icon, type
  your question, press Return.
- **Open chat directly:** menu bar → *Open chat* (or ⌘⇧J) opens the chat with no selection.
- **Close:** Esc, the ✕ button, or click outside the popup.
- **Settings:** menu bar → *Settings…* — choose the **backend** (Claude Code, or an
  OpenAI-compatible endpoint), the model, how many recent turns to include as context, and
  toggle select-to-ask.

## Project layout

| File | Responsibility |
|------|----------------|
| `AskAsideApp.swift` | App entry, `MenuBarExtra`, `AppDelegate` |
| `AppState.swift` | Shared services + wiring |
| `SelectionMonitor.swift` | Global mouse-up watch + clipboard-based selection capture |
| `PopupController.swift` / `PopupPanel.swift` | Floating icon + chat panel window |
| `ChatPanelView.swift` / `SettingsView.swift` | SwiftUI UI |
| `ContextLoader.swift` | Transcript discovery + JSONL parsing + context window |
| `ClaudeClient.swift` | `claude -p` subprocess wrapper |
| `ChatSession.swift` | Ephemeral in-memory chat model |

## Notes / limitations (v0.1)

- **Session heuristic:** "most-recently-modified transcript" is the default context, shown in
  the popup header with a picker to switch when it guesses wrong.
- **Latency:** `claude -p` spawns a process (a couple of seconds per answer). An optional
  bring-your-own-API-key backend for faster streaming is a planned follow-up.
- **Ad-hoc signing:** rebuilding may reset the Accessibility grant; re-enable it if capture
  stops working.
