# hs-tui-launcher

Terminal launcher overlay for local AI command-line tools.

## What it does

`hs-tui-launcher` opens a compact numbered menu for Codex, GitHub Copilot,
Cursor, Claude Code, Moonshot AI, OpenCode, OpenRouter, and Ollama. Each row
shows the model and reasoning effort. The platform wrapper exits the Go picker
before handing off to the selected CLI in the same console.

## Run

```powershell
.\run.ps1
```

On macOS and Linux:

```sh
./run.sh
```

Both wrappers use a bundled native executable when present and fall back to
`go run .`. The Unix wrapper also requires Python 3 to validate the launcher's
structured selection and start the selected CLI without shell evaluation.

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
      - name: GPT 5.6 Sol High
        description: Start Codex with GPT-5.6 Sol at high reasoning
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: GPT 5.6 Sol High/Fast
        description: Start Codex with GPT-5.6 Sol at high reasoning and fast service
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol
          -c 'service_tier="fast"'
          -c 'model_reasoning_effort="high"'
      - name: GPT 5.6 Luna
        description: Start Codex with GPT-5.6 Luna at medium reasoning
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-luna
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="medium"'
      - name: GPT 5.6 Luna/Fast
        description: Start Codex with GPT-5.6 Luna at medium reasoning and fast service
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-luna
          -c 'service_tier="fast"'
          -c 'model_reasoning_effort="medium"'
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
      - name: Qwen 3.8 27B (AMD Ollama)
        description: Use AMD Ollama over Tailscale with 262K context
        command: '& "$repoRoot\scripts\Start-CopilotAmdOllama.ps1"'
```

The Codex choices rely on the global Anvil setup in `~/.codex/config.toml` and
`~/.codex/agents/anvil.toml`; launcher flags can start a fresh session, resume
the last session, open the resume picker, or start GPT-5.6 Sol and GPT-5.6 Luna
with the selected reasoning and service tier. Codex starts in the directory
where `l` or `run.ps1` was invoked. GitHub Copilot opens a model submenu with
GPT-5.5, GPT-5.6 Sol, Claude Opus 5, and Qwen 3.8 27B on the `amd` Ollama
server. The AMD wrapper uses
Copilot's OpenAI-compatible BYOK mode with offline mode enabled. It reserves
245,760 prompt tokens and 16,384 output tokens, matching Qwen's 262,144-token
context window, and restores all provider environment variables after Copilot
exits.
Home's PowerShell profile also exposes `copamd` for the same path outside the
launcher. Reload the profile with `. $PROFILE`, then run `copamd`. The first
Copilot request can take several minutes because the CLI sends a large agent
prompt; the validated cold request contained about 41,000 prompt tokens.
Cursor starts with automatic CLI updates disabled to avoid PowerShell download
progress corrupting the launcher handoff; run `cursor-agent update` explicitly
when an update is wanted.
Moonshot AI launches Kimi K3 through OpenCode against `https://api.moonshot.ai/v1`
and charges the associated Moonshot API credits. It reads the API key from
`KIMI_K3_API_KEY` and injects only an inline OpenCode provider definition; it
does not write the key or modify the global OpenCode configuration.
OpenCode opens a model submenu led by GLM-5.3-Flash on OpenCode Go
(`opencode-go/glm-5.3-flash`), which uses twice the normal OpenCode Go allowance,
followed by the other OpenCode Go choices and two machine-specific choices:
Qwen 3.8 27B on `home` and Qwen 3.8 27B on `amd`.
The `home` choice uses the local Ollama server with a 131,072-token limit. The
`amd` choice connects directly to its Home-only Tailscale Ollama endpoint with a
262,144-token limit. It checks that the server advertises the selected model
before starting OpenCode and does not depend on SSH or Lemonade. Both OpenCode
launchers set Qwen's reasoning effort to `medium`; the Copilot-to-AMD launcher
uses the same default.
OpenRouter opens a separate submenu ordered as Kimi K3, Qwen 3.8 Max,
GLM-5.3-Flash, Fusion, DeepSeek V4 Flash 0731, Muse Spark V1.2, and Seedream
5.0 Pro.
Ollama opens a local-model submenu through OpenCode. Its first choice is
Qwen 3.8 27B, using the installed `qwen3.8:27b` model at
`http://localhost:11434/v1`. The OpenCode submenu exposes the same local choice
so it can be selected beside the AMD-hosted copy. These wrappers inject provider
definitions for one process and do not modify the global OpenCode configuration.
Parenthesized prices list the current OpenRouter catalog input/output rate per
million tokens. OpenRouter can route multi-provider models to endpoints with
different rates, so actual charges may differ. Fusion is variable because it
bills the underlying panel and judge calls. Seedream uses per-image pricing:
`$0.045` for 1K or `$0.09` for 2K. Its endpoint also lists `$0.003` per input
reference image, but the launcher currently sends text prompts only. The image
action asks for a prompt, resolution, and aspect ratio; shows the estimated
charge for confirmation; saves the returned image under
`Pictures\OpenRouter\Seedream`;
and opens it. It reads `OPENROUTER_API_KEY` from the environment. The menu reads
the prompt interactively. Paste the path to a UTF-8 text file at the description
prompt to use that file's contents as the image prompt. Paths copied with
matching single or double quotes are accepted. The script does not persist the
key or prompt.
The other wrappers update OpenCode's
persisted TUI model before launch so the selected model is active immediately.

Run a no-cost Seedream request preview directly:

```powershell
.\scripts\Start-OpenRouterImage.ps1 `
  -Prompt 'A red panda astronaut' `
  -Resolution 2K `
  -AspectRatio 16:9 `
  -DryRun
```

The `-Prompt` argument also accepts a text-file path:

```powershell
.\scripts\Start-OpenRouterImage.ps1 `
  -Prompt 'D:\prompts\red-panda.txt' `
  -Resolution 2K `
  -AspectRatio 16:9 `
  -DryRun
```

## Keys

- `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`: launch that numbered target
- `q`, `esc`, `ctrl+c`: exit
