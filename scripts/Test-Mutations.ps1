[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$gremlins = 'github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0'
$resultPath = Join-Path ([IO.Path]::GetTempPath()) "gremlins-$([guid]::NewGuid().ToString('N')).json"

try {
    $toolOutput = @(& go run $gremlins unleash --config .gremlins.yaml --output $resultPath . 2>&1)
    $toolExitCode = $LASTEXITCODE
    $toolOutput | ForEach-Object { Write-Host $_ }

    if ($toolExitCode -ne 0) {
        $thresholdExit = @($toolOutput | Select-String -Pattern '^exit status (10|11)$')
        if ($thresholdExit.Count -gt 0) {
            throw "Gremlins rejected a configured mutation threshold ($($thresholdExit[-1].Line))."
        }

        throw "Gremlins failed with exit code $toolExitCode."
    }

    $reportedErrors = @($toolOutput | Where-Object { "$_" -match '^ERROR:' })
    if ($reportedErrors.Count -gt 0) {
        throw "Gremlins reported $($reportedErrors.Count) tool error(s)."
    }

    if (-not (Test-Path -LiteralPath $resultPath)) {
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

    $generatedMutations = @($result.files | ForEach-Object { $_.mutations }).Count
    if ($generatedMutations -eq 0) {
        throw 'Gremlins generated no mutations for the configured scope.'
    }

    if ([int]$result.mutants_total -eq 0) {
        throw 'Gremlins did not execute any generated mutations.'
    }

    Write-Host ((
        'Mutation summary: generated={0}, killed={1}, lived={2}, uncovered={3}, ' +
        'not-viable={4}, efficacy={5:N2}%, coverage={6:N2}%'
    ) -f @(
        $generatedMutations,
        $result.mutants_killed,
        $result.mutants_lived,
        $result.mutants_not_covered,
        $result.mutants_not_viable,
        $result.test_efficacy,
        $result.mutations_coverage
    ))
}
finally {
    if (Test-Path -LiteralPath $resultPath) {
        Remove-Item -LiteralPath $resultPath -Force
    }
}
