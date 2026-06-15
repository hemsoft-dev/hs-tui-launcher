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
	status       string
	lastLaunched string
	choiceParent *launchItem
	selected     *config.LaunchItem
	width        int
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
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil
	case tea.KeyPressMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "esc":
			if m.choiceParent != nil {
				m.choiceParent = nil
				m.status = fmt.Sprintf("Press %s.", numberRange(len(m.cfg.Items)))
				return m, nil
			}
			return m, tea.Quit
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
		if m.width > 0 && len(line)+4 > m.width {
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
		m.status = fmt.Sprintf("Select %s mode.", item.Name)
		return m, nil
	}

	selected := item.LaunchItem
	m.selected = &selected
	m.status = fmt.Sprintf("Selected %s.", item.Name)
	m.lastLaunched = item.Name
	return m, tea.Quit
}

func (m Model) selectChoice(choice launchChoice) (tea.Model, tea.Cmd) {
	selected := m.choiceParent.LaunchItem
	selected.Name = fmt.Sprintf("%s %s", selected.Name, choice.Name)
	selected.Description = valueOrDefault(choice.Description, selected.Description)
	selected.Command = choice.Command
	selected.Choices = nil
	m.selected = &selected
	m.status = fmt.Sprintf("Selected %s.", selected.Name)
	m.lastLaunched = selected.Name
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
