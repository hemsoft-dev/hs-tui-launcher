# hs-tui-launcher

Terminal launcher overlay for local AI command-line tools.

## What it does

`hs-tui-launcher` opens a compact numbered menu for Codex, GitHub Copilot, and Cursor. Each row shows the model and reasoning effort before launching the selected target in the same console.

## Run

```powershell
.\run.ps1
```

Direct Go execution opens the same terminal picker:

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

The app loads `.hs-tui-launcher.yaml` from the current directory when present, otherwise it falls back to built-in defaults.

```yaml
title: HemSoft TUI Launcher
shell: powershell.exe
shell_args:
  - -NoLogo
  - -Command
items:
  - name: Codex
    description: Open the Codex CLI
    command: codex
    model: gpt-5.5
    reasoning_effort: high
    tags:
      - ai
      - openai
      - cli
```

## Keys

- `1`, `2`, `3`: launch that numbered target
- `q`, `esc`, `ctrl+c`: exit
