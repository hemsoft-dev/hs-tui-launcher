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

type Model struct {
	cfg          config.Config
	status       string
	lastLaunched string
	selected     *config.LaunchItem
}

func New(cfg config.Config, source string) Model {
	return Model{
		cfg:    cfg,
		status: fmt.Sprintf("Press %s.", numberRange(len(cfg.Items))),
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyPressMsg:
		switch msg.String() {
		case "ctrl+c", "q", "esc":
			return m, tea.Quit
		default:
			selected, ok := m.launchItemForKey(msg.String())
			if ok {
				return m.selectItem(selected)
			}
		}
	}

	return m, nil
}

func (m Model) View() tea.View {
	lines := m.menuLines()

	content := strings.Join(lines, "\n")

	frame := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#63B3ED")).
		Padding(0, 1).
		Render(content)

	view := tea.NewView(frame + "\n")
	view.AltScreen = false
	return view
}

func (m Model) menuLines() []string {
	lines := make([]string, 0, len(m.cfg.Items))
	for index, item := range m.cfg.Items {
		lines = append(lines, launchItem{
			LaunchItem: item,
			Number:     index + 1,
		}.Line())
	}
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

func (m Model) selectItem(item launchItem) (tea.Model, tea.Cmd) {
	selected := item.LaunchItem
	m.selected = &selected
	m.status = fmt.Sprintf("Selected %s.", item.Name)
	m.lastLaunched = item.Name
	return m, tea.Quit
}

func (m Model) SelectedItem() (config.LaunchItem, bool) {
	if m.selected == nil {
		return config.LaunchItem{}, false
	}

	return *m.selected, true
}

func numberRange(itemCount int) string {
	if itemCount <= 0 {
		return "a number"
	}
	if itemCount == 1 {
		return "1"
	}

	return fmt.Sprintf("1-%d", min(itemCount, 9))
}

func valueOrDefault(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}

	return value
}
