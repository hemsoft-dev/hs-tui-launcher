[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$gocyclo = 'github.com/fzipp/gocyclo/cmd/gocyclo@v0.6.1-0.20251227213109-7b6c7c5e29f1'
$complexityLimit = 15
$sourceRoot = (Resolve-Path -LiteralPath '.').Path
$testFilePattern = '_test\.go$'

$topOutput = @(& go run $gocyclo -top 1 -ignore $testFilePattern $sourceRoot 2>&1)
$topExitCode = $LASTEXITCODE
$topOutput | ForEach-Object { Write-Host $_ }

if ($topExitCode -ne 0) {
    throw "gocyclo measurement failed with exit code $topExitCode."
}

$topLines = @($topOutput | Where-Object { "$_" -match '^\d+\s+' })
if ($topLines.Count -ne 1) {
    throw "gocyclo returned $($topLines.Count) function measurements; expected one maximum."
}

$topMatch = [regex]::Match("$($topLines[0])", '^(?<complexity>\d+)\s+(?<details>.+)$')
if (-not $topMatch.Success) {
    throw 'Could not parse the maximum gocyclo measurement.'
}

Write-Host (
    'Complexity summary: max={0}, limit={1}, function={2}' -f
    $topMatch.Groups['complexity'].Value,
    $complexityLimit,
    $topMatch.Groups['details'].Value
)

$checkOutput = @(& go run $gocyclo -over $complexityLimit -ignore $testFilePattern $sourceRoot 2>&1)
$checkExitCode = $LASTEXITCODE
$checkOutput | ForEach-Object { Write-Host $_ }

if ($checkExitCode -ne 0) {
    $violations = @($checkOutput | Where-Object { "$_" -match '^\d+\s+' })
    if ($violations.Count -gt 0) {
        throw "$($violations.Count) function(s) exceed the cyclomatic complexity limit of $complexityLimit."
    }

    throw "gocyclo threshold check failed with exit code $checkExitCode."
}
