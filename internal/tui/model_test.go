package tui

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

func TestSelectingItemWithChoicesWaitsForChoice(t *testing.T) {
	model := New(config.Default(), "test")

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
	model := New(config.Default(), "test")

	updated, _ := model.Update(key("1"))
	model = updated.(Model)

	lines := model.choiceLines()
	if lines[3] != "3. Resume picker  Choose a Codex CLI session to resume" {
		t.Fatalf("Resume picker line = %q", lines[3])
	}
}

func TestChoiceMenuFallsBackToNamesForNarrowWidth(t *testing.T) {
	model := New(config.Default(), "test")

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
	if item.Command != "codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
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
	if item.Command != "codex resume --last --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
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
	if item.Command != "codex resume --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'" {
		t.Fatalf("Command = %q", item.Command)
	}
}

func TestEscapeFromChoiceMenuReturnsToMainMenu(t *testing.T) {
	model := New(config.Default(), "test")

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

func chooseCodex(t *testing.T, choice tea.KeyPressMsg) Model {
	t.Helper()

	model := New(config.Default(), "test")
	updated, _ := model.Update(key("1"))
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
