#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-performance-fixture-$([guid]::NewGuid().ToString('N'))"),
    [string] $BudgetPath = (Join-Path $PSScriptRoot 'performance-budgets.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$original = $env:HS_PERFORMANCE_FIXTURE_REGRESSION
try {
    # The Go benchmark code performs real additional work. The gate sees only measured metrics.
    $env:HS_PERFORMANCE_FIXTURE_REGRESSION = '1'
    $rejected = $false
    try { & (Join-Path $PSScriptRoot 'Test-Performance.ps1') -OutputDirectory $OutputDirectory -BudgetPath $BudgetPath }
    catch {
        if ($_.Exception.Message -notmatch '^Performance regression:') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Controlled latency and allocation regression unexpectedly qualified.' }
    $summary = Get-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json') -Raw | ConvertFrom-Json -AsHashtable
    if ($summary.policyPassed -or $summary.benchmarkExitCode -ne 0 -or $summary.benchmarks.Count -ne 29 -or
        @($summary.failures | Where-Object { $_ -match ' latency$' }).Count -eq 0 -or
        @($summary.failures | Where-Object { $_ -match ' bytes$' }).Count -eq 0) {
        throw 'Controlled regression was not rejected by actual latency and allocated-byte measurements.'
    }
    Write-Host 'Actual additional benchmark work was rejected by the latency and allocated-byte budgets.'
}
finally {
    if ($null -eq $original) { Remove-Item Env:HS_PERFORMANCE_FIXTURE_REGRESSION -ErrorAction SilentlyContinue }
    else { $env:HS_PERFORMANCE_FIXTURE_REGRESSION = $original }
}
