#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-typescript-metrics-$([guid]::NewGuid().ToString('N'))"),
    [string] $BudgetPath = (Join-Path $PSScriptRoot 'typescript-metric-budgets.json'),
    [switch] $RecordBaseline
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & npm ci --ignore-scripts --prefix scripts/coverage-tools
    if ($LASTEXITCODE -ne 0) { throw 'Locked TypeScript report tool installation failed.' }
    $unit = @(& node --test scripts/TypeScriptMetrics.test.mjs 2>&1)
    $code = $LASTEXITCODE
    $unit | ForEach-Object { Write-Host ([string]$_) }
    $plain = @($unit | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
    if ($code -ne 0 -or @($plain | Where-Object { $_ -match 'tests\s+6\s*$' }).Count -ne 1 -or
        @($plain | Where-Object { $_ -match 'pass\s+6\s*$' }).Count -ne 1 -or
        @($plain | Where-Object { $_ -match '(fail|cancelled|skipped|todo)\s+0\s*$' }).Count -ne 4) {
        throw 'TypeScript metric policy must pass all six tests without failures, cancellations, skips, or todos.'
    }
    $arguments = @('scripts/Measure-TypeScriptMetrics.mjs', '--output', $OutputDirectory, '--budget', $BudgetPath)
    if ($RecordBaseline) { $arguments += '--record-baseline' }
    & node @arguments
    if ($LASTEXITCODE -ne 0) { throw "TypeScript metric capture failed (exit $LASTEXITCODE)." }
}
finally { Pop-Location }
