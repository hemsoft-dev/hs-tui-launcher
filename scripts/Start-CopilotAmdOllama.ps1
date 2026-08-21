[CmdletBinding()]
param(
    [string] $Model = 'qwen3.8:27b',
    [string] $ProviderBaseUrl = 'http://100.113.233.103:11434/v1',
    [ValidateRange(1, 262144)]
    [int] $MaxPromptTokens = 245760,
    [ValidateRange(1, 262144)]
    [int] $MaxOutputTokens = 16384,
    [ValidateSet('none', 'low', 'medium', 'high', 'max')]
    [string] $ReasoningEffort = 'medium',
    [switch] $NoLaunch,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $CopilotArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$contextTokens = $MaxPromptTokens + $MaxOutputTokens
if ($contextTokens -gt 262144) {
    throw "Prompt and output limits total $contextTokens tokens; qwen3.8:27b supports at most 262144."
}

$commandText = "copilot --allow-all --model $Model --reasoning-effort $ReasoningEffort"
if ($NoLaunch) {
    [pscustomobject]@{
        Command          = $commandText
        ProviderBaseUrl  = $ProviderBaseUrl
        Model            = $Model
        MaxPromptTokens  = $MaxPromptTokens
        MaxOutputTokens  = $MaxOutputTokens
        ContextTokens    = $contextTokens
        ReasoningEffort  = $ReasoningEffort
        Offline          = $true
    } | ConvertTo-Json -Compress
    return
}

if (-not (Get-Command copilot -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'GitHub Copilot CLI is required, but copilot was not found on PATH.'
}

$providerVariableNames = @(
    'COPILOT_PROVIDER_BASE_URL'
    'COPILOT_PROVIDER_TYPE'
    'COPILOT_PROVIDER_API_KEY'
    'COPILOT_PROVIDER_BEARER_TOKEN'
    'COPILOT_PROVIDER_WIRE_API'
    'COPILOT_PROVIDER_TRANSPORT'
    'COPILOT_PROVIDER_MODEL_ID'
    'COPILOT_PROVIDER_WIRE_MODEL'
    'COPILOT_PROVIDER_MAX_PROMPT_TOKENS'
    'COPILOT_PROVIDER_MAX_OUTPUT_TOKENS'
    'COPILOT_PROVIDER_HEADERS'
    'COPILOT_MODEL'
    'COPILOT_OFFLINE'
)
$previousProviderEnvironment = @{}

foreach ($name in $providerVariableNames) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    $previousProviderEnvironment[$name] = @{
        Exists = $null -ne $item
        Value  = if ($null -ne $item) { $item.Value } else { $null }
    }
}

try {
    $env:COPILOT_PROVIDER_BASE_URL = $ProviderBaseUrl
    $env:COPILOT_PROVIDER_TYPE = 'openai'
    $env:COPILOT_PROVIDER_WIRE_API = 'completions'
    $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = [string] $MaxPromptTokens
    $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = [string] $MaxOutputTokens
    $env:COPILOT_MODEL = $Model
    $env:COPILOT_OFFLINE = 'true'

    foreach ($name in @(
        'COPILOT_PROVIDER_API_KEY'
        'COPILOT_PROVIDER_BEARER_TOKEN'
        'COPILOT_PROVIDER_TRANSPORT'
        'COPILOT_PROVIDER_MODEL_ID'
        'COPILOT_PROVIDER_WIRE_MODEL'
        'COPILOT_PROVIDER_HEADERS'
    )) {
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }

    $modelsUrl = $ProviderBaseUrl.TrimEnd('/') + '/models'
    try {
        $availableModels = @(Invoke-RestMethod -Uri $modelsUrl -TimeoutSec 15).data.id
    }
    catch {
        throw "AMD Ollama is unavailable at $modelsUrl. $($_.Exception.Message)"
    }
    if ($Model -notin $availableModels) {
        throw "AMD Ollama does not advertise model '$Model'. Available models: $($availableModels -join ', ')"
    }

    & copilot --allow-all --model $Model --reasoning-effort $ReasoningEffort @CopilotArgs
    $global:LASTEXITCODE = $LASTEXITCODE
}
finally {
    foreach ($name in $providerVariableNames) {
        $previous = $previousProviderEnvironment[$name]
        if ($previous.Exists) {
            Set-Item -LiteralPath "Env:$name" -Value $previous.Value
        }
        else {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}
