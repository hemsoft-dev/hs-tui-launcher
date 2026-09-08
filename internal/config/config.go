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

	gpt6AstraModel                 = "gpt-6-astra"
	gpt56SolModel                  = "gpt-5.6-sol"
	gpt56LunaModel                 = "gpt-5.6-luna"
	copilotGPT55Model              = "gpt-5.5"
	claudeModel                    = "claude-opus-4.8"
	copilotOpus5Model              = "claude-opus-5"
	selectModel                    = "select model"
	mediumReasoning                = "medium"
	highReasoning                  = "high"
	maxReasoning                   = "max"
	xhighReasoning                 = "xhigh"
	defaultReasoning               = "default"
	defaultServiceTier             = "default"
	fastServiceTier                = "fast"
	antigravityAgentCommand        = "agy --dangerously-skip-permissions"
	cursorAgentCommand             = "cursor-agent --disable-auto-update"
	opencodeGoProvider             = "opencode-go"
	openaiCodexProvider            = "openai-codex"
	openrouterProvider             = "openrouter"
	moonshotProvider               = "moonshot"
	ollamaProvider                 = "ollama"
	kimiK3Model                    = "kimi-k3"
	ollamaQwen3827BModel           = "qwen3.8:27b"
	opencodeQwen38Model            = "qwen3.8-max"
	opencodeGLM53FlashModel        = "glm-5.3-flash"
	opencodeDeepSeekV4FlashModel   = "deepseek-v4-flash"
	opencodeMuseSpark13Model       = "muse-spark-1.3-contributor"
	openrouterKimiK3               = "moonshotai/kimi-k3"
	openrouterDeepSeekV4FlashModel = "deepseek/deepseek-v4-flash-0731"
	openrouterMuseSpark13Model     = "meta/muse-spark-1.3"
	openrouterMuseSpark12Model     = "meta/muse-spark-1.2"
	openrouterSeedream50ProModel   = "bytedance-seed/seedream-5-0-pro"
	qwen38MaxModel                 = "qwen/qwen3.8-max"
	openrouterGLM53FlashModel      = "z-ai/glm-5.3-flash"
	fusionModel                    = "openrouter/fusion"
	moonshotLauncherCommand        = `& "$repoRoot\scripts\Start-Moonshot.ps1" kimi-k3`
	ollamaQwen3827BCommand         = `& "$repoRoot\scripts\Start-Ollama.ps1" qwen3.8:27b`
	amdOllamaQwen3827BCommand      = `& "$repoRoot\scripts\Start-AmdOllama.ps1" qwen3.8:27b`
	openrouterSeedreamCommand      = `& "$repoRoot\scripts\Start-OpenRouterImage.ps1"`
)

var (
	codexPreset            = modelPreset{Model: gpt6AstraModel, ReasoningEffort: highReasoning, ServiceTier: defaultServiceTier}
	codexSolHighPreset     = modelPreset{Model: gpt56SolModel, ReasoningEffort: highReasoning, ServiceTier: defaultServiceTier}
	copilotGPT55Preset     = modelPreset{Model: copilotGPT55Model, ReasoningEffort: highReasoning}
	copilotGPT56SolPreset  = modelPreset{Model: gpt56SolModel, ReasoningEffort: highReasoning}
	copilotOpus5Preset     = modelPreset{Model: copilotOpus5Model, ReasoningEffort: xhighReasoning}
	cursorPreset           = modelPreset{Model: claudeModel, ReasoningEffort: xhighReasoning}
	claudeCodePreset       = modelPreset{Model: claudeModel, ReasoningEffort: defaultReasoning}
	modelMenuPreset        = modelPreset{Model: selectModel, ReasoningEffort: defaultReasoning}
	codexSolHighFastPreset = modelPreset{Model: gpt56SolModel, ReasoningEffort: highReasoning, ServiceTier: fastServiceTier}
	codexLunaPreset        = modelPreset{Model: gpt56LunaModel, ReasoningEffort: mediumReasoning, ServiceTier: defaultServiceTier}
	codexLunaFastPreset    = modelPreset{Model: gpt56LunaModel, ReasoningEffort: mediumReasoning, ServiceTier: fastServiceTier}

	codexFreshCommand            = codexCommand("", codexPreset)
	codexResumeCommand           = codexCommand("resume --last", codexPreset)
	codexResumePickerCommand     = codexCommand("resume", codexPreset)
	codexSolHighCommand          = codexCommand("", codexSolHighPreset)
	codexSolHighFastCommand      = codexCommand("", codexSolHighFastPreset)
	codexLunaCommand             = codexCommand("", codexLunaPreset)
	codexLunaFastCommand         = codexCommand("", codexLunaFastPreset)
	copilotGPT55Command          = copilotCommand(copilotGPT55Preset)
	copilotGPT56SolCommand       = copilotCommand(copilotGPT56SolPreset)
	copilotOpus5Command          = copilotCommand(copilotOpus5Preset)
	opencodeKimiK3Command        = openCodeCommand(opencodeGoProvider, kimiK3Model)
	opencodeQwen38Command        = openCodeCommand(opencodeGoProvider, opencodeQwen38Model)
	opencodeGLM53FlashCommand    = openCodeCommand(opencodeGoProvider, opencodeGLM53FlashModel)
	opencodeDeepSeekCommand      = openCodeCommand(opencodeGoProvider, opencodeDeepSeekV4FlashModel)
	opencodeMuseSpark13Command   = openCodeCommand(opencodeGoProvider, opencodeMuseSpark13Model)
	piGLM53FlashCommand          = piCommand(opencodeGLM53FlashModel)
	piKimiK3Command              = piCommand(kimiK3Model)
	piQwen38Command              = piCommand(opencodeQwen38Model)
	piDeepSeekCommand            = piCommand(opencodeDeepSeekV4FlashModel)
	piMuseSpark13Command         = piCommand(opencodeMuseSpark13Model)
	piCodexAstraCommand          = piThinkingCommand(openaiCodexProvider, gpt6AstraModel, mediumReasoning)
	piCodexSolHighCommand        = piThinkingCommand(openaiCodexProvider, gpt56SolModel, highReasoning)
	piCodexLunaMaxCommand        = piThinkingCommand(openaiCodexProvider, gpt56LunaModel, maxReasoning)
	openrouterKimiK3Command      = openCodeCommand(openrouterProvider, openrouterKimiK3)
	openrouterQwen38Command      = openCodeCommand(openrouterProvider, qwen38MaxModel)
	openrouterGLM53FlashCommand  = openCodeCommand(openrouterProvider, openrouterGLM53FlashModel)
	openrouterFusionCommand      = openCodeCommand(openrouterProvider, fusionModel)
	openrouterDeepSeekCommand    = openCodeCommand(openrouterProvider, openrouterDeepSeekV4FlashModel)
	openrouterMuseSpark13Command = openCodeCommand(openrouterProvider, openrouterMuseSpark13Model)
	openrouterMuseSpark12Command = openCodeCommand(openrouterProvider, openrouterMuseSpark12Model)
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
	ServiceTier     string
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
				Name:            "Pi",
				Description:     "Open the Pi CLI",
				Model:           modelMenuPreset.Model,
				ReasoningEffort: modelMenuPreset.ReasoningEffort,
				Tags:            []string{"ai", "pi", "openai", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "GPT 6 Astra",
						Description: modelDescription(openaiCodexProvider, gpt6AstraModel) + " at medium reasoning",
						Command:     piCodexAstraCommand,
					},
					{
						Name:        "GPT 5.6 Sol High",
						Description: modelDescription(openaiCodexProvider, gpt56SolModel) + " at high reasoning",
						Command:     piCodexSolHighCommand,
					},
					{
						Name:        "GPT 5.6 Luna Max",
						Description: modelDescription(openaiCodexProvider, gpt56LunaModel) + " at max reasoning",
						Command:     piCodexLunaMaxCommand,
					},
					{
						Name:        "GLM-5.3-Flash (2x usage)",
						Description: modelDescription(opencodeGoProvider, opencodeGLM53FlashModel),
						Command:     piGLM53FlashCommand,
					},
					{
						Name:        "Kimi K3",
						Description: modelDescription(opencodeGoProvider, kimiK3Model),
						Command:     piKimiK3Command,
					},
					{
						Name:        "Qwen 3.8 Max",
						Description: modelDescription(opencodeGoProvider, opencodeQwen38Model),
						Command:     piQwen38Command,
					},
					{
						Name:        "DeepSeek V4 Flash",
						Description: modelDescription(opencodeGoProvider, opencodeDeepSeekV4FlashModel),
						Command:     piDeepSeekCommand,
					},
					{
						Name:        "Muse Spark V1.3 Contributor",
						Description: modelDescription(opencodeGoProvider, opencodeMuseSpark13Model),
						Command:     piMuseSpark13Command,
					},
				},
			},
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
					{
						Name:        "GPT 5.6 Sol High",
						Description: "Start Codex with GPT-5.6 Sol at high reasoning",
						Command:     codexSolHighCommand,
					},
					{
						Name:        "GPT 5.6 Sol High/Fast",
						Description: "Start Codex with GPT-5.6 Sol at high reasoning and fast service",
						Command:     codexSolHighFastCommand,
					},
					{
						Name:        "GPT 5.6 Luna",
						Description: "Start Codex with GPT-5.6 Luna at medium reasoning",
						Command:     codexLunaCommand,
					},
					{
						Name:        "GPT 5.6 Luna/Fast",
						Description: "Start Codex with GPT-5.6 Luna at medium reasoning and fast service",
						Command:     codexLunaFastCommand,
					},
				},
			},
			{
				Name:            "Antigravity",
				Description:     "Open the Antigravity CLI",
				Command:         antigravityAgentCommand,
				ReasoningEffort: defaultReasoning,
				Tags:            []string{"ai", "google", "cli"},
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
				Name:            "Moonshot AI",
				Description:     "Open Kimi K3 with Moonshot AI credits",
				Command:         moonshotLauncherCommand,
				Model:           modelDescription(moonshotProvider, kimiK3Model),
				ReasoningEffort: defaultReasoning,
				Tags:            []string{"ai", "moonshot", "kimi", "opencode", "cli"},
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
						Name:        "GLM-5.3-Flash (2x usage)",
						Description: modelDescription(opencodeGoProvider, opencodeGLM53FlashModel),
						Command:     opencodeGLM53FlashCommand,
					},
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
						Name:        "DeepSeek V4 Flash",
						Description: modelDescription(opencodeGoProvider, opencodeDeepSeekV4FlashModel),
						Command:     opencodeDeepSeekCommand,
					},
					{
						Name:        "Muse Spark V1.3 Contributor",
						Description: modelDescription(opencodeGoProvider, opencodeMuseSpark13Model),
						Command:     opencodeMuseSpark13Command,
					},
					{
						Name:        "Qwen 3.8 27B (home Ollama)",
						Description: modelDescription(ollamaProvider, ollamaQwen3827BModel),
						Command:     ollamaQwen3827BCommand,
					},
					{
						Name:        "Qwen 3.8 27B (amd Ollama)",
						Description: "amd-ollama/" + ollamaQwen3827BModel,
						Command:     amdOllamaQwen3827BCommand,
					},
				},
			},
			{
				Name:            "OpenRouter",
				Description:     "Open OpenRouter models and image generation",
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
						Name:        "GLM-5.3-Flash ($0.075/$0.25)",
						Description: modelDescription(openrouterProvider, openrouterGLM53FlashModel),
						Command:     openrouterGLM53FlashCommand,
					},
					{
						Name:        "Fusion (variable/variable)",
						Description: modelDescription(openrouterProvider, fusionModel),
						Command:     openrouterFusionCommand,
					},
					{
						Name:        "DeepSeek V4 Flash 0731 ($0.08/$0.18)",
						Description: modelDescription(openrouterProvider, openrouterDeepSeekV4FlashModel),
						Command:     openrouterDeepSeekCommand,
					},
					{
						Name:        "Muse Spark V1.3 ($1.25/$4.25)",
						Description: modelDescription(openrouterProvider, openrouterMuseSpark13Model),
						Command:     openrouterMuseSpark13Command,
					},
					{
						Name:        "Muse Spark V1.2 ($1.25/$4.25)",
						Description: modelDescription(openrouterProvider, openrouterMuseSpark12Model),
						Command:     openrouterMuseSpark12Command,
					},
					{
						Name:        "Seedream 5.0 Pro ($0.045 1K/$0.09 2K)",
						Description: "images/" + openrouterSeedream50ProModel,
						Command:     openrouterSeedreamCommand,
					},
				},
			},
			{
				Name:            "Ollama",
				Description:     "Open local Ollama models with OpenCode",
				Model:           modelMenuPreset.Model,
				ReasoningEffort: modelMenuPreset.ReasoningEffort,
				Tags:            []string{"ai", "ollama", "opencode", "local", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "Qwen 3.8 27B",
						Description: modelDescription(ollamaProvider, ollamaQwen3827BModel),
						Command:     ollamaQwen3827BCommand,
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
		},
	}
}

func codexCommand(subcommand string, preset modelPreset) string {
	parts := []string{"codex"}
	if strings.TrimSpace(subcommand) != "" {
		parts = append(parts, strings.Fields(subcommand)...)
	}
	parts = append(parts,
		"--dangerously-bypass-approvals-and-sandbox",
		"-m", preset.Model,
		"-c", fmt.Sprintf(`'service_tier="%s"'`, preset.ServiceTier),
		"-c", fmt.Sprintf(`'model_reasoning_effort="%s"'`, preset.ReasoningEffort),
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

func piCommand(model string) string {
	return piModelCommand(opencodeGoProvider, model)
}

func piModelCommand(provider string, model string) string {
	return fmt.Sprintf("pi --model %s/%s", provider, model)
}

func piThinkingCommand(provider string, model string, thinking string) string {
	return fmt.Sprintf("%s --thinking %s", piModelCommand(provider, model), thinking)
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
