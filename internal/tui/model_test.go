package tui

import (
	"fmt"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

func TestSelectingItemWithChoicesWaitsForChoice(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("1"))
	model = updated.(Model)

	if _, ok := model.SelectedItem(); ok {
		t.Fatal("SelectedItem returned a value before a Codex choice was selected")
	}
	if model.choiceParent == nil {
		t.Fatal("choiceParent was nil after selecting Codex")
	}
}

func TestChoiceMenuUsesCompactSpacing(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("2"))
	model = updated.(Model)

	lines := model.choiceLines()
	if lines[3] != "3. Resume picker                             Choose a Codex CLI session to resume" {
		t.Fatalf("Resume picker line = %q", lines[3])
	}
}

func TestChoiceLineHandlesMissingDescriptionWithDetail(t *testing.T) {
	choice := launchChoice{LaunchChoice: config.LaunchChoice{Name: "Choice (detail)"}}

	if got := choice.Line("1.", 10, 8); got != "1. Choice      (detail)" {
		t.Fatalf("Line = %q", got)
	}
}

func TestChoiceLineHandlesMissingDescriptionWithoutDetail(t *testing.T) {
	choice := launchChoice{LaunchChoice: config.LaunchChoice{Name: "Choice"}}

	if got := choice.Line("1.", 10, 0); got != "1. Choice" {
		t.Fatalf("Line = %q", got)
	}
}

func TestChoiceLineHandlesDescriptionWithoutDetail(t *testing.T) {
	choice := launchChoice{LaunchChoice: config.LaunchChoice{
		Name:        "Choice",
		Description: "description",
	}}

	if got := choice.Line("1.", 10, 0); got != "1. Choice      description" {
		t.Fatalf("Line = %q", got)
	}
}

func TestChoiceMenuAlignsDetailsAndDescriptions(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("7"))
	model = updated.(Model)

	lines := model.choiceLines()
	details := []string{
		"($10/$1/$50)",
		"($2/$0.2/$10)",
		"($0.1/$0.01/$0.5)",
		"($2/$0.2/$10)",
		"($0.2/$0.02/$1.2)",
		"($0.75/$0.075/$3.75)",
		"($4/$0.2/$20)",
		"($0.66/$0.66/$10)",
		"($2/$0.25/$6)",
		"($0.15/$0.03/$0.5)",
		"(variable/variable)",
		"($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)",
		"($1.25/$0.15/$4.25)",
		"($0.1/$0.002/$0.2)",
		"($1.25/$0.15/$4.25)",
		"($0.14/$0.0028/$0.28)",
		"($0.435/$0.0036/$0.87)",
		"($0.15/$0.016/$0.47)",
		"($0.075/$0.0375/$0.5)",
		"($0.37/$0.09/$1.25)",
		"($0.045 1K/$0.09 2K)",
		"($0.15/min)",
	}
	descriptions := []string{
		"openrouter/openai/gpt-6-astra",
		"openrouter/openai/gpt-6-sol",
		"openrouter/openai/gpt-6-luna",
		"openrouter/openai/gpt-5.6-sol",
		"openrouter/openai/gpt-5.6-luna",
		"openrouter/google/gemini-3.8-flash",
		"openrouter/anthropic/claude-opus-5.5",
		"openrouter/moonshotai/kimi-k3",
		"openrouter/qwen/qwen3.8-max-0902",
		"openrouter/z-ai/glm-5.3-flash",
		"openrouter/openrouter/fusion",
		"openrouter/deepseek/deepseek-v4.1-flash",
		"openrouter/meta/muse-spark-1.3",
		"openrouter/meta/muse-spark-1.3-contributor",
		"openrouter/meta/muse-spark-1.2",
		"openrouter/xiaomi/mimo-v2.6-flash",
		"openrouter/xiaomi/mimo-v2.6-pro",
		"openrouter/qwen/qwen3.8-omni-flash",
		"openrouter/prism-ml/ternary-bonsai-2-27b",
		"openrouter/z-ai/glm-5.3-flashx",
		"images/bytedance-seed/seedream-5-0-pro",
		"audio/bytedance-seed/seed-audio-1-0",
	}
	wantDetailColumn := -1
	wantDescriptionColumn := -1
	for index, description := range descriptions {
		detailColumn := strings.Index(lines[index+1], details[index])
		if detailColumn < 0 {
			t.Fatalf("choice %d line = %q, missing detail", index, lines[index+1])
		}
		descriptionColumn := strings.Index(lines[index+1], description)
		if descriptionColumn < 0 {
			t.Fatalf("choice %d line = %q, missing description", index, lines[index+1])
		}
		if wantDetailColumn < 0 {
			wantDetailColumn = detailColumn
			wantDescriptionColumn = descriptionColumn
		}
		if detailColumn != wantDetailColumn {
			t.Fatalf("choice %d detail column = %d, want %d", index, detailColumn, wantDetailColumn)
		}
		if descriptionColumn != wantDescriptionColumn {
			t.Fatalf("choice %d description column = %d, want %d", index, descriptionColumn, wantDescriptionColumn)
		}
	}
}

func TestChoiceMenuFallsBackToNamesForNarrowWidth(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(tea.WindowSizeMsg{Width: 45})
	model = updated.(Model)
	updated, _ = model.Update(key("2"))
	model = updated.(Model)

	lines := model.choiceLines()
	if lines[3] != "3. Resume picker" {
		t.Fatalf("Resume picker line = %q", lines[3])
	}
}

func TestSelectingPiWaitsForChoice(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("1"))
	model = updated.(Model)

	if _, ok := model.SelectedItem(); ok {
		t.Fatal("SelectedItem returned a value before a Pi choice was selected")
	}
	if model.choiceParent == nil {
		t.Fatal("choiceParent was nil after selecting Pi")
	}
	if model.choiceParent.Name != "Pi" {
		t.Fatalf("choiceParent name = %q, want Pi", model.choiceParent.Name)
	}
}

func TestSelectingPiChoicesReturnsModelCommands(t *testing.T) {
	tests := []struct {
		key     string
		name    string
		command string
	}{
		{"1", "Pi GPT 6 Astra ($10/$1/$50)", "pi --model openai-codex/gpt-6-astra --thinking medium"},
		{"2", "Pi GPT 6.1 Sol High ($2/$0.1/$10)", "pi --model openai-codex/gpt-6.1-sol --thinking high"},
		{"3", "Pi GPT 6 Luna Max ($0.1/$0.01/$0.5)", "pi --model openai-codex/gpt-6-luna --thinking max"},
		{"4", "Pi Copilot: Gemini 3.8 Flash ($0.75/$0.075/$3.75)", "pi --model github-copilot/gemini-3.8-flash"},
		{"5", "Pi Copilot: GPT 5.6 Luna Max ($0.2/$0.02/$1.2)", "pi --model github-copilot/gpt-5.6-luna --thinking max"},
		{"6", "Pi Copilot: GPT 5.6 Sol High ($4/$0.4/$20)", "pi --model github-copilot/gpt-5.6-sol --thinking high"},
		{"7", "Pi Copilot: GPT 6 Astra Medium ($10/$1/$50)", "pi --model github-copilot/gpt-6-astra --thinking medium"},
		{"8", "Pi Copilot: Opus 5.5 High ($4/$0.2/$20)", "pi --model github-copilot/claude-opus-5.5 --thinking high"},
		{"9", "Pi GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)", "pi --model opencode-go/glm-5.3-flash"},
		{"a", "Pi DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)", "pi --model opencode-go/deepseek-v4.1-flash"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			model := choosePi(t, key(test.key))
			item, ok := model.SelectedItem()
			if !ok {
				t.Fatal("SelectedItem returned no value")
			}
			if item.Name != test.name {
				t.Fatalf("Name = %q, want %q", item.Name, test.name)
			}
			if item.Command != test.command {
				t.Fatalf("Command = %q, want %q", item.Command, test.command)
			}
		})
	}
}

func TestSelectingAntigravitySkipsPermissions(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("3"))
	model = updated.(Model)

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Antigravity" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "agy --dangerously-skip-permissions" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCursorDisablesAutoUpdate(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("9"))
	model = updated.(Model)

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Cursor" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "cursor-agent --disable-auto-update" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCodexFreshChoiceReturnsFreshCommand(t *testing.T) {
	model := chooseCodex(t, key("1"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Codex Start fresh" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "codex --dangerously-bypass-approvals-and-sandbox -m gpt-6-astra -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCodexResumeChoiceReturnsResumeCommand(t *testing.T) {
	model := chooseCodex(t, key("2"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Codex Resume last" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "codex resume --last --dangerously-bypass-approvals-and-sandbox -m gpt-6-astra -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingPiChoicesPastNineWithLetterKeys(t *testing.T) {
	tests := []struct {
		key     string
		name    string
		command string
	}{
		{"a", "Pi DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)", "pi --model opencode-go/deepseek-v4.1-flash"},
		{"b", "Pi Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)", "pi --model opencode-go/muse-spark-1.3-contributor"},
		{"c", "Pi OpenRouter: DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)", "pi --model openrouter/deepseek/deepseek-v4.1-flash"},
		{"d", "Pi MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "pi --model opencode-go/mimo-v2.6-flash"},
		{"e", "Pi MiMo V2.6 Pro ($0.435/$0.003625/$0.87)", "pi --model opencode-go/mimo-v2.6-pro"},
		{"f", "Pi OpenRouter: MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "pi --model openrouter/xiaomi/mimo-v2.6-flash"},
		{"g", "Pi OpenRouter: MiMo V2.6 Pro ($0.435/$0.0036/$0.87)", "pi --model openrouter/xiaomi/mimo-v2.6-pro"},
		{"h", "Pi OpenRouter: Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)", "pi --model openrouter/qwen/qwen3.8-omni-flash"},
		{"i", "Pi OpenRouter: Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)", "pi --model openrouter/prism-ml/ternary-bonsai-2-27b"},
		{"j", "Pi OpenRouter: GLM-5.3-FlashX ($0.37/$0.09/$1.25)", "pi --model openrouter/z-ai/glm-5.3-flashx"},
		{"A", "Pi DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)", "pi --model opencode-go/deepseek-v4.1-flash"},
	}

	for _, test := range tests {
		t.Run(test.key, func(t *testing.T) {
			model := choosePi(t, key(test.key))
			item, ok := model.SelectedItem()
			if !ok {
				t.Fatal("SelectedItem returned no value")
			}
			if item.Name != test.name {
				t.Fatalf("Name = %q, want %q", item.Name, test.name)
			}
			if item.Command != test.command {
				t.Fatalf("Command = %q, want %q", item.Command, test.command)
			}
		})
	}
}

func TestChoiceNumberForKeyMapsKeysToChoices(t *testing.T) {
	tests := []struct {
		key         string
		choiceCount int
		wantNumber  int
		wantOK      bool
	}{
		{"1", 12, 1, true},
		{"9", 12, 9, true},
		{"0", 12, 0, false},
		{"10", 12, 0, false},
		{"a", 12, 10, true},
		{"A", 12, 10, true},
		{"c", 12, 12, true},
		{"d", 12, 0, false},
		{"a", 9, 0, false},
		{"z", 35, 35, true},
		{"!", 12, 0, false},
	}

	for _, test := range tests {
		number, ok := choiceNumberForKey(test.key, test.choiceCount)
		if ok != test.wantOK {
			t.Fatalf("choiceNumberForKey(%q, %d) ok = %v, want %v", test.key, test.choiceCount, ok, test.wantOK)
		}
		if number != test.wantNumber {
			t.Fatalf("choiceNumberForKey(%q, %d) number = %d, want %d", test.key, test.choiceCount, number, test.wantNumber)
		}
	}
}

func TestChoiceMenuLabelsChoicesPastNineWithLetters(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("1"))
	model = updated.(Model)

	lines := model.choiceLines()
	if !strings.HasPrefix(lines[1], "1. GPT 6 Astra") {
		t.Fatalf("first choice line = %q", lines[1])
	}
	want := []string{
		"1. GPT 6 Astra", "2. GPT 6.1 Sol High", "3. GPT 6 Luna Max",
		"4. Copilot: Gemini 3.8 Flash", "5. Copilot: GPT 5.6 Luna Max", "6. Copilot: GPT 5.6 Sol High",
		"7. Copilot: GPT 6 Astra Medium", "8. Copilot: Opus 5.5 High",
		"9. GLM-5.3-Flash", "A. DeepSeek V4.1 Flash", "B. Muse Spark V1.3 Contributor",
		"C. OpenRouter: DeepSeek V4.1 Flash", "D. MiMo V2.6 Flash",
		"E. MiMo V2.6 Pro", "F. OpenRouter: MiMo V2.6 Flash",
		"G. OpenRouter: MiMo V2.6 Pro", "H. OpenRouter: Qwen 3.8 Omni Flash",
		"I. OpenRouter: Ternary Bonsai 2 27B", "J. OpenRouter: GLM-5.3-FlashX",
	}
	for index, prefix := range want {
		if !strings.HasPrefix(lines[index+1], prefix) {
			t.Fatalf("choice %d line = %q, want prefix %q", index+1, lines[index+1], prefix)
		}
	}
}

func TestChoiceMenuKeepsDetailColumnAlignedPastNine(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("1"))
	model = updated.(Model)

	lines := model.choiceLines()
	wantDetailColumn := strings.Index(lines[1], "($10/$1/$50)")
	if wantDetailColumn < 0 {
		t.Fatalf("choice line = %q, missing detail", lines[1])
	}
	for index, line := range lines[10 : len(lines)-1] {
		detailColumn := strings.Index(line, "($")
		if detailColumn < 0 {
			t.Fatalf("choice %d line = %q, missing detail", index+10, line)
		}
		if detailColumn != wantDetailColumn {
			t.Fatalf("choice %d detail column = %d, want %d", index+10, detailColumn, wantDetailColumn)
		}
	}
}

func TestSelectingCodexResumePickerChoiceReturnsResumePickerCommand(t *testing.T) {
	model := chooseCodex(t, key("3"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Codex Resume picker" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "codex resume --dangerously-bypass-approvals-and-sandbox -m gpt-6-astra -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCodexModelChoicesReturnsExplicitModelCommands(t *testing.T) {
	tests := []struct {
		key     string
		name    string
		command string
	}{
		{"4", "Codex GPT 5.6 Sol High ($4/$0.4/$20)", `codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'service_tier="default"' -c 'model_reasoning_effort="high"'`},
		{"5", "Codex GPT 5.6 Sol High/Fast ($4/$0.4/$20)", `codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'service_tier="fast"' -c 'model_reasoning_effort="high"'`},
		{"6", "Codex GPT 5.6 Luna ($0.2/$0.02/$1.2)", `codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-luna -c 'service_tier="default"' -c 'model_reasoning_effort="medium"'`},
		{"7", "Codex GPT 5.6 Luna/Fast ($0.2/$0.02/$1.2)", `codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-luna -c 'service_tier="fast"' -c 'model_reasoning_effort="medium"'`},
	}

	for _, test := range tests {
		t.Run(test.key, func(t *testing.T) {
			model := chooseCodex(t, key(test.key))
			item, ok := model.SelectedItem()
			if !ok {
				t.Fatal("SelectedItem returned no value")
			}
			if item.Name != test.name {
				t.Fatalf("Name = %q, want %q", item.Name, test.name)
			}
			if item.Command != test.command {
				t.Fatalf("Command = %q, want %q", item.Command, test.command)
			}
		})
	}
}

func TestSelectingCopilotGPT55ChoiceReturnsExplicitModelCommand(t *testing.T) {
	model := chooseCopilot(t, key("1"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "GitHub Copilot GPT-5.5 ($5/$0.5/$30)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "copilot --allow-all --model gpt-5.5 --reasoning-effort high" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCopilotGPT56SolChoiceReturnsExplicitModelCommand(t *testing.T) {
	model := chooseCopilot(t, key("2"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "GitHub Copilot GPT-5.6 Sol ($4/$0.4/$20)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "copilot --allow-all --model gpt-5.6-sol --reasoning-effort high" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCopilotOpus5ChoiceReturnsExplicitModelCommand(t *testing.T) {
	model := chooseCopilot(t, key("3"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "GitHub Copilot Claude Opus 5 ($5/$0.5/$25)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != "copilot --allow-all --model claude-opus-5 --reasoning-effort xhigh" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingCopilotAutoChoiceUsesServerRouting(t *testing.T) {
	model := chooseCopilot(t, key("4"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "GitHub Copilot Auto (server-routed)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Description != "Let GitHub Copilot choose the model for each task" {
		t.Fatalf("Description = %q", item.Description)
	}
	if item.Command != "copilot --allow-all --model auto" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenCodeGLM53FlashChoiceReturnsOpenCodeGoCommand(t *testing.T) {
	model := chooseOpenCode(t, key("1"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenCode GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" opencode-go glm-5.3-flash` {
		t.Fatalf("Command = %q", item.Command)
	}
	if len(item.Env) != 1 || item.Env[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
		t.Fatalf("Env = %#v", item.Env)
	}
}

func TestSelectingOpenCodeKimiK3ChoiceReturnsKimiK3Command(t *testing.T) {
	model := chooseOpenCode(t, key("2"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenCode Kimi K3 ($3/$0.3/$15)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" opencode-go kimi-k3` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingMoonshotAIReturnsDirectKimiK3Command(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("5"))
	model = updated.(Model)

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Moonshot AI" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-Moonshot.ps1" kimi-k3` {
		t.Fatalf("Command = %q", item.Command)
	}
	if item.Model != "moonshot/kimi-k3" {
		t.Fatalf("Model = %q", item.Model)
	}
	if len(item.Env) != 0 {
		t.Fatalf("Env = %#v", item.Env)
	}
}

func TestSelectingOpenCodeQwen38MaxChoiceReturnsQwen38MaxCommand(t *testing.T) {
	model := chooseOpenCode(t, key("3"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenCode Qwen 3.8 Max ($2/$0.25/$6)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" opencode-go qwen3.8-max` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenCodeDeepSeekV41FlashChoiceReturnsDeepSeekV41FlashCommand(t *testing.T) {
	model := chooseOpenCode(t, key("4"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenCode DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" opencode-go deepseek-v4.1-flash` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenCodeMuseSparkV13ChoiceReturnsMuseSparkV13Command(t *testing.T) {
	model := chooseOpenCode(t, key("5"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenCode Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" opencode-go muse-spark-1.3-contributor` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenCodeHomeAndAmdModelChoices(t *testing.T) {
	tests := []struct {
		key     string
		name    string
		command string
	}{
		{"6", "OpenCode Qwen 3.8 27B (home Ollama)", `& "$repoRoot\scripts\Start-Ollama.ps1" qwen3.8:27b`},
		{"7", "OpenCode Qwen 3.8 27B (amd Ollama)", `& "$repoRoot\scripts\Start-AmdOllama.ps1" qwen3.8:27b`},
	}

	for _, test := range tests {
		t.Run(test.key, func(t *testing.T) {
			model := chooseOpenCode(t, key(test.key))
			item, ok := model.SelectedItem()
			if !ok {
				t.Fatal("SelectedItem returned no value")
			}
			if item.Name != test.name {
				t.Fatalf("Name = %q, want %q", item.Name, test.name)
			}
			if item.Command != test.command {
				t.Fatalf("Command = %q, want %q", item.Command, test.command)
			}
		})
	}
}

func TestSelectingNewOpenRouterModels(t *testing.T) {
	tests := []struct {
		key, name, model string
	}{
		{"1", "GPT 6 Astra ($10/$1/$50)", "openai/gpt-6-astra"},
		{"2", "GPT 6 Sol ($2/$0.2/$10)", "openai/gpt-6-sol"},
		{"3", "GPT 6 Luna ($0.1/$0.01/$0.5)", "openai/gpt-6-luna"},
		{"4", "GPT 5.6 Sol ($2/$0.2/$10)", "openai/gpt-5.6-sol"},
		{"5", "GPT 5.6 Luna ($0.2/$0.02/$1.2)", "openai/gpt-5.6-luna"},
		{"6", "Gemini 3.8 Flash ($0.75/$0.075/$3.75)", "google/gemini-3.8-flash"},
		{"7", "Claude Opus 5.5 ($4/$0.2/$20)", "anthropic/claude-opus-5.5"},
		{"e", "Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)", "meta/muse-spark-1.3-contributor"},
	}
	for _, test := range tests {
		t.Run(test.key, func(t *testing.T) {
			model := chooseOpenRouter(t, key(test.key))
			item, ok := model.SelectedItem()
			if !ok {
				t.Fatal("SelectedItem returned no value")
			}
			if want := "OpenRouter " + test.name; item.Name != want {
				t.Fatalf("Name = %q, want %q", item.Name, want)
			}
			if want := `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter ` + test.model; item.Command != want {
				t.Fatalf("Command = %q, want %q", item.Command, want)
			}
		})
	}
}

func TestSelectingNewTrialModels(t *testing.T) {
	tests := []struct {
		menu, key, name, model string
	}{
		{"OpenCode", "8", "MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "opencode-go mimo-v2.6-flash"},
		{"OpenCode", "9", "MiMo V2.6 Pro ($0.435/$0.003625/$0.87)", "opencode-go mimo-v2.6-pro"},
		{"OpenRouter", "g", "MiMo V2.6 Flash ($0.14/$0.0028/$0.28)", "openrouter xiaomi/mimo-v2.6-flash"},
		{"OpenRouter", "h", "MiMo V2.6 Pro ($0.435/$0.0036/$0.87)", "openrouter xiaomi/mimo-v2.6-pro"},
		{"OpenRouter", "i", "Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)", "openrouter qwen/qwen3.8-omni-flash"},
		{"OpenRouter", "j", "Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)", "openrouter prism-ml/ternary-bonsai-2-27b"},
		{"OpenRouter", "k", "GLM-5.3-FlashX ($0.37/$0.09/$1.25)", "openrouter z-ai/glm-5.3-flashx"},
	}
	for _, test := range tests {
		t.Run(test.menu+"/"+test.key, func(t *testing.T) {
			var model Model
			if test.menu == "OpenCode" {
				model = chooseOpenCode(t, key(test.key))
			} else {
				model = chooseOpenRouter(t, key(test.key))
			}
			item, ok := model.SelectedItem()
			if !ok {
				t.Fatal("SelectedItem returned no value")
			}
			if want := test.menu + " " + test.name; item.Name != want {
				t.Fatalf("Name = %q, want %q", item.Name, want)
			}
			if want := `& "$repoRoot\scripts\Start-OpenCode.ps1" ` + test.model; item.Command != want {
				t.Fatalf("Command = %q, want %q", item.Command, want)
			}
		})
	}
}

func TestSelectingOpenRouterKimiK3ChoiceReturnsKimiK3Command(t *testing.T) {
	model := chooseOpenRouter(t, key("8"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Kimi K3 ($0.66/$0.66/$10)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter moonshotai/kimi-k3` {
		t.Fatalf("Command = %q", item.Command)
	}
	if len(item.Env) != 1 || item.Env[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
		t.Fatalf("Env = %#v", item.Env)
	}
}

func TestSelectingOpenRouterQwen38MaxChoiceReturnsQwen38MaxCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("9"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Qwen 3.8 Max ($2/$0.25/$6)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter qwen/qwen3.8-max-0902` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterGLM53FlashChoiceReturnsGLM53FlashCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("a"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter GLM-5.3-Flash ($0.15/$0.03/$0.5)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter z-ai/glm-5.3-flash` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterFusionChoiceReturnsFusionCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("b"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Fusion (variable/variable)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter openrouter/fusion` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterDeepSeekV41FlashChoiceReturnsDeepSeekV41FlashCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("c"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter deepseek/deepseek-v4.1-flash` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterMuseSparkV13ChoiceReturnsMuseSparkV13Command(t *testing.T) {
	model := chooseOpenRouter(t, key("d"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Muse Spark V1.3 ($1.25/$0.15/$4.25)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter meta/muse-spark-1.3` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterMuseSparkV12ChoiceReturnsMuseSparkV12Command(t *testing.T) {
	model := chooseOpenRouter(t, key("f"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Muse Spark V1.2 ($1.25/$0.15/$4.25)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter meta/muse-spark-1.2` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterSeedream50ProChoiceReturnsImageCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("l"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Seedream 5.0 Pro ($0.045 1K/$0.09 2K)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenRouterImage.ps1"` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterSeedAudioChoiceReturnsAudioCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("m"))
	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter Seed Audio 1.0 ($0.15/min)" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenRouterAudio.ps1"` {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOllamaQwen3827BChoiceReturnsOpenCodeCommand(t *testing.T) {
	model := chooseOllama(t, key("1"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Ollama Qwen 3.8 27B" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-Ollama.ps1" qwen3.8:27b` {
		t.Fatalf("Command = %q", item.Command)
	}
	if len(item.Env) != 0 {
		t.Fatalf("Env = %#v", item.Env)
	}
}

func TestEscapeFromChoiceMenuReturnsToMainMenu(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(key("1"))
	model = updated.(Model)
	updated, _ = model.Update(specialKey(tea.KeyEsc))
	model = updated.(Model)

	if model.choiceParent != nil {
		t.Fatal("choiceParent was still set after escape")
	}
	if _, ok := model.SelectedItem(); ok {
		t.Fatal("SelectedItem returned a value after escaping choice menu")
	}
}

func TestArrowCursorCanSelectTenthItem(t *testing.T) {
	model := New(configWithItems(10))

	for range 9 {
		updated, _ := model.Update(specialKey(tea.KeyDown))
		model = updated.(Model)
	}
	updated, _ := model.Update(specialKey(tea.KeyEnter))
	model = updated.(Model)

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Item 10" {
		t.Fatalf("Name = %q", item.Name)
	}
}

func TestCursorWrapsAroundMainMenu(t *testing.T) {
	for _, up := range []tea.KeyPressMsg{specialKey(tea.KeyUp), key("k")} {
		model := New(configWithItems(3))
		updated, _ := model.Update(up)
		model = updated.(Model)
		if model.cursor != 2 {
			t.Fatalf("up from first item moved cursor to %d, want 2", model.cursor)
		}
		updated, _ = model.Update(specialKey(tea.KeyDown))
		model = updated.(Model)
		if model.cursor != 0 {
			t.Fatalf("down from last item moved cursor to %d, want 0", model.cursor)
		}
	}
}

func TestCursorWrapsAroundChoiceMenu(t *testing.T) {
	model := New(config.Default())
	updated, _ := model.Update(key("1"))
	model = updated.(Model)
	updated, _ = model.Update(specialKey(tea.KeyUp))
	model = updated.(Model)
	if want := len(model.choiceParent.Choices) - 1; model.cursor != want {
		t.Fatalf("up from first choice moved cursor to %d, want %d", model.cursor, want)
	}
	updated, _ = model.Update(specialKey(tea.KeyDown))
	model = updated.(Model)
	if model.cursor != 0 {
		t.Fatalf("down from last choice moved cursor to %d, want 0", model.cursor)
	}
}

func TestJKCursorMovementSelectsVisibleItem(t *testing.T) {
	model := New(configWithItems(3))

	updated, _ := model.Update(key("j"))
	model = updated.(Model)
	updated, _ = model.Update(key("j"))
	model = updated.(Model)
	updated, _ = model.Update(key("k"))
	model = updated.(Model)

	if !strings.Contains(model.View().Content, "> 2. Item 2") {
		t.Fatalf("View did not render cursor on Item 2:\n%s", model.View().Content)
	}

	updated, _ = model.Update(specialKey(tea.KeyEnter))
	model = updated.(Model)

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Item 2" {
		t.Fatalf("Name = %q", item.Name)
	}
}

func TestMainMenuUsesLetterForTenthItem(t *testing.T) {
	model := New(config.Default())
	if !strings.Contains(model.View().Content, "A. Claude Code") {
		t.Fatalf("View did not label Claude Code A:\n%s", model.View().Content)
	}

	for _, shortcut := range []string{"a", "A"} {
		model = New(config.Default())
		updated, _ := model.Update(key(shortcut))
		model = updated.(Model)
		item, ok := model.SelectedItem()
		if !ok || item.Name != "Claude Code" {
			t.Fatalf("key %q selected %q, ok = %v; want Claude Code", shortcut, item.Name, ok)
		}
	}
}

func TestNumberKeyAcceleratorsStopAtNine(t *testing.T) {
	model := New(configWithItems(10))

	updated, _ := model.Update(key("9"))
	model = updated.(Model)

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "Item 9" {
		t.Fatalf("Name = %q", item.Name)
	}

	for _, shortcut := range []string{"10", "b"} {
		model = New(configWithItems(10))
		updated, _ = model.Update(key(shortcut))
		model = updated.(Model)
		if _, ok := model.SelectedItem(); ok {
			t.Fatalf("key %q unexpectedly selected an item", shortcut)
		}
	}
}

func TestLongMenuDoesNotRenderPastTerminalHeight(t *testing.T) {
	model := New(configWithItems(20))

	updated, _ := model.Update(tea.WindowSizeMsg{Width: 80, Height: 5})
	model = updated.(Model)
	for range 15 {
		updated, _ = model.Update(specialKey(tea.KeyDown))
		model = updated.(Model)
	}

	content := strings.TrimSuffix(model.View().Content, "\n")
	lineCount := strings.Count(content, "\n") + 1
	if lineCount > 5 {
		t.Fatalf("View rendered %d lines, want at most 5:\n%s", lineCount, content)
	}
	if !strings.Contains(content, "> G. Item 16") {
		t.Fatalf("View did not keep the cursor visible:\n%s", content)
	}
}

func TestVeryShortTerminalUsesBoundedUnframedView(t *testing.T) {
	model := New(configWithItems(5))

	updated, _ := model.Update(tea.WindowSizeMsg{Width: 80, Height: 2})
	model = updated.(Model)

	content := strings.TrimSuffix(model.View().Content, "\n")
	lineCount := strings.Count(content, "\n") + 1
	if lineCount > 2 {
		t.Fatalf("View rendered %d lines, want at most 2:\n%s", lineCount, content)
	}
	if strings.Contains(content, "╭") || strings.Contains(content, "╰") {
		t.Fatalf("Very short view rendered a border:\n%s", content)
	}
}

func chooseCodex(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("2"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func choosePi(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("1"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func chooseCopilot(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("4"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func chooseOpenCode(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("6"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func chooseOpenRouter(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("7"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func chooseOllama(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("8"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func key(value string) tea.KeyPressMsg {
	return tea.KeyPressMsg(tea.Key{
		Text: value,
		Code: []rune(value)[0],
	})
}

func specialKey(code rune) tea.KeyPressMsg {
	return tea.KeyPressMsg(tea.Key{Code: code})
}

func configWithItems(count int) config.Config {
	cfg := config.Config{
		Title:     "Test launcher",
		Shell:     "pwsh",
		ShellArgs: []string{"-Command"},
		Items:     make([]config.LaunchItem, count),
	}

	for index := range count {
		number := index + 1
		cfg.Items[index] = config.LaunchItem{
			Name:    fmt.Sprintf("Item %d", number),
			Command: fmt.Sprintf("run-%d", number),
		}
	}

	return cfg
}
