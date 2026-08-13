[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Model = 'kimi-k3',

    [string] $StateFile = (Join-Path $HOME '.local\state\opencode\model.json'),

    [switch] $NoLaunch,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $OpenCodeArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$apiKeyName = 'KIMI_K3_API_KEY'
$previousApiKey = [Environment]::GetEnvironmentVariable($apiKeyName, 'Process')
$previousConfig = [Environment]::GetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', 'Process')
$previousPermission = [Environment]::GetEnvironmentVariable('OPENCODE_PERMISSION', 'Process')

$apiKey = $previousApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    foreach ($scope in @('User', 'Machine')) {
        $apiKey = [Environment]::GetEnvironmentVariable($apiKeyName, $scope)
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "$apiKeyName is not set at Process, User, or Machine scope."
}

$providerConfig = '{"provider":{"moonshot":{"npm":"@ai-sdk/openai-compatible","name":"Moonshot AI","options":{"baseURL":"https://api.moonshot.ai/v1","apiKey":"{env:KIMI_K3_API_KEY}"},"models":{"kimi-k3":{"name":"Kimi K3"}}}}}'
$startOpenCode = Join-Path $PSScriptRoot 'Start-OpenCode.ps1'
$startParameters = @{
    Provider     = 'moonshot'
    Model        = $Model
    StateFile    = $StateFile
    NoLaunch     = $NoLaunch
    OpenCodeArgs = @($OpenCodeArgs)
}

$exitCode = 0
try {
    [Environment]::SetEnvironmentVariable($apiKeyName, $apiKey, 'Process')
    [Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', $providerConfig, 'Process')
    [Environment]::SetEnvironmentVariable('OPENCODE_PERMISSION', '{"*":"allow"}', 'Process')

    & $startOpenCode @startParameters
    if (-not $NoLaunch) {
        $exitCode = $LASTEXITCODE
    }
}
finally {
    [Environment]::SetEnvironmentVariable($apiKeyName, $previousApiKey, 'Process')
    [Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_CONTENT', $previousConfig, 'Process')
    [Environment]::SetEnvironmentVariable('OPENCODE_PERMISSION', $previousPermission, 'Process')
}

exit $exitCode
