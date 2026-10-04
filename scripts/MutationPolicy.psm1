Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MutationThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Mutation threshold file '$Path' does not exist."
    }
    $thresholds = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($thresholds.schemaVersion -ne 1) {
        throw "Unsupported mutation threshold schema '$($thresholds.schemaVersion)'."
    }
    return $thresholds
}

function Assert-MutationPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('go', 'typescript')][string] $Language,
        [Parameter(Mandatory)][psobject] $Result,
        [Parameter(Mandatory)][psobject] $Thresholds,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $SurvivingMutants,
        [Parameter(Mandatory)][psobject] $SurvivorBaseline
    )

    $policy = $Thresholds.$Language
    $violations = [System.Collections.Generic.List[string]]::new()

    if ([int]$Result.Generated -lt [int]$policy.break.minimumGenerated) {
        $violations.Add("generated $($Result.Generated) is below $($policy.break.minimumGenerated)")
    }
    foreach ($name in @('Lived', 'Uncovered', 'TimedOut', 'NonViable', 'Skipped')) {
        $thresholdName = "maximum$name"
        $maximum = $policy.break.PSObject.Properties[$thresholdName]
        if ($null -ne $maximum -and [int]$Result.$name -gt [int]$maximum.Value) {
            $violations.Add("$($name.ToLowerInvariant()) $($Result.$name) exceeds $($maximum.Value)")
        }
    }

    if ($Language -eq 'go') {
        if ([double]$Result.TestEfficacy -lt [double]$policy.break.minimumTestEfficacy) {
            $violations.Add("test efficacy $($Result.TestEfficacy)% is below $($policy.break.minimumTestEfficacy)%")
        }
        if ([double]$Result.MutantCoverage -lt [double]$policy.break.minimumMutantCoverage) {
            $violations.Add("mutant coverage $($Result.MutantCoverage)% is below $($policy.break.minimumMutantCoverage)%")
        }
    }
    else {
        if ([double]$Result.MutationScore -lt [double]$policy.break.minimumMutationScore) {
            $violations.Add("mutation score $($Result.MutationScore)% is below $($policy.break.minimumMutationScore)%")
        }
    }

    $allowedSurvivors = @($SurvivorBaseline.$Language)
    if ($SurvivingMutants.Count -ne [int]$Result.Lived) {
        $violations.Add('survivor identities do not match the lived count')
    }
    $newSurvivors = @($SurvivingMutants | Where-Object { $_ -cnotin $allowedSurvivors })
    if ($newSurvivors.Count -gt 0) {
        $violations.Add("new lived mutants: $($newSurvivors -join ', ')")
    }
    if ($violations.Count -gt 0) {
        throw "$Language mutation policy failed: $($violations -join '; ')."
    }

    if ($Language -eq 'go') {
        return [pscustomobject]@{
            Met = (
                [double]$Result.TestEfficacy -ge [double]$policy.improvement.minimumTestEfficacy -and
                [double]$Result.MutantCoverage -ge [double]$policy.improvement.minimumMutantCoverage -and
                [int]$Result.Lived -le [int]$policy.improvement.maximumLived
            )
            Target = $policy.improvement
        }
    }

    return [pscustomobject]@{
        Met = (
            [double]$Result.MutationScore -ge [double]$policy.improvement.minimumMutationScore -and
            [int]$Result.Lived -le [int]$policy.improvement.maximumLived
        )
        Target = $policy.improvement
    }
}

Export-ModuleMember -Function Get-MutationThreshold, Assert-MutationPolicy
