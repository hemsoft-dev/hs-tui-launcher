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

    Confirm-ExpectedFinding "semgrep" {
        & $semgrep scan --config .semgrep.yml --error --metrics off (Join-Path $fixtureRoot "unsafe.ts")
    }

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
