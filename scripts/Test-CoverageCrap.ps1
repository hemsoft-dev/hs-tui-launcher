<#
.SYNOPSIS
Collects repository Go coverage, joins it to cyclomatic complexity, and enforces CRAP gates.

.DESCRIPTION
Run `./scripts/Test-CoverageCrap.ps1` from any location. The command runs
`go test ./...` with one count-mode coverage profile, verifies that every production
source file returned by `go list ./...` occurs in that profile, and measures every
production function with the same pinned gocyclo lineage as Test-Complexity.ps1.
Functions are joined by normalized repository-relative file path plus start line.

The JSON and text reports use statement coverage. CRAP is calculated as
`complexity^2 * (1 - coverage)^3 + complexity`, where coverage is in [0, 1].
The checked-in baseline is deliberately not overridable from the command line.

.PARAMETER OutputDirectory
Directory for coverage.out, coverage-crap.json, and coverage-crap.txt. The default
is a process-specific temporary directory, so a local run does not dirty the tree.
CI should pass an artifact staging directory explicitly.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "hs-tui-launcher-coverage-crap-$PID")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Import-Module (Join-Path $PSScriptRoot 'CoverageCrap.psm1') -Force

$gocyclo = 'github.com/fzipp/gocyclo/cmd/gocyclo@v0.6.1-0.20251227213109-7b6c7c5e29f1'
$coverageBasis = 'Statement coverage across every production Go package from go test ./... -covermode=count -coverprofile=<path>.'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baselinePath = Join-Path $PSScriptRoot 'coverage-crap-baseline.json'
$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json

if (
    $baseline.schemaVersion -ne 1 -or
    $null -eq $baseline.repositoryCoverageFloorPercent -or
    $null -eq $baseline.actionableCrap -or
    $null -eq $baseline.maximumCrapBaseline
) {
    throw "Unsupported or incomplete baseline '$baselinePath'."
}
if (
    [double]$baseline.repositoryCoverageFloorPercent -lt 0 -or
    [double]$baseline.repositoryCoverageFloorPercent -gt 100 -or
    [double]$baseline.actionableCrap -le 0 -or
    [double]$baseline.maximumCrapBaseline -le 0
) {
    throw "Baseline '$baselinePath' contains invalid gate values."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$coverageProfilePath = Join-Path $outputRoot 'coverage.out'
$jsonReportPath = Join-Path $outputRoot 'coverage-crap.json'
$textReportPath = Join-Path $outputRoot 'coverage-crap.txt'

Push-Location $repositoryRoot
try {
    $modulePathOutput = @(& go list -m)
    if ($LASTEXITCODE -ne 0 -or $modulePathOutput.Count -ne 1) {
        $modulePathOutput | ForEach-Object { Write-Host $_ }
        throw "go list -m failed or returned an unexpected module path."
    }
    $modulePath = "$($modulePathOutput[0])".Trim()

    $packageOutput = @(& go list -f '{{.ImportPath}}' ./...)
    if ($LASTEXITCODE -ne 0) {
        $packageOutput | ForEach-Object { Write-Host $_ }
        throw "go list ./... failed with exit code $LASTEXITCODE."
    }
    $packagePaths = @($packageOutput | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($packagePaths.Count -eq 0) {
        throw 'go list ./... returned zero production packages.'
    }

    $sourceFiles = [System.Collections.Generic.List[string]]::new()
    $absoluteSourceFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($packagePath in $packagePaths) {
        $packageJsonOutput = @(& go list -json $packagePath)
        if ($LASTEXITCODE -ne 0) {
            $packageJsonOutput | ForEach-Object { Write-Host $_ }
            throw "go list -json '$packagePath' failed with exit code $LASTEXITCODE."
        }
        $package = ($packageJsonOutput -join [Environment]::NewLine) | ConvertFrom-Json
        $packageFiles = @($package.GoFiles)
        if ($null -ne $package.PSObject.Properties['CgoFiles']) {
            $packageFiles += @($package.CgoFiles)
        }
        foreach ($packageFile in $packageFiles) {
            if (-not $packageFile) { continue }
            $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $package.Dir $packageFile))
            $normalizedPath = ConvertTo-NormalizedSourcePath `
                -Path $absolutePath `
                -RepositoryRoot $repositoryRoot `
                -ModulePath $modulePath
            if ($sourceFiles.Contains($normalizedPath)) {
                throw "Production source '$normalizedPath' was returned more than once by go list."
            }
            $sourceFiles.Add($normalizedPath)
            $absoluteSourceFiles.Add($absolutePath)
        }
    }
    if ($sourceFiles.Count -eq 0) {
        throw 'go list ./... returned zero production source files.'
    }

    $testOutput = @(& go test ./... -covermode=count "-coverprofile=$coverageProfilePath" 2>&1)
    $testExitCode = $LASTEXITCODE
    $testOutput | ForEach-Object { Write-Host $_ }
    if ($testExitCode -ne 0) {
        throw "go test coverage collection failed with exit code $testExitCode."
    }
    if (-not (Test-Path -LiteralPath $coverageProfilePath)) {
        throw "go test did not create coverage profile '$coverageProfilePath'."
    }

    $profileFiles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $profileLines = @(Get-Content -LiteralPath $coverageProfilePath)
    if ($profileLines.Count -lt 2 -or $profileLines[0] -ne 'mode: count') {
        throw 'Coverage profile is empty or does not use count mode.'
    }
    foreach ($profileLine in $profileLines | Select-Object -Skip 1) {
        $profileMatch = [regex]::Match(
            "$profileLine",
            '^(?<file>.+):\d+\.\d+,\d+\.\d+\s+\d+\s+\d+$'
        )
        if (-not $profileMatch.Success) {
            throw "Could not parse coverage profile line: '$profileLine'."
        }
        $normalizedProfileFile = ConvertTo-NormalizedSourcePath `
            -Path $profileMatch.Groups['file'].Value `
            -RepositoryRoot $repositoryRoot `
            -ModulePath $modulePath
        [void]$profileFiles.Add($normalizedProfileFile)
    }

    $missingProfileFiles = @($sourceFiles | Where-Object { -not $profileFiles.Contains($_) })
    $unexpectedProfileFiles = @($profileFiles | Where-Object { -not $sourceFiles.Contains($_) })
    if ($missingProfileFiles.Count -gt 0 -or $unexpectedProfileFiles.Count -gt 0) {
        throw (
            'Coverage production scope mismatch. Missing: [{0}]. Unexpected: [{1}].' -f
            ($missingProfileFiles -join ', '),
            ($unexpectedProfileFiles -join ', ')
        )
    }

    $coverOutput = @(& go tool cover "-func=$coverageProfilePath")
    if ($LASTEXITCODE -ne 0) {
        $coverOutput | ForEach-Object { Write-Host $_ }
        throw "go tool cover failed with exit code $LASTEXITCODE."
    }
    $coverage = ConvertFrom-CoverFunctionOutput `
        -Lines @($coverOutput | ForEach-Object { "$_" }) `
        -RepositoryRoot $repositoryRoot `
        -ModulePath $modulePath

    # Keep go's module-download diagnostics on stderr; only gocyclo's stdout is parseable data.
    $cycloOutput = @(& go run $gocyclo @absoluteSourceFiles)
    if ($LASTEXITCODE -ne 0) {
        throw "gocyclo measurement failed with exit code $LASTEXITCODE."
    }
    $complexity = ConvertFrom-GoCycloOutput `
        -Lines @($cycloOutput | ForEach-Object { "$_" }) `
        -RepositoryRoot $repositoryRoot `
        -ModulePath $modulePath

    $measurements = @(Merge-CoverageAndComplexity `
        -CoverageMeasurements $coverage.Measurements `
        -ComplexityMeasurements $complexity)

    $commitOutput = @(& git rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $commitOutput.Count -ne 1) {
        $commitOutput | ForEach-Object { Write-Host $_ }
        throw 'Could not determine the repository commit.'
    }
    $commit = "$($commitOutput[0])".Trim()

    $reportMeasurements = @($measurements | ForEach-Object {
        [ordered]@{
            file = $_.File
            line = $_.Line
            function = $_.Function
            complexity = $_.Complexity
            coveragePercent = $_.CoveragePercent
            crap = $_.Crap
        }
    })
    $report = [ordered]@{
        schemaVersion = 1
        commit = $commit
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        repositoryCoverage = [ordered]@{
            basis = $coverageBasis
            percent = $coverage.RepositoryCoveragePercent
            floorPercent = [double]$baseline.repositoryCoverageFloorPercent
            packagePattern = './...'
            packages = @($packagePaths)
            productionFiles = @($sourceFiles | Sort-Object)
        }
        thresholds = [ordered]@{
            actionableCrap = [double]$baseline.actionableCrap
            maximumCrapBaseline = [double]$baseline.maximumCrapBaseline
        }
        measurements = $reportMeasurements
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReportPath -Encoding utf8NoBOM

    $textLines = [System.Collections.Generic.List[string]]::new()
    $textLines.Add("Commit: $commit")
    $textLines.Add("Repository coverage basis: $coverageBasis")
    $textLines.Add(
        ('Repository coverage: {0:N1}% (floor: {1:N1}%)' -f
            $coverage.RepositoryCoveragePercent,
            [double]$baseline.repositoryCoverageFloorPercent)
    )
    $textLines.Add("Production scope: $($packagePaths.Count) package(s), $($sourceFiles.Count) file(s)")
    $textLines.Add(
        ('CRAP gates: actionable <= {0:N2}; maximum baseline <= {1:N2}' -f
            [double]$baseline.actionableCrap,
            [double]$baseline.maximumCrapBaseline)
    )
    $textLines.Add('')
    $textLines.Add('CRAP    Coverage  Complexity  File:Line  Function')
    foreach ($measurement in $measurements) {
        $textLines.Add(
            ('{0,6:N2}  {1,7:N1}%  {2,10}  {3}:{4}  {5}' -f
                $measurement.Crap,
                $measurement.CoveragePercent,
                $measurement.Complexity,
                $measurement.File,
                $measurement.Line,
                $measurement.Function)
        )
    }
    $textLines | Set-Content -LiteralPath $textReportPath -Encoding utf8NoBOM
    $textLines | ForEach-Object { Write-Host $_ }
    Write-Host "Machine-readable report: $jsonReportPath"
    Write-Host "Human-readable report: $textReportPath"

    $violations = @(Test-CrapGates `
        -Measurements $measurements `
        -RepositoryCoveragePercent $coverage.RepositoryCoveragePercent `
        -RepositoryCoverageFloorPercent ([double]$baseline.repositoryCoverageFloorPercent) `
        -ActionableCrap ([double]$baseline.actionableCrap) `
        -MaximumCrapBaseline ([double]$baseline.maximumCrapBaseline))
    if ($violations.Count -gt 0) {
        throw ("Coverage/CRAP gates failed:`n - " + ($violations -join "`n - "))
    }
} finally {
    Pop-Location
}
