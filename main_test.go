package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/HemSoft/hs-tui-launcher/internal/config"
)

func TestExecutePrintsResolvedConfigWithoutInteractiveTerminal(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(configPath, []byte("title: Printed config\n"), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	var commandOutput bytes.Buffer
	var printConfigOutput bytes.Buffer
	terminalChecked := false
	err := execute(
		[]string{"--config", configPath, "--print-config"},
		&commandOutput,
		&printConfigOutput,
		func() bool {
			terminalChecked = true
			return false
		},
	)
	if err != nil {
		t.Fatalf("execute returned error: %v", err)
	}
	if terminalChecked {
		t.Fatal("--print-config checked for an interactive terminal")
	}
	if commandOutput.Len() != 0 {
		t.Fatalf("normal command output = %q, want empty", commandOutput.String())
	}
	if !strings.Contains(printConfigOutput.String(), "title: Printed config") {
		t.Fatalf("--print-config output = %q", printConfigOutput.String())
	}
}

func TestExecuteWritesHelpToCommandOutput(t *testing.T) {
	var commandOutput bytes.Buffer
	var printConfigOutput bytes.Buffer
	terminalChecked := false

	err := execute([]string{"--help"}, &commandOutput, &printConfigOutput, func() bool {
		terminalChecked = true
		return false
	})

	if err != nil {
		t.Fatalf("execute returned error: %v", err)
	}
	if terminalChecked {
		t.Fatal("--help checked for an interactive terminal")
	}
	if !strings.Contains(commandOutput.String(), "Usage:") {
		t.Fatalf("normal command output = %q, want help", commandOutput.String())
	}
	if printConfigOutput.Len() != 0 {
		t.Fatalf("print-config output = %q, want empty", printConfigOutput.String())
	}
}

func TestExecuteReturnsConfigLoadError(t *testing.T) {
	missingPath := filepath.Join(t.TempDir(), "missing.yaml")
	terminalChecked := false

	err := execute(
		[]string{"--config", missingPath},
		&bytes.Buffer{},
		&bytes.Buffer{},
		func() bool {
			terminalChecked = true
			return true
		},
	)

	if err == nil {
		t.Fatal("execute returned nil for a missing config")
	}
	if terminalChecked {
		t.Fatal("execute checked the terminal after config loading failed")
	}
}

func TestExecuteRejectsNoninteractiveTerminal(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(configPath, []byte("title: Test config\n"), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	terminalChecks := 0
	err := execute(
		[]string{"--config", configPath},
		&bytes.Buffer{},
		&bytes.Buffer{},
		func() bool {
			terminalChecks++
			return false
		},
	)

	if err == nil {
		t.Fatal("execute returned nil without an interactive terminal")
	}
	if !strings.Contains(err.Error(), "requires an interactive terminal") {
		t.Fatalf("error = %q, want interactive-terminal context", err)
	}
	if terminalChecks != 1 {
		t.Fatalf("terminal checks = %d, want 1", terminalChecks)
	}
}

func TestWriteSelectionEmitsStructuredInvocation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:       "Tool",
		Command:    `tool --flag 'value with spaces' "literal; metacharacter"`,
		WorkingDir: `C:\work`,
		Env:        []string{"EXAMPLE=value"},
	}

	if err := writeSelection(path, item); err != nil {
		t.Fatalf("writeSelection returned error: %v", err)
	}

	selection := readSelection(t, path)
	if _, ok := selection["command"]; ok {
		t.Fatal("selection JSON included legacy command property")
	}
	if got := selection["name"]; got != "Tool" {
		t.Fatalf("name = %#v", got)
	}
	if got := selection["executable"]; got != "tool" {
		t.Fatalf("executable = %#v", got)
	}

	args, ok := selection["args"].([]any)
	if !ok {
		t.Fatalf("args = %#v, want array", selection["args"])
	}
	wantArgs := []string{"--flag", "value with spaces", "literal; metacharacter"}
	if len(args) != len(wantArgs) {
		t.Fatalf("len(args) = %d, want %d", len(args), len(wantArgs))
	}
	for index, want := range wantArgs {
		if got := args[index]; got != want {
			t.Fatalf("args[%d] = %#v, want %q", index, got, want)
		}
	}
}

func TestWriteSelectionResolvesRepoRootPowerShellInvocation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:    "OpenRouter GLM-5.3-Flash",
		Command: `& "$repoRoot\scripts\Start-OpenCode.ps1" openrouter z-ai/glm-5.3-flash`,
	}

	if err := writeSelection(path, item); err != nil {
		t.Fatalf("writeSelection returned error: %v", err)
	}

	selection := readSelection(t, path)
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}
	wantExecutable := filepath.Join(workingDir, "scripts", "Start-OpenCode.ps1")
	if got := selection["executable"]; got != wantExecutable {
		t.Fatalf("executable = %#v, want %q", got, wantExecutable)
	}

	args, ok := selection["args"].([]any)
	if !ok {
		t.Fatalf("args = %#v, want array", selection["args"])
	}
	wantArgs := []string{"openrouter", "z-ai/glm-5.3-flash"}
	if len(args) != len(wantArgs) {
		t.Fatalf("len(args) = %d, want %d", len(args), len(wantArgs))
	}
	for index, want := range wantArgs {
		if got := args[index]; got != want {
			t.Fatalf("args[%d] = %#v, want %q", index, got, want)
		}
	}
}

func TestParseSelectionCommandDoesNotExpandSimilarVariableNames(t *testing.T) {
	invocation, err := parseSelectionCommand(`$repoRooted --flag`)
	if err != nil {
		t.Fatalf("parseSelectionCommand returned error: %v", err)
	}
	if invocation.executable != "$repoRooted" {
		t.Fatalf("executable = %q, want $repoRooted", invocation.executable)
	}
}

func TestParseSelectionCommandRejectsEmptyCommand(t *testing.T) {
	if _, err := parseSelectionCommand(" \t\n"); err == nil {
		t.Fatal("parseSelectionCommand accepted an empty command")
	} else if !strings.Contains(err.Error(), "selection command is required") {
		t.Fatalf("error = %q, want required-command context", err)
	}
}

func TestWriteSelectionRejectsUnquotedPowerShellMetacharacters(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:    "Unsafe",
		Command: `tool safe; Set-Content breakout.txt bad`,
	}

	if err := writeSelection(path, item); err == nil {
		t.Fatal("writeSelection returned nil, want error")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("selection file exists after rejected command: %v", err)
	}
}

func TestWriteSelectionRejectsEmptyQuotedExecutable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "selection.json")
	item := config.LaunchItem{
		Name:    "Empty",
		Command: `"" --flag`,
	}

	if err := writeSelection(path, item); err == nil {
		t.Fatal("writeSelection returned nil, want error")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("selection file exists after rejected command: %v", err)
	}
}

func TestWriteSelectionRejectsDirectoryOutputPath(t *testing.T) {
	if err := writeSelection(t.TempDir(), config.LaunchItem{
		Name:    "Tool",
		Command: "tool",
	}); err == nil {
		t.Fatal("writeSelection returned nil for a directory output path")
	} else if !strings.Contains(err.Error(), "create selection file") {
		t.Fatalf("error = %q, want create-selection-file context", err)
	}
}

func TestDefaultCommandsParseAsStructuredInvocations(t *testing.T) {
	cfg := config.Default()

	for _, item := range cfg.Items {
		if item.Command != "" {
			assertCommandParses(t, item.Name, item.Command)
		}
		for _, choice := range item.Choices {
			assertCommandParses(t, item.Name+" "+choice.Name, choice.Command)
		}
	}
}

func TestStartMoonshotUsesDirectProviderWithoutLaunching(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	statePath := filepath.Join(t.TempDir(), "model.json")
	scriptPath := filepath.Join(workingDir, "scripts", "Start-Moonshot.ps1")
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"kimi-k3",
		"-StateFile", statePath,
		"-NoLaunch",
	)
	command.Env = append(os.Environ(), "KIMI_K3_API_KEY=test-only-key")

	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("Start-Moonshot.ps1 failed: %v\n%s", err, output)
	}
	if got := strings.TrimSpace(string(output)); got != "opencode --model moonshot/kimi-k3" {
		t.Fatalf("output = %q", got)
	}

	state := readSelection(t, statePath)
	recent, ok := state["recent"].([]any)
	if !ok || len(recent) == 0 {
		t.Fatalf("recent = %#v", state["recent"])
	}
	selected, ok := recent[0].(map[string]any)
	if !ok {
		t.Fatalf("recent[0] = %#v", recent[0])
	}
	if selected["providerID"] != "moonshot" || selected["modelID"] != "kimi-k3" {
		t.Fatalf("selected model = %#v", selected)
	}
}

func TestStartOllamaUsesLocalProviderWithoutLaunching(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	statePath := filepath.Join(t.TempDir(), "model.json")
	scriptPath := filepath.Join(workingDir, "scripts", "Start-Ollama.ps1")
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"qwen3.8:27b",
		"-StateFile", statePath,
		"-NoLaunch",
	)

	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("Start-Ollama.ps1 failed: %v\n%s", err, output)
	}
	if got := strings.TrimSpace(string(output)); got != "opencode --model ollama/qwen3.8:27b" {
		t.Fatalf("output = %q", got)
	}

	state := readSelection(t, statePath)
	recent, ok := state["recent"].([]any)
	if !ok || len(recent) == 0 {
		t.Fatalf("recent = %#v", state["recent"])
	}
	selected, ok := recent[0].(map[string]any)
	if !ok {
		t.Fatalf("recent[0] = %#v", recent[0])
	}
	if selected["providerID"] != "ollama" || selected["modelID"] != "qwen3.8:27b" {
		t.Fatalf("selected model = %#v", selected)
	}
	variants, ok := state["variant"].(map[string]any)
	if !ok || variants["ollama/qwen3.8:27b"] != "medium" {
		t.Fatalf("variant = %#v", state["variant"])
	}
}

func TestStartAmdOllamaSelectsScopedProviderWithoutLaunching(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	statePath := filepath.Join(t.TempDir(), "model.json")
	scriptPath := filepath.Join(workingDir, "scripts", "Start-AmdOllama.ps1")
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"qwen3.8:27b",
		"-StateFile", statePath,
		"-NoLaunch",
	)

	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("Start-AmdOllama.ps1 failed: %v\n%s", err, output)
	}
	if got := strings.TrimSpace(string(output)); got != "opencode --model amd-ollama/qwen3.8:27b" {
		t.Fatalf("output = %q", got)
	}

	state := readSelection(t, statePath)
	recent, ok := state["recent"].([]any)
	if !ok || len(recent) == 0 {
		t.Fatalf("recent = %#v", state["recent"])
	}
	selected, ok := recent[0].(map[string]any)
	if !ok {
		t.Fatalf("recent[0] = %#v", recent[0])
	}
	if selected["providerID"] != "amd-ollama" || selected["modelID"] != "qwen3.8:27b" {
		t.Fatalf("selected model = %#v", selected)
	}
	variants, ok := state["variant"].(map[string]any)
	if !ok || variants["amd-ollama/qwen3.8:27b"] != "medium" {
		t.Fatalf("variant = %#v", state["variant"])
	}
}

func TestStartCopilotAmdOllamaUsesFullContextWithoutLaunching(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	scriptPath := filepath.Join(workingDir, "scripts", "Start-CopilotAmdOllama.ps1")
	command := exec.Command("pwsh", "-NoProfile", "-File", scriptPath, "-NoLaunch")

	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("Start-CopilotAmdOllama.ps1 failed: %v\n%s", err, output)
	}

	var result map[string]any
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("NoLaunch output is not JSON: %v\n%s", err, output)
	}
	if result["Command"] != "copilot --allow-all --model qwen3.8:27b --reasoning-effort medium" {
		t.Fatalf("Command = %#v", result["Command"])
	}
	if result["ProviderBaseUrl"] != "http://100.113.233.103:11434/v1" {
		t.Fatalf("ProviderBaseUrl = %#v", result["ProviderBaseUrl"])
	}
	if result["Model"] != "qwen3.8:27b" {
		t.Fatalf("Model = %#v", result["Model"])
	}
	if result["MaxPromptTokens"] != float64(245760) || result["MaxOutputTokens"] != float64(16384) {
		t.Fatalf("token limits = %#v/%#v", result["MaxPromptTokens"], result["MaxOutputTokens"])
	}
	if result["ContextTokens"] != float64(262144) {
		t.Fatalf("ContextTokens = %#v", result["ContextTokens"])
	}
	if result["Offline"] != true {
		t.Fatalf("Offline = %#v", result["Offline"])
	}
	if result["ReasoningEffort"] != "medium" {
		t.Fatalf("ReasoningEffort = %#v", result["ReasoningEffort"])
	}
}

func TestStartOpenRouterImageDryRunDoesNotSpendCredits(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	outputDirectory := filepath.Join(t.TempDir(), "images")
	scriptPath := filepath.Join(workingDir, "scripts", "Start-OpenRouterImage.ps1")
	prompt := "test-only prompt that must not be echoed"
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"-Prompt", prompt,
		"-Resolution", "2k",
		"-AspectRatio", "AUTO",
		"-OutputDirectory", outputDirectory,
		"-DryRun",
	)

	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("Start-OpenRouterImage.ps1 dry run failed: %v\n%s", err, output)
	}
	if strings.Contains(string(output), prompt) {
		t.Fatal("dry-run output exposed the image prompt")
	}

	var result map[string]any
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("dry-run output is not JSON: %v\n%s", err, output)
	}
	if got := result["Model"]; got != "bytedance-seed/seedream-5-0-pro" {
		t.Fatalf("Model = %#v", got)
	}
	if got := result["Resolution"]; got != "2K" {
		t.Fatalf("Resolution = %#v", got)
	}
	if got := result["AspectRatio"]; got != "auto" {
		t.Fatalf("AspectRatio = %#v", got)
	}
	if got := result["EstimatedCostUSD"]; got != 0.09 {
		t.Fatalf("EstimatedCostUSD = %#v", got)
	}
	if _, err := os.Stat(outputDirectory); !os.IsNotExist(err) {
		t.Fatalf("dry run created output directory: %v", err)
	}
}

func TestStartOpenRouterImageReadsPromptFromQuotedFilePath(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	prompt := "A lighthouse above a stormy sea.\nUse a woodblock print style."
	promptPath := filepath.Join(t.TempDir(), "seedream prompt.txt")
	if err := os.WriteFile(promptPath, []byte(prompt+"\n"), 0o600); err != nil {
		t.Fatalf("write prompt file: %v", err)
	}

	scriptPath := filepath.Join(workingDir, "scripts", "Start-OpenRouterImage.ps1")
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"-Prompt", `"`+promptPath+`"`,
		"-Resolution", "1K",
		"-AspectRatio", "1:1",
		"-DryRun",
	)

	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("Start-OpenRouterImage.ps1 file prompt dry run failed: %v\n%s", err, output)
	}
	if strings.Contains(string(output), prompt) {
		t.Fatal("dry-run output exposed the file-backed image prompt")
	}

	var result map[string]any
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("dry-run output is not JSON: %v\n%s", err, output)
	}
	if got := result["PromptLength"]; got != float64(len(prompt)) {
		t.Fatalf("PromptLength = %#v, want %d", got, len(prompt))
	}
}

func TestStartOpenRouterImageRejectsEmptyPromptFile(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	promptPath := filepath.Join(t.TempDir(), "empty prompt.txt")
	if err := os.WriteFile(promptPath, []byte(" \r\n\t"), 0o600); err != nil {
		t.Fatalf("write prompt file: %v", err)
	}

	scriptPath := filepath.Join(workingDir, "scripts", "Start-OpenRouterImage.ps1")
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"-Prompt", promptPath,
		"-Resolution", "1K",
		"-AspectRatio", "1:1",
		"-DryRun",
	)

	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatal("Start-OpenRouterImage.ps1 accepted an empty prompt file")
	}
	if !strings.Contains(string(output), "Image prompt file is empty:") {
		t.Fatalf("unexpected error output: %s", output)
	}
}

func TestStartOpenRouterImageRejectsInvalidResolutionBeforeApiCall(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	scriptPath := filepath.Join(workingDir, "scripts", "Start-OpenRouterImage.ps1")
	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", scriptPath,
		"-Prompt", "test",
		"-Resolution", "4K",
		"-AspectRatio", "1:1",
		"-DryRun",
	)

	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatal("Start-OpenRouterImage.ps1 accepted unsupported 4K resolution")
	}
	if !strings.Contains(string(output), "Resolution must be one of: 1K, 2K") {
		t.Fatalf("unexpected error output: %s", output)
	}
}

func TestStartOpenRouterImageSavesMockedPngResponse(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}

	tempDir := t.TempDir()
	outputDirectory := filepath.Join(tempDir, "images")
	scriptPath := filepath.Join(workingDir, "scripts", "Start-OpenRouterImage.ps1")
	wrapperPath := filepath.Join(tempDir, "invoke-mocked-image.ps1")
	wrapper := `param([string] $TargetScript, [string] $OutputDirectory)
$global:HS_IMAGE_TEST_REQUESTS = 0
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $ContentType, $Body)
    $global:HS_IMAGE_TEST_REQUESTS++
    $request = $Body | ConvertFrom-Json
    if ($Uri -ne 'https://openrouter.ai/api/v1/images' -or
        $Method -ne 'Post' -or
        $request.model -ne 'bytedance-seed/seedream-5-0-pro' -or
        $request.resolution -ne '1K' -or
        $request.aspect_ratio -ne '1:1') {
        throw 'Unexpected mocked request'
    }
    return [pscustomobject]@{
        data = @([pscustomobject]@{ b64_json = 'AQID' })
        usage = [pscustomobject]@{ cost = 0.045 }
    }
}
& $TargetScript -Prompt 'mock prompt' -Resolution 1K -AspectRatio 1:1 -OutputDirectory $OutputDirectory -Force -NoOpen
if ($global:HS_IMAGE_TEST_REQUESTS -ne 1) { throw 'Expected exactly one request.' }
if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -ne 1) { throw 'Unexpected preflight artifacts.' }
`
	if err := os.WriteFile(wrapperPath, []byte(wrapper), 0o600); err != nil {
		t.Fatalf("write wrapper: %v", err)
	}

	command := exec.Command(
		"pwsh",
		"-NoProfile",
		"-File", wrapperPath,
		"-TargetScript", scriptPath,
		"-OutputDirectory", outputDirectory,
	)
	command.Env = append(os.Environ(), "OPENROUTER_API_KEY=test-only-key")
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("mocked image generation failed: %v\n%s", err, output)
	}
	if !strings.Contains(string(output), "OpenRouter reported cost: $0.045000") {
		t.Fatalf("missing reported cost: %s", output)
	}

	images, err := filepath.Glob(filepath.Join(outputDirectory, "seedream-5-0-pro-*.png"))
	if err != nil {
		t.Fatalf("glob images: %v", err)
	}
	if len(images) != 1 {
		t.Fatalf("saved images = %v, want one PNG", images)
	}
	content, err := os.ReadFile(images[0])
	if err != nil {
		t.Fatalf("read image: %v", err)
	}
	if string(content) != string([]byte{1, 2, 3}) {
		t.Fatalf("image bytes = %v", content)
	}
}

func TestStartOpenRouterImagePreflightAndCleanup(t *testing.T) {
	workingDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	scenarios := []string{"file", "blocked-parent", "request-failure", "invalid-response", "cancel", "dry-run"}
	if runtime.GOOS == "windows" {
		scenarios = append(scenarios, "unwritable")
	}
	for _, scenario := range scenarios {
		t.Run(scenario, func(t *testing.T) {
			tempDir := t.TempDir()
			wrapperPath := filepath.Join(tempDir, "mock-image.ps1")
			wrapper := `param([string]$TargetScript, [string]$Root, [string]$Scenario)
$ErrorActionPreference = 'Stop'
$global:HS_IMAGE_TEST_REQUESTS = 0
function Invoke-RestMethod {
    $global:HS_IMAGE_TEST_REQUESTS++
    if ($Scenario -eq 'request-failure') { throw 'Controlled provider failure' }
    return [pscustomobject]@{ data = @([pscustomobject]@{ b64_json = 'not base64' }) }
}
function Read-Host { return 'n' }
$destination = Join-Path $Root 'images'
$originalAcl = $null
if ($Scenario -eq 'unwritable') {
    New-Item -ItemType Directory -Path $destination | Out-Null
    $originalAcl = Get-Acl -LiteralPath $destination
    $deniedAcl = Get-Acl -LiteralPath $destination
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent().Name,
        'Write', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
    $deniedAcl.AddAccessRule($rule)
    Set-Acl -LiteralPath $destination -AclObject $deniedAcl
}
if ($Scenario -in @('file', 'blocked-parent')) {
    [IO.File]::WriteAllText($destination, 'preserve this file')
    if ($Scenario -eq 'blocked-parent') { $destination = Join-Path $destination 'child' }
}
$options = @{ Force = $true; NoOpen = $true }
if ($Scenario -eq 'cancel') { $options.Force = $false }
if ($Scenario -eq 'dry-run') { $options.DryRun = $true }
$failure = $null
try { & $TargetScript -Prompt 'inert test' -Resolution 1K -AspectRatio '1:1' -OutputDirectory $destination @options | Out-Null }
catch { $failure = $_.Exception.Message }
finally { if ($null -ne $originalAcl) { Set-Acl -LiteralPath $destination -AclObject $originalAcl } }
$expectedRequests = if ($Scenario -in @('request-failure', 'invalid-response')) { 1 } else { 0 }
if ($global:HS_IMAGE_TEST_REQUESTS -ne $expectedRequests) { throw "Requests=$global:HS_IMAGE_TEST_REQUESTS, expected=$expectedRequests" }
if ($Scenario -in @('cancel', 'dry-run')) {
    if ($null -ne $failure -or (Test-Path -LiteralPath $destination)) { throw 'Cancel/dry-run changed the destination or failed.' }
} elseif ($null -eq $failure) { throw 'Expected a controlled failure.' }
if ($Scenario -in @('file', 'blocked-parent')) {
    if ([IO.File]::ReadAllText((Join-Path $Root 'images')) -cne 'preserve this file') { throw 'Input file changed.' }
} elseif (Test-Path -LiteralPath $destination) {
    if (@(Get-ChildItem -LiteralPath $destination -Force).Count -ne 0) { throw 'Preflight artifacts remain.' }
}
Write-Output "Verified $Scenario requests=$global:HS_IMAGE_TEST_REQUESTS"
`
			if err := os.WriteFile(wrapperPath, []byte(wrapper), 0o600); err != nil {
				t.Fatal(err)
			}
			command := exec.Command("pwsh", "-NoProfile", "-File", wrapperPath,
				"-TargetScript", filepath.Join(workingDir, "scripts", "Start-OpenRouterImage.ps1"),
				"-Root", tempDir, "-Scenario", scenario)
			command.Env = append(os.Environ(), "OPENROUTER_API_KEY=inert-test-key")
			output, err := command.CombinedOutput()
			if err != nil || !strings.Contains(string(output), "Verified "+scenario+" requests=") {
				t.Fatalf("preflight %s: %v\n%s", scenario, err, output)
			}
		})
	}
}

func assertCommandParses(t *testing.T, name string, command string) {
	t.Helper()

	invocation, err := parseSelectionCommand(command)
	if err != nil {
		t.Fatalf("%s command did not parse: %v", name, err)
	}
	if invocation.executable == "" {
		t.Fatalf("%s parsed with empty executable", name)
	}
}

func readSelection(t *testing.T, path string) map[string]any {
	t.Helper()

	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}

	var selection map[string]any
	if err := json.Unmarshal(content, &selection); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	return selection
}
