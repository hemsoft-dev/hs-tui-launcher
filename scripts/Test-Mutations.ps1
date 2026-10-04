[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-tui-mutations-$([guid]::NewGuid().ToString('N'))")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Import-Module (Join-Path $PSScriptRoot 'MutationPolicy.psm1') -Force

function Get-MutationStatusCount {
    param(
        [Parameter(Mandatory)][object[]] $Mutations,
        [Parameter(Mandatory)][string] $Status
    )

    return @($Mutations | Where-Object { $_.status -eq $Status }).Count
}

$gremlins = 'github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0'
$mutationRoot = (Resolve-Path -LiteralPath '.').Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$languageRoot = Join-Path $outputRoot 'go'
New-Item -ItemType Directory -Path $languageRoot -Force | Out-Null
$resultPath = Join-Path $languageRoot 'gremlins.json'
$summaryPath = Join-Path $languageRoot 'summary.json'
foreach ($path in @($resultPath, $summaryPath)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
$thresholds = Get-MutationThreshold -Path (Join-Path $PSScriptRoot 'mutation-thresholds.json')

$commit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Unable to identify the exact commit for the mutation report.'
}
$workingTreeDirty = @(& git status --porcelain --untracked-files=normal).Count -gt 0
$toolOutput = @(& go run $gremlins unleash --config .gremlins.yaml --output $resultPath $mutationRoot 2>&1)
$toolExitCode = $LASTEXITCODE
$toolOutput | ForEach-Object { Write-Host $_ }
$toolOutput | Set-Content -LiteralPath (Join-Path $languageRoot 'tool.log') -Encoding utf8

$reportedErrors = @($toolOutput | Where-Object { "$_" -match '^ERROR:' })
if ($reportedErrors.Count -gt 0) {
    throw "Gremlins reported $($reportedErrors.Count) tool error(s)."
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw 'Gremlins did not produce its JSON result file.'
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$requiredProperties = @(
    'files',
    'mutants_total',
    'mutants_killed',
    'mutants_lived',
    'mutants_not_viable',
    'mutants_not_covered',
    'test_efficacy',
    'mutations_coverage'
)
foreach ($property in $requiredProperties) {
    if ($null -eq $result.PSObject.Properties[$property]) {
        throw "Gremlins JSON output is missing the '$property' property."
    }
}

$mutations = @($result.files | ForEach-Object { $_.mutations })
$knownStatuses = @('KILLED', 'LIVED', 'NOT COVERED', 'TIMED OUT', 'NOT VIABLE', 'SKIPPED')
if (@($mutations | Where-Object { $_.status -notin $knownStatuses }).Count -gt 0) {
    throw 'Gremlins reported unknown or unfinished mutant statuses.'
}
$policyResult = [pscustomobject]@{
    Generated = $mutations.Count
    Killed = Get-MutationStatusCount -Mutations $mutations -Status 'KILLED'
    Lived = Get-MutationStatusCount -Mutations $mutations -Status 'LIVED'
    Uncovered = Get-MutationStatusCount -Mutations $mutations -Status 'NOT COVERED'
    TimedOut = Get-MutationStatusCount -Mutations $mutations -Status 'TIMED OUT'
    NonViable = Get-MutationStatusCount -Mutations $mutations -Status 'NOT VIABLE'
    Skipped = Get-MutationStatusCount -Mutations $mutations -Status 'SKIPPED'
    TestEfficacy = [double]$result.test_efficacy
    MutantCoverage = [double]$result.mutations_coverage
}
$executed = $policyResult.Killed + $policyResult.Lived + $policyResult.TimedOut + $policyResult.NonViable
if ($policyResult.Generated -eq 0 -or $executed -eq 0) {
    throw 'Gremlins must generate and execute nonzero mutation counts.'
}
if ($policyResult.Killed -ne [int]$result.mutants_killed -or
    $policyResult.Lived -ne [int]$result.mutants_lived -or
    $policyResult.Uncovered -ne [int]$result.mutants_not_covered -or
    $policyResult.NonViable -ne [int]$result.mutants_not_viable) {
    throw 'Gremlins aggregate counts do not match its per-mutant statuses.'
}

$survivingMutants = @($result.files | ForEach-Object {
    $file = $_.file_name.Replace('\', '/')
    foreach ($mutant in $_.mutations) {
        if ($mutant.status -eq 'LIVED') {
            '{0}:{1}:{2}:{3}' -f $file, $mutant.line, $mutant.column, $mutant.type
        }
    }
} | Sort-Object)
$survivorBaseline = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mutation-survivors.json') -Raw | ConvertFrom-Json
$policyFailure = $null
$improvement = [pscustomobject]@{ Met = $false }
try {
    $improvement = Assert-MutationPolicy -Language go -Result $policyResult -Thresholds $thresholds -SurvivingMutants $survivingMutants -SurvivorBaseline $survivorBaseline
}
catch { $policyFailure = $_ }
$target = @(& go env GOOS GOARCH)
if ($LASTEXITCODE -ne 0 -or $target.Count -ne 2) {
    throw 'Unable to identify the native Go mutation target.'
}
$summary = [ordered]@{
    schemaVersion = 1
    language = 'go'
    commit = $commit
    pullRequestHead = $env:MUTATION_PR_HEAD
    workingTreeDirty = $workingTreeDirty
    toolExitCode = $toolExitCode
    policyPassed = $null -eq $policyFailure
    survivingMutants = $survivingMutants
    target = [ordered]@{ os = $target[0]; architecture = $target[1] }
    tool = [ordered]@{ name = 'Gremlins'; version = '0.6.0' }
    counts = [ordered]@{
        generated = $policyResult.Generated
        executed = $executed
        killed = $policyResult.Killed
        lived = $policyResult.Lived
        uncovered = $policyResult.Uncovered
        timedOut = $policyResult.TimedOut
        nonViable = $policyResult.NonViable
        skipped = $policyResult.Skipped
    }
    scores = [ordered]@{
        testEfficacy = [Math]::Round($policyResult.TestEfficacy, 2)
        mutantCoverage = [Math]::Round($policyResult.MutantCoverage, 2)
    }
    breakThresholds = $thresholds.go.break
    improvementTarget = $thresholds.go.improvement
    improvementTargetMet = $improvement.Met
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host ((
    'Go mutation summary: generated={0}, executed={1}, killed={2}, lived={3}, uncovered={4}, ' +
    'timed-out={5}, non-viable={6}, skipped={7}, efficacy={8:N2}%, coverage={9:N2}%, improvement-target={10}'
) -f @(
    $policyResult.Generated,
    $executed,
    $policyResult.Killed,
    $policyResult.Lived,
    $policyResult.Uncovered,
    $policyResult.TimedOut,
    $policyResult.NonViable,
    $policyResult.Skipped,
    $policyResult.TestEfficacy,
    $policyResult.MutantCoverage,
    $improvement.Met
))
Write-Host "Go mutation reports: '$languageRoot'."
if ($null -ne $policyFailure) { throw $policyFailure }
if ($toolExitCode -ne 0) { throw "Gremlins failed with exit code $toolExitCode." }
