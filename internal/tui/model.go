package tui

import (
	"fmt"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

type launchItem struct {
	config.LaunchItem
	Number int
}

func (i launchItem) Line() string {
	return fmt.Sprintf(
		"%d. %-15s  model: %-18s  effort: %s",
		i.Number,
		i.Name,
		valueOrDefault(i.Model, "default"),
		valueOrDefault(i.ReasoningEffort, "default"),
	)
}

type launchChoice struct {
	config.LaunchChoice
	Number int
}

func (c launchChoice) Line() string {
	if strings.TrimSpace(c.Description) == "" {
		return fmt.Sprintf("%d. %s", c.Number, c.Name)
	}

	return fmt.Sprintf(
		"%d. %s  %s",
		c.Number,
		c.Name,
		c.Description,
	)
}

type Model struct {
	cfg          config.Config
	choiceParent *launchItem
	selected     *config.LaunchItem
	cursor       int
	width        int
	height       int
}

func New(cfg config.Config) Model {
	return Model{
		cfg: cfg,
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case tea.KeyPressMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "esc":
			if m.choiceParent != nil {
				m.cursor = clampCursor(m.choiceParent.Number-1, len(m.cfg.Items))
				m.choiceParent = nil
				return m, nil
			}
			return m, tea.Quit
		case "up", "k":
			m.moveCursor(-1)
			return m, nil
		case "down", "j":
			m.moveCursor(1)
			return m, nil
		case "enter":
			return m.selectCursor()
		default:
			if m.choiceParent != nil {
				selected, ok := m.launchChoiceForKey(msg.String())
				if ok {
					return m.selectChoice(selected)
				}
				return m, nil
			}

			selected, ok := m.launchItemForKey(msg.String())
			if ok {
				return m.selectItem(selected)
			}
		}
	}

	return m, nil
}

func (m Model) View() tea.View {
	lines := m.displayLines()

	content := strings.Join(lines, "\n")

	if m.height > 0 && m.height < 3 {
		view := tea.NewView(content + "\n")
		view.AltScreen = false
		return view
	}

	frame := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#63B3ED")).
		Padding(0, 1).
		Render(content)

	view := tea.NewView(frame + "\n")
	view.AltScreen = false
	return view
}

func (m Model) displayLines() []string {
	lines := m.menuLines()
	if len(lines) == 0 {
		return lines
	}

	selectableOffset := 0
	selectableCount := len(m.cfg.Items)
	if m.choiceParent != nil {
		selectableOffset = 1
		selectableCount = len(m.choiceParent.Choices)
	}

	cursorLine := -1
	if selectableCount > 0 {
		cursor := clampCursor(m.cursor, selectableCount)
		cursorLine = selectableOffset + cursor
		lines = prefixCursor(lines, selectableOffset, selectableCount, cursorLine)
	}

	return m.fitLines(lines, cursorLine)
}

func prefixCursor(lines []string, selectableOffset int, selectableCount int, cursorLine int) []string {
	prefixed := make([]string, len(lines))
	copy(prefixed, lines)

	for index := selectableOffset; index < selectableOffset+selectableCount && index < len(prefixed); index++ {
		prefix := "  "
		if index == cursorLine {
			prefix = "> "
		}
		prefixed[index] = prefix + prefixed[index]
	}

	return prefixed
}

func (m Model) fitLines(lines []string, cursorLine int) []string {
	maxLines := m.contentHeight()
	if maxLines <= 0 || len(lines) <= maxLines {
		return lines
	}

	start := 0
	if cursorLine >= maxLines {
		start = cursorLine - maxLines + 1
	}
	if start+maxLines > len(lines) {
		start = len(lines) - maxLines
	}

	return lines[start : start+maxLines]
}

func (m Model) contentHeight() int {
	if m.height <= 0 {
		return 0
	}

	contentHeight := m.height - 2
	if contentHeight < 1 {
		return 1
	}
	return contentHeight
}

func (m Model) menuLines() []string {
	if m.choiceParent != nil {
		return m.choiceLines()
	}

	lines := make([]string, 0, len(m.cfg.Items))
	for index, item := range m.cfg.Items {
		lines = append(lines, launchItem{
			LaunchItem: item,
			Number:     index + 1,
		}.Line())
	}
	return lines
}

func (m Model) choiceLines() []string {
	parent := *m.choiceParent
	lines := make([]string, 0, len(parent.Choices)+2)
	lines = append(lines, fmt.Sprintf("%s:", parent.Name))
	for index, choice := range parent.Choices {
		line := launchChoice{
			LaunchChoice: choice,
			Number:       index + 1,
		}.Line()
		if m.width > 0 && len(line)+6 > m.width {
			line = fmt.Sprintf("%d. %s", index+1, choice.Name)
		}
		lines = append(lines, line)
	}
	lines = append(lines, "esc. Back")
	return lines
}

func (m Model) launchItemForKey(key string) (launchItem, bool) {
	number, err := strconv.Atoi(key)
	if err != nil || number < 1 || number > len(m.cfg.Items) || number > 9 {
		return launchItem{}, false
	}

	return launchItem{
		LaunchItem: m.cfg.Items[number-1],
		Number:     number,
	}, true
}

func (m Model) launchChoiceForKey(key string) (launchChoice, bool) {
	if m.choiceParent == nil {
		return launchChoice{}, false
	}

	number, err := strconv.Atoi(key)
	if err != nil || number < 1 || number > len(m.choiceParent.Choices) || number > 9 {
		return launchChoice{}, false
	}

	return launchChoice{
		LaunchChoice: m.choiceParent.Choices[number-1],
		Number:       number,
	}, true
}

func (m Model) selectItem(item launchItem) (tea.Model, tea.Cmd) {
	if len(item.Choices) > 0 {
		selected := item
		m.choiceParent = &selected
		m.cursor = 0
		return m, nil
	}

	selected := item.LaunchItem
	m.selected = &selected
	return m, tea.Quit
}

func (m *Model) moveCursor(delta int) {
	count := m.selectableCount()
	if count == 0 {
		m.cursor = 0
		return
	}

	m.cursor = clampCursor(m.cursor+delta, count)
}

func (m Model) selectCursor() (tea.Model, tea.Cmd) {
	if m.choiceParent != nil {
		if len(m.choiceParent.Choices) == 0 {
			return m, nil
		}
		cursor := clampCursor(m.cursor, len(m.choiceParent.Choices))
		return m.selectChoice(launchChoice{
			LaunchChoice: m.choiceParent.Choices[cursor],
			Number:       cursor + 1,
		})
	}

	if len(m.cfg.Items) == 0 {
		return m, nil
	}
	cursor := clampCursor(m.cursor, len(m.cfg.Items))
	return m.selectItem(launchItem{
		LaunchItem: m.cfg.Items[cursor],
		Number:     cursor + 1,
	})
}

func (m Model) selectableCount() int {
	if m.choiceParent != nil {
		return len(m.choiceParent.Choices)
	}
	return len(m.cfg.Items)
}

func (m Model) selectChoice(choice launchChoice) (tea.Model, tea.Cmd) {
	selected := m.choiceParent.LaunchItem
	selected.Name = fmt.Sprintf("%s %s", selected.Name, choice.Name)
	selected.Description = valueOrDefault(choice.Description, selected.Description)
	selected.Command = choice.Command
	selected.Choices = nil
	m.selected = &selected
	return m, tea.Quit
}

func (m Model) SelectedItem() (config.LaunchItem, bool) {
	if m.selected == nil {
		return config.LaunchItem{}, false
	}

	return *m.selected, true
}

func clampCursor(cursor int, itemCount int) int {
	if itemCount <= 0 || cursor < 0 {
		return 0
	}
	if cursor >= itemCount {
		return itemCount - 1
	}
	return cursor
}

func valueOrDefault(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}

	return value
}
