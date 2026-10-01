[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CoverageCrap.psm1') -Force

$assertions = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Because)
    $script:assertions++
    if ($Expected -ne $Actual) {
        throw "Assertion failed ($Because): expected '$Expected', got '$Actual'."
    }
}

function Assert-Near {
    param([double]$Expected, [double]$Actual, [double]$Tolerance, [string]$Because)
    $script:assertions++
    if ([math]::Abs($Expected - $Actual) -gt $Tolerance) {
        throw "Assertion failed ($Because): expected '$Expected' +/- '$Tolerance', got '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$MessagePattern, [string]$Because)
    $script:assertions++
    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw "Assertion failed ($Because): unexpected error '$($_.Exception.Message)'."
        }
        return
    }
    throw "Assertion failed ($Because): expected an exception."
}

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$module = 'example.test/repository'
$coverage = ConvertFrom-CoverFunctionOutput -Lines @(
    'example.test/repository/internal/widget.go:12: widget 50.0%',
    'total: (statements) 83.0%'
) -RepositoryRoot $root -ModulePath $module
Assert-Equal 83.0 $coverage.RepositoryCoveragePercent 'repository coverage is parsed'
Assert-Equal 'internal/widget.go' $coverage.Measurements[0].File 'module paths are normalized'
Assert-Equal 12 $coverage.Measurements[0].Line 'coverage start line is parsed'

$complexity = ConvertFrom-GoCycloOutput -Lines @(
    '2 widget (*Thing).widget internal\widget.go:12:1'
) -RepositoryRoot $root -ModulePath $module
Assert-Equal '(*Thing).widget' $complexity[0].Function 'gocyclo function name is retained'
Assert-Equal 2 $complexity[0].Complexity 'complexity is parsed'

$joined = @(Merge-CoverageAndComplexity `
    -CoverageMeasurements $coverage.Measurements `
    -ComplexityMeasurements $complexity)
Assert-Near 2.5 $joined[0].RawCrap 0.000001 'CRAP formula uses fractional coverage'
Assert-Equal 2.5 $joined[0].Crap 'reported CRAP is rounded to two decimals'

$equalToGates = [pscustomobject]@{
    File = 'main.go'; Line = 1; Function = 'main'; Complexity = 1
    CoveragePercent = 0.0; Crap = 30.0; RawCrap = 30.0
}
$violations = @(Test-CrapGates `
    -Measurements @($equalToGates) `
    -RepositoryCoveragePercent 83.0 `
    -RepositoryCoverageFloorPercent 83.0 `
    -ActionableCrap 30.0 `
    -MaximumCrapBaseline 30.0)
Assert-Equal 0 $violations.Count 'gate boundaries are inclusive'

$overGates = [pscustomobject]@{
    File = 'main.go'; Line = 1; Function = 'main'; Complexity = 1
    CoveragePercent = 0.0; Crap = 30.01; RawCrap = 30.01
}
$violations = @(Test-CrapGates `
    -Measurements @($overGates) `
    -RepositoryCoveragePercent 82.9 `
    -RepositoryCoverageFloorPercent 83.0 `
    -ActionableCrap 30.0 `
    -MaximumCrapBaseline 30.0)
Assert-Equal 3 $violations.Count 'coverage, actionable CRAP, and baseline regressions all fail'

Assert-Throws -Because 'unrecognized coverage lines fail closed' -MessagePattern 'Could not parse' -Action {
    ConvertFrom-CoverFunctionOutput `
        -Lines @('not coverage', 'total: (statements) 83.0%') `
        -RepositoryRoot $root `
        -ModulePath $module
}
Assert-Throws -Because 'a mismatched function location fails the join' -MessagePattern 'No coverage measurement' -Action {
    Merge-CoverageAndComplexity -CoverageMeasurements $coverage.Measurements -ComplexityMeasurements @(
        [pscustomobject]@{
            File = 'different.go'; Line = 1; Function = 'different'; Complexity = 1
        }
    )
}

Write-Host "Coverage/CRAP unit checks passed ($assertions assertions)."
