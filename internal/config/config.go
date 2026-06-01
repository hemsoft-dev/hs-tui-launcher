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

const defaultConfigFile = ".hs-tui-launcher.yaml"

type Config struct {
	Title     string       `yaml:"title"`
	Shell     string       `yaml:"shell"`
	ShellArgs []string     `yaml:"shell_args"`
	Items     []LaunchItem `yaml:"items"`
}

type LaunchItem struct {
	Name            string   `yaml:"name"`
	Description     string   `yaml:"description"`
	Command         string   `yaml:"command"`
	Model           string   `yaml:"model,omitempty"`
	ReasoningEffort string   `yaml:"reasoning_effort,omitempty"`
	WorkingDir      string   `yaml:"working_dir,omitempty"`
	Env             []string `yaml:"env,omitempty"`
	Tags            []string `yaml:"tags,omitempty"`
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
				Command:         "codex",
				Model:           "gpt-5.5",
				ReasoningEffort: "high",
				Tags:            []string{"ai", "openai", "cli"},
			},
			{
				Name:            "GitHub Copilot",
				Description:     "Open GitHub Copilot CLI",
				Command:         "gh copilot",
				Model:           "claude-opus-4.8",
				ReasoningEffort: "default",
				Tags:            []string{"ai", "github", "cli"},
			},
			{
				Name:            "Cursor",
				Description:     "Open the Cursor Agent CLI",
				Command:         "cursor agent",
				Model:           "claude-opus-4-8",
				ReasoningEffort: "xhigh",
				Tags:            []string{"ai", "editor", "cli"},
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
		if strings.TrimSpace(item.Command) == "" {
			return fmt.Errorf("items[%d].command is required", idx)
		}
	}
	return nil
}
