package tui

import (
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

var launcherFrameStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(lipgloss.Color("#63B3ED")).
	Padding(0, 1)

type launchItem struct {
	config.LaunchItem
	Number int
}

func (i launchItem) Line() string {
	return fmt.Sprintf(
		"%s %-15s  model: %-18s  effort: %s",
		choiceLabel(i.Number),
		i.Name,
		valueOrDefault(i.Model, "default"),
		valueOrDefault(i.ReasoningEffort, "default"),
	)
}

type launchChoice struct {
	config.LaunchChoice
}

func (c launchChoice) Line(label string, nameWidth int, detailWidth int) string {
	name, detail := splitChoiceName(c.Name)
	if strings.TrimSpace(c.Description) == "" {
		if detailWidth > 0 {
			return fmt.Sprintf("%s %-*s  %s", label, nameWidth, name, detail)
		}
		return fmt.Sprintf("%s %s", label, c.Name)
	}

	if detailWidth == 0 {
		return fmt.Sprintf(
			"%s %-*s  %s",
			label,
			nameWidth,
			name,
			c.Description,
		)
	}

	return fmt.Sprintf(
		"%s %-*s  %-*s  %s",
		label,
		nameWidth,
		name,
		detailWidth,
		detail,
		c.Description,
	)
}

// choiceLabel names a menu item for display and keyboard selection: items 1-9
// use their number, items 10 and beyond use letters (10 -> A, 11 -> B, ...)
// so every label stays two characters wide and remains a single keypress.
func choiceLabel(number int) string {
	if number <= 9 {
		return fmt.Sprintf("%d.", number)
	}
	return fmt.Sprintf("%c.", 'A'+number-10)
}

func splitChoiceName(name string) (string, string) {
	detailStart := strings.LastIndex(name, " (")
	if detailStart < 0 || !strings.HasSuffix(name, ")") {
		return name, ""
	}
	return name[:detailStart], name[detailStart+1:]
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
		case "up":
			m.moveCursor(-1)
			return m, nil
		case "down":
			m.moveCursor(1)
			return m, nil
		case "j", "k":
			if m.choiceParent != nil {
				if selected, ok := m.launchChoiceForKey(msg.String()); ok {
					return m.selectChoice(selected)
				}
			}
			if msg.String() == "j" {
				m.moveCursor(1)
			} else {
				m.moveCursor(-1)
			}
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

	frame := launcherFrameStyle.Render(content)

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
	nameWidth := 0
	detailWidth := 0
	for _, choice := range parent.Choices {
		name, detail := splitChoiceName(choice.Name)
		nameWidth = max(nameWidth, utf8.RuneCountInString(name))
		detailWidth = max(detailWidth, utf8.RuneCountInString(detail))
	}
	for index, choice := range parent.Choices {
		line := launchChoice{
			LaunchChoice: choice,
		}.Line(choiceLabel(index+1), nameWidth, detailWidth)
		if m.width > 0 && len(line)+6 > m.width {
			line = fmt.Sprintf("%s %s", choiceLabel(index+1), choice.Name)
		}
		lines = append(lines, line)
	}
	lines = append(lines, "esc. Back")
	return lines
}

func (m Model) launchItemForKey(key string) (launchItem, bool) {
	number, ok := choiceNumberForKey(key, len(m.cfg.Items))
	if !ok {
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

	number, ok := choiceNumberForKey(key, len(m.choiceParent.Choices))
	if !ok {
		return launchChoice{}, false
	}

	return launchChoice{
		LaunchChoice: m.choiceParent.Choices[number-1],
	}, true
}

// choiceNumberForKey maps a keypress to a choice: digit keys pick choices
// 1-9, letter keys pick choices 10 and beyond ("a" is the 10th choice, "b"
// the 11th, and so on, case-insensitively).
func choiceNumberForKey(key string, choiceCount int) (int, bool) {
	if number, err := strconv.Atoi(key); err == nil {
		if number < 1 || number > 9 || number > choiceCount {
			return 0, false
		}
		return number, true
	}

	if len(key) != 1 {
		return 0, false
	}
	letter := strings.ToLower(key)[0]
	if letter < 'a' || letter > 'z' {
		return 0, false
	}

	number := 10 + int(letter-'a')
	if number > choiceCount {
		return 0, false
	}
	return number, true
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

	m.cursor = (clampCursor(m.cursor, count) + delta + count) % count
}

func (m Model) selectCursor() (tea.Model, tea.Cmd) {
	if m.choiceParent != nil {
		if len(m.choiceParent.Choices) == 0 {
			return m, nil
		}
		cursor := clampCursor(m.cursor, len(m.choiceParent.Choices))
		return m.selectChoice(launchChoice{
			LaunchChoice: m.choiceParent.Choices[cursor],
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
