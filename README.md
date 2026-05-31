# hs-tui-launcher

Terminal launcher overlay for local AI command-line tools.

## What it does

`hs-tui-launcher` opens a filterable terminal menu and launches selected entries through PowerShell. The initial menu targets Codex, GitHub Copilot, and Cursor CLI commands.

## Run

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
  - -NoExit
  - -Command
items:
  - name: Codex
    description: Open the Codex CLI in PowerShell
    command: codex
    tags:
      - ai
      - openai
      - cli
```

## Keys

- `up` / `down`: move selection
- type text: filter
- `enter`: launch selected command
- `q`, `esc`, `ctrl+c`: exit
