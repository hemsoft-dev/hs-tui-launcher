# hs-tui-launcher

[![Set it Free Loop](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FHemSoft%2Fhs-tui-launcher%2Fmain%2Fsfl.json&query=%24.version&prefix=v&label=Set%20it%20Free%20Loop&color=FFD700&style=flat&logo=githubactions&logoColor=white)](https://github.com/HemSoft/set-it-free-loop)
<!-- SFL_BADGE: auto-updated by deploy-workflow.ps1 -->
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
```

The Codex choices rely on the global Anvil setup in `~/.codex/config.toml` and
`~/.codex/agents/anvil.toml`; launcher flags can start a fresh session, resume
the last session, or open the resume picker with sandbox bypass, model, service
tier, and reasoning effort. Codex starts in the directory where `l` or `run.ps1`
was invoked. GitHub Copilot opens a model submenu with GPT-5.5 first and GPT-5.6
Sol second, and passes the selected model and reasoning effort to the CLI.
OpenCode opens a model submenu for OpenCode Zen models. OpenRouter opens a
separate model submenu, with GLM 5.2 as the first choice. The wrapper updates
OpenCode's persisted TUI model before launch so the selected model is active
immediately.

## Keys

- `1`, `2`, `3`, `4`, `5`, `6`: launch that numbered target
- `q`, `esc`, `ctrl+c`: exit
