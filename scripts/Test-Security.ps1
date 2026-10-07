[CmdletBinding()]
param([string] $OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "hs-security-$([guid]::NewGuid().ToString('N'))"))

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$toolDirectory = Join-Path $repositoryRoot "bin/security-tools"
$executableSuffix = if ($isWindowsPlatform) { ".exe" } else { "" }
$govulncheck = Join-Path $toolDirectory "govulncheck$executableSuffix"
$gitleaks = Join-Path $toolDirectory "gitleaks$executableSuffix"
$osvScanner = Join-Path $toolDirectory "osv-scanner$executableSuffix"
$semgrep = if ($isWindowsPlatform) {
    Join-Path $toolDirectory "python/Scripts/semgrep.exe"
} else {
    Join-Path $toolDirectory "python/bin/semgrep"
}

Push-Location $repositoryRoot
try {
    Write-Host "Checking reachable Go vulnerabilities"
    & $govulncheck ./...
    if ($LASTEXITCODE -ne 0) {
        throw "govulncheck failed (exit $LASTEXITCODE)."
    }

    & (Join-Path $PSScriptRoot 'Test-SecretScanning.ps1') -GitleaksPath $gitleaks -OutputDirectory $OutputDirectory

    Write-Host "Checking Go and TypeScript security patterns"
    & $semgrep scan --config .semgrep.yml --error --metrics off --exclude .github/security/fixtures .
    if ($LASTEXITCODE -ne 0) {
        throw "semgrep failed (exit $LASTEXITCODE)."
    }

    Write-Host "Checking dependency manifests against OSV"
    & $osvScanner scan source --recursive .
    if ($LASTEXITCODE -ne 0) {
        throw "osv-scanner failed (exit $LASTEXITCODE)."
    }
} finally {
    Pop-Location
}
