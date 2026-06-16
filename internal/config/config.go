package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"gopkg.in/yaml.v3"
)

const (
	defaultConfigFile        = ".hs-tui-launcher.yaml"
	codexFreshCommand        = "codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'"
	codexResumeCommand       = "codex resume --last --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'"
	codexResumePickerCommand = "codex resume --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c 'service_tier=\"default\"' -c 'model_reasoning_effort=\"high\"'"
	copilotCommand           = "copilot --allow-all"
)

type Config struct {
	Title     string       `yaml:"title"`
	Shell     string       `yaml:"shell"`
	ShellArgs []string     `yaml:"shell_args"`
	Items     []LaunchItem `yaml:"items"`
}

type LaunchItem struct {
	Name            string         `yaml:"name"`
	Description     string         `yaml:"description"`
	Command         string         `yaml:"command,omitempty"`
	Model           string         `yaml:"model,omitempty"`
	ReasoningEffort string         `yaml:"reasoning_effort,omitempty"`
	WorkingDir      string         `yaml:"working_dir,omitempty"`
	Env             []string       `yaml:"env,omitempty"`
	Tags            []string       `yaml:"tags,omitempty"`
	Choices         []LaunchChoice `yaml:"choices,omitempty"`
}

type LaunchChoice struct {
	Name        string `yaml:"name"`
	Description string `yaml:"description,omitempty"`
	Command     string `yaml:"command"`
}

func Load(path string) (Config, string, error) {
	if strings.TrimSpace(path) != "" {
		cfg, err := loadFile(path)
		return cfg, path, err
	}

	if _, err := os.Stat(defaultConfigFile); err == nil {
		cfg, err := loadFile(defaultConfigFile)
		return cfg, defaultConfigFile, err
	} else if !errors.Is(err, os.ErrNotExist) {
		return Config{}, "", fmt.Errorf("inspect config: %w", err)
	}

	cfg := Default()
	return cfg, "built-in defaults", nil
}

func Default() Config {
	shell := "pwsh"
	if runtime.GOOS == "windows" {
		shell = "powershell.exe"
	}

	return Config{
		Title:     "HemSoft TUI Launcher",
		Shell:     shell,
		ShellArgs: []string{"-NoLogo", "-Command"},
		Items: []LaunchItem{
			{
				Name:            "Codex",
				Description:     "Open the Codex CLI",
				Model:           "gpt-5.5",
				ReasoningEffort: "high",
				Tags:            []string{"ai", "openai", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "Start fresh",
						Description: "Open a new Codex CLI session",
						Command:     codexFreshCommand,
					},
					{
						Name:        "Resume last",
						Description: "Resume the last Codex CLI session",
						Command:     codexResumeCommand,
					},
					{
						Name:        "Resume picker",
						Description: "Choose a Codex CLI session to resume",
						Command:     codexResumePickerCommand,
					},
				},
			},
			{
				Name:            "GitHub Copilot",
				Description:     "Open GitHub Copilot CLI",
				Command:         copilotCommand,
				Model:           "gpt-5.5",
				ReasoningEffort: "high",
				Tags:            []string{"ai", "github", "cli"},
			},
			{
				Name:            "Cursor",
				Description:     "Open the Cursor Agent CLI",
				Command:         "cursor-agent",
				Model:           "claude-opus-4-8",
				ReasoningEffort: "xhigh",
				Tags:            []string{"ai", "editor", "cli"},
			},
			{
				Name:            "Claude Code",
				Description:     "Open Claude Code CLI",
				Command:         "claude --dangerously-skip-permissions",
				Model:           "claude-opus-4.8",
				ReasoningEffort: "default",
				Tags:            []string{"ai", "anthropic", "cli"},
			},
			{
				Name:            "OpenCode Kimi K2.7 Code",
				Description:     "Open OpenCode with Kimi K2.7 Code",
				Command:         "opencode --model opencode-go/kimi-k2.7-code",
				Model:           "opencode-go/kimi-k2.7-code",
				ReasoningEffort: "default",
				Env:             []string{`OPENCODE_PERMISSION={"*":"allow"}`},
				Tags:            []string{"ai", "opencode", "cli"},
			},
		},
	}
}

func loadFile(path string) (Config, error) {
	content, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return Config{}, fmt.Errorf("read config %q: %w", path, err)
	}

	cfg := Default()
	if err := yaml.Unmarshal(content, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config %q: %w", path, err)
	}
	if err := cfg.Validate(); err != nil {
		return Config{}, fmt.Errorf("validate config %q: %w", path, err)
	}

	return cfg, nil
}

func (c Config) Validate() error {
	if strings.TrimSpace(c.Title) == "" {
		return errors.New("title is required")
	}
	if strings.TrimSpace(c.Shell) == "" {
		return errors.New("shell is required")
	}
	if len(c.Items) == 0 {
		return errors.New("at least one launcher item is required")
	}
	for idx, item := range c.Items {
		if strings.TrimSpace(item.Name) == "" {
			return fmt.Errorf("items[%d].name is required", idx)
		}
		hasCommand := strings.TrimSpace(item.Command) != ""
		hasChoices := len(item.Choices) > 0
		if !hasCommand && !hasChoices {
			return fmt.Errorf("items[%d].command or choices are required", idx)
		}
		for choiceIdx, choice := range item.Choices {
			if strings.TrimSpace(choice.Name) == "" {
				return fmt.Errorf("items[%d].choices[%d].name is required", idx, choiceIdx)
			}
			if strings.TrimSpace(choice.Command) == "" {
				return fmt.Errorf("items[%d].choices[%d].command is required", idx, choiceIdx)
			}
		}
	}
	return nil
}
