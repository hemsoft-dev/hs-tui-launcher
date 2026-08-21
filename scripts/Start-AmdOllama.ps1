[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Model = 'qwen3.8:27b',

    [ValidateRange(1, 262144)]
    [int] $ContextLength = 262144,

    [ValidateRange(1, 262144)]
    [int] $OutputLength = 16384,

    [ValidateSet('none', 'low', 'medium', 'high', 'max')]
    [string] $ReasoningEffort = 'medium',

    [string] $BaseUrl = 'http://amd:11434/v1',

    [string] $StateFile = (Join-Path $HOME '.local\state\opencode\model.json'),

    [switch] $NoLaunch,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $OpenCodeArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ModelAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ModelsUrl,

        [Parameter(Mandatory = $true)]
        [string] $ModelId
    )

    try {
        $availableModels = @((Invoke-RestMethod -Uri $ModelsUrl -TimeoutSec 15).data.id)
    }
    catch {
        throw "Ollama on amd is unavailable at $ModelsUrl. $($_.Exception.Message)"
    }
    if ($ModelId -notin $availableModels) {
        throw "Ollama on amd does not advertise model '$ModelId'. Available models: $($availableModels -join ', ')"
    }
}

$baseUrlValue = $BaseUrl.TrimEnd('/')
$modelName = switch ($Model) {
    'qwen3.8:27b' { 'Qwen 3.8 27B on amd' }
    default { "$Model on amd" }
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
        'amd-ollama' = [ordered]@{
            npm = '@ai-sdk/openai-compatible'
            name = 'Ollama on amd'
            options = [ordered]@{
                baseURL = $baseUrlValue
            }
            models = $models
        }
    }
} | ConvertTo-Json -Depth 10 -Compress

$previousConfig = [Environment]::GetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', 'Process')
$previousPermission = [Environment]::GetEnvironmentVariable('OPENCODE_PERMISSION', 'Process')
$startOpenCode = Join-Path $PSScriptRoot 'Start-OpenCode.ps1'
$startParameters = @{
    Provider     = 'amd-ollama'
    Model        = $Model
    Variant      = $ReasoningEffort
    StateFile    = $StateFile
    NoLaunch     = $NoLaunch
    OpenCodeArgs = @($OpenCodeArgs)
}

$exitCode = 0
try {
    if (-not $NoLaunch) {
        Assert-ModelAvailable -ModelsUrl "$baseUrlValue/models" -ModelId $Model
    }

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
