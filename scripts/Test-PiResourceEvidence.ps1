#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PriorEvidenceDirectory,
    [Parameter(Mandatory)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$realNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$attemptState = [pscustomobject]@{ count = 0; exitCode = $null }
foreach ($fixture in @('timer', 'listener', 'heap')) {
    $source = Join-Path (Join-Path $PriorEvidenceDirectory $fixture) 'summary.json'
    $folder = Join-Path $OutputDirectory $fixture
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $folder 'summary.json') -Force
}

# Run policy tests with real Node. Each sampler attempt instead executes an
# actual native Node process whose import fails before any summary is written.
function node {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidOverwritingBuiltInCmdlets', '',
        Justification = 'A fixture-local shim runs real Node with a failing import, then is removed in finally.'
    )]
    param()
    if ($args -contains '--test') { & $realNode @args; return }
    $attemptState.count++
    & $realNode --input-type=module --eval 'import("node:hs-inert-missing-evidence-fixture")'
    $attemptState.exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = $attemptState.exitCode
}

$rejected = $false
try {
    try { & (Join-Path $PSScriptRoot 'Test-PiResources.ps1') -NegativeCheck -OutputDirectory $OutputDirectory }
    catch {
        if ($_.Exception.Message -notmatch '^Controlled timer run did not write fresh summary evidence\.') { throw }
        $rejected = $true
    }
    if (-not $rejected -or $attemptState.count -ne 1 -or $attemptState.exitCode -ne 1 -or
        (Test-Path -LiteralPath (Join-Path (Join-Path $OutputDirectory 'timer') 'summary.json'))) {
        throw 'Stale resource evidence was accepted after an actual sampler startup failure.'
    }
    $result = [ordered]@{ rejected = $true; startupAttempts = $attemptState.count; nativeExitCode = $attemptState.exitCode; staleSummaryRemoved = $true }
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'stale-evidence-result.json') -Encoding utf8NoBOM
    Write-Host 'Actual Node import failure cannot qualify using prior resource fixture evidence.'
    $global:LASTEXITCODE = 0
}
finally { Remove-Item -LiteralPath function:node -ErrorAction SilentlyContinue }
