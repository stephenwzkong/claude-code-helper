# claude-code-helper

Small tools that make working in [Claude Code](https://claude.com/claude-code) nicer.

## [Ask Aside](AskAside/) — select-to-ask popup

A macOS menu-bar app for quick side-questions about your current Claude Code
conversation, without cluttering the main task thread. Select any text (EuDic-style),
a floating icon appears near the cursor, ask a question, and get an answer that
understands your conversation — then close it, leaving the main thread untouched.

- **Context-aware:** reads your current Claude Code transcript; a header picker lets you
  switch conversations, and it auto-skips context for selections outside terminals/editors.
- **Pluggable model backend:** reuses your Claude Code login via `claude -p` (no API key),
  or any OpenAI-compatible endpoint (OpenAI, OpenRouter, Groq, Ollama/LM Studio).
- **Isolated:** the side-chat never writes to your main task transcript.

See **[AskAside/README.md](AskAside/README.md)** for build, setup, and usage.

```bash
cd AskAside
./setup-dev-cert.sh   # one-time: stable signing identity
./build.sh            # produces AskAside.app
open AskAside.app
```

## Requirements

- macOS 13+
- Xcode Command Line Tools (Swift 5.9+)
- [Claude Code](https://claude.com/claude-code) installed and logged in (for the default backend)
