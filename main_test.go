package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

func TestWriteSelectionEmitsStructuredInvocation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:       "Tool",
		Command:    `tool --flag 'value with spaces' "literal; metacharacter"`,
		WorkingDir: `C:\work`,
		Env:        []string{"EXAMPLE=value"},
	}

	if err := writeSelection(path, item); err != nil {
		t.Fatalf("writeSelection returned error: %v", err)
	}

	selection := readSelection(t, path)
	if _, ok := selection["command"]; ok {
		t.Fatal("selection JSON included legacy command property")
	}
	if got := selection["name"]; got != "Tool" {
		t.Fatalf("name = %#v", got)
	}
	if got := selection["executable"]; got != "tool" {
		t.Fatalf("executable = %#v", got)
	}

	args, ok := selection["args"].([]any)
	if !ok {
		t.Fatalf("args = %#v, want array", selection["args"])
	}
	wantArgs := []string{"--flag", "value with spaces", "literal; metacharacter"}
	if len(args) != len(wantArgs) {
		t.Fatalf("len(args) = %d, want %d", len(args), len(wantArgs))
	}
	for index, want := range wantArgs {
		if got := args[index]; got != want {
			t.Fatalf("args[%d] = %#v, want %q", index, got, want)
		}
	}
}

func TestWriteSelectionResolvesRepoRootPowerShellInvocation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:    "OpenRouter GLM 5.2",
		Command: `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter z-ai/glm-5.2`,
	}

	if err := writeSelection(path, item); err != nil {
		t.Fatalf("writeSelection returned error: %v", err)
	}

	selection := readSelection(t, path)
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}
	wantExecutable := filepath.Join(workingDir, "scripts", "Start-OpenCode.ps1")
	if got := selection["executable"]; got != wantExecutable {
		t.Fatalf("executable = %#v, want %q", got, wantExecutable)
	}

	args, ok := selection["args"].([]any)
	if !ok {
		t.Fatalf("args = %#v, want array", selection["args"])
	}
	wantArgs := []string{"openrouter", "z-ai/glm-5.2"}
	if len(args) != len(wantArgs) {
		t.Fatalf("len(args) = %d, want %d", len(args), len(wantArgs))
	}
	for index, want := range wantArgs {
		if got := args[index]; got != want {
			t.Fatalf("args[%d] = %#v, want %q", index, got, want)
		}
	}
}

func TestParseSelectionCommandDoesNotExpandSimilarVariableNames(t *testing.T) {
	invocation, err := parseSelectionCommand(`$repoRooted --flag`)
	if err != nil {
		t.Fatalf("parseSelectionCommand returned error: %v", err)
	}
	if invocation.executable != "$repoRooted" {
		t.Fatalf("executable = %q, want $repoRooted", invocation.executable)
	}
}

func TestWriteSelectionRejectsUnquotedPowerShellMetacharacters(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:    "Unsafe",
		Command: `tool safe; Set-Content breakout.txt bad`,
	}

	if err := writeSelection(path, item); err == nil {
		t.Fatal("writeSelection returned nil, want error")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("selection file exists after rejected command: %v", err)
	}
}

func TestWriteSelectionRejectsEmptyQuotedExecutable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:    "Empty",
		Command: `"" --flag`,
	}

	if err := writeSelection(path, item); err == nil {
		t.Fatal("writeSelection returned nil, want error")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("selection file exists after rejected command: %v", err)
	}
}

func TestDefaultCommandsParseAsStructuredInvocations(t *testing.T) {
	cfg := config.Default()

	for _, item := range cfg.Items {
		if item.Command != "" {
			assertCommandParses(t, item.Name, item.Command)
		}
		for _, choice := range item.Choices {
			assertCommandParses(t, item.Name+" "+choice.Name, choice.Command)
		}
	}
}

func assertCommandParses(t *testing.T, name string, command string) {
	t.Helper()

	invocation, err := parseSelectionCommand(command)
	if err != nil {
		t.Fatalf("%s command did not parse: %v", name, err)
	}
	if invocation.executable == "" {
		t.Fatalf("%s parsed with empty executable", name)
	}
}

func readSelection(t *testing.T, path string) map[string]any {
	t.Helper()

	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}

	var selection map[string]any
	if err := json.Unmarshal(content, &selection); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	return selection
}
