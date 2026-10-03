# hs-tui-launcher

[![CI](https://github.com/HemSoft/hs-tui-launcher/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/HemSoft/hs-tui-launcher/actions/workflows/ci.yml)

Terminal launcher overlay for local AI command-line tools.

## What it does

`hs-tui-launcher` opens a compact shortcut menu for Pi, Codex, Antigravity,
GitHub Copilot, Moonshot AI, OpenCode, OpenRouter, Ollama, Cursor, and
Claude Code. Each row shows the model and reasoning effort. The platform
wrapper exits the Go picker before handing off to the selected CLI in the
same console.

## Run

```powershell
.\run.ps1
```

On macOS and Linux:

```sh
./run.sh
```

Both wrappers use a bundled native executable when present and fall back to
`go run .`. `run.ps1` retains Windows PowerShell 5.1 compatibility; PowerShell 7
(`pwsh`) is also supported. The Unix wrapper requires Python 3 to validate the
launcher's structured selection and start the selected CLI without shell
evaluation. Building or using the fallback requires the Go version declared in
`go.mod`.

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
  - name: Pi
    description: Open the Pi CLI
    model: select model
    reasoning_effort: default
    tags:
      - ai
      - pi
      - openai-codex
      - cli
    choices:
      - name: GPT 6 Astra ($10/$1/$50)
        description: openai-codex/gpt-6-astra
        command: pi --model openai-codex/gpt-6-astra --thinking medium
      - name: GPT 6.1 Sol High ($2/$0.1/$10)
        description: openai-codex/gpt-6.1-sol at high reasoning
        command: pi --model openai-codex/gpt-6.1-sol --thinking high
      - name: GPT 6 Luna Max ($0.1/$0.01/$0.5)
        description: openai-codex/gpt-6-luna at max reasoning
        command: pi --model openai-codex/gpt-6-luna --thinking max
      - name: Copilot: Gemini 3.8 Flash ($0.75/$0.075/$3.75)
        description: github-copilot/gemini-3.8-flash
        command: pi --model github-copilot/gemini-3.8-flash
      - name: Copilot: GPT 5.6 Luna Max ($0.2/$0.02/$1.2)
        description: github-copilot/gpt-5.6-luna at max reasoning
        command: pi --model github-copilot/gpt-5.6-luna --thinking max
      - name: Copilot: GPT 5.6 Sol High ($4/$0.4/$20)
        description: github-copilot/gpt-5.6-sol at high reasoning
        command: pi --model github-copilot/gpt-5.6-sol --thinking high
      - name: Copilot: GPT 6 Astra Medium ($10/$1/$50)
        description: github-copilot/gpt-6-astra at medium reasoning
        command: pi --model github-copilot/gpt-6-astra --thinking medium
      - name: 'Copilot: Opus 5.5 High ($4/$0.2/$20)'
        description: github-copilot/claude-opus-5.5 at high reasoning
        command: pi --model github-copilot/claude-opus-5.5 --thinking high
      - name: GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)
        description: opencode-go/glm-5.3-flash
        command: pi --model opencode-go/glm-5.3-flash
      - name: DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)
        description: opencode-go/deepseek-v4.1-flash
        command: pi --model opencode-go/deepseek-v4.1-flash
      - name: Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)
        description: opencode-go/muse-spark-1.3-contributor
        command: pi --model opencode-go/muse-spark-1.3-contributor
      - name: 'OpenRouter: DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)'
        description: openrouter/deepseek/deepseek-v4.1-flash
        command: pi --model openrouter/deepseek/deepseek-v4.1-flash
      - name: MiMo V2.6 Flash ($0.14/$0.0028/$0.28)
        description: opencode-go/mimo-v2.6-flash
        command: pi --model opencode-go/mimo-v2.6-flash
      - name: MiMo V2.6 Pro ($0.435/$0.003625/$0.87)
        description: opencode-go/mimo-v2.6-pro
        command: pi --model opencode-go/mimo-v2.6-pro
      - name: 'OpenRouter: MiMo V2.6 Flash ($0.14/$0.0028/$0.28)'
        description: openrouter/xiaomi/mimo-v2.6-flash
        command: pi --model openrouter/xiaomi/mimo-v2.6-flash
      - name: 'OpenRouter: MiMo V2.6 Pro ($0.435/$0.0036/$0.87)'
        description: openrouter/xiaomi/mimo-v2.6-pro
        command: pi --model openrouter/xiaomi/mimo-v2.6-pro
      - name: 'OpenRouter: Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)'
        description: openrouter/qwen/qwen3.8-omni-flash
        command: pi --model openrouter/qwen/qwen3.8-omni-flash
      - name: 'OpenRouter: Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)'
        description: openrouter/prism-ml/ternary-bonsai-2-27b
        command: pi --model openrouter/prism-ml/ternary-bonsai-2-27b
      - name: 'OpenRouter: GLM-5.3-FlashX ($0.37/$0.09/$1.25)'
        description: openrouter/z-ai/glm-5.3-flashx
        command: pi --model openrouter/z-ai/glm-5.3-flashx
  - name: Codex
    description: Open the Codex CLI
    model: gpt-6-astra
    reasoning_effort: high
    tags:
      - ai
      - openai
      - cli
    choices:
      - name: Start fresh
        description: Open a new Codex CLI session
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-6-astra
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: Resume last
        description: Resume the last Codex CLI session
        command: >-
          codex resume --last --dangerously-bypass-approvals-and-sandbox
          -m gpt-6-astra
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: Resume picker
        description: Choose a Codex CLI session to resume
        command: >-
          codex resume --dangerously-bypass-approvals-and-sandbox
          -m gpt-6-astra
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: GPT 5.6 Sol High ($4/$0.4/$20)
        description: Start Codex with GPT-5.6 Sol at high reasoning
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="high"'
      - name: GPT 5.6 Sol High/Fast ($4/$0.4/$20)
        description: Start Codex with GPT-5.6 Sol at high reasoning and fast service
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol
          -c 'service_tier="fast"'
          -c 'model_reasoning_effort="high"'
      - name: GPT 5.6 Luna ($0.2/$0.02/$1.2)
        description: Start Codex with GPT-5.6 Luna at medium reasoning
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-luna
          -c 'service_tier="default"'
          -c 'model_reasoning_effort="medium"'
      - name: GPT 5.6 Luna/Fast ($0.2/$0.02/$1.2)
        description: >-
          Start Codex with GPT-5.6 Luna at medium reasoning and fast service
        command: >-
          codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-luna
          -c 'service_tier="fast"'
          -c 'model_reasoning_effort="medium"'
  - name: Antigravity
    description: Open the Antigravity CLI
    command: agy --dangerously-skip-permissions
    reasoning_effort: default
    tags:
      - ai
      - google
      - cli
  - name: GitHub Copilot
    description: Open GitHub Copilot CLI
    model: select model
    reasoning_effort: default
    tags:
      - ai
      - github
      - cli
    choices:
      - name: GPT-5.5 ($5/$0.5/$30)
        description: Use GPT-5.5 with high reasoning effort
        command: >-
          copilot --allow-all --model gpt-5.5 --reasoning-effort high
      - name: GPT-5.6 Sol ($4/$0.4/$20)
        description: Use GPT-5.6 Sol with high reasoning effort
        command: >-
          copilot --allow-all --model gpt-5.6-sol --reasoning-effort high
      - name: Claude Opus 5 ($5/$0.5/$25)
        description: Use Claude Opus 5 with xhigh reasoning effort
        command: >-
          copilot --allow-all --model claude-opus-5 --reasoning-effort xhigh
      - name: Auto (server-routed)
        description: Let GitHub Copilot choose the model for each task
        command: copilot --allow-all --model auto
```

The Codex choices rely on the global Anvil setup in `~/.codex/config.toml` and
`~/.codex/agents/anvil.toml`; launcher flags can start a fresh session, resume
the last session, open the resume picker, or start GPT-5.6 Sol and GPT-5.6 Luna
with the selected reasoning and service tier. Codex starts in the directory
where `l` or `run.ps1` was invoked. Pi opens the first menu and a model submenu
led by GPT-6 Astra, GPT-6.1 Sol High, and GPT-6 Luna Max. These
Codex-subscription models launch via
`pi --model openai-codex/<model>` with an optional `--thinking <level>` flag.
Copilot-hosted models include Gemini 3.8 Flash, GPT 5.6 Luna at max reasoning,
GPT 5.6 Sol at high reasoning, GPT 6 Astra at medium reasoning, and Opus 5.5
at high reasoning. They launch via `pi --model github-copilot/<model>`.  Pi removed its Antigravity provider in
version 0.71.0, so the launcher does not offer Antigravity as a Pi model route.
The remaining choices use OpenCode Go or OpenRouter through
`pi --model <provider>/<model>`. MiMo V2.6 Flash and Pro each have routes through
both providers; Qwen 3.8 Omni Flash, Ternary Bonsai 2 27B, and GLM-5.3-FlashX
use OpenRouter. Model choice labels show per-million-token prices as
`($input/$cached input/$output)`.
GitHub Copilot opens a model submenu with GPT-5.5, GPT-5.6 Sol, Claude Opus
5, and Copilot's server-routed Auto mode. Auto is launched through the
supported Copilot CLI command `copilot --allow-all --model auto`; it is not
listed under Pi because Pi's GitHub Copilot provider does not expose
`github-copilot/auto`. The standalone AMD wrapper uses Copilot's
OpenAI-compatible BYOK mode with offline mode enabled. It reserves
245,760 prompt tokens and 16,384 output tokens, matching Qwen's 262,144-token
context window, and restores all provider environment variables after Copilot
exits.
Home's PowerShell profile also exposes `copamd` for the same path outside the
launcher. Reload the profile with `. $PROFILE`, then run `copamd`. The first
Copilot request can take several minutes because the CLI sends a large agent
prompt; the validated cold request contained about 41,000 prompt tokens.
Antigravity starts the `agy` agent CLI with permission prompts auto-approved.
Cursor starts with automatic CLI updates disabled to avoid PowerShell download
progress corrupting the launcher handoff; run `cursor-agent update` explicitly
when an update is wanted.
Moonshot AI launches Kimi K3 through OpenCode against `https://api.moonshot.ai/v1`
and charges the associated Moonshot API credits. It reads the API key from
`KIMI_K3_API_KEY` and injects only an inline OpenCode provider definition; it
does not write the key or modify the global OpenCode configuration.
OpenCode opens a model submenu led by GLM-5.3-Flash on OpenCode Go
(`opencode-go/glm-5.3-flash`), which uses twice the normal OpenCode Go allowance,
followed by the other OpenCode Go choices, including DeepSeek V4.1 Flash,
Muse Spark V1.3 Contributor, MiMo V2.6 Flash, and MiMo V2.6 Pro,
and two machine-specific choices: Qwen 3.8 27B on `home` and Qwen 3.8 27B on
`amd`.
The `home` choice uses the local Ollama server with a 131,072-token limit. The
`amd` choice connects directly to its Home-only Tailscale Ollama endpoint with a
262,144-token limit. It checks that the server advertises the selected model
before starting OpenCode and does not depend on SSH or Lemonade. Both OpenCode
launchers set Qwen's reasoning effort to `medium`; the Copilot-to-AMD launcher
uses the same default.
OpenRouter opens a separate submenu with OpenRouter equivalents for every model
in the Pi menu, plus Kimi K3, Qwen 3.8 Max, Claude Opus 5.5, Fusion, Muse
Spark V1.3 and V1.2, MiMo V2.6 Flash and Pro, Qwen 3.8 Omni Flash, Ternary
Bonsai 2 27B, GLM-5.3-FlashX, Seedream 5.0 Pro, and Seed Audio 1.0. MiMo Flash and Pro are
available here and in OpenCode Go. The provider variants in Pi map to one
OpenRouter entry per model. DeepSeek V4.1 Flash has weekday peak windows, so its displayed rate
is a base-to-peak range.
Ollama opens a local-model submenu through OpenCode. Its first choice is
Qwen 3.8 27B, using the installed `qwen3.8:27b` model at
`http://localhost:11434/v1`. The OpenCode submenu exposes the same local choice
so it can be selected beside the AMD-hosted copy. These wrappers inject provider
definitions for one process and do not modify the global OpenCode configuration.
Parenthesized prices list current catalog input/cached-input/output rates per
million tokens at the base tier. `n/a` means the catalog does not publish a
cached-input rate. OpenRouter rates were checked against the
[OpenRouter model catalog](https://openrouter.ai/api/v1/models) on October 1, 2026.
The OpenCode Go GLM-5.3-Flash choice shows its usage-equivalent half-rate because that model consumes twice the normal allowance. OpenRouter can
apply discounts, scheduled rates, and provider-specific routing, so actual
charges may differ. Fusion is variable because it
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

### Seed Audio voices

OpenRouter choice `M`, immediately after Seedream at `L`, runs
[Start-OpenRouterAudio.ps1](D:/github/HemSoft/hs-tui-launcher/scripts/Start-OpenRouterAudio.ps1)
with `bytedance-seed/seed-audio-1-0`. It uses the dedicated speech endpoint,
shows numbered voice choices with descriptions, asks where to save the MP3,
and asks for approval before spending credits. Press Enter at the folder prompt
to use `Music/OpenRouter/SeedAudio`, or enter another folder. New folders are
created and checked for write access before the paid request. [Seed Audio pricing](https://openrouter.ai/bytedance-seed/seed-audio-1-0)
is $0.15 per generated minute, up to 120 seconds or $0.30 at the published rate.

Voice profiles `narrator`, `guide`, and `character` are setup slots, not
provider-supplied voices. The numbered menu shows `1. narrator`, `2. guide`,
and `3. character` in the default registry. Enter the number to select a voice,
or press Enter to choose narrator. An unconfigured voice asks for a licensed
WAV or MP3 reference clip and permission to upload it. The saved profile reuses that
same clip on subsequent requests. Profiles are stored outside the repository
in `~/.config/hs-tui-launcher/seed-audio-voices.json`. This is stateless cloning,
not guaranteed identical output. OpenRouter does not publish a Seed speaker-ID
list; a known valid ID can also be stored with `-SaveVoice` and `-SpeakerId`.

Configure and preview a reference voice with the
[audio script](D:/github/HemSoft/hs-tui-launcher/scripts/Start-OpenRouterAudio.ps1):

```powershell
.\scripts\Start-OpenRouterAudio.ps1 `
  -SaveVoice narrator -ReferenceAudio 'D:\voices\narrator.wav' `
  -ReferenceText 'The exact words spoken in the sample.' -Consent

.\scripts\Start-OpenRouterAudio.ps1 `
  -Voice narrator -Prompt 'Use the reference speaker. Say: Welcome aboard.' -DryRun
```

Remove `-DryRun` to generate with confirmation. `OPENROUTER_API_KEY` is required
only for generation. Dry runs do not upload the sample or spend credits.
`-ListVoices` lists profile status. `-PromptOnly` explicitly opts out of identity
consistency, and `-NoOpen` suppresses playback. `-OutputDirectory` supplies an
output folder without prompting; command-line voice names still work with
`-Voice`. The output sidecar records the
model, profile, reference hash, and generation ID without saving prompts or
reference transcripts. No automatic retries are made.

See the [research notes](D:/github/HemSoft/hs-tui-launcher/research/2026-09-29-seed-audio-openrouter.md)
for API evidence, reference-recording advice, undocumented controls, and live
testing limits.

`jev.ps1` calls [OpenRouter's Decisions API](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request) with the special
`~typesafe/jev-latest` model. It accepts a state plus a structured choice,
yes/no, or score question and writes one JSON response to stdout. It reads
`OPENROUTER_API_KEY` from the environment and never prints the key.

A simple choice request looks like this:

```powershell
jev.ps1 `
  -State 'Choose where to deploy this build.' `
  -Question 'Which target is the better fit?' `
  -Criteria @(
    'mini=Prefer local network access',
    'air=Prefer a portable macOS target'
  )
```

For a chat model or another program, pass the complete request as JSON. This
avoids shell quoting around larger state objects:

```powershell
$request = @{
  model = '~typesafe/jev-latest'
  state = @{ task = 'Choose a deployment target'; options = @('mini', 'air') }
  questions = @{
    target = @{
      type = 'choice'
      instructions = 'Choose the better target.'
      criteria = @{ mini = 'Local network access'; air = 'Portable macOS target' }
    }
  }
} | ConvertTo-Json -Depth 10

$request | pwsh -NoProfile -File (Get-Command jev.ps1).Source -StdinJson
```

The response is JSON containing `answers`, the resolved model, and usage. That
makes `jev.ps1` suitable for a chat model to call, inspect, and use in its next
step. Use `-DryRun` to inspect the request without spending credits. The
underlying endpoint is [`https://openrouter.ai/api/alpha/decisions`](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request), not the
normal chat-completions endpoint.

### Pi skill and native tool

The repository also contains the Pi integration sources:

- `pi/consult-jev/SKILL.md` defines when a typed second opinion is useful and
  keeps Jev advisory; it excludes deterministic work, permission decisions, and
  human-approval gates.
- `pi/jev-decide/index.ts` registers the native `jev_decide` tool. It resolves
  OpenRouter authentication through Pi, redacts likely secrets, bounds the
  request, supports cancellation, and validates answer keys, probabilities,
  confidence, usage, and the resolved model before returning them.
- `pi/jev-decide/jev-core.test.ts` can be run without spending credits:

  ```powershell
  node --experimental-strip-types --test pi/jev-decide/*.test.ts
  ```

Install the two source files under `~/.pi/agent/extensions/jev-decide/` and the
skill under `~/.pi/agent/skills/consult-jev/` (or load them with `-e` and
`--skill` for a one-off test). The native tool is advisory only: its answer
cannot grant permissions, bypass tests or policy, or approve destructive or
production actions. Start with shadow-mode comparisons against the parent
agent's actual route.

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

## Completion audio

The repository-local [Pi completion extension](D:/github/HemSoft/hs-tui-launcher/.pi/extensions/done-sound.ts)
plays [assets/done.mp3](D:/github/HemSoft/hs-tui-launcher/assets/done.mp3)
after an interactive task fully settles, including any retries or queued
follow-ups. It is a Pi lifecycle hook, not a Git hook. Git has no event for an
assistant finishing work without a commit.

Pi loads it when this trusted project starts or resources are reloaded with
`/reload`. No global Pi configuration or Git hooks are changed. Other
repositories, nested repositories, and headless runs do not play the sound.
Set `HS_TUI_LAUNCHER_DONE_SOUND=0` before starting Pi to mute it.

The [playback script](D:/github/HemSoft/hs-tui-launcher/scripts/Play-DoneSound.ps1)
uses `ffplay` on Windows and Linux or `afplay` on macOS without opening a player
window. PowerShell is required. Playback errors produce a warning without
failing the completed task. Test the extension without playback with
`node --test .pi/tests/done-sound.test.mjs` on Node.js 24 or newer.

## Keys

- `1`–`9`: launch the corresponding item in the current menu
- `a`–`z` (case-insensitive): launch the tenth item and beyond in the main menu
  or a choice submenu (`a` picks the 10th, `b` the 11th, and so on)
- `↑`/`↓` or `j`/`k` + `enter`: pick a target with the cursor; moving past
  either end wraps to the other
- `q`, `esc`, `ctrl+c`: exit (`esc` returns from a choice submenu to the main
  menu first)
