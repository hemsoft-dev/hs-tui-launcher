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
	defaultConfigFile = ".hs-tui-launcher.yaml"

	gpt56SolModel       = "gpt-5.6-sol"
	copilotGPT55Model   = "gpt-5.5"
	claudeModel         = "claude-opus-4.8"
	copilotOpus5Model   = "claude-opus-5"
	selectModel         = "select model"
	highReasoning       = "high"
	xhighReasoning      = "xhigh"
	defaultReasoning    = "default"
	cursorAgentCommand  = "cursor-agent --disable-auto-update"
	opencodeGoProvider  = "opencode-go"
	openrouterProvider  = "openrouter"
	kimiK3Model         = "kimi-k3"
	opencodeQwen38Model = "qwen3.8-max"
	opencodeGLM52Model  = "glm-5.2"
	openrouterKimiK3    = "moonshotai/kimi-k3"
	qwen38MaxModel      = "qwen/qwen3.8-max"
	glmModel            = "z-ai/glm-5.2"
	fusionModel         = "openrouter/fusion"
)

var (
	codexPreset           = modelPreset{Model: gpt56SolModel, ReasoningEffort: highReasoning}
	copilotGPT55Preset    = modelPreset{Model: copilotGPT55Model, ReasoningEffort: highReasoning}
	copilotGPT56SolPreset = modelPreset{Model: gpt56SolModel, ReasoningEffort: highReasoning}
	copilotOpus5Preset    = modelPreset{Model: copilotOpus5Model, ReasoningEffort: xhighReasoning}
	cursorPreset          = modelPreset{Model: claudeModel, ReasoningEffort: xhighReasoning}
	claudeCodePreset      = modelPreset{Model: claudeModel, ReasoningEffort: defaultReasoning}
	modelMenuPreset       = modelPreset{Model: selectModel, ReasoningEffort: defaultReasoning}

	codexFreshCommand        = codexCommand("")
	codexResumeCommand       = codexCommand("resume --last")
	codexResumePickerCommand = codexCommand("resume")
	copilotGPT55Command      = copilotCommand(copilotGPT55Preset)
	copilotGPT56SolCommand   = copilotCommand(copilotGPT56SolPreset)
	copilotOpus5Command      = copilotCommand(copilotOpus5Preset)
	opencodeKimiK3Command    = openCodeCommand(opencodeGoProvider, kimiK3Model)
	opencodeQwen38Command    = openCodeCommand(opencodeGoProvider, opencodeQwen38Model)
	opencodeGLM52Command     = openCodeCommand(opencodeGoProvider, opencodeGLM52Model)
	openrouterKimiK3Command  = openCodeCommand(openrouterProvider, openrouterKimiK3)
	openrouterQwen38Command  = openCodeCommand(openrouterProvider, qwen38MaxModel)
	openrouterGLMCommand     = openCodeCommand(openrouterProvider, glmModel)
	openrouterFusionCommand  = openCodeCommand(openrouterProvider, fusionModel)
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

type modelPreset struct {
	Model           string
	ReasoningEffort string
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
				Model:           codexPreset.Model,
				ReasoningEffort: codexPreset.ReasoningEffort,
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
				Model:           modelMenuPreset.Model,
				ReasoningEffort: modelMenuPreset.ReasoningEffort,
				Tags:            []string{"ai", "github", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "GPT-5.5",
						Description: "Use GPT-5.5 with high reasoning effort",
						Command:     copilotGPT55Command,
					},
					{
						Name:        "GPT-5.6 Sol",
						Description: "Use GPT-5.6 Sol with high reasoning effort",
						Command:     copilotGPT56SolCommand,
					},
					{
						Name:        "Claude Opus 5",
						Description: "Use Claude Opus 5 with xhigh reasoning effort",
						Command:     copilotOpus5Command,
					},
				},
			},
			{
				Name:            "Cursor",
				Description:     "Open the Cursor Agent CLI",
				Command:         cursorAgentCommand,
				Model:           cursorPreset.Model,
				ReasoningEffort: cursorPreset.ReasoningEffort,
				Tags:            []string{"ai", "editor", "cli"},
			},
			{
				Name:            "Claude Code",
				Description:     "Open Claude Code CLI",
				Command:         "claude --dangerously-skip-permissions",
				Model:           claudeCodePreset.Model,
				ReasoningEffort: claudeCodePreset.ReasoningEffort,
				Tags:            []string{"ai", "anthropic", "cli"},
			},
			{
				Name:            "OpenCode",
				Description:     "Open OpenCode",
				Model:           modelMenuPreset.Model,
				ReasoningEffort: modelMenuPreset.ReasoningEffort,
				Env:             []string{`OPENCODE_PERMISSION={"*":"allow"}`},
				Tags:            []string{"ai", "opencode", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "Kimi K3",
						Description: modelDescription(opencodeGoProvider, kimiK3Model),
						Command:     opencodeKimiK3Command,
					},
					{
						Name:        "Qwen 3.8 Max",
						Description: modelDescription(opencodeGoProvider, opencodeQwen38Model),
						Command:     opencodeQwen38Command,
					},
					{
						Name:        "GLM 5.2",
						Description: modelDescription(opencodeGoProvider, opencodeGLM52Model),
						Command:     opencodeGLM52Command,
					},
				},
			},
			{
				Name:            "OpenRouter",
				Description:     "Open OpenCode with OpenRouter",
				Model:           modelMenuPreset.Model,
				ReasoningEffort: modelMenuPreset.ReasoningEffort,
				Env:             []string{`OPENCODE_PERMISSION={"*":"allow"}`},
				Tags:            []string{"ai", "openrouter", "opencode", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "Kimi K3 ($3/$15)",
						Description: modelDescription(openrouterProvider, openrouterKimiK3),
						Command:     openrouterKimiK3Command,
					},
					{
						Name:        "Qwen 3.8 Max ($2/$6)",
						Description: modelDescription(openrouterProvider, qwen38MaxModel),
						Command:     openrouterQwen38Command,
					},
					{
						Name:        "GLM 5.2 ($0.76/$2.42)",
						Description: modelDescription(openrouterProvider, glmModel),
						Command:     openrouterGLMCommand,
					},
					{
						Name:        "Fusion (variable/variable)",
						Description: modelDescription(openrouterProvider, fusionModel),
						Command:     openrouterFusionCommand,
					},
				},
			},
		},
	}
}

func codexCommand(subcommand string) string {
	parts := []string{"codex"}
	if strings.TrimSpace(subcommand) != "" {
		parts = append(parts, strings.Fields(subcommand)...)
	}
	parts = append(parts,
		"--dangerously-bypass-approvals-and-sandbox",
		"-m", codexPreset.Model,
		"-c", `'service_tier="default"'`,
		"-c", fmt.Sprintf(`'model_reasoning_effort="%s"'`, codexPreset.ReasoningEffort),
	)
	return strings.Join(parts, " ")
}

func copilotCommand(preset modelPreset) string {
	return strings.Join([]string{
		"copilot",
		"--allow-all",
		"--model", preset.Model,
		"--reasoning-effort", preset.ReasoningEffort,
	}, " ")
}

func openCodeCommand(provider string, model string) string {
	// run.ps1 launches structured arguments through PowerShell array splatting.
	// Use positional script arguments because parameter-name strings in an array
	// are bound as values instead of named parameters.
	return fmt.Sprintf(`& "$repoRoot\scripts\Start-OpenCode.ps1" %s %s`, provider, model)
}

func modelDescription(provider string, model string) string {
	return provider + "/" + model
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
