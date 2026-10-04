Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ThresholdNumber {
    param([object] $Value, [string] $Name, [switch] $Count)
    if ($null -eq $Value -or $Value -is [bool] -or
        -not ($Value -is [long] -or $Value -is [int] -or $Value -is [double] -or $Value -is [decimal])) {
        throw "Mutation threshold '$Name' must be a number."
    }
    $number = [double]$Value
    if (-not [double]::IsFinite($number) -or $number -lt 0 -or
        ($Count -and $number -ne [Math]::Floor($number)) -or
        (-not $Count -and $number -gt 100)) {
        throw "Mutation threshold '$Name' is out of bounds."
    }
}

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
    foreach ($language in @('go', 'typescript')) {
        foreach ($name in @('minimumGenerated', 'maximumLived', 'maximumUncovered', 'maximumTimedOut', 'maximumNonViable', 'maximumSkipped')) {
            $property = $thresholds.$language.break.PSObject.Properties[$name]
            if ($null -eq $property) { throw "Mutation threshold '$language.break.$name' is missing." }
            Assert-ThresholdNumber -Value $property.Value -Name "$language.break.$name" -Count
        }
        $scores = if ($language -eq 'go') { @('minimumTestEfficacy', 'minimumMutantCoverage') } else { @('minimumMutationScore') }
        foreach ($score in $scores) {
            foreach ($gate in @('break', 'improvement')) {
                $property = $thresholds.$language.$gate.PSObject.Properties[$score]
                if ($null -eq $property) { throw "Mutation threshold '$language.$gate.$score' is missing." }
                Assert-ThresholdNumber -Value $property.Value -Name "$language.$gate.$score"
            }
            if ($thresholds.$language.improvement.$score -le $thresholds.$language.break.$score) {
                throw "$language improvement score must be higher than the break threshold."
            }
        }
        Assert-ThresholdNumber -Value $thresholds.$language.improvement.maximumLived -Name "$language.improvement.maximumLived" -Count
        if ($thresholds.$language.improvement.maximumLived -ge $thresholds.$language.break.maximumLived) {
            throw "$language improvement lived count must be below the break threshold."
        }
    }
    if ($thresholds.go.break.minimumMutantCoverage -lt 10.88) {
        throw 'Go mutant coverage may not regress below the audited 10.88% floor.'
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
        if ($null -eq $maximum) { throw "Mutation threshold '$thresholdName' is missing." }
        if ([int]$Result.$name -gt [int]$maximum.Value) {
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

function Assert-GoMutationTotal {
    param([Parameter(Mandatory)][psobject] $Result, [Parameter(Mandatory)][psobject] $Counts)
    # Gremlins 0.6.0 defines mutants_total as killed + lived + not viable.
    # Its total excludes uncovered, timed-out, and skipped mutants.
    if (($Counts.Killed + $Counts.Lived + $Counts.NonViable) -ne [int]$Result.mutants_total) {
        throw 'Gremlins mutants_total does not match its executed per-mutant statuses.'
    }
}

Export-ModuleMember -Function Get-MutationThreshold, Assert-MutationPolicy, Assert-GoMutationTotal
