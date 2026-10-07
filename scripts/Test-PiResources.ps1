#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-pi-resources-$([guid]::NewGuid().ToString('N'))"),
    [string] $BudgetPath = (Join-Path $PSScriptRoot 'pi-resource-budgets.json'),
    [switch] $RecordBaseline,
    [switch] $NegativeCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$repository = Split-Path -Parent $PSScriptRoot
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
Push-Location $repository
try {
    $unitOutput = @(& node --test scripts/PiResourcePolicy.test.mjs 2>&1)
    $unitExit = $LASTEXITCODE
    $unitOutput | ForEach-Object { Write-Host ([string]$_) }
    $plain = @($unitOutput | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
    if ($unitExit -ne 0 -or
        @($plain | Where-Object { $_ -match 'tests\s+5\s*$' }).Count -ne 1 -or
        @($plain | Where-Object { $_ -match 'pass\s+5\s*$' }).Count -ne 1 -or
        @($plain | Where-Object { $_ -match '(fail|cancelled|skipped|todo)\s+0\s*$' }).Count -ne 4) {
        throw 'Resource policy must pass exactly five tests without failures, cancellations, skips, or todos.'
    }
    $arguments = @('--expose-gc', '--import', './scripts/mutation-tools/offline.mjs', '--experimental-strip-types',
        'scripts/Measure-PiResources.mjs', '--budget', $BudgetPath)
    if ($NegativeCheck) {
        if ($RecordBaseline) { throw 'Controlled rejection requires a reviewed heap budget.' }
        foreach ($fixture in @('timer', 'listener', 'heap')) {
            $folder = Join-Path $outputRoot $fixture
            $toolOutput = @(& node @arguments --output $folder --fixture $fixture 2>&1)
            $toolExit = $LASTEXITCODE
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $toolOutput | Set-Content -LiteralPath (Join-Path $folder 'tool.log') -Encoding utf8
            if ($toolExit -eq 0) { throw "Controlled $fixture retention unexpectedly qualified." }
            $summary = Get-Content -LiteralPath (Join-Path $folder 'summary.json') -Raw | ConvertFrom-Json -AsHashtable
            $expected = switch ($fixture) {
                timer { 'retained resource: settledTimers' }
                listener { 'retained resource: parentAbortListeners' }
                heap { 'managed heap growth exceeds measured budget' }
            }
            if ($summary.policyPassed -or $summary.samples.Count -ne 5 -or $expected -notin $summary.failures -or
                @($summary.teardown.Values | Where-Object { $_ -ne 0 }).Count -gt 0) {
                throw "Controlled $fixture was not rejected by measured resources with complete cleanup."
            }
            Write-Host "Actual retained $fixture rejected; teardown complete."
        }
    }
    else {
        if ($RecordBaseline) { $arguments += '--record-baseline' }
        $toolOutput = @(& node @arguments --output $outputRoot 2>&1)
        $toolExit = $LASTEXITCODE
        $toolOutput | ForEach-Object { Write-Host ([string]$_) }
        $toolOutput | Set-Content -LiteralPath (Join-Path $outputRoot 'tool.log') -Encoding utf8
        if ($toolExit -ne 0) { throw "Resource sampler failed (exit $toolExit)." }
    }
}
finally { Pop-Location }
