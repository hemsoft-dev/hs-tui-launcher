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

	updated, _ := model.Update(key("1"))
	model = updated.(Model)

	lines := model.choiceLines()
	if lines[3] != "3. Resume picker  Choose a Codex CLI session to resume" {
		t.Fatalf("Resume picker line = %q", lines[3])
	}
}

func TestChoiceMenuFallsBackToNamesForNarrowWidth(t *testing.T) {
	model := New(config.Default())

	updated, _ := model.Update(tea.WindowSizeMsg{Width: 45})
	model = updated.(Model)
	updated, _ = model.Update(key("1"))
	model = updated.(Model)

	lines := model.choiceLines()
	if lines[3] != "3. Resume picker" {
		t.Fatalf("Resume picker line = %q", lines[3])
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
	if item.Command != "codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
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
	if item.Command != "codex resume --last --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
		t.Fatalf("Command = %q", item.Command)
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
	if item.Command != "codex resume --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestSelectingOpenRouterGLMChoiceReturnsGLMCommand(t *testing.T) {
	model := chooseOpenRouter(t, key("1"))

	item, ok := model.SelectedItem()
	if !ok {
		t.Fatal("SelectedItem returned no value")
	}
	if item.Name != "OpenRouter GLM 5.2" {
		t.Fatalf("Name = %q", item.Name)
	}
	if item.Command != `& "$repoRoot\scripts\Start-OpenCode.ps1" -Provider openrouter -Model z-ai/glm-5.2` {
		t.Fatalf("Command = %q", item.Command)
	}
	if len(item.Env) != 1 || item.Env[0] != `OPENCODE_PERMISSION={"*":"allow"}` {
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

	model = New(configWithItems(10))
	updated, _ = model.Update(key("10"))
	model = updated.(Model)
	if _, ok := model.SelectedItem(); ok {
		t.Fatal("Synthetic multi-digit key unexpectedly selected an item")
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
	if !strings.Contains(content, "> 16. Item 16") {
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
	updated, _ := model.Update(key("1"))
	model = updated.(Model)
	updated, _ = model.Update(choice)
	return updated.(Model)
}

func chooseOpenRouter(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default())
	updated, _ := model.Update(key("6"))
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
