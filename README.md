# hs-tui-launcher

Terminal launcher overlay for local AI command-line tools.

## What it does

`hs-tui-launcher` opens a compact numbered menu for Codex, GitHub Copilot,
Cursor, Claude Code, and OpenCode. Each row shows the model and reasoning
effort. The PowerShell wrapper exits the Go picker before handing off to the
selected CLI in the same console.

## Run

```powershell
.\run.ps1
```

Direct Go execution opens the picker without the PowerShell handoff:

```powershell
go run .
```

Print the resolved config:

```powershell
go run . --print-config
```

Use a specific config:

```powershell
go run . --config .\.hs-tui-launcher.yaml
```

## Configure

The app loads `.hs-tui-launcher.yaml` from the current directory when present,
otherwise it falls back to built-in defaults.

```yaml
title: HemSoft TUI Launcher
shell: powershell.exe
shell_args:
  - -NoLogo
  - -Command
items:
  - name: Codex
    description: Open the Codex CLI
    model: gpt-5.6-sol
    reasoning_effort: high
    tags:
      - ai
      - openai
      - cli
    choices:
      - name: Start fresh
        description: Open a new Codex CLI session
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: Resume last
        description: Resume the last Codex CLI session
        command: >-
          codex resume --last --dangerously-bypass-approvals-and-sandbox
          -m gpt-5.6-sol
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: Resume picker
        description: Choose a Codex CLI session to resume
        command: >-
          codex resume --dangerously-bypass-approvals-and-sandbox
          -m gpt-5.6-sol
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
  - name: GitHub Copilot
    description: Open GitHub Copilot CLI
    model: select model
    reasoning_effort: default
    tags:
      - ai
      - github
      - cli
    choices:
      - name: GPT-5.5
        description: Use GPT-5.5 with high reasoning effort
        command: >-
          copilot --allow-all --model gpt-5.5 --reasoning-effort high
      - name: GPT-5.6 Sol
        description: Use GPT-5.6 Sol with high reasoning effort
        command: >-
          copilot --allow-all --model gpt-5.6-sol --reasoning-effort high
      - name: Claude Opus 5
        description: Use Claude Opus 5 with xhigh reasoning effort
        command: >-
          copilot --allow-all --model claude-opus-5 --reasoning-effort xhigh
```

The Codex choices rely on the global Anvil setup in `~/.codex/config.toml` and
`~/.codex/agents/anvil.toml`; launcher flags can start a fresh session, resume
the last session, or open the resume picker with sandbox bypass, model, service
tier, and reasoning effort. Codex starts in the directory where `l` or `run.ps1`
was invoked. GitHub Copilot opens a model submenu with GPT-5.5, GPT-5.6 Sol,
and Claude Opus 5, and passes the selected model and reasoning effort to the
CLI.
Cursor starts with automatic CLI updates disabled to avoid PowerShell download
progress corrupting the launcher handoff; run `cursor-agent update` explicitly
when an update is wanted.
OpenCode opens an OpenCode Go model submenu ordered as Kimi K3, Qwen 3.8 Max,
GLM 5.2, and DeepSeek V4 Flash. OpenRouter opens a separate model submenu
ordered as Kimi K3, Qwen 3.8 Max, GLM 5.2, Fusion, DeepSeek V4 Flash, and Muse
Spark V1.2.
Parenthesized prices list input/output cost per million tokens; Fusion is
variable because it bills the underlying panel and judge calls. The wrapper
updates OpenCode's persisted TUI model before launch so the selected model is
active immediately.

## Keys

- `1`, `2`, `3`, `4`, `5`, `6`: launch that numbered target
- `q`, `esc`, `ctrl+c`: exit
