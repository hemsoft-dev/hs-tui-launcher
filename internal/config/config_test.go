package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadReturnsDefaultsWhenNoConfigFileExists(t *testing.T) {
	chdir(t, t.TempDir())

	cfg, source, err := Load("")
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if source != "built-in defaults" {
		t.Fatalf("source = %q, want built-in defaults", source)
	}
	if cfg.Title != "HemSoft TUI Launcher" {
		t.Fatalf("Title = %q", cfg.Title)
	}
	if len(cfg.Items) != 6 {
		t.Fatalf("len(Items) = %d, want 6", len(cfg.Items))
	}
	if got := cfg.Items[0].Command; got != "" {
		t.Fatalf("Codex command = %q", got)
	}
	if got := cfg.Items[0].Model; got != "gpt-5.6-sol" {
		t.Fatalf("Codex model = %q", got)
	}
	if got := cfg.Items[0].ReasoningEffort; got != "high" {
		t.Fatalf("Codex reasoning effort = %q", got)
	}
	if len(cfg.Items[0].Choices) != 3 {
		t.Fatalf("Codex choices = %d, want 3", len(cfg.Items[0].Choices))
	}
	if got := cfg.Items[0].Choices[0].Command; got != codexFreshCommand {
		t.Fatalf("Codex fresh command = %q", got)
	}
	if got := cfg.Items[0].Choices[1].Command; got != codexResumeCommand {
		t.Fatalf("Codex resume command = %q", got)
	}
	if got := cfg.Items[0].Choices[2].Command; got != codexResumePickerCommand {
		t.Fatalf("Codex resume picker command = %q", got)
	}
	if got := cfg.Items[1].Command; got != copilotCommand {
		t.Fatalf("GitHub Copilot command = %q", got)
	}
	if got := cfg.Items[1].Model; got != "gpt-5.5" {
		t.Fatalf("GitHub Copilot model = %q", got)
	}
	if got := cfg.Items[1].ReasoningEffort; got != "high" {
		t.Fatalf("GitHub Copilot reasoning effort = %q", got)
	}
	if got := cfg.Items[2].Model; got != "claude-opus-4.8" {
		t.Fatalf("Cursor model = %q", got)
	}
	if got := cfg.Items[3].Command; got != "claude --dangerously-skip-permissions" {
		t.Fatalf("Claude Code command = %q", got)
	}
	if got := cfg.Items[4].Command; got != "" {
		t.Fatalf("OpenCode command = %q", got)
	}
	if got := cfg.Items[4].Name; got != "OpenCode" {
		t.Fatalf("OpenCode name = %q", got)
	}
	if got := cfg.Items[4].Model; got != "select model" {
		t.Fatalf("OpenCode model = %q", got)
	}
	if got := cfg.Items[4].Env; len(got) != 1 || got[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
		t.Fatalf("OpenCode env = %#v", got)
	}
	if got := len(cfg.Items[4].Choices); got != 1 {
		t.Fatalf("OpenCode choices = %d, want 1", got)
	}
	opencodeChoices := []struct {
		name        string
		description string
		command     string
	}{
		{"Kimi K2.7 Code", "opencode/kimi-k2.7-code", opencodeKimiCommand},
	}
	for index, want := range opencodeChoices {
		choice := cfg.Items[4].Choices[index]
		if choice.Name != want.name {
			t.Fatalf("OpenCode choice %d name = %q", index, choice.Name)
		}
		if choice.Description != want.description {
			t.Fatalf("OpenCode choice %d description = %q", index, choice.Description)
		}
		if choice.Command != want.command {
			t.Fatalf("OpenCode choice %d command = %q", index, choice.Command)
		}
	}
	if got := cfg.Items[5].Name; got != "OpenRouter" {
		t.Fatalf("OpenRouter name = %q", got)
	}
	if got := cfg.Items[5].Command; got != "" {
		t.Fatalf("OpenRouter command = %q", got)
	}
	if got := cfg.Items[5].Model; got != "select model" {
		t.Fatalf("OpenRouter model = %q", got)
	}
	if got := cfg.Items[5].Env; len(got) != 1 || got[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
		t.Fatalf("OpenRouter env = %#v", got)
	}
	if got := len(cfg.Items[5].Choices); got != 2 {
		t.Fatalf("OpenRouter choices = %d, want 2", got)
	}
	openrouterChoice := cfg.Items[5].Choices[0]
	if openrouterChoice.Name != "GLM 5.2" {
		t.Fatalf("OpenRouter choice name = %q", openrouterChoice.Name)
	}
	if openrouterChoice.Description != "openrouter/z-ai/glm-5.2" {
		t.Fatalf("OpenRouter choice description = %q", openrouterChoice.Description)
	}
	if openrouterChoice.Command != openrouterGLMCommand {
		t.Fatalf("OpenRouter choice command = %q", openrouterChoice.Command)
	}
	fusionChoice := cfg.Items[5].Choices[1]
	if fusionChoice.Name != "Fusion" {
		t.Fatalf("OpenRouter fusion choice name = %q", fusionChoice.Name)
	}
	if fusionChoice.Description != "openrouter/fusion" {
		t.Fatalf("OpenRouter fusion choice description = %q", fusionChoice.Description)
	}
	if fusionChoice.Command != openrouterFusionCommand {
		t.Fatalf("OpenRouter fusion choice command = %q", fusionChoice.Command)
	}
	for _, arg := range cfg.ShellArgs {
		if arg == "-NoExit" {
			t.Fatal("default ShellArgs must not keep a nested shell open")
		}
	}
}

func TestLoadMergesFileWithDefaults(t *testing.T) {
	dir := t.TempDir()
	chdir(t, dir)

	path := filepath.Join(dir, defaultConfigFile)
	writeFile(t, path, `
title: Custom Launcher
items:
  - name: Test
    command: echo test
`)

	cfg, source, err := Load("")
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if source != defaultConfigFile {
		t.Fatalf("source = %q, want %q", source, defaultConfigFile)
	}
	if cfg.Title != "Custom Launcher" {
		t.Fatalf("Title = %q", cfg.Title)
	}
	if cfg.Shell == "" {
		t.Fatal("Shell was not preserved from defaults")
	}
	if got := cfg.Items[0].Command; got != "echo test" {
		t.Fatalf("Command = %q", got)
	}
}

func TestLoadAllowsFullFileOverride(t *testing.T) {
	dir := t.TempDir()
	chdir(t, dir)

	path := filepath.Join(dir, "custom.yaml")
	writeFile(t, path, `
title: Fully Custom
shell: pwsh
shell_args:
  - -NoProfile
  - -Command
items:
  - name: Custom Tool
    description: Custom description
    command: custom-tool --flag
    model: custom-model
    reasoning_effort: low
    working_dir: C:\tools
    env:
      - CUSTOM_ENV=1
    tags:
      - custom
`)

	cfg, source, err := Load(path)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if source != path {
		t.Fatalf("source = %q, want %q", source, path)
	}
	if cfg.Title != "Fully Custom" {
		t.Fatalf("Title = %q", cfg.Title)
	}
	if cfg.Shell != "pwsh" {
		t.Fatalf("Shell = %q", cfg.Shell)
	}
	if len(cfg.ShellArgs) != 2 || cfg.ShellArgs[0] != "-NoProfile" || cfg.ShellArgs[1] != "-Command" {
		t.Fatalf("ShellArgs = %#v", cfg.ShellArgs)
	}
	if len(cfg.Items) != 1 {
		t.Fatalf("len(Items) = %d, want 1", len(cfg.Items))
	}
	item := cfg.Items[0]
	if item.Name != "Custom Tool" || item.Command != "custom-tool --flag" || item.Model != "custom-model" {
		t.Fatalf("Item = %#v", item)
	}
	if item.WorkingDir != `C:\tools` {
		t.Fatalf("WorkingDir = %q", item.WorkingDir)
	}
	if len(item.Env) != 1 || item.Env[0] != "CUSTOM_ENV=1" {
		t.Fatalf("Env = %#v", item.Env)
	}
}

func TestLoadMergesPartialFileWithDefaults(t *testing.T) {
	dir := t.TempDir()
	chdir(t, dir)

	path := filepath.Join(dir, defaultConfigFile)
	writeFile(t, path, `
title: Partial Launcher
`)

	cfg, source, err := Load("")
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if source != defaultConfigFile {
		t.Fatalf("source = %q, want %q", source, defaultConfigFile)
	}
	if cfg.Title != "Partial Launcher" {
		t.Fatalf("Title = %q", cfg.Title)
	}
	if cfg.Shell == "" {
		t.Fatal("Shell was not preserved from defaults")
	}
	if len(cfg.Items) != len(Default().Items) {
		t.Fatalf("len(Items) = %d, want %d", len(cfg.Items), len(Default().Items))
	}
	if cfg.Items[0].Name != Default().Items[0].Name {
		t.Fatalf("First item name = %q", cfg.Items[0].Name)
	}
}

func TestLoadWrapsMalformedYAMLError(t *testing.T) {
	dir := t.TempDir()
	chdir(t, dir)

	path := filepath.Join(dir, defaultConfigFile)
	writeFile(t, path, `
title: Broken
items:
  - name: Test
    command: echo test
    bad: [unterminated
`)

	_, _, err := Load("")
	assertErrorContains(t, err, `parse config ".hs-tui-launcher.yaml"`)
}

func TestLoadWrapsValidationError(t *testing.T) {
	dir := t.TempDir()
	chdir(t, dir)

	path := filepath.Join(dir, defaultConfigFile)
	writeFile(t, path, `
title: Invalid
items:
  - name: Missing Command
`)

	_, _, err := Load("")
	assertErrorContains(t, err, `validate config ".hs-tui-launcher.yaml"`)
	assertErrorContains(t, err, "items[0].command or choices are required")
}

func TestValidateRejectsEmptyItems(t *testing.T) {
	cfg := Default()
	cfg.Items = nil

	err := cfg.Validate()
	assertErrorContains(t, err, "at least one launcher item is required")
}

func TestValidateRejectsMissingName(t *testing.T) {
	cfg := Default()
	cfg.Items[0].Name = " "

	err := cfg.Validate()
	assertErrorContains(t, err, "items[0].name is required")
}

func TestValidateRejectsMissingCommand(t *testing.T) {
	cfg := Default()
	cfg.Items[1].Command = ""

	err := cfg.Validate()
	assertErrorContains(t, err, "items[1].command or choices are required")
}

func TestValidateRejectsMissingChoiceCommand(t *testing.T) {
	cfg := Default()
	cfg.Items[0].Choices[0].Command = ""

	err := cfg.Validate()
	assertErrorContains(t, err, "items[0].choices[0].command is required")
}

func chdir(t *testing.T, dir string) {
	t.Helper()

	original, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("Chdir: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(original); err != nil {
			t.Fatalf("restore cwd: %v", err)
		}
	})
}

func writeFile(t *testing.T, path string, content string) {
	t.Helper()

	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
}

func assertErrorContains(t *testing.T, err error, want string) {
	t.Helper()

	if err == nil {
		t.Fatalf("error = nil, want %q", want)
	}
	if !strings.Contains(err.Error(), want) {
		t.Fatalf("error = %q, want substring %q", err, want)
	}
}
