[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-NodeTestSummary {
    param(
        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter(Mandatory)]
        [object[]] $Output,

        [Parameter(Mandatory)]
        [int] $ExitCode,

        [Parameter(Mandatory)]
        [int] $ExpectedTests
    )

    $Output | ForEach-Object { Write-Host ([string] $_) }
    if ($ExitCode -ne 0) {
        throw "$Suite exited with code $ExitCode."
    }

    $summary = @{}
    foreach ($line in $Output) {
        $plain = ([string] $line) -replace "`e\[[0-9;]*m", ''
        if ($plain -match '(tests|pass|fail|cancelled|skipped|todo)\s+(\d+)\s*$') {
            $summary[$Matches[1]] = [int] $Matches[2]
        }
    }

    foreach ($field in @('tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo')) {
        if (-not $summary.ContainsKey($field)) {
            throw "$Suite did not report the '$field' summary."
        }
    }
    if ($summary.tests -ne $ExpectedTests -or $summary.pass -ne $ExpectedTests) {
        throw "$Suite must pass exactly $ExpectedTests tests; reported tests=$($summary.tests), pass=$($summary.pass)."
    }
    foreach ($field in @('fail', 'cancelled', 'skipped', 'todo')) {
        if ($summary[$field] -ne 0) {
            throw "$Suite reported $field=$($summary[$field]); expected zero."
        }
    }
}

$jevOutput = @(& node --experimental-strip-types --test pi/jev-decide/*.test.ts 2>&1)
$jevExitCode = $LASTEXITCODE
Assert-NodeTestSummary -Suite 'Jev' -Output $jevOutput -ExitCode $jevExitCode -ExpectedTests 5

$doneSoundOutput = @(& node --test .pi/tests/done-sound.test.mjs 2>&1)
$doneSoundExitCode = $LASTEXITCODE
Assert-NodeTestSummary -Suite 'done sound' -Output $doneSoundOutput -ExitCode $doneSoundExitCode -ExpectedTests 6

Write-Host 'Node test guard passed: 11 tests, 11 passed, 0 failed/cancelled/skipped/todo.'
