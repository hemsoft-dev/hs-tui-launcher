[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Model = 'qwen3.8:27b',

    [ValidateRange(1, 262144)]
    [int] $ContextLength = 131072,

    [ValidateRange(1, 262144)]
    [int] $OutputLength = 16384,

    [ValidateSet('none', 'low', 'medium', 'high', 'max')]
    [string] $ReasoningEffort = 'medium',

    [string] $StateFile = (Join-Path $HOME '.local\state\opencode\model.json'),

    [switch] $NoLaunch,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $OpenCodeArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$previousConfig = [Environment]::GetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', 'Process')
$previousPermission = [Environment]::GetEnvironmentVariable('OPENCODE_PERMISSION', 'Process')

$modelName = switch ($Model) {
    'qwen3.8:27b' { 'Qwen 3.8 27B' }
    default { $Model }
}
$models = [ordered]@{}
$variants = [ordered]@{}
$variants[$ReasoningEffort] = [ordered]@{
    reasoningEffort = $ReasoningEffort
}
$models[$Model] = [ordered]@{
    name        = $modelName
    tool_call   = $true
    temperature = $true
    reasoning   = $true
    modalities  = [ordered]@{
        input  = @('text')
        output = @('text')
    }
    limit       = [ordered]@{
        context = $ContextLength
        output  = $OutputLength
    }
    options     = [ordered]@{
        reasoningEffort = $ReasoningEffort
    }
    variants    = $variants
}
$providerConfig = [ordered]@{
    provider = [ordered]@{
        ollama = [ordered]@{
            npm = '@ai-sdk/openai-compatible'
            name = 'Ollama (local)'
            options = [ordered]@{
                baseURL = 'http://localhost:11434/v1'
            }
            models = $models
        }
    }
} | ConvertTo-Json -Depth 10 -Compress

$startOpenCode = Join-Path $PSScriptRoot 'Start-OpenCode.ps1'
$startParameters = @{
    Provider     = 'ollama'
    Model        = $Model
    Variant      = $ReasoningEffort
    StateFile    = $StateFile
    NoLaunch     = $NoLaunch
    OpenCodeArgs = @($OpenCodeArgs)
}

$exitCode = 0
try {
    [Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', $providerConfig, 'Process')
    [Environment]::SetEnvironmentVariable('OPENCODE_PERMISSION', '{"*":"allow"}', 'Process')

    & $startOpenCode @startParameters
    if (-not $NoLaunch) {
        $exitCode = $LASTEXITCODE
    }
}
finally {
    [Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', $previousConfig, 'Process')
    [Environment]::SetEnvironmentVariable('OPENCODE_PERMISSION', $previousPermission, 'Process')
}

exit $exitCode
