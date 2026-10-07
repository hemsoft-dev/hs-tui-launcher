#Requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PerformancePolicy.psm1') -Force

function Assert-PolicyFailure {
    param([scriptblock] $Action)
    $rejected = $false
    try { & $Action | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Controlled invalid performance evidence was accepted.' }
}

$lines = @()
$budget = [ordered]@{}
foreach ($name in Get-ExpectedBenchmarkName) {
    foreach ($duration in @(100, 101, 102, 103, 104)) { $lines += "$name 1000 $duration ns/op 40 B/op 2 allocs/op" }
    $budget[$name] = [ordered]@{ maximumMedianNanoseconds = 103; maximumBytes = 42; maximumAllocations = 2 }
}
$results = ConvertFrom-BenchmarkOutput -Lines $lines
$firstName = @(Get-ExpectedBenchmarkName)[0]
if ($results.Count -ne 29 -or $results[$firstName].medianNanoseconds -ne 102 -or
    $results[$firstName].medianAbsoluteDeviation -ne 1 -or @(Test-PerformanceBudget $results $budget).Count -ne 0) {
    throw 'Complete controlled baseline was not parsed or qualified correctly.'
}

Assert-PolicyFailure { ConvertFrom-BenchmarkOutput -Lines $lines[1..($lines.Count - 1)] }
Assert-PolicyFailure { ConvertFrom-BenchmarkOutput -Lines @($lines + 'BenchmarkUnexpected 1000 102 ns/op 40 B/op 2 allocs/op') }
Assert-PolicyFailure { ConvertFrom-BenchmarkOutput -Lines @($lines + 'BenchmarkMalformed malformed') }
Assert-PolicyFailure { ConvertFrom-BenchmarkOutput -Lines @($lines | ForEach-Object { $_ -replace '1000 ', '0 ' }) }
Assert-PolicyFailure { ConvertFrom-BenchmarkOutput -Lines @($lines | ForEach-Object { $_ -replace 'ns/op', 'ms/op' }) }
foreach ($kind in @('latency', 'bytes', 'allocations')) {
    $changed = $results | ConvertTo-Json -Depth 15 | ConvertFrom-Json -AsHashtable
    $field = switch ($kind) { 'latency' { 'medianNanoseconds' }; 'bytes' { 'maximumBytes' }; 'allocations' { 'maximumAllocations' } }
    $changed[$firstName][$field] = 10000
    $failures = @(Test-PerformanceBudget $changed $budget)
    if ($failures.Count -ne 1 -or $failures[0] -ne "$firstName $kind") { throw "Controlled $kind regression was not rejected." }
}
$incomplete = $budget | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
$incomplete.Remove($firstName)
Assert-PolicyFailure { Test-PerformanceBudget $results $incomplete }
$invalid = $budget | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
$invalid[$firstName].maximumBytes = -1
Assert-PolicyFailure { Test-PerformanceBudget $results $invalid }
Write-Host 'Performance parsing, sample completeness, units, latency, bytes, and allocation policy fixtures passed.'
