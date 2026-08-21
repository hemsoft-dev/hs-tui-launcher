#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
native_launcher="$repo_root/hs-tui-launcher"
launcher_mode=native

if [ ! -x "$native_launcher" ]; then
    if ! command -v go >/dev/null 2>&1; then
        printf '%s\n' 'hs-tui-launcher is missing and no Go executable was found on PATH.' >&2
        exit 1
    fi
    launcher_mode=go
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Python 3 is required to launch the selected command.' >&2
    exit 1
fi

original_dir=$PWD
selection_file=$(mktemp "${TMPDIR:-/tmp}/hs-tui-launcher.XXXXXX")
trap 'rm -f -- "$selection_file"' EXIT HUP INT TERM

cd "$repo_root"
if [ "$launcher_mode" = native ]; then
    "$native_launcher" --selection-file "$selection_file" "$@"
else
    go run . --selection-file "$selection_file" "$@"
fi
launcher_exit=$?
cd "$original_dir"

if [ "$launcher_exit" -ne 0 ] || [ ! -s "$selection_file" ]; then
    exit "$launcher_exit"
fi

# The handoff program is passed with -c so python3 keeps the caller's stdin;
# a heredoc would replace stdin and the exec'd CLI would inherit it instead
# of the terminal, failing with "stdin is not a terminal".
handoff_script=$(cat <<'PY'
import json
import os
import shutil
import sys

selection_path, original_dir = sys.argv[1:]
with open(selection_path, encoding="utf-8") as stream:
    selection = json.load(stream)

if not isinstance(selection, dict):
    raise SystemExit("Selection file has invalid shape: expected a JSON object.")

allowed = {"name", "executable", "args", "working_dir", "env"}
unsupported = set(selection) - allowed
if unsupported:
    name = sorted(unsupported)[0]
    raise SystemExit(f"Selection file has invalid shape: unsupported property '{name}'.")

name = selection.get("name")
executable = selection.get("executable")
arguments = selection.get("args", [])
working_dir = selection.get("working_dir") or original_dir
environment_entries = selection.get("env", [])

if not isinstance(name, str) or not name.strip():
    raise SystemExit("Selection file has invalid shape: name is required.")
if not isinstance(executable, str) or not executable.strip():
    raise SystemExit("Selection file has invalid shape: executable is required.")
if not isinstance(arguments, list) or not all(isinstance(value, str) for value in arguments):
    raise SystemExit("Selection file has invalid shape: args must be a JSON array of strings.")
if not isinstance(working_dir, str):
    raise SystemExit("Selection file has invalid shape: working_dir must be a string.")
if not isinstance(environment_entries, list) or not all(isinstance(value, str) for value in environment_entries):
    raise SystemExit("Selection file has invalid shape: env must be a JSON array of strings.")

environment = os.environ.copy()
for entry in environment_entries:
    variable, separator, value = entry.partition("=")
    if not separator or not variable.strip():
        raise SystemExit("Selection file has invalid shape: env entries must use NAME=VALUE.")
    environment[variable] = value

command = [executable, *arguments]
if executable.lower().endswith(".ps1"):
    powershell = shutil.which("pwsh")
    if powershell is None:
        raise SystemExit(f"'{name}' requires PowerShell 7, but pwsh was not found on PATH.")
    command = [powershell, "-NoLogo", "-File", executable, *arguments]

os.chdir(working_dir)
os.execvpe(command[0], command, environment)
PY
)
python3 -c "$handoff_script" "$selection_file" "$original_dir"
