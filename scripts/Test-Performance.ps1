#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-performance-$([guid]::NewGuid().ToString('N'))"),
    [string] $BudgetPath = (Join-Path $PSScriptRoot 'performance-budgets.json'),
    [switch] $RecordBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
Import-Module (Join-Path $PSScriptRoot 'PerformancePolicy.psm1') -Force
$repository = Split-Path -Parent $PSScriptRoot
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$rawOutput = @()
$primaryError = $null
$report = [ordered]@{
    schemaVersion = 1; revision = $null; pullRequestHead = $null; workingTreeDirty = $null
    goVersion = $null; platform = $null; processor = @(); benchmarkExitCode = $null
    command = @(); samplesPerWorkload = 5; cpu = 1; terminal = @{ NO_COLOR = '1'; TERM = 'dumb' }
    recordBaseline = [bool]$RecordBaseline; policyPassed = $false; failures = @(); benchmarks = @{}
}

Push-Location $repository
try {
    $revision = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $revision -notmatch '^[0-9a-f]{40}$') { throw 'Performance report requires a valid Git revision.' }
    $report.revision = $revision
    $candidate = $env:PERFORMANCE_PR_HEAD
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = $revision }
    if ($candidate -notmatch '^[0-9a-f]{40}$') { throw 'Performance candidate must be a complete Git revision.' }
    $report.pullRequestHead = $candidate
    $dirty = @(& git status --porcelain --untracked-files=normal).Count -gt 0
    if ($LASTEXITCODE -ne 0) { throw 'Unable to determine performance source state.' }
    $report.workingTreeDirty = $dirty
    $goVersion = (& go env GOVERSION).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to identify Go toolchain.' }
    $report.goVersion = $goVersion
    $goTarget = @(& go env GOOS GOARCH)
    if ($LASTEXITCODE -ne 0 -or $goTarget.Count -ne 2) { throw 'Unable to identify Go platform.' }
    $platform = $goTarget -join '/'
    $report.platform = $platform
    $arguments = @('test', '-run', '^$', '-bench', 'Benchmark(LauncherView|SelectionInvocation)', '-benchmem', '-benchtime=200ms', '-count=5', '-cpu=1', './...')
    $rawOutput = @(& go @arguments 2>&1)
    $toolExit = $LASTEXITCODE
    $report.command = @('go') + $arguments
    $report.benchmarkExitCode = $toolExit
    $report.processor = @($rawOutput | Where-Object { $_ -match '^cpu:' } | ForEach-Object { [string]$_ })
    if ($toolExit -ne 0) { throw "Go benchmark process failed (exit $toolExit)." }
    $results = ConvertFrom-BenchmarkOutput -Lines @($rawOutput | ForEach-Object { [string]$_ })
    $report.benchmarks = $results
    $failures = @()
    if (-not $RecordBaseline) {
        $policy = Get-Content -LiteralPath $BudgetPath -Raw | ConvertFrom-Json -AsHashtable
        if ($policy.schemaVersion -ne 1 -or -not $policy.platforms.ContainsKey($platform)) { throw "No reviewed performance budget for $platform." }
        if ($policy.goVersion -ne $goVersion) { throw 'Go toolchain changed; reproduce and review the performance baseline.' }
        $failures = @(Test-PerformanceBudget -Results $results -Budget $policy.platforms[$platform].benchmarks)
    }
    $report.failures = $failures
    $report.policyPassed = -not $RecordBaseline -and $failures.Count -eq 0
    Write-Host "Performance ${platform}: $($results.Count) workloads, five samples each; baseline-only=$RecordBaseline."
    if ($failures.Count -gt 0) { throw "Performance regression: $($failures -join ', ')." }
}
catch {
    $primaryError = $_
    $report.policyPassed = $false
    $report.failures += $_.Exception.Message
}
finally { Pop-Location }
try {
    $rawOutput | Set-Content -LiteralPath (Join-Path $outputRoot 'benchmarks.txt') -Encoding utf8
    $report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $outputRoot 'summary.json') -Encoding utf8
}
catch {
    if ($null -eq $primaryError) { throw }
    Write-Warning 'Performance evidence could not be written; preserving the original qualification failure.'
}
if ($null -ne $primaryError) { throw $primaryError }
