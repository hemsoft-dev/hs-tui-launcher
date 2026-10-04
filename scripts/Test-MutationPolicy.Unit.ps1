[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MutationPolicy.psm1') -Force

$thresholds = Get-MutationThreshold -Path (Join-Path $PSScriptRoot 'mutation-thresholds.json')
$survivors = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mutation-survivors.json') -Raw | ConvertFrom-Json
$assertions = 0

foreach ($language in @('go', 'typescript')) {
    $result = [pscustomobject]@{
        Generated = $thresholds.$language.baseline.generated
        Killed = $thresholds.$language.baseline.killed
        Lived = $thresholds.$language.baseline.lived
        Uncovered = $thresholds.$language.baseline.uncovered
        TimedOut = $thresholds.$language.baseline.timedOut
        NonViable = $thresholds.$language.baseline.nonViable
        Skipped = $thresholds.$language.baseline.skipped
    }
    $scores = if ($language -eq 'go') { @('testEfficacy', 'mutantCoverage') } else { @('mutationScore') }
    foreach ($score in $scores) {
        $result | Add-Member -NotePropertyName $score -NotePropertyValue $thresholds.$language.baseline.$score
    }
    $arguments = @{
        Language = $language
        Result = $result
        Thresholds = $thresholds
        SurvivingMutants = @($survivors.$language)
        SurvivorBaseline = $survivors
    }
    $improvement = Assert-MutationPolicy @arguments
    if ($improvement.Met) { throw "$language baseline unexpectedly meets its higher improvement target." }
    $assertions++

    # Exercise every checked-in break threshold, not just the score wrapper.
    foreach ($property in $thresholds.$language.break.PSObject.Properties) {
        $regression = $result.PSObject.Copy()
        $name = $property.Name -replace '^(minimum|maximum)', ''
        $name = switch ($name) {
            'TestEfficacy' { 'testEfficacy' }
            'MutantCoverage' { 'mutantCoverage' }
            'MutationScore' { 'mutationScore' }
            default { $name }
        }
        $regression.$name = if ($property.Name.StartsWith('minimum')) { [double]$property.Value - 1 } else { [int]$property.Value + 1 }
        $arguments.Result = $regression
        $failed = $false
        try { Assert-MutationPolicy @arguments | Out-Null }
        catch {
            if ($_.Exception.Message -notlike "*$language mutation policy failed:*") { throw }
            $failed = $true
        }
        if (-not $failed) { throw "$language $($property.Name) regression was accepted." }
        $assertions++
    }

    # Killing one old survivor must not conceal a different new survivor.
    $arguments.Result = $result
    $replacementSurvivors = @($survivors.$language)
    $replacementSurvivors[0] = 'new-mutant-at-the-same-lived-count'
    $arguments.SurvivingMutants = $replacementSurvivors
    $failed = $false
    try { Assert-MutationPolicy @arguments | Out-Null }
    catch {
        if ($_.Exception.Message -notlike '*new lived mutants:*') { throw }
        $failed = $true
    }
    if (-not $failed) { throw "$language accepted a new survivor at an unchanged lived count." }
    $assertions++
}
Write-Host "Mutation policy unit checks passed ($assertions assertions)."
