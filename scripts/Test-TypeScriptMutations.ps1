[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-tui-mutations-$([guid]::NewGuid().ToString('N'))"),
    [string] $ThresholdPath = (Join-Path $PSScriptRoot 'mutation-thresholds.json')
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

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$toolRoot = Join-Path $PSScriptRoot 'mutation-tools'
$toolManifest = Join-Path $toolRoot 'package.json'
$toolLock = Join-Path $toolRoot 'package-lock.json'
if (-not (Test-Path -LiteralPath $toolManifest -PathType Leaf) -or
    -not (Test-Path -LiteralPath $toolLock -PathType Leaf)) {
    throw 'The pinned TypeScript mutation tool manifest or lockfile is missing.'
}

Push-Location $repositoryRoot
try {
    $commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Unable to identify the exact commit for the mutation report.'
    }
    $workingTreeDirty = @(& git status --porcelain --untracked-files=normal).Count -gt 0
    & npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw "Root npm ci failed (exit $LASTEXITCODE)." }
    & npm ci --prefix $toolRoot --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw "Mutation-tool npm ci failed (exit $LASTEXITCODE)." }

    & node --import ./scripts/mutation-tools/offline.mjs --test scripts/mutation-tools/offline.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Offline mutation-test guard failed.' }
    & node --import ./scripts/mutation-tools/offline.mjs --experimental-strip-types --test pi/jev-decide/*.test.ts
    if ($LASTEXITCODE -ne 0) { throw 'Existing Jev tests failed under the offline guard.' }

    $thresholds = Get-MutationThreshold -Path $ThresholdPath
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
    $languageRoot = Join-Path $outputRoot 'typescript'
    New-Item -ItemType Directory -Path $languageRoot -Force | Out-Null
    $resultPath = Join-Path $languageRoot 'stryker.json'
    $summaryPath = Join-Path $languageRoot 'summary.json'
    foreach ($path in @($resultPath, $summaryPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }

    $baseConfigPath = Join-Path $repositoryRoot 'stryker.config.json'
    $config = Get-Content -LiteralPath $baseConfigPath -Raw | ConvertFrom-Json
    $config.jsonReporter.fileName = $resultPath.Replace('\', '/')
    $config.thresholds.high = [double]$thresholds.typescript.improvement.minimumMutationScore
    $config.thresholds.low = [double]$thresholds.typescript.break.minimumMutationScore
    $config.thresholds.break = [double]$thresholds.typescript.break.minimumMutationScore
    $temporaryConfig = Join-Path ([IO.Path]::GetTempPath()) "stryker-$([guid]::NewGuid().ToString('N')).json"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryConfig -Encoding utf8

    try {
        $stryker = Join-Path $toolRoot 'node_modules/@stryker-mutator/core/bin/stryker.js'
        $toolOutput = @(& node $stryker run $temporaryConfig 2>&1)
        $toolExitCode = $LASTEXITCODE
        $toolOutput | ForEach-Object { Write-Host $_ }
        $toolOutput | Set-Content -LiteralPath (Join-Path $languageRoot 'tool.log') -Encoding utf8
    }
    finally {
        Remove-Item -LiteralPath $temporaryConfig -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "StrykerJS failed with exit code $toolExitCode and produced no JSON report."
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -AsHashtable
    if ($result['schemaVersion'] -ne '1.0' -or $null -eq $result['files']) {
        throw 'StrykerJS produced an unsupported or incomplete JSON report.'
    }
    $mutations = @($result['files'].Values | ForEach-Object { $_['mutants'] })
    $knownStatuses = @('Killed', 'Survived', 'Timeout', 'NoCoverage', 'CompileError', 'Ignored')
    $unknownStatuses = @($mutations | Where-Object { $_.status -notin $knownStatuses } | Select-Object -ExpandProperty status -Unique)
    if ($unknownStatuses.Count -gt 0) {
        throw "StrykerJS reported unknown mutant statuses: $($unknownStatuses -join ', ')."
    }

    $policyResult = [pscustomobject]@{
        Generated = $mutations.Count
        Killed = Get-MutationStatusCount -Mutations $mutations -Status 'Killed'
        Lived = Get-MutationStatusCount -Mutations $mutations -Status 'Survived'
        Uncovered = Get-MutationStatusCount -Mutations $mutations -Status 'NoCoverage'
        TimedOut = Get-MutationStatusCount -Mutations $mutations -Status 'Timeout'
        NonViable = Get-MutationStatusCount -Mutations $mutations -Status 'CompileError'
        Skipped = Get-MutationStatusCount -Mutations $mutations -Status 'Ignored'
        MutationScore = 0.0
    }
    $executed = $policyResult.Killed + $policyResult.Lived + $policyResult.TimedOut
    $scored = $executed + $policyResult.Uncovered
    if ($policyResult.Generated -eq 0 -or $executed -eq 0 -or $scored -eq 0) {
        throw 'StrykerJS must generate and execute nonzero mutation counts.'
    }
    $policyResult.MutationScore = 100.0 * ($policyResult.Killed + $policyResult.TimedOut) / $scored
    $survivingMutants = @($result['files'].GetEnumerator() | ForEach-Object {
        $file = $_.Key.Replace('\', '/')
        foreach ($mutant in $_.Value['mutants']) {
            if ($mutant.status -eq 'Survived') {
                $start = $mutant.location.start
                $end = $mutant.location.end
                '{0}:{1}:{2}:{3}:{4}:{5}:{6}' -f $file, $start.line, $start.column, $end.line, $end.column, $mutant.mutatorName, $mutant.replacement
            }
        }
    } | Sort-Object)
    $survivorBaseline = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mutation-survivors.json') -Raw | ConvertFrom-Json
    $policyFailure = $null
    $improvement = [pscustomobject]@{ Met = $false }
    try {
        $improvement = Assert-MutationPolicy -Language typescript -Result $policyResult -Thresholds $thresholds -SurvivingMutants $survivingMutants -SurvivorBaseline $survivorBaseline
    }
    catch { $policyFailure = $_ }

    $nodeVersion = (& node --version).TrimStart('v')
    if ($LASTEXITCODE -ne 0) { throw 'Unable to identify the Node.js version.' }

    $summary = [ordered]@{
        schemaVersion = 1
        language = 'typescript'
        commit = $commit
        pullRequestHead = $env:MUTATION_PR_HEAD
        workingTreeDirty = $workingTreeDirty
        toolExitCode = $toolExitCode
        policyPassed = $null -eq $policyFailure
        survivingMutants = $survivingMutants
        target = [ordered]@{ node = $nodeVersion; platform = [Environment]::OSVersion.Platform.ToString(); architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
        tool = [ordered]@{ name = 'StrykerJS'; version = '10.0.0'; typeScriptChecker = '10.0.0'; typeScript = '5.9.3' }
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
        scores = [ordered]@{ mutationScore = [Math]::Round($policyResult.MutationScore, 2) }
        breakThresholds = $thresholds.typescript.break
        improvementTarget = $thresholds.typescript.improvement
        improvementTargetMet = $improvement.Met
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8

    Write-Host ((
        'TypeScript mutation summary: generated={0}, executed={1}, killed={2}, lived={3}, uncovered={4}, ' +
        'timed-out={5}, non-viable={6}, skipped={7}, score={8:N2}%, improvement-target={9}'
    ) -f @(
        $policyResult.Generated,
        $executed,
        $policyResult.Killed,
        $policyResult.Lived,
        $policyResult.Uncovered,
        $policyResult.TimedOut,
        $policyResult.NonViable,
        $policyResult.Skipped,
        $policyResult.MutationScore,
        $improvement.Met
    ))
    Write-Host "TypeScript mutation reports: '$languageRoot'."
    if ($null -ne $policyFailure) { throw $policyFailure }
    if ($toolExitCode -ne 0) { throw "StrykerJS failed with exit code $toolExitCode." }
}
finally {
    Pop-Location
}
