$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Confirm-ExpectedFinding {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Scan
    )

    & $Scan
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 1) {
        throw "$Name fixture expected a finding (exit 1), but scanner exited $exitCode."
    }
    Write-Host "$Name fixture produced the expected finding."
}

function Confirm-SemgrepResult {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Target,
        [Parameter(Mandatory)] [string] $RuleId,
        [Parameter(Mandatory)] [int] $ExpectedCount
    )

    $reportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("semgrep-" + [guid]::NewGuid().ToString("N") + ".json")
    try {
        & $semgrep scan --config .semgrep.yml --error --metrics off --json --output $reportPath $Target
        $exitCode = $LASTEXITCODE
        $expectedExitCode = if ($ExpectedCount -eq 0) { 0 } else { 1 }
        if ($exitCode -ne $expectedExitCode) {
            throw "$Name expected scanner exit $expectedExitCode, but scanner exited $exitCode."
        }

        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $errors = @($report.errors)
        if ($errors.Count -ne 0) {
            throw "$Name produced $($errors.Count) Semgrep error(s)."
        }

        $results = @($report.results)
        $matchingResults = @($results | Where-Object { $_.check_id -eq $RuleId })
        if ($results.Count -ne $ExpectedCount -or $matchingResults.Count -ne $ExpectedCount) {
            $actualRuleIds = @($results | ForEach-Object { $_.check_id }) -join ", "
            throw "$Name expected $ExpectedCount '$RuleId' finding(s), but received $($results.Count) total: $actualRuleIds"
        }
        Write-Host "$Name produced exactly $ExpectedCount '$RuleId' finding(s)."
    } finally {
        Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$fixtureRoot = Join-Path $repositoryRoot ".github/security/fixtures"
$toolDirectory = Join-Path $repositoryRoot "bin/security-tools"
$executableSuffix = if ($isWindowsPlatform) { ".exe" } else { "" }
$gitleaks = Join-Path $toolDirectory "gitleaks$executableSuffix"
$osvScanner = Join-Path $toolDirectory "osv-scanner$executableSuffix"
$semgrep = if ($isWindowsPlatform) {
    Join-Path $toolDirectory "python/Scripts/semgrep.exe"
} else {
    Join-Path $toolDirectory "python/bin/semgrep"
}

Push-Location $repositoryRoot
try {
    Confirm-ExpectedFinding "gitleaks sentinel rule" {
        & $gitleaks dir --config (Join-Path $fixtureRoot "gitleaks.toml") --redact --no-banner (Join-Path $fixtureRoot "secret.txt")
    }

    $defaultRuleFixture = Join-Path $fixtureRoot "default-rule-secret.generated.txt"
    try {
        $inertToken = "AK" + "IA" + "QWERTYUIOPASDFGH"
        Set-Content -LiteralPath $defaultRuleFixture -Value "fixture=$inertToken" -Encoding Ascii -NoNewline
        Confirm-ExpectedFinding "gitleaks default rules" {
            & $gitleaks dir --config .gitleaks.toml --redact --no-banner $fixtureRoot
        }
    } finally {
        Remove-Item -LiteralPath $defaultRuleFixture -Force -ErrorAction SilentlyContinue
    }

    Confirm-SemgrepResult "Semgrep dynamic-code fixture" (Join-Path $fixtureRoot "unsafe.ts") "typescript-dynamic-code-execution" 1
    Confirm-SemgrepResult "Semgrep Go shell positive fixture" (Join-Path $fixtureRoot "go-shell-positive.go") "go-shell-command-from-variable" 2
    Confirm-SemgrepResult "Semgrep Go shell negative fixture" (Join-Path $fixtureRoot "go-shell-negative.go") "go-shell-command-from-variable" 0
    Confirm-SemgrepResult "Semgrep TypeScript shell positive fixture" (Join-Path $fixtureRoot "typescript-shell-positive.ts") "typescript-shell-command-from-variable" 10
    Confirm-SemgrepResult "Semgrep TypeScript shell negative fixture" (Join-Path $fixtureRoot "typescript-shell-negative.ts") "typescript-shell-command-from-variable" 0

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("hs-tui-security-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    try {
        Copy-Item (Join-Path $fixtureRoot "package-lock.json.fixture") (Join-Path $temporaryDirectory "package-lock.json")
        Confirm-ExpectedFinding "osv-scanner" {
            & $osvScanner scan source --recursive $temporaryDirectory
        }
    } finally {
        Remove-Item -Recurse -Force $temporaryDirectory
    }
} finally {
    Pop-Location
}

# The expected scanner findings leave a native exit code of 1; report the
# fixture harness result, not the last intentionally failing scanner result.
exit 0
