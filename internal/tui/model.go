package tui

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"charm.land/bubbles/v2/list"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

type launchItem struct {
	config.LaunchItem
}

func (i launchItem) Title() string {
	return i.Name
}

func (i launchItem) Description() string {
	parts := []string{i.LaunchItem.Description}
	if len(i.Tags) > 0 {
		parts = append(parts, strings.Join(i.Tags, ", "))
	}
	return strings.Join(parts, " | ")
}

func (i launchItem) FilterValue() string {
	return strings.Join([]string{
		i.Name,
		i.LaunchItem.Description,
		i.Command,
		strings.Join(i.Tags, " "),
	}, " ")
}

type Model struct {
	cfg          config.Config
	source       string
	list         list.Model
	status       string
	lastLaunched string
}

type launchedMsg struct {
	name string
	err  error
}

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#9AE6B4")).
			Padding(0, 1)
	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FBD38D")).
			Padding(0, 1)
	footerStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#A0AEC0")).
			Padding(0, 1)
)

func New(cfg config.Config, source string) Model {
	items := make([]list.Item, 0, len(cfg.Items))
	for _, entry := range cfg.Items {
		items = append(items, launchItem{LaunchItem: entry})
	}

	delegate := list.NewDefaultDelegate()
	delegate.ShowDescription = true

	l := list.New(items, delegate, 80, 24)
	l.Title = "Launch targets"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.SetShowHelp(true)

	return Model{
		cfg:    cfg,
		source: source,
		list:   l,
		status: "Enter launches. Type to filter. q exits.",
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetSize(msg.Width, max(6, msg.Height-6))
	case tea.KeyPressMsg:
		switch msg.String() {
		case "ctrl+c", "q", "esc":
			return m, tea.Quit
		case "enter":
			selected, ok := m.list.SelectedItem().(launchItem)
			if !ok {
				m.status = "No launch target selected."
				return m, nil
			}
			m.status = fmt.Sprintf("Launching %s with %s...", selected.Name, m.cfg.Shell)
			m.lastLaunched = selected.Name
			return m, m.launch(selected)
		}
	case launchedMsg:
		if msg.err != nil {
			m.status = fmt.Sprintf("%s exited with error: %v", msg.name, msg.err)
		} else {
			m.status = fmt.Sprintf("%s exited. Select another target or press q.", msg.name)
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m Model) View() tea.View {
	header := titleStyle.Render(m.cfg.Title)
	status := statusStyle.Render(m.status)
	source := footerStyle.Render("Config: " + m.source)

	content := strings.Join([]string{
		header,
		m.list.View(),
		status,
		source,
	}, "\n")

	view := tea.NewView(content)
	view.AltScreen = true
	view.WindowTitle = m.cfg.Title
	return view
}

func (m Model) launch(item launchItem) tea.Cmd {
	args := append([]string{}, m.cfg.ShellArgs...)
	args = append(args, item.Command)

	cmd := exec.Command(m.cfg.Shell, args...)
	if strings.TrimSpace(item.WorkingDir) != "" {
		cmd.Dir = item.WorkingDir
	}
	if len(item.Env) > 0 {
		cmd.Env = append(os.Environ(), item.Env...)
	}

	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return launchedMsg{name: item.Name, err: err}
	})
}
