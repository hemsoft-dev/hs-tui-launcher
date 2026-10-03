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

	gpt6AstraModel                  = "gpt-6-astra"
	gpt6SolModel                    = "gpt-6-sol"
	gpt61SolModel                   = "gpt-6.1-sol"
	gpt6LunaModel                   = "gpt-6-luna"
	gpt56SolModel                   = "gpt-5.6-sol"
	gpt56LunaModel                  = "gpt-5.6-luna"
	copilotGPT55Model               = "gpt-5.5"
	claudeModel                     = "claude-opus-4.8"
	copilotOpus5Model               = "claude-opus-5"
	copilotOpus55Model              = "claude-opus-5.5"
	githubCopilotProvider           = "github-copilot"
	copilotGemini38FlashModel       = "gemini-3.8-flash"
	selectModel                     = "select model"
	mediumReasoning                 = "medium"
	highReasoning                   = "high"
	maxReasoning                    = "max"
	xhighReasoning                  = "xhigh"
	defaultReasoning                = "default"
	defaultServiceTier              = "default"
	fastServiceTier                 = "fast"
	antigravityAgentCommand         = "agy --dangerously-skip-permissions"
	cursorAgentCommand              = "cursor-agent --disable-auto-update"
	opencodeGoProvider              = "opencode-go"
	openaiCodexProvider             = "openai-codex"
	openrouterProvider              = "openrouter"
	moonshotProvider                = "moonshot"
	ollamaProvider                  = "ollama"
	kimiK3Model                     = "kimi-k3"
	ollamaQwen3827BModel            = "qwen3.8:27b"
	opencodeQwen38Model             = "qwen3.8-max"
	opencodeGLM53FlashModel         = "glm-5.3-flash"
	opencodeDeepSeekV41FlashModel   = "deepseek-v4.1-flash"
	opencodeMuseSpark13Model        = "muse-spark-1.3-contributor"
	mimoV26FlashModel               = "mimo-v2.6-flash"
	mimoV26ProModel                 = "mimo-v2.6-pro"
	openrouterQwenOmniFlashModel    = "qwen/qwen3.8-omni-flash"
	openrouterBonsai227BModel       = "prism-ml/ternary-bonsai-2-27b"
	openrouterGLM53FlashXModel      = "z-ai/glm-5.3-flashx"
	openrouterKimiK3                = "moonshotai/kimi-k3"
	openrouterDeepSeekV41FlashModel = "deepseek/deepseek-v4.1-flash"
	openrouterMuseSpark13Model      = "meta/muse-spark-1.3"
	openrouterMuseContributorModel  = "meta/muse-spark-1.3-contributor"
	openrouterOpus55Model           = "anthropic/claude-opus-5.5"
	openrouterGemini38Model         = "google/gemini-3.8-flash"
	openrouterMuseSpark12Model      = "meta/muse-spark-1.2"
	openrouterSeedream50ProModel    = "bytedance-seed/seedream-5-0-pro"
	openrouterSeedAudio10Model      = "bytedance-seed/seed-audio-1-0"
	qwen38MaxModel                  = "qwen/qwen3.8-max-0902"
	openrouterGLM53FlashModel       = "z-ai/glm-5.3-flash"
	fusionModel                     = "openrouter/fusion"
	moonshotLauncherCommand         = `& "$repoRoot\scripts\Start-Moonshot.ps1" kimi-k3`
	ollamaQwen3827BCommand          = `& "$repoRoot\scripts\Start-Ollama.ps1" qwen3.8:27b`
	amdOllamaQwen3827BCommand       = `& "$repoRoot\scripts\Start-AmdOllama.ps1" qwen3.8:27b`
	openrouterSeedreamCommand       = `& "$repoRoot\scripts\Start-OpenRouterImage.ps1"`
	openrouterSeedAudioCommand      = `& "$repoRoot\scripts\Start-OpenRouterAudio.ps1"`
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

	codexFreshCommand                = codexCommand("", codexPreset)
	codexResumeCommand               = codexCommand("resume --last", codexPreset)
	codexResumePickerCommand         = codexCommand("resume", codexPreset)
	codexSolHighCommand              = codexCommand("", codexSolHighPreset)
	codexSolHighFastCommand          = codexCommand("", codexSolHighFastPreset)
	codexLunaCommand                 = codexCommand("", codexLunaPreset)
	codexLunaFastCommand             = codexCommand("", codexLunaFastPreset)
	copilotGPT55Command              = copilotCommand(copilotGPT55Preset)
	copilotGPT56SolCommand           = copilotCommand(copilotGPT56SolPreset)
	copilotOpus5Command              = copilotCommand(copilotOpus5Preset)
	copilotAutoCommand               = "copilot --allow-all --model auto"
	opencodeKimiK3Command            = openCodeCommand(opencodeGoProvider, kimiK3Model)
	opencodeQwen38Command            = openCodeCommand(opencodeGoProvider, opencodeQwen38Model)
	opencodeGLM53FlashCommand        = openCodeCommand(opencodeGoProvider, opencodeGLM53FlashModel)
	opencodeDeepSeekV41Command       = openCodeCommand(opencodeGoProvider, opencodeDeepSeekV41FlashModel)
	opencodeMuseSpark13Command       = openCodeCommand(opencodeGoProvider, opencodeMuseSpark13Model)
	opencodeMimoV26FlashCommand      = openCodeCommand(opencodeGoProvider, mimoV26FlashModel)
	opencodeMimoV26ProCommand        = openCodeCommand(opencodeGoProvider, mimoV26ProModel)
	piGLM53FlashCommand              = piCommand(opencodeGLM53FlashModel)
	piDeepSeekV41Command             = piCommand(opencodeDeepSeekV41FlashModel)
	piMuseSpark13Command             = piCommand(opencodeMuseSpark13Model)
	piOpenRouterDeepSeekV41Command   = piModelCommand(openrouterProvider, openrouterDeepSeekV41FlashModel)
	piGoMimoV26FlashCommand          = piModelCommand(opencodeGoProvider, mimoV26FlashModel)
	piGoMimoV26ProCommand            = piModelCommand(opencodeGoProvider, mimoV26ProModel)
	piRouterMimoV26FlashCommand      = piModelCommand(openrouterProvider, "xiaomi/"+mimoV26FlashModel)
	piRouterMimoV26ProCommand        = piModelCommand(openrouterProvider, "xiaomi/"+mimoV26ProModel)
	piRouterQwenOmniFlashCommand     = piModelCommand(openrouterProvider, openrouterQwenOmniFlashModel)
	piRouterBonsai227BCommand        = piModelCommand(openrouterProvider, openrouterBonsai227BModel)
	piRouterGLM53FlashXCommand       = piModelCommand(openrouterProvider, openrouterGLM53FlashXModel)
	piCodexAstraCommand              = piThinkingCommand(openaiCodexProvider, gpt6AstraModel, mediumReasoning)
	piCodexSol61HighCommand          = piThinkingCommand(openaiCodexProvider, gpt61SolModel, highReasoning)
	piCodexLuna6MaxCommand           = piThinkingCommand(openaiCodexProvider, gpt6LunaModel, maxReasoning)
	piCopilotGemini38Command         = piModelCommand(githubCopilotProvider, copilotGemini38FlashModel)
	piCopilotLunaMaxCommand          = piThinkingCommand(githubCopilotProvider, gpt56LunaModel, maxReasoning)
	piCopilotSolHighCommand          = piThinkingCommand(githubCopilotProvider, gpt56SolModel, highReasoning)
	piCopilotAstraCommand            = piThinkingCommand(githubCopilotProvider, gpt6AstraModel, mediumReasoning)
	piCopilotOpus55HighCommand       = piThinkingCommand(githubCopilotProvider, copilotOpus55Model, highReasoning)
	openrouterAstraCommand           = openCodeCommand(openrouterProvider, "openai/"+gpt6AstraModel)
	openrouterSol6Command            = openCodeCommand(openrouterProvider, "openai/"+gpt6SolModel)
	openrouterLuna6Command           = openCodeCommand(openrouterProvider, "openai/"+gpt6LunaModel)
	openrouterSol56Command           = openCodeCommand(openrouterProvider, "openai/"+gpt56SolModel)
	openrouterLuna56Command          = openCodeCommand(openrouterProvider, "openai/"+gpt56LunaModel)
	openrouterGemini38Command        = openCodeCommand(openrouterProvider, openrouterGemini38Model)
	openrouterOpus55Command          = openCodeCommand(openrouterProvider, openrouterOpus55Model)
	openrouterMuseContributorCommand = openCodeCommand(openrouterProvider, openrouterMuseContributorModel)
	openrouterKimiK3Command          = openCodeCommand(openrouterProvider, openrouterKimiK3)
	openrouterQwen38Command          = openCodeCommand(openrouterProvider, qwen38MaxModel)
	openrouterGLM53FlashCommand      = openCodeCommand(openrouterProvider, openrouterGLM53FlashModel)
	openrouterFusionCommand          = openCodeCommand(openrouterProvider, fusionModel)
	openrouterDeepSeekV41Command     = openCodeCommand(openrouterProvider, openrouterDeepSeekV41FlashModel)
	openrouterMuseSpark13Command     = openCodeCommand(openrouterProvider, openrouterMuseSpark13Model)
	openrouterMuseSpark12Command     = openCodeCommand(openrouterProvider, openrouterMuseSpark12Model)
	openrouterMimoV26FlashCommand    = openCodeCommand(openrouterProvider, "xiaomi/"+mimoV26FlashModel)
	openrouterMimoV26ProCommand      = openCodeCommand(openrouterProvider, "xiaomi/"+mimoV26ProModel)
	openrouterQwenOmniFlashCommand   = openCodeCommand(openrouterProvider, openrouterQwenOmniFlashModel)
	openrouterBonsai227BCommand      = openCodeCommand(openrouterProvider, openrouterBonsai227BModel)
	openrouterGLM53FlashXCommand     = openCodeCommand(openrouterProvider, openrouterGLM53FlashXModel)
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
				Tags:            []string{"ai", "pi", "openai-codex", "github-copilot", "cli"},
				Choices: []LaunchChoice{
					{
						Name:        "GPT 6 Astra ($10/$1/$50)",
						Description: modelDescription(openaiCodexProvider, gpt6AstraModel) + " at medium reasoning",
						Command:     piCodexAstraCommand,
					},
					{
						Name:        "GPT 6.1 Sol High ($2/$0.1/$10)",
						Description: modelDescription(openaiCodexProvider, gpt61SolModel) + " at high reasoning",
						Command:     piCodexSol61HighCommand,
					},
					{
						Name:        "GPT 6 Luna Max ($0.1/$0.01/$0.5)",
						Description: modelDescription(openaiCodexProvider, gpt6LunaModel) + " at max reasoning",
						Command:     piCodexLuna6MaxCommand,
					},
					{
						Name:        "Copilot: Gemini 3.8 Flash ($0.75/$0.075/$3.75)",
						Description: modelDescription(githubCopilotProvider, copilotGemini38FlashModel),
						Command:     piCopilotGemini38Command,
					},
					{
						Name:        "Copilot: GPT 5.6 Luna Max ($0.2/$0.02/$1.2)",
						Description: modelDescription(githubCopilotProvider, gpt56LunaModel) + " at max reasoning",
						Command:     piCopilotLunaMaxCommand,
					},
					{
						Name:        "Copilot: GPT 5.6 Sol High ($4/$0.4/$20)",
						Description: modelDescription(githubCopilotProvider, gpt56SolModel) + " at high reasoning",
						Command:     piCopilotSolHighCommand,
					},
					{
						Name:        "Copilot: GPT 6 Astra Medium ($10/$1/$50)",
						Description: modelDescription(githubCopilotProvider, gpt6AstraModel) + " at medium reasoning",
						Command:     piCopilotAstraCommand,
					},
					{
						Name:        "Copilot: Opus 5.5 High ($4/$0.2/$20)",
						Description: modelDescription(githubCopilotProvider, copilotOpus55Model) + " at high reasoning",
						Command:     piCopilotOpus55HighCommand,
					},
					{
						Name:        "GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)",
						Description: modelDescription(opencodeGoProvider, opencodeGLM53FlashModel),
						Command:     piGLM53FlashCommand,
					},
					{
						Name:        "DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)",
						Description: modelDescription(opencodeGoProvider, opencodeDeepSeekV41FlashModel),
						Command:     piDeepSeekV41Command,
					},
					{
						Name:        "Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)",
						Description: modelDescription(opencodeGoProvider, opencodeMuseSpark13Model),
						Command:     piMuseSpark13Command,
					},
					{
						Name:        "OpenRouter: DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)",
						Description: modelDescription(openrouterProvider, openrouterDeepSeekV41FlashModel),
						Command:     piOpenRouterDeepSeekV41Command,
					},
					{
						Name:        "MiMo V2.6 Flash ($0.14/$0.0028/$0.28)",
						Description: modelDescription(opencodeGoProvider, mimoV26FlashModel),
						Command:     piGoMimoV26FlashCommand,
					},
					{
						Name:        "MiMo V2.6 Pro ($0.435/$0.003625/$0.87)",
						Description: modelDescription(opencodeGoProvider, mimoV26ProModel),
						Command:     piGoMimoV26ProCommand,
					},
					{
						Name:        "OpenRouter: MiMo V2.6 Flash ($0.14/$0.0028/$0.28)",
						Description: modelDescription(openrouterProvider, "xiaomi/"+mimoV26FlashModel),
						Command:     piRouterMimoV26FlashCommand,
					},
					{
						Name:        "OpenRouter: MiMo V2.6 Pro ($0.435/$0.0036/$0.87)",
						Description: modelDescription(openrouterProvider, "xiaomi/"+mimoV26ProModel),
						Command:     piRouterMimoV26ProCommand,
					},
					{
						Name:        "OpenRouter: Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)",
						Description: modelDescription(openrouterProvider, openrouterQwenOmniFlashModel),
						Command:     piRouterQwenOmniFlashCommand,
					},
					{
						Name:        "OpenRouter: Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)",
						Description: modelDescription(openrouterProvider, openrouterBonsai227BModel),
						Command:     piRouterBonsai227BCommand,
					},
					{
						Name:        "OpenRouter: GLM-5.3-FlashX ($0.37/$0.09/$1.25)",
						Description: modelDescription(openrouterProvider, openrouterGLM53FlashXModel),
						Command:     piRouterGLM53FlashXCommand,
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
						Name:        "GPT 5.6 Sol High ($4/$0.4/$20)",
						Description: "Start Codex with GPT-5.6 Sol at high reasoning",
						Command:     codexSolHighCommand,
					},
					{
						Name:        "GPT 5.6 Sol High/Fast ($4/$0.4/$20)",
						Description: "Start Codex with GPT-5.6 Sol at high reasoning and fast service",
						Command:     codexSolHighFastCommand,
					},
					{
						Name:        "GPT 5.6 Luna ($0.2/$0.02/$1.2)",
						Description: "Start Codex with GPT-5.6 Luna at medium reasoning",
						Command:     codexLunaCommand,
					},
					{
						Name:        "GPT 5.6 Luna/Fast ($0.2/$0.02/$1.2)",
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
						Name:        "GPT-5.5 ($5/$0.5/$30)",
						Description: "Use GPT-5.5 with high reasoning effort",
						Command:     copilotGPT55Command,
					},
					{
						Name:        "GPT-5.6 Sol ($4/$0.4/$20)",
						Description: "Use GPT-5.6 Sol with high reasoning effort",
						Command:     copilotGPT56SolCommand,
					},
					{
						Name:        "Claude Opus 5 ($5/$0.5/$25)",
						Description: "Use Claude Opus 5 with xhigh reasoning effort",
						Command:     copilotOpus5Command,
					},
					{
						Name:        "Auto (server-routed)",
						Description: "Let GitHub Copilot choose the model for each task",
						Command:     copilotAutoCommand,
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
						Name:        "GLM-5.3-Flash (2x usage) ($0.075/$0.015/$0.25)",
						Description: modelDescription(opencodeGoProvider, opencodeGLM53FlashModel),
						Command:     opencodeGLM53FlashCommand,
					},
					{
						Name:        "Kimi K3 ($3/$0.3/$15)",
						Description: modelDescription(opencodeGoProvider, kimiK3Model),
						Command:     opencodeKimiK3Command,
					},
					{
						Name:        "Qwen 3.8 Max ($2/$0.25/$6)",
						Description: modelDescription(opencodeGoProvider, opencodeQwen38Model),
						Command:     opencodeQwen38Command,
					},
					{
						Name:        "DeepSeek V4.1 Flash ($0.15/$0.003/$0.6)",
						Description: modelDescription(opencodeGoProvider, opencodeDeepSeekV41FlashModel),
						Command:     opencodeDeepSeekV41Command,
					},
					{
						Name:        "Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)",
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
					{
						Name:        "MiMo V2.6 Flash ($0.14/$0.0028/$0.28)",
						Description: modelDescription(opencodeGoProvider, mimoV26FlashModel),
						Command:     opencodeMimoV26FlashCommand,
					},
					{
						Name:        "MiMo V2.6 Pro ($0.435/$0.003625/$0.87)",
						Description: modelDescription(opencodeGoProvider, mimoV26ProModel),
						Command:     opencodeMimoV26ProCommand,
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
						Name:        "GPT 6 Astra ($10/$1/$50)",
						Description: modelDescription(openrouterProvider, "openai/"+gpt6AstraModel),
						Command:     openrouterAstraCommand,
					},
					{
						Name:        "GPT 6 Sol ($2/$0.2/$10)",
						Description: modelDescription(openrouterProvider, "openai/"+gpt6SolModel),
						Command:     openrouterSol6Command,
					},
					{
						Name:        "GPT 6 Luna ($0.1/$0.01/$0.5)",
						Description: modelDescription(openrouterProvider, "openai/"+gpt6LunaModel),
						Command:     openrouterLuna6Command,
					},
					{
						Name:        "GPT 5.6 Sol ($2/$0.2/$10)",
						Description: modelDescription(openrouterProvider, "openai/"+gpt56SolModel),
						Command:     openrouterSol56Command,
					},
					{
						Name:        "GPT 5.6 Luna ($0.2/$0.02/$1.2)",
						Description: modelDescription(openrouterProvider, "openai/"+gpt56LunaModel),
						Command:     openrouterLuna56Command,
					},
					{
						Name:        "Gemini 3.8 Flash ($0.75/$0.075/$3.75)",
						Description: modelDescription(openrouterProvider, openrouterGemini38Model),
						Command:     openrouterGemini38Command,
					},
					{
						Name:        "Claude Opus 5.5 ($4/$0.2/$20)",
						Description: modelDescription(openrouterProvider, openrouterOpus55Model),
						Command:     openrouterOpus55Command,
					},
					{
						Name:        "Kimi K3 ($0.66/$0.66/$10)",
						Description: modelDescription(openrouterProvider, openrouterKimiK3),
						Command:     openrouterKimiK3Command,
					},
					{
						Name:        "Qwen 3.8 Max ($2/$0.25/$6)",
						Description: modelDescription(openrouterProvider, qwen38MaxModel),
						Command:     openrouterQwen38Command,
					},
					{
						Name:        "GLM-5.3-Flash ($0.15/$0.03/$0.5)",
						Description: modelDescription(openrouterProvider, openrouterGLM53FlashModel),
						Command:     openrouterGLM53FlashCommand,
					},
					{
						Name:        "Fusion (variable/variable)",
						Description: modelDescription(openrouterProvider, fusionModel),
						Command:     openrouterFusionCommand,
					},
					{
						Name:        "DeepSeek V4.1 Flash ($0.15-$0.3/$0.003-$0.006/$0.6-$1.2)",
						Description: modelDescription(openrouterProvider, openrouterDeepSeekV41FlashModel),
						Command:     openrouterDeepSeekV41Command,
					},
					{
						Name:        "Muse Spark V1.3 ($1.25/$0.15/$4.25)",
						Description: modelDescription(openrouterProvider, openrouterMuseSpark13Model),
						Command:     openrouterMuseSpark13Command,
					},
					{
						Name:        "Muse Spark V1.3 Contributor ($0.1/$0.002/$0.2)",
						Description: modelDescription(openrouterProvider, openrouterMuseContributorModel),
						Command:     openrouterMuseContributorCommand,
					},
					{
						Name:        "Muse Spark V1.2 ($1.25/$0.15/$4.25)",
						Description: modelDescription(openrouterProvider, openrouterMuseSpark12Model),
						Command:     openrouterMuseSpark12Command,
					},
					{
						Name:        "MiMo V2.6 Flash ($0.14/$0.0028/$0.28)",
						Description: modelDescription(openrouterProvider, "xiaomi/"+mimoV26FlashModel),
						Command:     openrouterMimoV26FlashCommand,
					},
					{
						Name:        "MiMo V2.6 Pro ($0.435/$0.0036/$0.87)",
						Description: modelDescription(openrouterProvider, "xiaomi/"+mimoV26ProModel),
						Command:     openrouterMimoV26ProCommand,
					},
					{
						Name:        "Qwen 3.8 Omni Flash ($0.15/$0.016/$0.47)",
						Description: modelDescription(openrouterProvider, openrouterQwenOmniFlashModel),
						Command:     openrouterQwenOmniFlashCommand,
					},
					{
						Name:        "Ternary Bonsai 2 27B ($0.075/$0.0375/$0.5)",
						Description: modelDescription(openrouterProvider, openrouterBonsai227BModel),
						Command:     openrouterBonsai227BCommand,
					},
					{
						Name:        "GLM-5.3-FlashX ($0.37/$0.09/$1.25)",
						Description: modelDescription(openrouterProvider, openrouterGLM53FlashXModel),
						Command:     openrouterGLM53FlashXCommand,
					},
					{
						Name:        "Seedream 5.0 Pro ($0.045 1K/$0.09 2K)",
						Description: "images/" + openrouterSeedream50ProModel,
						Command:     openrouterSeedreamCommand,
					},
					{
						Name:        "Seed Audio 1.0 ($0.15/min)",
						Description: "audio/" + openrouterSeedAudio10Model,
						Command:     openrouterSeedAudioCommand,
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
