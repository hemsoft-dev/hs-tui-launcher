package config

import (
	"os"
	"path/filepath"
	"reflect"
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
	if len(cfg.Items) != 10 {
		t.Fatalf("len(Items) = %d, want 10", len(cfg.Items))
	}
	if got := cfg.Items[1].Command; got != "" {
		t.Fatalf("Codex command = %q", got)
	}
	if got := cfg.Items[1].Model; got != "gpt-6-astra" {
		t.Fatalf("Codex model = %q", got)
	}
	if got := cfg.Items[1].ReasoningEffort; got != "high" {
		t.Fatalf("Codex reasoning effort = %q", got)
	}
	if len(cfg.Items[1].Choices) != 7 {
		t.Fatalf("Codex choices = %d, want 7", len(cfg.Items[1].Choices))
	}
	if got := cfg.Items[1].Choices[0].Command; got != codexFreshCommand {
		t.Fatalf("Codex fresh command = %q", got)
	}
	if got := cfg.Items[1].Choices[1].Command; got != codexResumeCommand {
		t.Fatalf("Codex resume command = %q", got)
	}
	if got := cfg.Items[1].Choices[2].Command; got != codexResumePickerCommand {
		t.Fatalf("Codex resume picker command = %q", got)
	}
	codexChoices := []struct {
		name        string
		description string
		command     string
	}{
		{"GPT 5.6 Sol High ($4/$0.4/$20)", "Start Codex with GPT-5.6 Sol at high reasoning", codexSolHighCommand},
		{"GPT 5.6 Sol High/Fast ($4/$0.4/$20)", "Start Codex with GPT-5.6 Sol at high reasoning and fast service", codexSolHighFastCommand},
		{"GPT 5.6 Luna ($0.2/$0.02/$1.2)", "Start Codex with GPT-5.6 Luna at medium reasoning", codexLunaCommand},
		{"GPT 5.6 Luna/Fast ($0.2/$0.02/$1.2)", "Start Codex with GPT-5.6 Luna at medium reasoning and fast service", codexLunaFastCommand},
	}
	for index, want := range codexChoices {
		choice := cfg.Items[1].Choices[index+3]
		if choice.Name != want.name {
			t.Fatalf("Codex choice %d name = %q", index+3, choice.Name)
		}
		if choice.Description != want.description {
			t.Fatalf("Codex choice %d description = %q", index+3, choice.Description)
		}
		if choice.Command != want.command {
			t.Fatalf("Codex choice %d command = %q", index+3, choice.Command)
		}
	}
	pi := cfg.Items[0]
	if pi.Name != "Pi" {
		t.Fatalf("Pi name = %q", pi.Name)
	}
	if pi.Description != "Open the Pi CLI" {
		t.Fatalf("Pi description = %q", pi.Description)
	}
	if pi.Command != "" {
		t.Fatalf("Pi command = %q", pi.Command)
	}
	if pi.Model != "select model" {
		t.Fatalf("Pi model = %q", pi.Model)
	}
	if pi.ReasoningEffort != "default" {
		t.Fatalf("Pi reasoning effort = %q", pi.ReasoningEffort)
	}
	if got := len(pi.Choices); got != 19 {
		t.Fatalf("Pi choices = %d, want 19", got)
	}
	piChoices := []struct {
		name        string
		description string
		command     string
	}{
		{"GPT 6 Astra ($10/$1/$50)", "openai-codex/gpt-6-astra at medium reasoning", piCodexAstraCommand},
		{"GPT 6.1 Sol High ($2/$0.1/$10)", "openai-codex/gpt-6.1-sol at high reasoning", piCodexSol61HighCommand},
		{"GPT 6 Luna Max ($0.1/$0.01/$0.5)", "openai-codex/gpt-6-luna at max reasoning", piCodexLuna6MaxCommand},
		{"Copilot: Gemini 3.8 Flash ($0.75/$0.075/$3.75)", "github-copilot/gemini-3.8-flash", piCopilotGemini38Command},
		{"Copilot: GPT 5.6 Luna Max ($0.2/$0.02/$1.2)", "github-copilot/gpt-5.6-luna at max reasoning", piCopilotLunaMaxCommand},
		{"Copilot: GPT 5.6 Sol High ($4/$0.4/$20)", "github-copilot/gpt-5.6-sol at high reasoning", piCopilotSolHighCommand},
		{"Copilot: GPT 6 Astra Medium ($10/$1/$50)", "github-copilot/gpt-6-astra at medium reasoning", piCopilotAstraCommand},
		{"Copilot: Opus 5.5 High ($4/$0.2/$20)", "github-copilot/claude-opus-5.5 at high reasoning", piCopilotOpus55HighCommand},
		{"GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)", "opencode-go/glm-5.3-flash", piGLM53FlashCommand},
		{"DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)", "opencode-go/deepseek-v4.1-flash", piDeepSeekV41Command},
		{"Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)", "opencode-go/muse-spark-1.3-contributor", piMuseSpark13Command},
		{"OpenRouter: DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)", "openrouter/deepseek/deepseek-v4.1-flash", piOpenRouterDeepSeekV41Command},
		{"MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "opencode-go/mimo-v2.6-flash", piGoMimoV26FlashCommand},
		{"MiMo V2.6 Pro ($0.435/$0.003625/$0.87)", "opencode-go/mimo-v2.6-pro", piGoMimoV26ProCommand},
		{"OpenRouter: MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "openrouter/xiaomi/mimo-v2.6-flash", piRouterMimoV26FlashCommand},
		{"OpenRouter: MiMo V2.6 Pro ($0.435/$0.0036/$0.87)", "openrouter/xiaomi/mimo-v2.6-pro", piRouterMimoV26ProCommand},
		{"OpenRouter: Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)", "openrouter/qwen/qwen3.8-omni-flash", piRouterQwenOmniFlashCommand},
		{"OpenRouter: Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)", "openrouter/prism-ml/ternary-bonsai-2-27b", piRouterBonsai227BCommand},
		{"OpenRouter: GLM-5.3-FlashX ($0.37/$0.09/$1.25)", "openrouter/z-ai/glm-5.3-flashx", piRouterGLM53FlashXCommand},
	}
	for index, want := range piChoices {
		choice := pi.Choices[index]
		if choice.Name != want.name {
			t.Fatalf("Pi choice %d name = %q", index, choice.Name)
		}
		if choice.Description != want.description {
			t.Fatalf("Pi choice %d description = %q", index, choice.Description)
		}
		if choice.Command != want.command {
			t.Fatalf("Pi choice %d command = %q", index, choice.Command)
		}
	}
	antigravity := cfg.Items[2]
	if antigravity.Name != "Antigravity" {
		t.Fatalf("Antigravity name = %q", antigravity.Name)
	}
	if antigravity.Description != "Open the Antigravity CLI" {
		t.Fatalf("Antigravity description = %q", antigravity.Description)
	}
	if antigravity.Command != antigravityAgentCommand {
		t.Fatalf("Antigravity command = %q", antigravity.Command)
	}
	if antigravity.ReasoningEffort != "default" {
		t.Fatalf("Antigravity reasoning effort = %q", antigravity.ReasoningEffort)
	}
	if got := cfg.Items[3].Command; got != "" {
		t.Fatalf("GitHub Copilot command = %q", got)
	}
	if got := cfg.Items[3].Model; got != "select model" {
		t.Fatalf("GitHub Copilot model = %q", got)
	}
	if got := cfg.Items[3].ReasoningEffort; got != "default" {
		t.Fatalf("GitHub Copilot reasoning effort = %q", got)
	}
	if got := len(cfg.Items[3].Choices); got != 4 {
		t.Fatalf("GitHub Copilot choices = %d, want 4", got)
	}
	copilotGPT55Choice := cfg.Items[3].Choices[0]
	if copilotGPT55Choice.Name != "GPT-5.5 ($5/$0.5/$30)" {
		t.Fatalf("GitHub Copilot first choice name = %q", copilotGPT55Choice.Name)
	}
	if copilotGPT55Choice.Description != "Use GPT-5.5 with high reasoning effort" {
		t.Fatalf("GitHub Copilot first choice description = %q", copilotGPT55Choice.Description)
	}
	if copilotGPT55Choice.Command != copilotGPT55Command {
		t.Fatalf("GitHub Copilot first choice command = %q", copilotGPT55Choice.Command)
	}
	copilotGPT56SolChoice := cfg.Items[3].Choices[1]
	if copilotGPT56SolChoice.Name != "GPT-5.6 Sol ($4/$0.4/$20)" {
		t.Fatalf("GitHub Copilot second choice name = %q", copilotGPT56SolChoice.Name)
	}
	if copilotGPT56SolChoice.Description != "Use GPT-5.6 Sol with high reasoning effort" {
		t.Fatalf("GitHub Copilot second choice description = %q", copilotGPT56SolChoice.Description)
	}
	if copilotGPT56SolChoice.Command != copilotGPT56SolCommand {
		t.Fatalf("GitHub Copilot second choice command = %q", copilotGPT56SolChoice.Command)
	}
	copilotOpus5Choice := cfg.Items[3].Choices[2]
	if copilotOpus5Choice.Name != "Claude Opus 5 ($5/$0.5/$25)" {
		t.Fatalf("GitHub Copilot third choice name = %q", copilotOpus5Choice.Name)
	}
	if copilotOpus5Choice.Description != "Use Claude Opus 5 with xhigh reasoning effort" {
		t.Fatalf("GitHub Copilot third choice description = %q", copilotOpus5Choice.Description)
	}
	if copilotOpus5Choice.Command != copilotOpus5Command {
		t.Fatalf("GitHub Copilot third choice command = %q", copilotOpus5Choice.Command)
	}
	copilotAutoChoice := cfg.Items[3].Choices[3]
	if copilotAutoChoice.Name != "Auto (server-routed)" {
		t.Fatalf("GitHub Copilot fourth choice name = %q", copilotAutoChoice.Name)
	}
	if copilotAutoChoice.Description != "Let GitHub Copilot choose the model for each task" {
		t.Fatalf("GitHub Copilot fourth choice description = %q", copilotAutoChoice.Description)
	}
	if copilotAutoChoice.Command != copilotAutoCommand {
		t.Fatalf("GitHub Copilot fourth choice command = %q", copilotAutoChoice.Command)
	}
	if got := cfg.Items[8].Model; got != "claude-opus-4.8" {
		t.Fatalf("Cursor model = %q", got)
	}
	if got := cfg.Items[8].Command; got != "cursor-agent --disable-auto-update" {
		t.Fatalf("Cursor command = %q", got)
	}
	if got := cfg.Items[9].Command; got != "claude --dangerously-skip-permissions" {
		t.Fatalf("Claude Code command = %q", got)
	}
	moonshot := cfg.Items[4]
	if moonshot.Name != "Moonshot AI" {
		t.Fatalf("Moonshot AI name = %q", moonshot.Name)
	}
	if moonshot.Description != "Open Kimi K3 with Moonshot AI credits" {
		t.Fatalf("Moonshot AI description = %q", moonshot.Description)
	}
	if moonshot.Command != moonshotLauncherCommand {
		t.Fatalf("Moonshot AI command = %q", moonshot.Command)
	}
	if moonshot.Model != "moonshot/kimi-k3" {
		t.Fatalf("Moonshot AI model = %q", moonshot.Model)
	}
	if len(moonshot.Env) != 0 {
		t.Fatalf("Moonshot AI env = %#v", moonshot.Env)
	}
	if got := cfg.Items[5].Command; got != "" {
		t.Fatalf("OpenCode command = %q", got)
	}
	if got := cfg.Items[5].Name; got != "OpenCode" {
		t.Fatalf("OpenCode name = %q", got)
	}
	if got := cfg.Items[5].Model; got != "select model" {
		t.Fatalf("OpenCode model = %q", got)
	}
	if got := cfg.Items[5].Env; len(got) != 1 || got[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
		t.Fatalf("OpenCode env = %#v", got)
	}
	if got := len(cfg.Items[5].Choices); got != 9 {
		t.Fatalf("OpenCode choices = %d, want 9", got)
	}
	opencodeChoices := []struct {
		name        string
		description string
		command     string
	}{
		{"GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)", "opencode-go/glm-5.3-flash", opencodeGLM53FlashCommand},
		{"Kimi K3 ($3/$0.3/$15)", "opencode-go/kimi-k3", opencodeKimiK3Command},
		{"Qwen 3.8 Max ($2/$0.25/$6)", "opencode-go/qwen3.8-max", opencodeQwen38Command},
		{"DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)", "opencode-go/deepseek-v4.1-flash", opencodeDeepSeekV41Command},
		{"Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)", "opencode-go/muse-spark-1.3-contributor", opencodeMuseSpark13Command},
		{"Qwen 3.8 27B (home Ollama)", "ollama/qwen3.8:27b", ollamaQwen3827BCommand},
		{"Qwen 3.8 27B (amd Ollama)", "amd-ollama/qwen3.8:27b", amdOllamaQwen3827BCommand},
		{"MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "opencode-go/mimo-v2.6-flash", opencodeMimoV26FlashCommand},
		{"MiMo V2.6 Pro ($0.435/$0.003625/$0.87)", "opencode-go/mimo-v2.6-pro", opencodeMimoV26ProCommand},
	}
	for index, want := range opencodeChoices {
		choice := cfg.Items[5].Choices[index]
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
	if got := cfg.Items[6].Name; got != "OpenRouter" {
		t.Fatalf("OpenRouter name = %q", got)
	}
	if got := cfg.Items[6].Description; got != "Open OpenRouter models and image generation" {
		t.Fatalf("OpenRouter description = %q", got)
	}
	if got := cfg.Items[6].Command; got != "" {
		t.Fatalf("OpenRouter command = %q", got)
	}
	if got := cfg.Items[6].Model; got != "select model" {
		t.Fatalf("OpenRouter model = %q", got)
	}
	if got := cfg.Items[6].Env; len(got) != 1 || got[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
		t.Fatalf("OpenRouter env = %#v", got)
	}
	if got := len(cfg.Items[6].Choices); got != 22 {
		t.Fatalf("OpenRouter choices = %d, want 22", got)
	}
	openrouterChoices := []struct {
		name        string
		description string
		command     string
	}{
		{"GPT 6 Astra ($10/$1/$50)", "openrouter/openai/gpt-6-astra", openrouterAstraCommand},
		{"GPT 6 Sol ($2/$0.2/$10)", "openrouter/openai/gpt-6-sol", openrouterSol6Command},
		{"GPT 6 Luna ($0.1/$0.01/$0.5)", "openrouter/openai/gpt-6-luna", openrouterLuna6Command},
		{"GPT 5.6 Sol ($2/$0.2/$10)", "openrouter/openai/gpt-5.6-sol", openrouterSol56Command},
		{"GPT 5.6 Luna ($0.2/$0.02/$1.2)", "openrouter/openai/gpt-5.6-luna", openrouterLuna56Command},
		{"Gemini 3.8 Flash ($0.75/$0.075/$3.75)", "openrouter/google/gemini-3.8-flash", openrouterGemini38Command},
		{"Claude Opus 5.5 ($4/$0.2/$20)", "openrouter/anthropic/claude-opus-5.5", openrouterOpus55Command},
		{"Kimi K3 ($0.66/$0.66/$10)", "openrouter/moonshotai/kimi-k3", openrouterKimiK3Command},
		{"Qwen 3.8 Max ($2/$0.25/$6)", "openrouter/qwen/qwen3.8-max-0902", openrouterQwen38Command},
		{"GLM-5.3-Flash ($0.15/$0.03/$0.5)", "openrouter/z-ai/glm-5.3-flash", openrouterGLM53FlashCommand},
		{"Fusion (variable/variable)", "openrouter/openrouter/fusion", openrouterFusionCommand},
		{"DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)", "openrouter/deepseek/deepseek-v4.1-flash", openrouterDeepSeekV41Command},
		{"Muse Spark V1.3 ($1.25/$0.15/$4.25)", "openrouter/meta/muse-spark-1.3", openrouterMuseSpark13Command},
		{"Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)", "openrouter/meta/muse-spark-1.3-contributor", openrouterMuseContributorCommand},
		{"Muse Spark V1.2 ($1.25/$0.15/$4.25)", "openrouter/meta/muse-spark-1.2", openrouterMuseSpark12Command},
		{"MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "openrouter/xiaomi/mimo-v2.6-flash", openrouterMimoV26FlashCommand},
		{"MiMo V2.6 Pro ($0.435/$0.0036/$0.87)", "openrouter/xiaomi/mimo-v2.6-pro", openrouterMimoV26ProCommand},
		{"Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)", "openrouter/qwen/qwen3.8-omni-flash", openrouterQwenOmniFlashCommand},
		{"Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)", "openrouter/prism-ml/ternary-bonsai-2-27b", openrouterBonsai227BCommand},
		{"GLM-5.3-FlashX ($0.37/$0.09/$1.25)", "openrouter/z-ai/glm-5.3-flashx", openrouterGLM53FlashXCommand},
		{"Seedream 5.0 Pro ($0.045 1K/$0.09 2K)", "images/bytedance-seed/seedream-5-0-pro", openrouterSeedreamCommand},
		{"Seed Audio 1.0 ($0.15/min)", "audio/bytedance-seed/seed-audio-1-0", openrouterSeedAudioCommand},
	}
	for index, want := range openrouterChoices {
		choice := cfg.Items[6].Choices[index]
		if choice.Name != want.name {
			t.Fatalf("OpenRouter choice %d name = %q", index, choice.Name)
		}
		if choice.Description != want.description {
			t.Fatalf("OpenRouter choice %d description = %q", index, choice.Description)
		}
		if choice.Command != want.command {
			t.Fatalf("OpenRouter choice %d command = %q", index, choice.Command)
		}
	}
	ollama := cfg.Items[7]
	if ollama.Name != "Ollama" {
		t.Fatalf("Ollama name = %q", ollama.Name)
	}
	if ollama.Description != "Open local Ollama models with OpenCode" {
		t.Fatalf("Ollama description = %q", ollama.Description)
	}
	if ollama.Command != "" {
		t.Fatalf("Ollama command = %q", ollama.Command)
	}
	if ollama.Model != "select model" {
		t.Fatalf("Ollama model = %q", ollama.Model)
	}
	if len(ollama.Env) != 0 {
		t.Fatalf("Ollama env = %#v", ollama.Env)
	}
	if got := len(ollama.Choices); got != 1 {
		t.Fatalf("Ollama choices = %d, want 1", got)
	}
	ollamaQwen := ollama.Choices[0]
	if ollamaQwen.Name != "Qwen 3.8 27B" {
		t.Fatalf("Ollama first choice name = %q", ollamaQwen.Name)
	}
	if ollamaQwen.Description != "ollama/qwen3.8:27b" {
		t.Fatalf("Ollama first choice description = %q", ollamaQwen.Description)
	}
	if ollamaQwen.Command != ollamaQwen3827BCommand {
		t.Fatalf("Ollama first choice command = %q", ollamaQwen.Command)
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

func TestCommittedConfigFileMatchesDefaults(t *testing.T) {
	path := filepath.Join("..", "..", ".hs-tui-launcher.yaml")
	if _, err := os.Stat(path); err != nil {
		t.Skip("committed .hs-tui-launcher.yaml is not present")
	}

	cfg, source, err := Load(path)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if source != path {
		t.Fatalf("source = %q, want %q", source, path)
	}
	// The committed config is the home machine's variant, so its shell differs
	// from Default() on non-Windows platforms. Exclude the machine-specific
	// shell fields from the drift check.
	cfg.Shell = ""
	cfg.ShellArgs = nil
	expected := Default()
	expected.Shell = ""
	expected.ShellArgs = nil

	if !reflect.DeepEqual(cfg, expected) {
		t.Fatal("committed .hs-tui-launcher.yaml drifted from Default(); update it alongside config.go")
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
	cfg.Items[9].Command = ""

	err := cfg.Validate()
	assertErrorContains(t, err, "items[9].command or choices are required")
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
